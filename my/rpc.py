#!/usr/bin/env python
# -*- coding: utf-8 -*-

# локаль
import sys
reload(sys)
sys.setdefaultencoding("utf-8")

import os, shlex, json
from collections import Iterator

from pprint import pprint

class RPC:

	PROG = {
		"perl": "perl -I'%s' -e 'require rpc; rpc->new'",
		"php": "php -r 'require_once \"%s/rpc.php\"; new rpc();'",
		"python": "python -c 'import sys; sys.path.append(\"%s\"); from rpc import RPC; RPC()'",
		"ruby": "ruby -I'%s' -e 'require \"rpc.rb\"; RPC.new'"
	}

	# конструктор. Создаёт соединение
	def __init__(self, prog = None, r = None, w = None):
	
		self.prog = prog
		self.objects = {}
		self.warn = 0
		self._erase = []
		self.wantarray = 1
	
		if prog is None: return self.minor()
		
		if prog == -1:
			self.r = r
			self.w = w
			self.role = "TEST"
			return
	
		ch_reader, writer = os.pipe()
		reader, ch_writer = os.pipe()
		
		pid = os.fork()
		
		if pid==0:
			prog = PROG.get(prog, prog)
			prog = prog % (os.path.dirname(RPC.__module__.__file__))
			if ch_reader != 4: os.dup2(ch_reader, 4)
			if ch_writer != 5: os.dup2(ch_writer, 5)
			args = shlex.split(prog)
			os.execvp(args[0], args[1:])
		
		self.r = os.fdopen(reader, "rb")
		self.w = os.fdopen(writer, "wb")
		self.role = "MAJOR"

	# закрывает соединение
	def close(self):
		self.w.write("ok\nnull\n")
		self.r.close()
		self.w.close()

	# создаёт подчинённого
	def minor(self):
		
		self.r = os.fdopen(4, "rb")
		self.w = os.fdopen(5, "wb")
		self.role = "MINOR"

		ret = self.ret()
		
		if self.warn: sys.stderr.write("MINOR ENDED %s\n" % ret)
		return ret

	# превращает в бинарный формат и сразу отправляет. Объекты складирует в this.objects
