#!/usr/bin/env python
# -*- coding: utf-8 -*-

# локаль
import sys
reload(sys)
sys.setdefaultencoding("utf-8")

import os, shlex, json
from collections import Iterator
from struct import pack, unpack

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
			hash = isinstance(arr, dict)
			arr = arr.iteritems() if hash else arr = ( for arr)
			
			for a in arr:
				for val in a:
				
					if isinstance(val, (dict, list, tuple)):
						hash = isinstance(val, dict)
						n = IS.get(val)
						if n is not None:
							pipe.write("h" + pack("l", n))
							continue
						num = len(IS)
						IS[val] = num
						pipe.write(("H" if hash else "A") + pack("l", len(val))
						st.append(arr)
						arr = val
					elif val is True:
						pipe.write("T")
					elif val is False:
						pipe.write("F")
					elif val is None:
						pipe.write("U")
					elif isinstance(val, RPCstub):
						rpc, num = stub.__dict__["rpc.num"]
						pipe.write("S"+pack("l", num))
					elif type(val) is int:	# integer
						pipe.write("1" if val is 1 else "0" if val is 0 else ("i", pack "l", val))
					elif type(val) is str:		# string
						pipe.write("s" + pack("l", len(val)) + val)
					elif type(val) is float:		# double
						pipe.write("n" + pack("d", val))
					else:
						objects = self.objects
						num = len(objects)
						objects[num] = val
						if self.warn >= 2: 
							sys.stderr.write("%s add(%i) =" % (self.role, num) )
							pprint(objects) 
						pipe.write("B"+pack("l", num)
					
					#else:	die "Значение неизвестного типа ".Devel::Peek::Dump(val)." val=`val`"
					
		return self

	# считывает структуру из потока ввода
	def unpack (self):
		pipe = self.r
		
		objects = self.objects
		ret = []
		st = [[ret, 0, 0, 1]]

		while st:
			arr, hash, key, len = st.pop()

			while len--:

				v = pipe.read(1)
				if 1 != len(v): raise RPCException("Не 1 байт считан.")
				
				if ch == "h":
					v = pipe.read(4)
					if 4 != len(v): raise RPCException("Не 4 байта считано.")
					num = unpack("l", v)
					val = IS[num]
				elif ch == "H":	replace_arr = 1; val = {}
				elif ch == "A": replace_arr = 0; val = []
				elif ch == "S":
					v = pipe.read(4))
					if 4 != len(v): raise RPCException("Не 4 байта считано.")
					val = objects[unpack("l", v)]
				elif ch == "B":
					v = pipe.read(4)
					if 4 != len(v): raise RPCException("Не 4 байта считано.")
					val = self.stub(unpack("l", v))
				elif ch == "T": val = True
				elif ch == "F": val = False
				elif ch == "U": val = None
				elif ch == "1": val = 1
				elif ch == "0": val = 0
				elif ch == "i":
					v = pipe.read(4)
					if 4 != len(v): raise RPCException("Не 4 байта считано.")
					val = unpack "l", _
				elif ch == "n":		# double
					v = pipe.read(8)
					if 8 != len(v): raise RPCException("Не 8 байт считано.")
					val = unpack("d", v);
				elif ch == "s":		# string
					v = pipe.read(4)
					if 4 != len(v): raise RPCException("Не 4 байта считано.")
					n = unpack("l", v)
					v = pipe.read(n)
					if n != len(v): raise RPCException("Не %i байта считано." % n)
				
				if hash:
					if len % 2:
						key = val
					else: 
						arr.key = val
				else:
					arr.append(val)
				
				if replace_arr is not None:
					st.append( [arr, hash, key, len] )
					arr = val
					IS.append(arr)
					v = pipe.read(4)
					if 4 != len(v): raise RPCException("Не 4 байта считано.")
					hash, len = replace_arr, (replace_arr+1) * unpack("l", v)
					replace_arr = None
		return ret[0]


	# отправляет команду и получает ответ
	def reply(self, *av):
		if self.warn: sys.stderr.write("%s -> %s %s\n" % (self.role, av))
		self.pack(av).pack(self.nums)
		self.nums = []
		return self.ret()

	# отправляет ответ
	def ok (self, ret, cmd="ok"):
		if self.warn: sys.stderr.write("%s -> %s %s\n" % (self.role, cmd, repr(ret)))
		self.pack([cmd, ret]).pack(self.nums)
		self.nums = []
		return self

	# создаёт экземпляр класса
	def new_instance(self, Class, *av):
		return self.reply("new", Class, av, wantarray)

	# вызывает функцию
	def call(self, name, *av):
		return self.reply("call", name, av, self.wantarray)

	# вызывает метод
	def apply(self, cls, name, *av):
		return self.reply("apply", cls, name, av, self.wantarray)

	# выполняет код eval eval, args...
	def eval(self, evl, *av):
		return self.reply("eval", evl, av, self.wantarray)

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
		
		while 1:	# клиент послал запрос
			try:
				ret = self.unpack()
				nums = self.unpack()
			except EOFError as e:
				if self.warn: sys.stderr.write("%s closed\n" % self.role)
				return		# закрыт

			if self.warn: sys.stderr.write("%s <- %s %s\n" % (self.role, repr(ret), repr(nums)));
			
			if ret == "ok":
				self.erase(nums)
				break
			if ret == "error":
				self.erase(nums)
				raise RPCException(ret)
			
			try:
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
