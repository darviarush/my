package mail;

use MIME::Lite;
use MIME::Base64;


sub subj { "=?utf-8?B?".MIME::Base64::encode($_[0], "")."?=" }

sub send {
	my ($to, $subj, $text) = @_;
	
	my $msg = MIME::Lite->new(
		From    => $ini::server{from},
		To      => $to,
		Subject => subj($subj),
		Type    => 'text/plain; charset=utf-8',
		Data    => $text
	);
	$msg->send();
}

1;