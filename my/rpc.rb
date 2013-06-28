#!/usr/bin/env ruby
# encoding: UTF-8

# gem install json
require 'json'

include ObjectSpace

class RPC

	@@PROG = Hash[
		"perl" => "perl -I'%s' -e 'require rpc; rpc->new'",
		"php" => "php -r 'require_once \"%s/rpc.php\"; new rpc();'",
		"python" => "python -c 'import sys; sys.path.append(\"%s\"); from rpc import RPC; RPC()'",
		"ruby" => "ruby -I'%s' -e 'require \"rpc.rb\"; RPC.new'"
	]

	# конструктор. Создаёт соединение
	def initialize(prog = nil)
		
		@finalizer = proc do |id|
			self.erase.push id
		end
		
		@prog = prog
		@objects = Hash.new
		@warn = 0
		@erase = []
		@wantarray = 1
	
		if prog.equal?(nil)
			return self.minor
		end
		
		ch_reader, writer = IO.pipe
		reader, ch_writer = IO.pipe
		
		pid = fork do
			prog = @@PROG[prog]
			#$LOAD_PATH
			prog = prog % $LOADED_FEATURES.select { |x| /\/rpc\.pm$/ =~ x }.last if prog
			ch_reader.dup2(4) if ch_reader.fileno != 4
			ch_writer.dup2(5) if ch_writer.fileno != 5
			exec prog
		end

		@r = reader
		@w = writer
		@bless = "\0bless\0"
		@stub = "\0stub\0"
		@role = "MAJOR"
	end

	# закрывает соединение
	def close
		@w.puts "ok\nnull\n"
		@r.close
		@w.close
	end

	# создаёт подчинённого
	def minor
	
		@r = IO.new(4, "rb")
		@w = IO.new(5, "wb")

		@bless = "\0stub\0"
		@stub = "\0bless\0"
		@role = "MINOR"

		ret = self.ret
		
		$stderr.puts "MINOR ENDED #{ret}\n"
		@object = []
		return ret
	end

	# превращает в json и сразу отправляет. Объекты складирует в self->objects
	def pack(cmd, data)
		pipe = @w
		
		ret = [data]
		st = [ret]
		
		while st
			ls = st.pop
			for i, val in if ls.instance_of? Array then (0..ls.length - 1).to_a.zip(ls) else ls end
				if val.instance_of? RPCstub
					ls[i] = {@stub => val.num}
				elsif [Hash, Array].include? val.class
					st.push val
				elsif not( [TrueClass, FalseClass, NilClass].include? val.class or val.is_a? Enumerable )
					idx = @objects.length
					ls[i] = {@bless => idx}
					@objects[idx] = val
				end
			end
		end
		
		data = ret[0]
		
		$stderr.puts "#{@role} -> #{cmd} #{JSON.dump(data)} #{@erase.to_s}\n" if @warn
		
		pipe.puts "#{cmd}\n"
		JSON.dump(data, pipe)
		pipe.puts "\n#{@erase.join("\n")}\n"
		pipe.flush
		@erase = []
		return self
	end

	# распаковывает
	def unpack(data)

		data = JSON.load(data)
		
		ret = [data]
		st = [ret]
		
		while st
			ls = st.pop()
			for i, val in if ls.instance_of? Array then (0..ls.length - 1).to_a.zip(ls) else ls end
				if val[@stub] != nil
					ls[i] = self.stub(val[@stub])
				elsif val[@bless] != nil 
					ls[i] = @objects[val[@bless]]
				elsif [Hash, Array].include? val
					st.push val
				end
			end
		end
		
		data = ret[0]

		return data
	end

	# вызывает функцию
	def call(name, *args)
		self.pack("call #{name} #{@wantarray}", args).ret
	end

	# вызывает метод
	def apply(cls, name, *args)
		self.pack("apply #{cls} #{name} #{@wantarray}", args).ret
	end

	# выполняет код eval eval, args...
	def eval(eval, *args)
		args.unshift eval
		self.pack("eval #{@wantarray}", args).ret
	end

	# устанавливает warn на миноре
	def warn(val)
		val = val.to_i
		@warn = val
		self.pack("warn", val).ret
	end

	# удаляет ссылки на объекты из objects
	def erase(nums)
		for num in nums
			@objects.delete num.to_i
		end
	end
	
	# получает и возвращает данные и устанавливает ссылочные параметры
	def ret
		pipe = @r
		
		while 1	# клиент послал запрос
			if pipe.eof?
				if @warn
					$stderr.puts "#{@role} closed: #{caller.join("\n")}\n"
				end
				return	# закрыт
			end
			ret = pipe.readline.rtrim
			arg = pipe.readline.rtrim
			nums = pipe.readline.rtrim
			argnums = nums.split(",")
			args = self.unpack(arg)

			
			if @warn
				$stderr.puts "#{@role} <- `#{ret}` #{arg} #{nums}\n"
			end
			
			if ret == "ok" 
				self.erase(argnums)
			elsif ret == "error"
				self.erase(argnums)
				raise RPCException, args, caller
			end
			
			begin
			
				arg = ret.split(" ")
				cmd = arg[0]
				if cmd == "stub"
					ret = @objects[arg[1]].send(arg[2], *args); 
					self.pack("ok", ret)
				elsif cmd == "get"
					prop = args[0];
					ret = @objects[arg[1]].send prop
					self.pack("ok", ret)
				elsif cmd == "set"
					prop = args[0]
					@objects[arg[1]].send prop, args[1]
					self.pack("ok", 1)
				elsif cmd == "warn"
					@warn = args
					self.pack("ok", 1)
				elsif cmd == "apply"
					ret = arg[1].send arg[2], *args
					self.pack("ok", ret)
				elsif cmd == "call"
					ret = Kernel.send arg[1], *args
					self.pack("ok", ret)
				elsif cmd == "eval"
					buf = args.shift
					ret = eval(buf)
					self.pack("ok", ret)
				else
					raise RPCException, "Неизвестная команда `cmd`", caller
				end
			rescue SyntaxError, NameError, StandardError => e
				self.pack("error", e.to_s)
			end
			self.erase(argnums)
		end

		return args
	end

	# создаёт заглушку, для удалённого объекта
	def stub(num)
		stub = RPCStub.new(self, num)
		define_finalizer(stub, @finalizer)
		return stub
	end
	
end

# заглушка
class RPCstub
	
	def initialize(rpc, num)
		@rpc = rpc
		@num = num
	end
	
	def method_missing(name, *param)
		self.rpc.pack("stub #{@num} #{name} #{@rpc.wantarray}", param).ret
	end
	
end

class RPCException < RuntimeError
end