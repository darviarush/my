<?php

class RPC {

	static $PROG = array(
		"perl" => "perl -I'%s' -e 'require rpc; rpc->new'",
		"php" => "php -r 'require_once \"%s/rpc.php\"; new rpc();'",
		"python" => "python -c 'import sys; sys.path.append(\"%s\"); from rpc import RPC; RPC()'",
		"ruby" => "ruby -I'%s' -e 'require \"rpc.rb\"; RPC.new'"
	);

	public $r, $w, $objects = array(), $prog, $role, $process, $wantarray = 1, $erase = array(), $warn = 0;



	# конструктор. Создаёт соединение
	function __construct($prog = null, $r = null, $w = null) {
	
		$this->prog = $prog;
	
		if($prog === null) return $this->minor();
		if($prog === -1) {
			$this->r = $r;
			$this->w = $w;
			$this->role = "TEST";
			return;
		}
		
		$descriptorspec = array(
			4 => array("pipe", "rb"),	// это канал, из которого потомок будет читать
			5 => array("pipe", "wb"),	// это канал, в который потомок будет записывать
		);
				
		$real_prog = isset(self::$PROG[$prog])? self::$PROG[$prog]: $prog;
		$real_prog = sprintf($real_prog, dirname(__FILE__));
		
		$process = proc_open($real_prog, $descriptorspec, $pipe);
		if(!is_resource($process)) throw new RPCException("RPC not started"); 
	// $pipes выглядит теперь примерно так:
	// 0 => записываемый дескриптор, соединённый с дочерним stdin
	// 1 => читаемый дескриптор, соединённый с дочерним stdout
	// Любой вывод ошибки будет присоединён к /tmp/error-output.txt
		
		$this->process = $process;
		$this->r = $pipe[5];
		$this->w = $pipe[4];
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
		$this->role = "MINOR";

		$ret = $this->ret();
		
		if($this->warn) fprintf(STDERR, "MINOR ENDED %s\n", $ret);
		return $ret;
	}
	
	# превращает в бинарный формат и сразу отправляет. Объекты складирует в $this->objects
	function pack($data) {
	
		function is_assoc($val) {
			if(!is_array($val)) return false;
			return array_keys($val) == range(0, count($val)-1);
		}
	
		$pipe = $this->w;
		
		$is = array();
		$st = array(array(&$data), 0);
		
		while($st) {
			$hash = array_pop($st);
			$arr = &$st[count($st)-1];
			array_pop($st);
			
			echo "arr cur = ".current($arr)."\n";
			
			while(list($key, $val) = each($arr)) {
				
				if($hash) fwrite($pipe, "s".pack("l", strlen($key)).$key);
				
				#foreach(($hash? array($key, $val): array($val)) as $val) {
				
					echo "$key		".gettype($val)."=$val\n";
				
					if(is_array($val)) {
						if($n = in_array($val, $is, true)) fwrite($pipe, "h".pack("l", $n));
						$is[] = $val;
						
						$is_assoc = is_assoc($val);
						
						fwrite($pipe, ($is_assoc? "H": "A").pack("l", count($val)));
						#reset($arr);
						$st []= &$arr;
						$st []= $hash;
						$arr = $val;
						$hash = $is_assoc;
					}
					else if($val === true) fwrite($pipe, "T");
					else if($val === false) fwrite($pipe, "F");
					else if($val === null) fwrite($pipe, "U");
					else if(is_object($val)) {
						if($val instanceof RPCstub) fwrite($pipe, "S".pack("l", $val->__num));
						else {
							$num = count($this->objects);
							$this->objects[$num] = $val;
							if($this->warn >= 2) fwrite(STDERR, $this->role." add($num) =".print_r($objects, true));
							fwrite($pipe, "B".pack("l", $num));
						}
					}
					else if(is_int($val)) fwrite($pipe, $val === 1? "1": $val === 0? "0": "i".pack("l", $val));
					else if(is_string($val)) fwrite($pipe, "s".pack("l", strlen($val)).$val);
					else if(is_float($val)) fwrite($pipe, "n".pack("d", $val));
					else throw new RPCException("Значение неизвестного типа ".var_dump($val)." val=`$val`");
				#}
			}
		}
		
		return $this;
	}

