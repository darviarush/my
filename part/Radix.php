<?php

class Radix {
	public $val;

	function __construct($n) {
		$this->val = $n;
	}

	// переводит натуральное число в заданную систему счисления
	function to($radix = 62, $sep = '') {
	    $n = $this->val;
	    $x = $y = "";
	    for (; ;) {
	        $y = $n % $radix;
	        if ($y < 10) $k = $y;
	        else if ($y < 36) $k = chr($y + ord("A") - 10);
	        else if ($y < 62) $k = chr($y + ord("a") - 36);
	        else $k = chr($y + 128 - 62);
	        $x = $k . $sep . $x;
	        if (!($n = (int)($n / $radix))) break;
	    }
	    $this->val = $x;
	    return $this;
	}

	// парсит число в указанной системе счисления
	function from($radix = 62) {
	    $s = $this->val;
	    $x = 0;
	    $len = strlen($s);
	    for ($i = 0; $i < $len; $i++) {
	        $a = ord($s[$i]);
	        $x = $x * $radix + $a;
	        if ($a <= ord("9")) $x -= ord("0");
	        else if ($a <= ord("Z")) $x -= ord('A') - 10;
	        else if ($a <= ord('z')) $x -= ord('a') - 36;
	        else $x -= 128 - 62;
	    }
	    $this->val = $x;
	    return $this;
	}

	function len($n) {
		$val = $this->val;
		for($n -= strlen($val); $n>=0; $n--) $val = "0$val";
		$this->val = $val;
		return $this;
	}

	function path($ext) {
		$this->to()->len(6);
		$val = $this->val;
		$len = strlen($val);
		$path = "../banners/".$val[$len-1]."/".$val[$len-2];
		if(!file_exists($path)) {
			@mkdir("../banners/".$val[$len-1]);
			@mkdir($path);
		}
		$path .= "/".$val.".$ext";
		$this->val = $path;
		return $this;
	}

	function url() {
		return Yii::app()->getRequest()->getHostInfo('').substr($this->val, 2);
	}

	function delete() {
		if(!unlink($this->val)) throw CHttpException(500, "Файл ".$this->val." отсутствует на сервере");
		$path = dirname($this->val);
		@rmdir($path);
		@rmdir(dirname($path));
	}
}
