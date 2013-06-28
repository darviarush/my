#!/usr/bin/env python
# -*- coding: utf-8 -*-


import os, sys, shlex, json
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
	def __init__(self, prog = None):
	
		self.prog = prog
		self.objects = {}
		self.warn = 0
		self._erase = []
		self.wantarray = 1
	
		if prog is None: return self.minor()
		
	
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
		self.bless = "\0bless\0"
		self._stub = "\0stub\0"
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
		self.bless = "\0stub\0"
		self._stub = "\0bless\0"
		self.role = "MINOR"

		ret = self.ret()
		
		if self.warn: sys.stderr.write("MINOR ENDED %s\n" % ret)
		return ret

	# превращает в json и сразу отправляет. Объекты складирует в self.objects
	def pack(self, cmd, data):
		pipe = self.w
		
		ret = [data]
		st = [ret]
		
		while st:
			ls = st.pop()
			for i, val in (enumerate(ls) if isinstance(ls, list) else ls.iteritems()):
				if isinstance(val, Stub):
					ls[i] = {self._stub: val.num}
				elif type(val) in ('instance', 'classobj'):
					idx = len(self.objects)
					ls[i] = {self.bless: idx}
					self.objects[idx] = val
				elif isinstance(val, (dict, list)):
					st.append(val)
				elif isinstance(val, (tuple, Iterator)):
					ls[i] = val = list(val)
					st.append(val)
		
		data = ret[0]
		
		erase = ",".join(self._erase)
		
		if self.warn: sys.stderr.write("%s -> `%s` %s %s\n" % (self.role, cmd, json.dumps(data), erase))
		
		pipe.write("%s\n" % cmd)
		json.dump(data, pipe)
		pipe.write("\n")
		pipe.write(erase+"\n")
		pipe.flush()
		self._erase = []
		return self

	# распаковывает
	def unpack(self, data):

		data = json.loads(data)
		
		ret = [data]
		st = [ret]
		
		while st:
			ls = st.pop()
			for i, val in (enumerate(ls) if isinstance(ls, list) else ls.iteritems()):
				if isinstance(val, list):
					st.append(val)
				elif isinstance(val, dict):
					if self._stub in val:
						ls[i] = self.stub(val[self._stub])
					elif self.bless in val:
						ls[i] = self.objects[val[self.bless]]
					else:
						st.append(val)
		
		data = ret[0]
		
		return data

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
		stub.num = num
		stub.rpc = self
		return stub

# заглушка
class Stub:
	
	def __getattr__(self, name):
		return self.rpc.pack("get %i" % self.num, [name]).ret()
		
	def __setattr__(self, name, val):
		return self.rpc.pack("set %i" % self.num, [name, param]).ret()
	
	def __get__(self, key):
		raise RPCException("__get__(%s) not implemented" % key)
	
	def __delattr__(self, name):
		raise RPCException("__delattr__(%s) not implemented" % name)
		
	def __del__(self):
		self.rpc._erase.append(self.num)

class RPCException(Exception):
	def __init__(self, value):
		self.value = value
	
	def __str__(self):
		print ":", self.value
		return self.value