	# считывает структуру из потока ввода
	function unpack() {
		$pipe = $this->r;
		
		$ret = array();
		$st = array(&$ret, 0, 0, 1);

		while($st) {
			$arr = &$st[count($st)-1][0];
			list($tmp, $hash, $key, $len) = array_pop($st);

			while($len--) {

				$_ = fread($pipe, 1); if(!$_) throw new RPCException("Оборван поток ввода.");
				
				if($_ == "h") {
					$_ = fread($pipe, 4); if(strlen($_) != 4) throw new RPCException("Не 4 байта считано.");
					$num = unpack("l", $_);
					$val = $is[$num];
				}
				else if($_ == "H") { $replace_arr = 1; $val = array(); }
				else if($_ == "A") { $replace_arr = 0; $val = array(); }
				else if($_ == "S") {
					$_ = fread($pipe, 4); if(strlen($_) != 4) throw new RPCException("Не 4 байта считано.");
					$val = $this->objects[unpack("l", $_)];
				}
				else if($_ == "B") {
					$_ = fread($pipe, 4); if(strlen($_) != 4) throw new RPCException("Не 4 байта считано.");
					$val = $this->stub(unpack("l", $_));
				}
				else if($_ == "T") $val = true;
				else if($_ == "F") $val = false;
				else if($_ == "U") $val = null;
				else if($_ == "1") $val = 1;
				else if($_ == "0") $val = 0;
				else if($_ == "i") {
					$_ = fread($pipe, 4); if(strlen($_) != 4) throw new RPCException("Не 4 байта считано.");
					$val = unpack("l", $_);
				}
				else if($_ == "n") {		# double
					$_ = fread($pipe, 8); if(strlen($_) != 8) throw new RPCException("Не 8 байт считано.");
					$val = unpack("d", $_);
				}
				else if($_ == "s") {		# string
					$_ = fread($pipe, 4); if(strlen($_) != 4) throw new RPCException("Не 4 байта считано.");
					$n = unpack("l", $_);
					$_ = fread($pipe, $n); if(strlen($_) != $n) throw new RPCException("Не $n байта считано.");
				}
				
				if($hash) {
					if($len % 2) $key = $val;
					else $arr[$key] = $val;
				}
				else $arr[] = $val;
				
				if($replace_arr === null) {
					$st []= array(&$arr, $hash, $key, $len);
					$arr = &$val;
					$is []= &$arr;
					$_ = fread($pipe, 4); if(strlen($_) != 4) throw new RPCException("Не 4 байта считано.");
					$len = ($replace_arr+1) * unpack("l", $_);
					$hash = $replace_arr;
					$replace_arr = null;
				}
				
			}
		}
		
		return $ret[0];
	}

	# отправляет команду и получает ответ
	function reply() {
		$args = func_get_args();
		if($self->warn) fwrite(STDERR, $this->role." -> ".print_r($args, true));
		$self->pack($args)->pack($self->nums);
		$self->nums = array();
		return $self->ret();
	}

	# отправляет ответ
	function ok($ret, $cmd = "ok") {
		if($self->warn) fwrite(STDERR, $self->role." -> ".print_r(array($cmd, $ret), true));
		$self->pack(array($cmd, $ret))->pack($self->nums);
		$self->nums = array();
		return $this;
	}

	
	# создаёт экземпляр класса
	function new_instance($class) {
		$args = func_get_args(); array_shift($args);
		$self->reply("new", $class, $args, $this->wantarray);
	}
	
	# вызывает функцию
	function call($name) {
		$args = func_get_args(); array_shift($args);
		return $this->reply("call", $name, $args, $this->wantarray);
	}

	# вызывает метод
	function apply($class, $name) {
		$args = func_get_args(); array_shift($args); array_shift($args);
		return $this->reply("apply", $class, $name, $args, $this->wantarray);
	}

