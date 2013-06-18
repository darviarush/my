package my;

@ISA = qw/Exporter/;
@EXPORT = qw/init/;

sub h ($$&) {
	my $s = [@_];
	$COMMAND{$_[0]} = $s;
	push @COMMAND, $s;
}

h "init", "создаёт окружение", sub {
	require utils;

	mkdir "lib";
	mkdir "page";
	mkdir "script";
	mkdir "t";
	mkdir "tmp";
	mkdir "www";
	
	utils::writeno("my", << 'END');
#!/usr/bin/env perl

use lib "../my";
use lib "lib";

use Carp 'verbose';
$SIG{ __DIE__ } = *Carp::confess;

$\ = "\n";
$" = ", ";
$, = ", ";

$0 =~ m![^/]+$!;
chdir $` if $` ne "";
require "my.pm";
my::run();
END

	chmod 0744, "my";
	
	utils::writeno("ini.pm", << 'END');
package ini;

%server = (							# конфигурация сервера
	port => 3000,
	workers => 3,
	user => 'root',					# пользователь, на которого переключится сервер после запуска
	buf_size => 4*1024*1024,		# размер буфера, для выдачи статики
	host => 'my.cc',
	from => 'noreply@',
	test => 1
);
%DBI = (			# конфигурация базы данных
	DNS => 'dbi:Pg:dbname=my',
	user => 'user1',
	password => '%bLamesh%'	#'siKsta'
);
%session = (
	time_clear => 3600,
	key_length => 20
);
%TEST = (				# конфигурация тестов
	DBI => {			# конфигурация базы данных
		DNS => 'dbi:sqlite:dbname=:memory:',
		user => '',
		password => ''
	}
);
END

	utils::writeno("t/model.t", << 'END');
use Test::More tests => 1;

use Data::Dumper;

use lib "../my";
use lib "lib";

use_ok "model";

model->connect({DSN => "dbi:SQLite:dbname=$dbfile"})->sync;

END

	utils::writeno("t/lib.t", << 'END');
use Test::More tests => 0;

use Data::Dumper;

use lib "../my";
use lib "lib";

END

	utils::writeno("t/pages.t", << 'END');
use Test::More tests => 1;

use Data::Dumper;

use lib "../my";
use lib "lib";

use_ok "pages";

END


	utils::writeno("model.pl", "");

	exit;
};

h "check", "проверка синтаксиса", sub {
	require serv;
};

h "run", "запуск", sub {
	require serv;
};

h "start", "запуск демона", sub {
	$ARGV[0] = "daemon";
	require serv;
};

h "stop", "завершение демона", sub {
	require utils;
	my $pid = utils::read("tmp/serv.pid");
	print("Процесс не запущен\n"), return 0 if !$pid or not kill 0, $pid;
	print("Не могу остановить. $!\n"), return 0 unless kill SIGTERM, $pid;
	return 1;
};

h "restart", "перезапуск демона", sub {
	$COMMAND{stop}->[2]->();
	$COMMAND{start}->[2]->();
};


h "status", "статус запуска", sub {
	require utils;
	require ini;
	$path = "tmp/serv.status";
	$pid = utils::read("tmp/serv.pid");
	unlink $path;
	$is = $pid && kill(0, $pid);
	if($is) {
		use Socket;
		$port = $ini::server{port};
		if($port =~ /^\d+$/) {
			socket sd, PF_INET, SOCK_STREAM, getprotobyname('tcp') or die "socket: $!";
			connect sd, sockaddr_in($port, inet_aton('localhost')) or die "connect: $!";
		} else {
			socket sd, PF_UNIX, SOCK_STREAM, getprotobyname('tcp') or die "socket: $!";
			connect sd, sockaddr_un($port) or die "connect: $!";
		}
		send sd, "OPTIONS * HTTP/1.1\n\n", 0;
		print while <sd>;
		close sd;
	} else {
		print "не запущен";
	}
};

h "sync", "синхронизация базы данных", sub {
	require model;
	model->connect->init("model.pl")->sync_sql();
	print for @model::change;
	print "========================";
	if($ARGV[1]) {
		print(STDERR $_), $model::dbh->do($_) for @model::change;
		print "База синхронизирована";
	} else {
		if(utils::confirm("Применить изменения?")) {
			$model::dbh->do($_) for @model::change;
			print "База синхронизирована";
		}
	}
};

