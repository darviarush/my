class RPC

	static PROG = array(
		"perl" => "perl -I'%s' -e 'require rpc; rpc->new'",
		"php" => "php -r 'require_once \"%s/rpc.php\"; new rpc();'",
		"python" => "",
		"ruby" => ""
	);

	public r, w, objects, prog, bless, stub, role, process, wantarray = 1, erase = array(), warn = 0;



	# конструктор. Создаёт соединение
	def __construct(prog = null)
	
		if(prog === null) return self->minor();
		
		 = IO::pipe()
		pipe $ch_reader, $writer or die "not create pipe. $!";
		pipe $reader, $ch_writer or die "not create pipe. $!";;
		
		binmode $reader; binmode $writer; binmode $ch_reader; binmode $ch_writer;

		my $stdout = select $in; $| = 1;
		select $writer; $| = 1;
		select $ch_writer; $| = 1;
		select $stdout;
		
		my $pid = fork;
		
		die "fork. $!" if $pid < 0;
		
		if !pid
			$prog = $prog{$prog};
			$prog = sprintf $prog, $INC{'rpc.pm'} =~ /\/rpc.pm$/ && $` if defined $prog;
			my $ch4 = fileno $ch_reader;
			my $ch5 = fileno $ch_writer;
			POSIX::dup2($ch4, 4) if $ch4 != 4;
			POSIX::dup2($ch5, 5) if $ch5 != 5;
			exec $prog or die "Ошибка создания подчинённого. $!";
		end
		
		self->process = process;
		self->r = pipe[5];
		self->w = pipe[4];
		self->prog = prog;
		self->bless = "\0bless\0";
		self->stub = "\0stub\0";
		self->role = "MAJOR";
	end

	# закрывает соединение
	def close() {
		fwrite(self->w, "ok\nnull\n");
		fclose(self->r);
		fclose(self->w);
		proc_close(self->process);
	end

	# создаёт подчинённого
	def minor() {
	
		r = fopen("php://fd/4", "rb");
		if(!r) throw new RPCException("NOT DUP IN");
		w = fopen("php://fd/5", "wb");
		if(!w) throw new RPCException("NOT DUP OUT");
		
		self->r = r;
		self->w = w;
		self->prog = prog;
		self->bless = "\0stub\0";
		self->stub = "\0bless\0";
		self->role = "MINOR";

		ret = self->ret();
		
		if(self->warn) fprintf(STDERR, "MINOR ENDED %s\n", ret);
		return ret;
	end

	# превращает в json и сразу отправляет. Объекты складирует в self->objects
	def pack(cmd, data) {
		pipe = self->w;
		
		fn = def(&val, key) {
			if(val instanceof RPCstub) val = array(self->stub => val->num);
			else if(is_object(val)) {
				self->objects[] = val;
				val = array(self->bless => count(self->objects)-1);
			end
		end;
		
		if(is_array(data)) array_walk_recursive(data, fn);
		else fn(data, 0);
		
		json = json_encode(data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_NUMERIC_CHECK);
		
		if(self->warn) fprintf(STDERR, "%s -> `%s` %s %s\n", self->role, cmd, json, implode(",", self->erase));
		
		fwrite(pipe, "cmd\n");
		fwrite(pipe, json);
		fwrite(pipe, "\n");
		fwrite(pipe, implode("\n", self->erase)."\n");
		flush(pipe);
		self->erase = array();
		return self;
	end

	# распаковывает
	def unpack(data) {

		data = json_decode(data, true);
		
		if(!is_array(data)) return data;
		
		st = array(&data);

		for(i=0; st; i++) {
			val = &st[i];
			
			if(isset(val[self->stub])) val = self->stub(val[self->stub]);
			elseif(isset(val[self->bless])) val = self->objects[val[self->bless]];
			else foreach(val as &x) if(is_array(x)) st []= &x;
			
			unset(st[i]);
		end
		#if(self->warn) fprintf(STDERR, "%s data=%s", self->role, print_r(data, true));
		return data;
	end

	# вызывает функцию
	def call(name) {
		args = func_get_args(); array_shift(args);
		return self->pack("call name ".self->wantarray, args)->ret();
	end

	# вызывает метод
	def apply(class, name) {
		args = func_get_args(); array_shift(args); array_shift(args);
		return self->pack("apply class name ".self->wantarray, args)->ret();
	end

	# выполняет код eval eval, args...
	def _eval() {
		return self->pack("eval ".self->wantarray, func_get_args())->ret();
	end

	# устанавливает warn на миноре
	def warn(val) {
		self->warn = val+=0;
		return self->pack("warn", val)->ret();
	end

	# удаляет ссылки на объекты из objects
	def erase(nums) {
		foreach(nums as num) unset(self->objects[num]);
	end
	
	# получает и возвращает данные и устанавливает ссылочные параметры
	def ret() {
		pipe = self->r;
		
		for(;;) {	# клиент послал запрос
			if(feof(pipe)) {
				if(self->warn) fprintf(STDERR, "%s closed: %s\n", self->role, implode("\n", debug_backtrace()));
				return;	# закрыт
			end
			ret = rtrim(fgets(pipe));
			arg = rtrim(fgets(pipe));
			nums = rtrim(fgets(pipe));
			argnums = explode(",", nums);
			args = self->unpack(arg);

			
			if(self->warn) fprintf(STDERR, "%s <- `%s` %s %s\n", self->role, ret, arg, nums);
			
			if(ret == "ok") { self->erase(argnums); break; }
			if(ret == "error") { self->erase(argnums); throw new RPCException(args); }
			
			try {
			
				arg = explode(" ", ret);
				cmd = arg[0];
				if(cmd == "stub") {
					ret = self.objects[arg[1]].send(arg[2], *args); 
					self->pack("ok", ret);
				end
				else if(cmd == "get") {
					prop = args[0];
					ret = self->objects[arg[1]]->prop; 
					self->pack("ok", ret);
				end
				else if(cmd == "set") {
					prop = args[0];
					self->objects[arg[1]]->prop = args[1];
					self->pack("ok", 1);
				end
				else if(cmd == "warn") {
					self->warn = args;
					self->pack("ok", 1);
				end
				elseif(cmd == "apply") {
					ret = call_user_func_array(array(arg[1], arg[2]), args); 
					self->pack("ok", ret);
				end
				elseif(cmd == "call") {
					ret = call_user_func_array(arg[1], args); 
					self->pack("ok", ret);
				end
				elseif(cmd == "eval") {
					buf = array_shift(args);
					ret = eval(buf);
					if ( ret === false && ( error = error_get_last() ) )
						throw new RPCException("Ошибка в eval: ".error['type']." ".error['message']." at ".error['file'].":".error['line']);

					self->pack("ok", ret);
				end
				else {
					throw new RPCException("Неизвестная команда `cmd`");
				end
			end catch(Exception e) {
				self->pack("error", e->getMessage());
			end
			self->erase(argnums);
		end

		return args;
	end

	# создаёт заглушку, для удалённого объекта
	def stub(num) {
		stub = new RPCStub();
		stub->num = num;
		stub->rpc = self;
		return stub;
	end
end

# заглушка
class RPCstub {
	public num, rpc;
	
	def __call(name, param) {
		return self->rpc->pack("stub ".self->num." name ".self->rpc->wantarray, param)->ret();
	end

	def __callStatic(name, param) {
		return self->rpc->pack("stub ".self->num." name ".self->rpc->wantarray, param)->ret();
	end
	
	def __get(key) {
		return self->rpc->pack("get ".self->num, array(key))->ret();
	end
	
	def __set(key, val) {
		self->rpc->pack("set ".self->num, array(key, val))->ret();
	end
	
	def __destruct() {
		self->rpc->erase[] = self->num;
	end
end

class RPCException extends Exception {}
