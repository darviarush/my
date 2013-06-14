use Test::More tests => 15;

use Carp 'verbose';
$SIG{ __DIE__ } = *Carp::confess;

use Data::Dumper;
use lib '../../my';
use lib '../lib';

use_ok "rpc";

$rpc = rpc->new("perl");

=pod

$a = $rpc->unpack('{"f":["x",1]}');
is_deeply($a, {"f"=>["x",1]});

@A = $rpc->eval('reverse(@$args)', 1,[2,4],{"f"=>"p"},3);
is_deeply(\@A, [3,{"f"=>"p"},[2,4],1]);

$rpc->eval("require Cwd; use Data::Dumper");

$pwd = $rpc->call("Cwd::getcwd");
ok($pwd);

$dump = $rpc->call("Dumper", [1]);
is($dump, "\$VAR1 = [\n          1\n        ];\n");
=cut
$rpc->eval("use CGI;");
warn "eval xxx use";
$cgi = $rpc->apply("CGI", "new");
warn "objects=".Dumper($rpc->{objects});
warn "dumper=".Dumper($cgi);
$h1 = $cgi->h1('hello world');
is($h1, '<h1>hello world</h1>');


$header = $cgi->header;
is($header, "");

$header = $cgi->header(-type=>'image/gif',-expires=>'+3d');
is($header, "");

$rpc->close;



