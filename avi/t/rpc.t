use Test::More tests => 9;

use Carp 'verbose';
$SIG{ __DIE__ } = *Carp::confess;

use Data::Dumper;
use lib '../../my';
use lib '../lib';

use_ok "rpc";
use_ok "utils";

$rpc = rpc->new("perl");


$a = $rpc->unpack('{"f":["x",1]}');
is_deeply($a, {"f"=>["x",1]});

@A = $rpc->eval('reverse(@$args)', 1,[2,4],{"f"=>"p"},3);
is_deeply(\@A, [3,{"f"=>"p"},[2,4],1]);

$rpc->eval("require Cwd; use Data::Dumper");

$pwd = $rpc->call("Cwd::getcwd");
ok($pwd);

$dump = $rpc->call("Dumper", [1]);
is($dump, "\$VAR1 = [\n          1\n        ];\n");

$rpc->eval("use CGI;");

$cgi = $rpc->apply("CGI", "new");
$h1 = $cgi->h1('hello world');
is($h1, '<h1>hello world</h1>');


$header = $cgi->header;
is($header, "Content-Type: text/html; charset=ISO-8859-1\r\n\r\n");

$header = $cgi->header(-type=>'image/gif',-expires=>'+3d');
like($header, qr/Content-Type: image\/gif/);

$rpc->close;



