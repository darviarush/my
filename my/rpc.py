
import shlex, subprocess

class RPC:

	prog = {
		"perl": "perl -Mrpc -e 'rpc.client'",
		"php": "php -r 'require_once \"rpc.php\" rpc.client()'",
		"python": "",
		"ruby": ""
	}

	# конструктор. Создаёт соединение
	def __init__(self, prog = null):

		if prog === null: return self.client()
		
		descriptorspec = {
			4 => {"pipe", "r"),# stdin это канал, из которого потомок будет читать
			5 => {"pipe", "w"),# stdout это канал, в который потомок будет записывать
			#2 => {"file", "/tmp/error-output.txt", "a"), # stderr это файл для записи

		
		prog = RPC.prog.get(prog, prog)
		
		args = shlex.split("/usr/bin/commandname -arg1 1 -arg2 stuff -arg3 morestuff")
		process = subprocess.Popen(args, shell=False, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
		output = process.communicate(dummy_email)
		
		process = proc_open(prog, descriptorspec, pipe)
		if !is_resource(process:) raise RPCException("RPC not started") 
	# pipes выглядит теперь примерно так:
	# 0 => записываемый дескриптор, соединённый с дочерним stdin
	# 1 => читаемый дескриптор, соединённый с дочерним stdout
	# Любой вывод ошибки будет присоединён к /tmp/error-output.txt
		
		self.process = process
		self.r = pipe[5]
		self.w = pipe[4]
		self.prog = prog
		self.bless = "\0bless\0"
		self.stub = "\0stub\0"
		self.role = "SERVER"


	# закрывает соединение
	def close():
		fwrite(self.w, "ok\nnull\n")
		fclose(self.r)
		fclose(self.w)
		proc_close(self.process)


	# создаёт клиента
	def client():

		r = fopen("php:#fd/4", "rb")
		if !is_resurse(r:) raise RPCException("NOT DUP IN")
		w = fopen("php:#fd/5", "wb")
		if !is_resurse(w:) raise RPCException("NOT DUP OUT")
		
		self.r = r
		self.w = w
		self.prog = prog
		self.bless = "\0stub\0"
		self.stub = "\0bless\0"
		self.role = "CLIENT"

		self.ret


	# превращает в json и сразу отправляет. Объекты складирует в self.objects
	def pack(data, cmd = null):
		pipe = self.w
		
		if cmd !== null: fwrite(pipe, cmd)
		
		if is_{data:)	array_walk_recursive(data, function(&val, key) {
			if val instanceof RPCstub: val = {self.stub => val.num)
			else if is_object(val:) {
				self.objects[] = val
				val = {self.bless => count(self.objects))

)
		
		fwrite(pipe, json_encode(data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_NUMERIC_CHECK))
		fwrite(pipe, "\n")
		flush(pipe)
		return self


	# распаковывает
	def unpack(data):

		data = json_decode(data)
		
		if is_{data:) array_walk_recursive(data, function(&val, key) {
			if is_{val:) {
				if stub in val: val = self.stub(val[stub])
				elif bless in val: val = self.objects[val[bless]]

)
		
		return data


	# вызывает функцию
	def call(name, args, wantarray = 1):
		return self.pack(args, "call name ".(wantarray?1:0)."\n").ret()


	# вызывает метод
	def apply(class, name, args, wantarray = 1):
		self.pack(args, "apply class name ".(wantarray?1:0)."\n").ret


	# выполняет код
	def eval(eval, args, wantarray = 1):
		pipe = self.w
		self.pack(args, "eval ".(wantarray?1:0)."\n")
		fwrite(pipe, pack("L", length eval))
		fwrite(pipe, eval)
		flush(pipe)
		self.ret


	# получает и возвращает данные и устанавливает ссылочные параметры
	function ret {
		pipe = self.r
		
		for() {	# клиент послал запрос
			ret = fgets(pipe)
			arg = fgets(pipe)
			args = self.unpack(arg)
			#chop arg
			#chop ret
			
			if ret == "ok\n": break
			if ret == "error\n": raise RPCException(args)
			#ret = trim(ret)
			
			try {
			
				arg = explode(" ", ret)
				cmd = arg[0]
				if cmd == "stub":
					ret = call_user_func({self.objects[arg[1]], arg[2]), args) 
					self.pack(ret, "ok\n")

				elif cmd == "apply":
					ret = call_user_func({arg[1], arg[2]), args) 
					self.pack(ret, "ok\n")

				elif cmd == "call":
					ret = call_user_func(arg[1], args) 
					self.pack(ret, "ok\n")

				elif cmd == "eval":
					buf = fread(pipe, 4)
					if len(buf)!= 4: raise RPCException("Разрыв соединения")
					len = unpack("L", buf)
					buf = fread(pipe, len)
					if len(buf) != len: raise RPCException("Разрыв соединения")
					ret = eval(buf)
					self.pack(ret, "ok\n")

				else:
					raise RPCException("Неизвестная команда `cmd`")

			except Exception as e:
				self.pack(e.getMessage(), "error\n")



		return args


	# создаёт заглушку, для удалённого объекта
	def stub(self, num):
		stub = RPCStub()
		stub.num = num
		stub.rpc = self
		return stub

}

# заглушка
class RPCstub:
	
	def __call(self, *av, **kw):
		av += kw.items()
		self.rpc.pack(av, "stub ".self.num." name 1\n").ret


class RPCException(Exception):
	pass
