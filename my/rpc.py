#!/usr/bin/env python
# -*- coding: utf-8 -*-


import os, sys, shlex, json

class RPC:

	PROG = {
		"perl": "perl -I'%s' -e 'require rpc; rpc.new'",
		"php": "php -r 'require_once \"%s/rpc.php\"; new rpc();'",
		"python": "",
		"ruby": ""
	}

	# конструктор. Создаёт соединение
	def __init__(self, prog = None):
	
		self.prog = prog
		self.objects = {}
		self.warn = 0
		self.erase = []
		self.wantarray = 1
	
		if prog is None: return self.minor()
		
	
		ch_reader, writer = os.pipe()
		reader, ch_writer = os.pipe()
		
		pid = os.fork()
		
		if pid==0:
			prog = PROG.get(prog, prog)
			prog = prog % (os.path.dirname(__file__) + "/../my")
			if ch_reader != 4: os.dup2(ch_reader, 4)
			if ch_writer != 5: os.dup2(ch_writer, 5)
			args = shlex.split(prog)
			os.execvp(args[0], args[1:])
		
		self.r = os.fdopen(reader, "rb")
		self.w = os.fdopen(writer, "wb")
		self.bless = "\0bless\0"
		self.stub = "\0stub\0"
		self.role = "MAJOR"

	# закрывает соединение
	def close():
		self.w.write("ok\nnull\n")
		self.r.close()
		self.w.close()

	# создаёт подчинённого
	def minor():
		
		self.r = os.fdopen(4, "rb")
		self.w = os.fdopen(5, "wb")
		self.bless = "\0stub\0"
		self.stub = "\0bless\0"
		self.role = "MINOR"

		ret = self.ret()
		
		if self.warn: sys.stderr.write("MINOR ENDED %s\n" % ret)
		return ret

	# превращает в json и сразу отправляет. Объекты складирует в self.objects
	def pack(cmd, data):
		pipe = self.w
		
		ret = [data]
		st = [ret]
		
		while st:
			ls = st.pop()
			for i, val in (enumerate(ls) if isinstance(ls, list) else ls.iteritems()):
				if isinstance(val, RPCstub):
					ls[i] = {self.stub: val.num}
				elif type(val) in ('instance', 'classobj'):
					idx = len(self.objects)
					ls[i] = {self.bless: idx}
					self.objects[idx] = val
				elif isinstance(val, (dict, list)):
					st.append(val)
				elif isinstance(val, tuple):
					ls[i] = val = list(val)
					st.append(val)
		
		data = ret[0]
		
		json = json.dumps(data)
		erase = self.erase.join(",")
		
		if self.warn: sys.stderr.write("%s . `%s` %s %s\n" % (self.role, cmd, json, erase))
		
		pipe.write("cmd\n")
		pipe.write(json)
		pipe.write("\n")
		pipe.write(implode("\n", self.erase)."\n")
		pipe.flush()
		self.erase = []
		return self

	# распаковывает
	def unpack(self, data):

		data = json.loads(data)
		
		ret = [data]
		st = [ret]
		
		while st:
			ls = st.pop()
			for i, val in (enumerate(ls) if isinstance(ls, list) else ls.iteritems()):
				if self.stub in val:
					ls[i] = self.stub(val[self.stub])
				elif self.bless in val: 
					ls[i] = self.objects[val[self.bless]]
				elif isinstance(val, (dict, list)):
					st.append(val)
		
		data = ret[0]
		
		return data

	# вызывает функцию
	def call(self, name, *av):
		return self.pack("call %s %i" % (name, self.wantarray), av).ret()
	}

	# вызывает метод
	def apply(self, cls, name, *av):
		return self.pack("apply %s %s %i" % (cls, name, self.wantarray), av).ret()
	}

	# выполняет код eval eval, args...
	def eval(self, *av):
		return self.pack("eval %i" % self.wantarray, av).ret()
	}

	# устанавливает warn на миноре
	def warn(self, val):
		self.warn = val+=0
		return self.pack("warn", val).ret()
	}

	# удаляет ссылки на объекты из objects
	def erase(self, nums):
		foreach(nums as num) unset(self.objects[num])
	}
	
	# получает и возвращает данные и устанавливает ссылочные параметры
	def ret():
		pipe = self.r
		
		while 1:	# клиент послал запрос
			if pipe.eof():
				if self.warn: sys.stderr.write("%s closed\n" % self.role)
				return		# закрыт

			ret = pipe.readline()[:-1]
			arg = pipe.readline()[:-1]
			nums = pipe.readline()[:-1]
			argnums = nums.split(",")
			args = self.unpack(arg)

			if self.warn: sys.stderr.write("%s <- `%s` %s %s\n" % (self.role, ret, arg, nums));
			
			if ret == "ok":
				self.erase(argnums)
				break
			if ret == "error":
				self.erase(argnums)
				raise RPCException(args)
			
			try:
				arg = ret.split(",")
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
					ret = globals()[arg[1]](*args)
					self.pack("ok", ret)
				elif cmd == "eval":
					ret = eval(args[0])
					self.pack("ok", ret)
				else:
					raise RPCException("Неизвестная команда `cmd`");

			except Exception as e:
				self.pack("error", "%s %s" % (e.__name__, e.message))
			
			self.erase(argnums)

		return args;
	}

	# создаёт заглушку, для удалённого объекта
	def stub(num):
		stub = RPCStub()
		stub.num = num
		stub.rpc = self
		return stub

# заглушка
class RPCstub:
	
	def __getattr__(self, *param, **kv):
		return self.rpc.pack("stub %s %s %i" % (self.num, name, self.rpc.wantarray), param).ret()
		
	def __setattr__(self, *param, **kv):
		return self.rpc.pack("stub %s %s %i" % (self.num, name, self.rpc.wantarray), param).ret()
	
	def __get__(self, key):
		raise RPCException("__get__(%s) not implemented" % key)
	
	def __delattr__(self, name):
		raise RPCException("__delattr__(%s) not implemented" % name)
		
	def __del__(self):
		self.rpc.erase.append(self.num)

class RPCException(Exception):
	pass