h "gmv", "таблица [путь] [шаблон] - генерирует страницы на основе модели", sub {
	require utils;
	($table, $path, $sample) = @ARGV;
	$path = "pages/".($path // $table);
	$sample = "sam/".($sample // $table);
	utils::read("$sample.pl");
	utils::read("$sample.html");
};

h "gen", "генерирует тестовые данные", sub {
};

h "t", "тесты [-3..1] [файл теста1 ...] - 1-й параметр - verbosity", sub {
	require TAP::Harness;
	chdir "t";
	if($ARGV[1] =~ /^-?\d+$/) {
		$from = 2;
		$verbosity = $ARGV[1];
	} else {
		$from = 1;
		$verbosity = -3;
	}

	my @test = map { my $u = $_; my @t = grep { -e $_ } ($_, map { "$u.$_" } qw(t t.php t.py t.rb)); @t[0] } @ARGV[$from..$#ARGV];
	@test = (<*.t>, <*.t.*>) unless @test;
	my $harness = TAP::Harness->new({
		verbosity => $verbosity,		# -3, 1
		color => 1,
		timer => 1,
		lib => [".", "../../my", "../lib", ".."],
		exec => sub {
			my ( $harness, $test_file ) = @_;
			return [ qw( /usr/bin/env php ), $test_file ] if $test_file =~ /[.]php$/;
			return [ qw( /usr/bin/env python ), $test_file ] if $test_file =~ /[.]py$/;
			return [ qw( /usr/bin/env ruby -w ), $test_file ] if $test_file =~ /[.]rb$/;
			return undef;
		}
	});
	$harness->runtests(@test);
	chdir "..";
};

h "tt", "самоперезапускающиеся тесты", sub {
	require utils;
	#use Term::ANSIColor qw(:constants);
	require Term::ANSIColor;
	
	my @SCRIPT_DIR;
	my %SCRIPT;
	my $run = sub {
		my $param = join " ", @ARGV[1..$#ARGV];
		`my t $param`;
		print Term::ANSIColor::BLACK(). Term::ANSIColor::ON_GREEN(). "\n                 ".
					"   Конец теста   ".
					"                 \n\n". Term::ANSIColor::RESET();
		@SCRIPT_DIR = %SCRIPT = ();
		my $walk = sub { push @SCRIPT_DIR, @_; };
		utils::walk("../my", "ini.pm", "lib", "pages", "t", $walk, $walk);
		$SCRIPT{$_} = -M $_ for @SCRIPT_DIR;
	};
	
	$run->();
	
	for(;;) {
		sleep 1;
		for my $path (@SCRIPT_DIR) {
			my $mtime = $SCRIPT{$path};
			next if $mtime <= -M $path;	# если не изменилось время модификации корневой папки
			$run->();
			last;
		}
	}
	
	
};

h "dist", "архивирование и сохранение", sub {
	chdir "..";
	my $res = $ARGV[1] // 'save';
	
	print `git status`;
	print `git add .`;
	print `git commit -am "$res"`;
	print `git push`;
	#$, = " ";
	#@dir = grep { $_ ne ".my" } <*>;
	#$date = `date '+%F_%T'`;
	#chomp $date;
	#$name = "my.$date.tar.bz2";
	#print "tar /var/bk/$name cfj @dir\n";
	#if(-e "/var/bk") {
#		`tar cfj /var/bk/$name @dir > /dev/null`;
#		`echo my | /usr/local/bin/mutt -a /var/bk/$name -s $name darviarush\@ya.ru > /dev/null`;
#	} else {
#		`tar cfj my.tbz2 @dir > /dev/null`;
#	}
	#require "lib/mailer.pm";
	#use ini;
	#$mailer = maler->new(\%ini{"smtp"});
	#$mailer->send("darviarush\@mail.ru");
#	`/cygdrive/c/sbin/blat/blat.exe -server smtp.mail.ru -f darviarush@mail.ru -u darviarush@mail.ru -pw pol2naqZaschita -to darviarush@mail.ru -subject "Неизвестный В" -body 'hi!' -attach my.tar.bz2`;
};

h "help", "список команд", sub {
	print "$_->[0]\t\t$_->[1]" for @COMMAND;
};

sub run {
	$name = $_[0] // $ARGV[0];
	$x = $COMMAND{$name};
	print("Нет команды `$name`. Воспользуйтесь: my help"), exit unless $x;
	$x->[2]->();
}

sub init {
	run("init");
}

return 1;
