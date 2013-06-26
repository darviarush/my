<?php

require_once dirname(__FILE__)."/../../my/php/test-more-php/Test-More.php";
require_once dirname(__FILE__)."/../../my/rpc.php";

plan(23);



$rpc = new rpc('php');

$a = $rpc->unpack('{"f":["x",1]}');
is_deeply($a, array("f"=>["x",1]));

//$rpc->warn(1);

$A = $rpc->_eval('return array_reverse($args);', 1,array(2,4),array("f"=>"p"),3);
is_deeply($A, array(3,array("f"=>"p"),array(2,4),1));


$A = $rpc->call('array_reverse', array(1,array(2,4),array("f"=>"p"),3));
is_deeply($A, array(3,array("f"=>"p"),array(2,4),1));


try { $rpc->_eval("throw new Exception('test exception');"); } catch(Exception $e) { $msg = $e->getMessage(); }
like($msg, '/test exception/');

class myclass {
	function ex($a, $b) { return $a+$b+$this->x10; }
}
$myobj = new myclass();

$ret = $rpc->_eval("return \$args[0]->x10 = 10;", $myobj);
is($ret, 10);
is($myobj->x10, 10);

$ret = $rpc->_eval("return \$args[0]->x10;", $myobj);
is($ret, 10);

$ret = $rpc->_eval("return \$args[0]->ex(\$args[1], \$args[2]);", $myobj, 20, 30);
is($ret, 60);

$stub = $rpc->_eval('class A { public $c; function ex($a, $b=0) { return $a+$b+$this->c; } } return new A();');
isa_ok($stub, "RPCstub");

$stub->c = 30;
is($stub->c, 30);

$ret = $stub->ex(10);
is($ret, 40);

$ret = $stub->ex(10, 20);
is($ret, 60);


$rpc->close();



$rpc = new rpc('perl');

$A = $rpc->_eval('reverse(@$args)', 1,array(2,4),array("f"=>"p"),3);
is_deeply($A, array(3,array("f"=>"p"),array(2,4),1));


$A = $rpc->call('reverse', 1,array(2,4),array("f"=>"p"),3);
is_deeply($A, array(3,array("f"=>"p"),array(2,4),1));

$rpc->wantarray = 0;

try { $rpc->_eval("die 'test exception'"); } catch(Exception $e) { $msg = $e->getMessage(); }
like($msg, '/test exception/');

$myobj = new myclass();

$ret = $rpc->_eval('$args->[0]->{x10} = 10', $myobj);
is($ret, 10);
is($myobj->x10, 10);

$ret = $rpc->_eval('$args->[0]->{x10}', $myobj);
is($ret, 10);

$ret = $rpc->_eval('$args->[0]->ex(@$args[1..$#$args])', $myobj, 20, 30);
is($ret, 60);

$stub = $rpc->_eval('sub A::ex { $_[1]+$_[2]+$_[0]->{c} } bless {}, "A";');
isa_ok($stub, "RPCstub");

$stub->c = 30;
is($stub->c, 30);

$ret = $stub->ex(10);
is($ret, 40);

$ret = $stub->ex(10, 20);
is($ret, 60);


$rpc->close();
