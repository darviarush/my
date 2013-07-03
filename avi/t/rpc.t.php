<?php

require_once dirname(__FILE__)."/../../my/php/test-more-php/Test-More.php";
require_once dirname(__FILE__)."/../../my/rpc.php";

plan(23);

$f = fopen("php://memory", "rb+");
ok($f);

$rpc = new rpc(-1, $f, $f);


class test_class1 { function __tostring(){ return get_class($this); } }; $obj1 = new test_class1();
class test_class2 extends test_class1 {}; $obj2 = new test_class2();
class test_class_for_stub extends test_class1 {}; $obj3 = new test_class_for_stub();

$rpc->objects[0] = $obj3;
$stub3 = $rpc->stub(0);

$data_x = array(1, 3.0, $obj1, 4, "1", true);
$data = array("f"=> array(0, $stub3, array($data_x), 33.1, array("data_x" => $data_x, "obj2" => $obj2), "pp", 33), "g"=> "Привет!");

$rpc->pack($data);

#$_ = $file;
#s/[\x0-\x1f]/ /g;
#print "$_\n";

is(count($rpc->objects), 3);

$unpack = $rpc->unpack();

$dx2 = $unpack["f"][2][0];

is($dx2, $unpack["f"][4]["data_x"]);
is(get_class($dx2[2]), "RPCstub");
is(get_class($unpack["f"][4]["obj2"]), "RPCstub");
ok($dx2[5] === true);
is($unpack["f"][1], $obj3);
is($dx2[0], 1);
is($unpack["f"][0], 0, "end");

/*
$rpc = new rpc('php');

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
*/