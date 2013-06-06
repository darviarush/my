use lib "../lib";
use mailer;
$m = mailer->new();
$m->send("root");