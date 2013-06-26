<?php

class Utils {

	function trace() {
		$arr = debug_backtrace();
		foreach($arr as &$x) {
			$args = isset($x["args"])? "(".implode(", ", $x["args"]).")": "";
			$str .= $x["file"].":".$x["line"]." ".$x["class"].$x["type"].$x["function"].$args."\n";
		}
		return $str;
	}
	
}
