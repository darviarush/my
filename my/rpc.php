<?php

class RPC {

	static $PROG = array(
		"perl" => "perl -e 'require \"%s/rpc.pm\"; rpc->new'",
		"php" => "php -r 'require_once \"%s/rpc.php\"; new rpc();'",
		"python" => "",
		"ruby" => ""
	);

	public $r, $w, $objects, $prog, $bless, $stub, $role, $process, $wantarray = 1, $erase = array(), $warn = 0;



	# конструктор. Создаёт соединение
	function __construct($prog = null) {
	
		if($prog === null) return $this->minor();
		
		$descriptorspec = array(
			4 => array("pipe", "r"),// stdin это канал, из которого потомок будет читать
			5 => array("pipe", "w"),// stdout это канал, в который потомок будет записывать
			#2 => array("file", "/tmp/error-output.txt", "a"), // stderr это файл для записи
		);
		
		if(isset(self::$PROG[$prog])) {
			$prog = self::$PROG[$prog];
			$prog = sprintf($prog, dirname(__FILE__)."/../my");
		}
		
		$process = proc_open($prog, $descriptorspec, $pipe);
		if(!is_resource($process)) throw new RPCException("RPC not started"); 
	// $pipes выглядит теперь примерно так:
	// 0 => записываемый дескриптор, соединённый с дочерним stdin
	// 1 => читаемый дескриптор, соединённый с дочерним stdout
	// Любой вывод ошибки будет присоединён к /tmp/error-output.txt
		
		$this->process = $process;
		$this->r = $pipe[5];
		$this->w = $pipe[4];
		$this->prog = $prog;
		$this->bless = "\0bless\0";
		$this->stub = "\0stub\0";
		$this->role = "MAJOR";
	}

	# закрывает соединение
	function close() {
		fwrite($this->w, "ok\nnull\n");
		fclose($this->r);
		fclose($this->w);
		proc_close($this->process);
	}

	# создаёт подчинённого
	function minor() {
	
		$r = fopen("php://fd/4", "rb");
		if(!$r) throw new RPCException("NOT DUP IN");
		$w = fopen("php://fd/5", "wb");
		if(!$w) throw new RPCException("NOT DUP OUT");
		
		$this->r = $r;
		$this->w = $w;
		$this->prog = $prog;
		$this->bless = "\0stub\0";
		$this->stub = "\0bless\0";
		$this->role = "MINOR";

		$this->ret();
	}

	# превращает в json и сразу отправляет. Объекты складирует в $this->objects
	function pack($cmd, $data) {
		$pipe = $this->w;
		
		if(is_array($data))	array_walk_recursive($data, function(&$val, $key) {
			if($val instanceof RPCstub) $val = array($this->stub => $val->num);
			else if(is_object($val)) {
				$this->objects[] = $val;
				$val = array($this->bless => count($this->objects));
			}
		});
		
		$json = json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_NUMERIC_CHECK);
		
		if($this->warn) fprintf(STDERR, "%s -> `%s` %s %s\n", $this->role, $cmd, $json, implode(",", $this->erase));
		
		fwrite($pipe, "$cmd\n");
		fwrite($pipe, $json);
		fwrite($pipe, "\n");
		fwrite($pipe, implode("\n", $this->erase)."\n");
		flush($pipe);
		$this->erase = array();
		return $this;
	}

	# распаковывает
	function unpack($data) {

		$data = json_decode($data, true);
		
		if(is_array($data)) array_walk_recursive($data, function(&$val, $key) {
			if(is_array($val)) {
				if(isset($val[$this->stub])) $val = $this->stub($val[$this->stub]);
				else if(isset($val[$this->bless])) $val = $this->objects[$val[$this->bless]];
			}
		});
		
		return $data;
	}

	# вызывает функцию
	function call($name) {
		$args = func_get_args(); array_shift($args);
		return $this->pack("call $name ".$this->wantarray, $args)->ret();
	}

	# вызывает метод
	function apply($class, $name) {
		$args = func_get_args(); array_shift($args); array_shift($args);
		$this->pack("apply $class $name ".$this->wantarray, $args)->ret;
	}

	# выполняет код evaluate $eval, $args...
	function evaluate() {
		$this->pack("eval ".$this->wantarray, func_get_args())->ret;
	}

	# устанавливает warn на миноре
	function warn($val) {
		$this->warn = $val+=0;
		$this->pack("warn", $val)->ret;
	}

	# удаляет ссылки на объекты из objects
	function erase($nums) {
		foreach($nums as $num) unset($this->objects[$num]);
	}
	
	# получает и возвращает данные и устанавливает ссылочные параметры
	function ret() {
		$pipe = $this->r;
		
		for(;;) {	# клиент послал запрос
			if(feof($pipe)) return;	# закрыт
			$ret = rtrim(fgets($pipe));
			$arg = rtrim(fgets($pipe));
			$nums = rtrim(fgets($pipe));
			$argnums = explode(",", $nums);
			$args = $this->unpack($arg);

			
			if($this->warn) fprintf(STDERR, "%s <- `%s` %s %s\n", $this->role, $ret, $arg, $nums);
			
			if($ret == "ok") { $this->erase($argnums); break; }
			if($ret == "error") { $this->erase($argnums); throw new RPCException($args); }
			
			try {
			
				$arg = explode(" ", $ret);
				$cmd = $arg[0];
				if($cmd == "stub") {
					$ret = call_user_func_array(array($this->objects[$arg[1]], $arg[2]), $args); 
					$this->pack("ok", $ret);
				}
				else if($cmd == "get") {
					$ret = $this->objects[$arg[1]][$args[0]]; 
					$this->pack("ok", $ret);
				}
				else if($cmd == "set") {
					$this->objects[$arg[1]][$args[0]] = $args[1];
					$this->pack("ok", 1);
				}
				else if($cmd == "warn") {
					$this->warn = $args;
					$this->pack("ok", 1);
				}
				elseif($cmd == "apply") {
					$ret = call_user_func_array(array($arg[1], $arg[2]), $args); 
					$this->pack("ok", $ret);
				}
				elseif($cmd == "call") {
					echo $arg[1]." args=".print_r($args, true);
					$ret = call_user_func_array($arg[1], $args); 
					$this->pack("ok", $ret);
				}
				elseif($cmd == "eval") {
					$buf = array_shift($args);
					$ret = eval($buf);
					if ( $ret === false && ( $error = error_get_last() ) )
						throw new RPCException("Ошибка в eval: ".$error['type']." ".$error['message']." ".$error['file'].":".$error['line']);
							
					$this->pack("ok", $ret);
				}
				else {
					throw new RPCException("Неизвестная команда `$cmd`");
				}
			} catch(Exception $e) {
				$this->pack("error", $e->getMessage());
			}
			$this->erase($argnums);
		}

		return $args;
	}

	# создаёт заглушку, для удалённого объекта
	function stub($num) {
		$stub = new RPCStub();
		$stub->num = $num;
		$stub->rpc = $this;
		return $stub;
	}
}

# заглушка
class RPCstub {
	public $num, $rpc;
	
	function __call($name, $param) {
		return $this->rpc->pack("stub ".$this->num, $param)->ret;
	}
	
	function __get($key) {
		return $this->rpc->pack("get ".$this->num, array($key))->ret;
	}
	
	function __set($key, $val) {
		return $this->rpc->pack("set ".$this->num, array($key, $val))->ret;
	}
}

class RPCException extends Exception {}
