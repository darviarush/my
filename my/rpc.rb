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
	def initialize(prog = nil, r=nil, w=nil)
		
		@finalizer = proc do |id|
			self.erase.push id
		end
		
		@prog = prog
		@objects = Hash.new
		@warn = 0
		@erase = []
		@wantarray = 1
		
		if prog == -1
			@role = "TEST"
			@r = r
			@w = w
			return
		end
	
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

		@role = "MINOR"

		ret = self.ret

		$stderr.puts "MINOR ENDED #{ret}\n"
		@objects = []
		return ret
	end

	# превращает в бинарный формат и сразу отправляет. Объекты складирует в $this->objects
	def pack(data)
		is = Hash.new
		pipe = @w
		
		lun = Proc.new do		
			if hash
				pipe.puts "s", [key.length].pack("l"), key
			end
			
			if [Hash, Array].include? val.class 
				if n = is[val.object_id]
					pipe.puts "h", [n].pack("l")
				else
					num = is.length
					is[val.object_id] = num
					if val.class == Hash
						pipe.puts "H", [val.length].pack("l")
						for k, v in val
							lun.call k
							lun.call v
						end
					else
						pipe.puts "A", [val.length].pack("l")
						val.each(lun)
					end
				end
			elsif val.class == TrueClass
				pipe.putc "T"
			elsif val.class == FalseClass
				pipe.putc "F"
			elsif val.class == NilClass
				pipe.putc "U"
			elsif val.class == RPCstub
				pipe.puts "S", [val.__num].pack("l")
			elsif val.class == Fixnum			# 0.class.class.ancestors
				pipe.puts val == 1? "1": val == 0? "0": "i"+[val].pack("l")
			elsif val.class == String
				pipe.puts "s", [val.length].pack("l"), val
			elsif val.class == Float
				pipe.puts "n", [val].pack("d")
			else	# несериализируемый object
				num = @objects.length
				@objects[num] = val
				$stderr.puts "#{@role} add(#{num}) ="+objects if @warn >= 2
				pipe "B", [num].pack("l")
				#raise RPCException, "Значение неизвестного типа #{val}"
			end
		end
		
		lun.call data
		
		return self

	# считывает структуру из потока ввода
	def unpack 
		pipe = @r
		
		replace_arr = nil
		ret = []
		st = [[ret, 0, 0, 1]]

		while st.length != 0
			arr, hash, key, len = st.pop

			while len-- != 0

				ch = pipe.getc
				
				if ch == "h"
					num = pipe.gets(4).unpack("l")[0]
					val = is[num]
				elsif ch == "H"
					replace_arr = 1
					val = {}
				elsif ch == "A"
					replace_arr = 0
					val = []
				elsif ch == "S"
					val = @objects[pipe.gets(4).unpack("l")[0]]
				elsif ch == "B"
					val = self.stub(pipe.gets(4).unpack("l")[0])
				elsif ch == "T"
					val = true
				elsif ch == "F"
					val = false
				elsif ch == "U"
					val = nil
				elsif ch == "1"
					val = 1
				elsif ch == "0"
					val = 0
				elsif ch == "i"		# integer
					val = pipe.gets(4).unpack("l")[0]
				elsif ch == "n"		# double
					val = pipe.gets(8).unpack("d")[0]
				elsif ch == "s"		# string
					n = pipe.gets(4).unpack("l")[0]
					val = pipe.gets(n)
					if val.length != n
						raise RPCException, "Неизвестный тип в потоке ввода"
					end
				else
					raise RPCException, "Неизвестный тип в потоке ввода"
				end
				
				if hash == 1
					if len % 2 != 0
						key = val
					else 
						arr[key] = val
					end
				else
					arr.push val
				end
				
				unless replace_arr.eq? nil
					st.push [arr, hash, key, len]
					arr = val
					is.push arr
					hash, len = replace_arr, (replace_arr+1) * pipe.gets(4).unpack("l")[0]
					replace_arr = nil
				end

			end
		end
		
		return ret[0]
	}

	# отправляет команду и получает ответ
	def reply(*av)
		$stderr.puts "#{@role} #{cmd} #{ret}" if @warn
		self.pack(av).pack(@nums)
		@nums = []
		self.ret
	}

	# отправляет ответ
	def ok(ret, cmd = "ok")
		$stderr.puts "#{@role} #{cmd} #{ret}" if @warn
		self.pack([cmd, ret]).pack(@nums)
		@nums = []
		return self

	# создаёт экземпляр класса
	def new_instance(name, *av)
		self.reply("new", name, av, @wantarray)
	end

	# вызывает функцию
	def call(name, *av)
		self.reply("call", name, av, @wantarray)
	end

	# вызывает метод
	def apply(cls, name, *av)
		self.reply("apply", cls, name, av, @wantarray)
	end

	# выполняет код eval eval, args...
	def eval(eval, *av)
		self.reply("eval", eval, av, @wantarray)
	end

	# устанавливает warn на миноре
	def warn(val)
		val = val.to_i
		@warn = val
		self.reply("warn", val)
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
		
		while true	# клиент послал запрос
			if pipe.eof?
				if @warn == 1
					$stderr.puts "#{@role} closed: #{caller.join("\n")}\n"
				end
				return	# закрыт
			end
			ret = self.unpack
			nums = self.unpack

			
			if @warn == 1
				$stderr.puts "#{@role} <- #{ret} #{nums}\n"
			end
			
			cmd = ret.shift
			
			if cmd == "ok"
				self.erase(nums)
				break
			elsif cmd == "error"
				self.erase(nums)
				raise RPCException, args, caller
			end
			
			begin

				if cmd == "stub"
					num, name, args, wantarray = ret
					ret = @objects[num].send(name, *args)
					self.pack("ok", ret)
				elsif cmd == "get"
					num, key = ret
					self.pack("ok", @objects[num][key])
				elsif cmd == "set"
					num, key, val = ret
					@objects[num][key] = val
					self.pack("ok", 1)
				elsif cmd == "warn"
					@warn = ret
					self.pack("ok", 1)
				elsif cmd == "apply"
					cls, name, args, wantarray = ret
					ret = Kernel.send(cls).send(name, *args)
					self.pack("ok", ret)
				elsif cmd == "call"
					name, args, wantarray = ret
					ret = Kernel.send(name, *args)
					self.pack("ok", ret)
				elsif cmd == "eval"
					buf, args, wantarray = ret
					ret = eval(buf)
					self.pack("ok", ret)
				else
					raise RPCException, "Неизвестная команда `cmd`", caller
				end
			rescue SyntaxError, NameError, StandardError => e
				self.pack("error", e.to_s)
			end
			self.erase(nums)
		end

		return args
	end

	# создаёт заглушку, для удалённого объекта
	def stub(num)
		stub = RPCStub.new(self, num)
		define_finalizer(stub, @finalizer)
		return stub
	end
	
	# возвращает wantarray
	def wantarray
		@wantarray
	end
	
end

# заглушка
class RPCstub
	
	def initialize(rpc, num)
		@rpc = rpc
		@num = num
	end
	
	def method_missing(name, *param)
		@rpc.reply("stub", @num, name, @rpc.wantarray, param)
	end
	
	def [](key)
		self.rpc.reply("get", @num, key)
	end
	
	def [](key, val)
		self.rpc.reply("set", @num, key, val)
	end

	def __num
		@num
	end
	
end

class RPCException < RuntimeError
end