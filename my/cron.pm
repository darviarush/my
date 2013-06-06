package cron;
# крон

use threads::shared;
use Data::Dumper;


my @CRON :shared;	# задания

sub add {	# добавляет задание
	my ($interval, $fn) = @_;
	my $y :shared = shared_clone([time + $interval, $interval, $fn]);
	push @CRON, $y;
}

sub run {	# менеджер заданий
	for(;;) {
		sleep 1;
		for my $cron (@CRON) {
			my ($time, $interval, $fn) = @$cron;
			*{$fn}->(), $cron->[0]+=$interval if $time <= time;
		}
	}
}

1;