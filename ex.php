<?php

$data = array(array(30, 40, array(50, 60, array('bless'=>44), 7), 8, 9), r=>array('bless'=>22));

$st = array(&$data);

for($i=0; $st; $i++) {
	$val = &$st[$i];
	echo "$i. $val ".print_r($st, true);
	
	if(isset($val['bless'])) $val = 10;
	else foreach($val as &$x) if(is_array($x)) $st []= &$x;
	
	unset($st[$i]);
}

print_r($data);