	# выполняет код eval $eval, $args...
	function _eval() {
		return $this->reply("eval", func_get_args(), $this->wantarray);
	}

	# устанавливает warn на миноре
	function warn($val) {
		$this->warn = $val+=0;
		return $this->reply("warn", $val);
	}

	# удаляет ссылки на объекты из objects
	function erase($nums) {
		foreach($nums as $num) unset($this->objects[$num]);
	}
	
	# получает и возвращает данные и устанавливает ссылочные параметры
	function ret() {
		$pipe = $this->r;
		
		for(;;) {	# клиент послал запрос
			if(feof($pipe)) {
				if($this->warn) fprintf(STDERR, "%s closed: %s\n", $this->role, implode("\n", debug_backtrace()));
				return;	# закрыт
			}
			$ret = $this->unpack();
			$nums = $this->unpack();

			
			if($this->warn) fprintf(STDERR, "%s <- %s %s\n", $this->role, print_r($ret, true), $nums);
			
			$cmd = array_shift($ret);
			
			if($cmd == "ok") { $this->erase($nums); $args = $ret[0]; break; }
			if($cmd == "error") { $this->erase($nums); throw new RPCException($ret[0]); }
			
			try {
			
				if($cmd == "stub") {
					list($num, $name, $args, $wantarray) = $ret;
					$ret = call_user_func_array(array($this->objects[$num], $name), $args); 
					$this->ok($ret);
				}
				else if($cmd == "get") {
					list($num, $key) = $ret;
					$this->ok($this->objects[$num]->$key);
				}
				else if($cmd == "set") {
					list($num, $key, $val) = $ret;
					$this->objects[$num]->$key = $val;
					$this->ok(1);
				}
				else if($cmd == "warn") {
					$this->warn = $ret[0];
					$this->ok(1);
				}
				else if($cmd == "new") {
					list($class, $args, $wantarray) = $ret;
					$ret = new $class($args); 
					$this->ok($ret);
				}
				else if($cmd == "apply") {
					list($class, $name, $args, $wantarray) = $ret;
					$ret = call_user_func_array(array($class, $name), $args); 
					$this->ok($ret);
				}
				else if($cmd == "call") {
					list($name, $args, $wantarray) = $ret;
					$ret = call_user_func_array($name, $args); 
					$this->ok($ret);
				}
				else if($cmd == "eval") {
					list($eval, $args, $wantarray) = $ret;
					$ret = eval($eval);
					if ( $ret === false && ( $error = error_get_last() ) )
						throw new RPCException("Ошибка в eval: ".$error['type']." ".$error['message']." at ".$error['file'].":".$error['line']);

					$this->ok($ret);
				}
				else {
					throw new RPCException("Неизвестная команда `$cmd`");
				}
			} catch(Exception $e) {
				$this->pack($e->getMessage(), "error");
			}
			$this->erase($nums);
		}

		return $args;
	}
	
	# создаёт заглушку
	function stub($num) {
		$stub = new RPCstub;
		$stub->__num = $num;
		$stub->__rpc = $this;
		return $stub;
	}

}

# заглушка
class RPCstub {
	public $__num, $__rpc;
		
	function __call($name, $param) {
		return $this->__rpc->reply("stub", $this->__num, $name, $param, $this->__rpc->wantarray, $param);
	}

	/*static function __callStatic($name, $param) {
		return $this->rpc->pack("stub ".$this->num." $name ".$this->rpc->wantarray, $param)->ret();
	}*/
	
	function __get($key) {
		return $this->__rpc->reply("get", $this->__num, $key);
	}
	
	function __set($key, $val) {
		$this->__rpc->reply("set", $this->__num, $key, $val);
	}
	
	function __destruct() {
		$this->__rpc->erase[] = $self->__num;
	}
	
	function __toString() {
		return "RPCstub(".$this->__num.")";
	}
}

class RPCException extends Exception {}