def pack (self, data):
	IS = {}
	pipe = self.w
	
	st = [[data]]
	
	while st:
		arr = st.pop
		hash = arr.__class__ == dict
		arr = arr.iteritems() if hash else arr = enumerate(arr)
		
		for a in arr:
			
			for val in ([] if hash else a):
			
			if(ref val eq "HASH") {
				pipe.write("h", pack "l", n), next if defined(n = is{val});
				num = keys %is;
				is{val} = num;
				pipe.write("H", pack "l", 0+keys(%val);
				push @st, arr;
				arr = val;
				hash = 1;
			}
			elif(ref val eq "ARRAY") {
				pipe.write("h", pack "l", n), next if defined(n = is{val});
				num = keys %is;
				is{val} = num;
				pipe.write("A", pack "l", 0+@val;
				push @st, arr;
				arr = val;
				hash = 0;
			}
			elif(ref val eq "utils::boolean") {
				pipe.write(val? "T": "F";
			}
			elif(ref val eq "rpc::stub") {
				stub = tied %val;
				pipe.write("S", pack "l", stub.{num};
			}
			elif(ref val) {
				objects = self.{objects};
				num = keys %objects;
				objects.{num} = val;
				warn "self.{role} add(num) =".Dumper(objects) if self.{warn} >= 2;
				pipe.write("B", pack "l", num;
			}
			elif(!defined val) {
				pipe.write("U";	# undef
			}
			elif((svref = svref_2object \val) && ((svref = svref.FLAGS) & B::SVp_IOK)) {	# integer
				pipe.write(val == 1? "1": val == 0? "0": ("i", pack "l", val);
			}
			elif(svref & B::SVp_POK) {		# string
				_utf8_off(val) if is_utf8(val);
				pipe.write("s", pack("l", length val), val;
			}
			elif(svref & B::SVp_NOK) {		# double
				pipe.write("n", pack "d", val;
			}
			else {	die "Значение неизвестного типа ".Devel::Peek::Dump(val)." val=`val`" }
		}
	}
	
	return self;
}

# считывает структуру из потока ввода
def unpack (self):
	pipe = self.{r};
	
	local (_, /) = ();
	
	objects = self.{objects};
	(@is, len, arr, hash, key, val, replace_arr);
	ret = [];
	@st = [ret, 0, 0, 1];

	while(@st) {
		(arr, hash, key, len) = @{pop @st};

		while(len--) {

			pipe.read(1) or die "Оборван поток ввода. !";
			
			if(ch == "h") {
				die "Не 4 байта считано. !" if 4 != pipe.read(4);
				num = unpack "l", _;
				val = is[num];
			}
			elif(ch == "H") { replace_arr = 1; val = {} }
			elif(ch == "A") { replace_arr = 0; val = []; }
			elif(ch == "S") {
				die "Не 4 байта считано. !" if 4 != pipe.read(4);
				val = objects.{unpack "l", _};
			}
			elif(ch == "B") {
				die "Не 4 байта считано. !" if 4 != pipe.read(4);
				val = self.stub(unpack "l", _);
			}
			elif(ch == "T") { val = utils::boolean::true }
			elif(ch == "F") { val = utils::boolean::false }
			elif(ch == "U") { val = undef }
			elif(ch == "1") { val = 1 }
			elif(ch == "0") { val = 0 }
			elif(ch == "i") {
				die "Не 4 байта считано. !" if 4 != pipe.read(4);
				val = unpack "l", _;
			}
			elif(ch == "n") {		# double
				die "Не 8 байт считано. !" if 8 != pipe.read(8);
				val = unpack "d", _;
			}
			elif(ch == "s") {		# string
				die "Не 4 байта считано. !" if 4 != pipe.read(4);
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
				die "Не 4 байта считано. !" if 4 != pipe.read(4);
				(hash, len) = (replace_arr, (replace_arr+1) * unpack "l", _);
				replace_arr = undef;
			}
			
		}
	}
	
	return ret.[0];
}

# отправляет команду и получает ответ
def reply self = shift;
	if self.warn warn "self.{role} . ".Dumper(\@_)
	self.pack(\@_).pack(self.{nums});
	self.{nums} = [];
	self.ret
}

# отправляет ответ
def ok (self, ret, cmd):
	cmd //= "ok";
	warn "self.{role} . ".Dumper([cmd, ret]) if self.{warn};
	self.pack([cmd, ret]).pack(self.{nums});
	self.{nums} = [];
	return self;
}

# создаёт экземпляр класса
def new_instance self = shift;
	class = shift;
	self.reply("new", class, \@_, wantarray);


	# вызывает функцию
	def call(self, name, *av):
		return self.pack("call %s %i" % (name, self.wantarray), av).ret()

	# вызывает метод
	def apply(self, cls, name, *av):
		return self.pack("apply %s %s %i" % (cls, name, self.wantarray), av).ret()

	# выполняет код eval eval, args...
	def eval(self, *av):
		return self.pack("eval %i" % self.wantarray, av).ret()

	# устанавливает warn на миноре
	def warn(self, val):
		val += 0
		self.warn = val
		return self.pack("warn", val).ret()

	# удаляет ссылки на объекты из objects
	def erase(self, nums):
			for num in nums: del self.objects[num]
	
	# получает и возвращает данные и устанавливает ссылочные параметры
	def ret(self):
		pipe = self.r
		
		while 1:	# клиент послал запрос
			try:
				ret = pipe.readline()[:-1]
				arg = pipe.readline()[:-1]
				nums = pipe.readline()[:-1]
			except EOFError as e:
				if self.warn: sys.stderr.write("%s closed\n" % self.role)
				return		# закрыт

			argnums = [i for i in nums.split(",") if i!='']
			args = self.unpack(arg)

			if self.warn: sys.stderr.write("%s <- `%s` %s %s\n" % (self.role, ret, arg, nums));
			
			if ret == "ok":
				self.erase(argnums)
				break
			if ret == "error":
				self.erase(argnums)
				raise RPCException(args)
			
			try:
				arg = ret.split(" ")
				cmd = arg[0]
				if cmd == "stub":
					ret = getattr(self.objects[arg[1]], arg[2])(*args)
					self.pack("ok", ret)
				elif cmd == "get":
					ret = getattr(self.objects[arg[1]], args[0])
					self.pack("ok", ret)
				elif cmd == "set":
					setattr(self.objects[arg[1]], args[0], args[1])
					self.pack("ok", 1)
				elif cmd == "warn":
					self.warn = args
					self.pack("ok", 1)
				elif cmd == "apply":
					ret = getattr(globals()[arg[1]], arg[2])(*args)
					self.pack("ok", ret)
				elif cmd == "call":
					ret = eval(arg[1]+'(*args)')
					self.pack("ok", ret)
				elif cmd == "eval":
					evl = args[0]
					args = args[1:]
					ret = eval(evl)
					self.pack("ok", ret)
				else:
					raise RPCException("Неизвестная команда `%s`" % cmd);

			except BaseException as e:
				self.pack("error", "%s %s" % (e.__class__.__name__, e))
			
			self.erase(argnums)

		return args

	# создаёт заглушку, для удалённого объекта
	def stub(self, num):
		stub = Stub()
		stub.__dict__['rpc.num'] = self, num
		return stub

# заглушка для значения
class StubVal:
	
	def __init__(self, key, stub):
		self.__dict__['key.stub'] = key, stub
	
	def __call__(self, *av):
		rpc, num = self.__dict__['rpc.num']
		return rpc.pack("stub %s %s %i" % (num, key, rpc.wantarray), av).ret()

	def __len__(self):
		
		
	def __lt__(self, other):
			pass
	def __le__(self, other):
			pass
	def __eq__(self, other):
			pass
	def __ne__(self, other):
			pass
	def __gt__(self, other):
			pass
	def __ge__(self, other):
			pass

__str__(self)
__unicode__(self)
__repr__(self)	
object.__cmp__(self, other)
object.__rcmp__(self, other)
object.__hash__(self)

	
# заглушка
class Stub:
		
	def __getattr__(self, name):
		return StubVal(name, self)
		
	def __setattr__(self, name, val):
		return self.rpc.pack("set %i" % self.num, [name, param]).ret()
		
	def __del__(self):
		self.rpc._erase.append(self.num)

class RPCException(Exception):
	def __init__(self, value):
		self.value = value
	
	def __str__(self):
		print ":", self.value
		return self.value
