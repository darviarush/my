<?php

require_once dirname(__FILE__)."/../../my/php/test-more-php/Test-More.php";
require_once dirname(__FILE__)."/../../my/rpc.php";

plan(12);


#require_ok(dirname(__FILE__)."/../../my/rpc.php");

$rpc = new rpc("perl");


$a = $rpc->unpack('{"f":["x",1]}');
is_deeply($a, array("f"=>["x",1]));

$A = $rpc->evaluate('reverse(@$args)', 1,array(2,4),array("f"=>"p"),3);
is_deeply($A, array(3,array("f"=>"p"),array(2,4),1));

$A = $rpc->call('reverse', 1,array(2,4),array("f"=>"p"),3);
is_deeply($A, 3,array("f"=>"p"),array(2,4),1);

try { $rpc->evaluate("die 'test exception'"); } catch(Exception $e) {
	like($e->getMessage(), '/test exception/');
}


$rpc->evaluate("require Cwd; use Data::Dumper");

$pwd = $rpc->call("Cwd::getcwd");
ok($pwd);

$dump = $rpc->call("Dumper", array(1));
is($dump, "\$VAR1 = [\n          1\n        ];\n");

$rpc->evaluate("use CGI;");

$cgi = $rpc->apply("CGI", "new");
$h1 = $cgi->h1('hello world');
is($h1, '<h1>hello world</h1>');


$header = $cgi->header;
is($header, "Content-Type: text/html; charset=ISO-8859-1\r\n\r\n");

$header = $cgi->header("-type", 'image/gif', "-expires", '+3d');
like($header, '/Content-Type: image\/gif/');


$ret = $rpc->evaluate("\$args->[0]->call('reverse', 1,2,\@\$args)", $rpc, 4);
is_deeply($ret, array(4,$rpc,2,1));


$rpc->close();