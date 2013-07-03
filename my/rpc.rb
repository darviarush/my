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
		
		st = [[data]]
		
		while st.length != 0
			arr = st.pop
			i = st.pop
			hash = arr.class == Hash

			while(my(key, val) = hash? each %arr: each @arr) {
				
				if(hash) {
					_utf8_off(key) if is_utf8(key);
					print pipe "s", pack("l", length key), key;
				}
				
				if(ref val eq "HASH") {
					print(pipe "h", pack "l", n), next if defined(n = is{val});
					my num = keys %is;
					is{val} = num;
					print pipe "H", pack "l", 0+keys(%val);
					push @st, arr;
					arr = val;
					hash = 1;
				}
				elsif(ref val eq "ARRAY") {
					print(pipe "h", pack "l", n), next if defined(n = is{val});
					my num = keys %is;
					is{val} = num;
					print pipe "A", pack "l", 0+@val;
					push @st, arr;
					arr = val;
					hash = 0;
				}
				elsif(ref val eq "utils::boolean") {
					print pipe val? "T": "F";
				}
				elsif(ref val eq "rpc::stub") {
					my stub = tied %val;
					print pipe "S", pack "l", stub->{num};
				}
				elsif(ref val) {
					my objects = self->{objects};
					my num = keys %objects;
					objects->{num} = val;
					warn "self->{role} add(num) =".Dumper(objects) if self->{warn} >= 2;
					print pipe "B", pack "l", num;
				}
				elsif(!defined val) {
					print pipe "U";	# undef
				}
				elsif((svref = svref_2object \val) && ((svref = svref->FLAGS) & B::SVp_IOK)) {	# integer
					print pipe val == 1? "1": val == 0? "0": ("i", pack "l", val);
				}
				elsif(svref & B::SVp_POK) {		# string
					_utf8_off(val) if is_utf8(val);
					print pipe "s", pack("l", length val), val;
				}
				elsif(svref & B::SVp_NOK) {		# double
					print pipe "n", pack "d", val;
				}
				else {	die "Значение неизвестного типа ".Devel::Peek::Dump(val)." val=`val`" }
			}
		}
		
		return self;
	}

	# считывает структуру из потока ввода
	def unpack {
		(self) = @_;
		pipe = self.{r};
		
		objects = self.[objects};
		(@is, len, arr, hash, key, val, replace_arr);
		ret = [];
		@st = [ret, 0, 0, 1];

		while(@st) {
			(arr, hash, key, len) = @{pop @st};

			while(len--) {

				read pipe, _, 1 or die "Оборван поток ввода. !";
				
				if(_ eq "h") {
					die "Не 4 байта считано. !" if 4 != read pipe, _, 4;
					num = unpack "l", _;
					val = is[num];
				}
				elsif(_ eq "H") { replace_arr = 1; val = {} }
				elsif(_ eq "A") { replace_arr = 0; val = []; }
				elsif(_ eq "S") {
					die "Не 4 байта считано. !" if 4 != read pipe, _, 4;
					val = objects.{unpack "l", _};
				}
				elsif(_ eq "B") {
					die "Не 4 байта считано. !" if 4 != read pipe, _, 4;
					val = self.stub(unpack "l", _);
				}
				elsif(_ eq "T") { val = utils::boolean::true }
				elsif(_ eq "F") { val = utils::boolean::false }
				elsif(_ eq "U") { val = undef }
				elsif(_ eq "1") { val = 1 }
				elsif(_ eq "0") { val = 0 }
				elsif(_ eq "i") {
					die "Не 4 байта считано. !" if 4 != read pipe, _, 4;
					val = unpack "l", _;
				}
				elsif(_ eq "n") {		# double
					die "Не 8 байт считано. !" if 8 != read pipe, _, 8;
					val = unpack "d", _;
				}
				elsif(_ eq "s") {		# string
					die "Не 4 байта считано. !" if 4 != read pipe, _, 4;
					n = unpack "l", _;
					die "Не n байт считано. !" if n != read pipe, val, n;
				}
				
				if(hash) {
					if(len % 2) { key = val }
					else { arr.{key} = val }
				}
				else { push @arr, val }
				
				if(defined replace_arr) {
					push @st, [arr, hash, key, len];
					push @is, arr = val;
					die "Не 4 байта считано. !" if 4 != read pipe, _, 4;
					(hash, len) = (replace_arr, (replace_arr+1) * unpack "l", _);
					replace_arr = undef;
				}
				
			}
		}
		
		return ret.[0];
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

	
	# превращает в json и сразу отправляет. Объекты складирует в self->objects
	def pack(cmd, data)
		pipe = @w
		
		ret = [data]
		st = [ret]
		
		until st.length==0
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
		
		$stderr.puts "#{@role} -> #{cmd} #{JSON.dump(data)} #{@erase.to_s}\n" if @warn == 1
		
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
		
		until st.length == 0
			ls = st.pop

			if ls.instance_of? Hash
				for i, val in ls
					if val[@stub] != nil
						ls[i] = self.stub(val[@stub])
					elsif val[@bless] != nil 
						ls[i] = @objects[val[@bless]]
					elsif [Hash, Array].include? val
						st.push val
					end
				end
			else
				for i, val in (0..ls.length - 1).to_a.zip(ls)
					st.push val if [Hash, Array].include? val
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
		
		while true	# клиент послал запрос
			if pipe.eof?
				if @warn == 1
					$stderr.puts "#{@role} closed: #{caller.join("\n")}\n"
				end
				return	# закрыт
			end
			ret = pipe.readline.rstrip
			arg = pipe.readline.rstrip
			nums = pipe.readline.rstrip
			argnums = nums.split(",")
			args = self.unpack(arg)

			
			if @warn == 1
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
	
	def [](key)
		self.rpc.pack("get #{@num}", [key]).ret
	end
	
	def [](key, val)
		self.rpc.pack("set #{@num}", [key, val]).ret
	end

	
end

class RPCException < RuntimeError
end