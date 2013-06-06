#!/usr/bin/perl

# http://www.w3.org/Protocols/HTTP/1.1/draft-ietf-http-v11-spec-01.html

package serv;

use Socket;
use POSIX qw/:sys_wait_h setsid strftime/;
use Time::HiRes qw//;
use Term::ANSIColor qw(:constants);
use threads ('yield',
	'stack_size' => 64*4096,
	'exit' => 'threads_only',
	'stringify');
use threads::shared;

use Data::Dumper;

use model;
use pages;
use cron;
use utils;
use ini;


sub msg ($) { return if $ARGV[0] eq "check"; $TIME = Time::HiRes::time(); $\ = ""; print $_[0].RESET." ... ";  $\ = "\n"; }
sub ok () { return if $ARGV[0] eq "check"; my $t = Time::HiRes::time() - $TIME; $ALLTIME += $t; print GREEN."ok".RESET." $t" }
sub alltime () { return if $ARGV[0] eq "check"; print "всего".CYAN.":".RESET." $ALLTIME\n" }

msg "запуск ".RED."perl";
$TIME = utils::read("tmp/serv.stop") || $^T;
unlink "tmp/serv.stop";
ok;

$user = $ini::server{user};
if($user) {
	if(`id $user` =~ /^uid=(\d+).*?\bgid=(\d+)/) {
		($uid, $gid) = ($1, $2);
		msg "установка пользователя ".RED.$user.RESET." $uid (".RED."uid".RESET.") $gid (".RED."gid".RESET.")";
		POSIX::setuid($uid);
		POSIX::setgid($gid);
	} else {
		msg "Не удаётся определить id пользователя. $!";
	}
	ok;
}

# инициализируем базу
msg "инициализация ".RED."модели";
model->init("model.pl");
ok;


# подгружаем страницы
msg "подгрузка страниц ".RED."pages";
pages::init();
ok;

exit 0 if $ARGV[0] eq "check";	# если просто нужно просто проверить работоспособность - выходим

# создаём сокет
$SERVER_PORT = $ini::server{port};
msg "создание сокета :".RED.$SERVER_PORT;
if($SERVER_PORT =~ /^\d+$/) {
	socket sd, AF_INET, SOCK_STREAM, getprotobyname("tcp") or die "socket: $!\n";
	setsockopt sd, SOL_SOCKET, SO_REUSEADDR, pack("l", 1) or die "setsockopt: $!\n"; # захватываем сокет, если он занят другим процессом
	bind sd, sockaddr_in($SERVER_PORT, INADDR_ANY) or die "bind: $!\n";
	listen sd, SOMAXCONN or die "listen: $!\n";
} else {
	socket sd, PF_UNIX, SOCK_STREAM, 0 or die "socket: $!\n";
	unlink $SERVER_PORT;
	bind sd, sockaddr_un($SERVER_PORT) or die "bind: $!\n";
	listen sd, SOMAXCONN  or die "listen: $!\n";
}
ok;


# ставим слежение за исходниками и перезагрузку в случае их изменения
# рекурсивно просматриваем папки lib, pages и файлы в корне: serv.pl и ini.pm
if($ini::server{test}) {
	msg "установка слежения за исходниками";
	package cron;
	
	my @SCRIPT_DIR :shared = ();
	my $walk = sub { push @SCRIPT_DIR, @_ if $_[0] !~ /^\.#/; };
	utils::walk("../my", "my", "ini.pm", "lib", "page", $walk, $walk);
	
	my %SCRIPT :shared;
	$SCRIPT{$_} = -M $_ for @SCRIPT_DIR;
	
	sub change_code {
		for my $path (@SCRIPT_DIR) {
			my $mtime = $SCRIPT{$path};
			next if $mtime <= -M $path;	# если не изменилось время модификации корневой папки

			`perl $0 check`;
			return -1 if $? != 0;
			package serv;
			print "\n".RED."Перезагружаюсь".GREEN."\t\tM".RESET." $path";
			utils::write("tmp/serv.stop", Time::HiRes::time());
			close sd;
			exec $0, @ARGV;
		}
	}
	package serv;
	cron::add(1, "cron::change_code");
	ok;
}

# процесс-обработчик
sub worker {
	local ($_, $`, $', $1);

	# коннектимся к базе postgres
	model->connect;

	package request;

	use Term::ANSIColor qw(:constants);
	use URI::Escape;

	for(; $paddr = accept ns, *serv::sd; close ns) {
		#($REMOTE_PORT, $iaddr) = sockaddr_in($paddr);
		#$REMOTE_NAME = gethostbyaddr $iaddr, AF_INET;
		#$REMOTE_IP = inet_ntoa($iaddr);

		for(;;) {
			$HTTP = <ns>;
			last unless defined $HTTP; # выходим, если сервер закрыл соединение
			print "";
			$serv::ALLTIME = 0;
			serv::msg("разбор");

			chomp $HTTP;

			my $tid = threads->tid();
			# если это не запрос HTTP - отключаем
			print("$tid: Неверный заголовок HTTP"), last unless $HTTP =~ m!^(\w+) ([^\s\?]*?(\.\w+)?)(?:\?(\S+))? HTTP\/(\d\.\d)\r?$!o;
			($PROTO, $URL, $EXT, $SEARCH, $VERSION) = ($1, $2, $3, $4, $5);

			if($URL eq "*" and $PROTO eq "OPTIONS") {
				@BODY = ("$$ PID\nstack size: ", threads->get_stack_size(), "\n",
					threads->tid(), " main\n",
					map { my $i = threads->list($_); ($i->tid, " $_", ($i->tid()==$cron? " cron": " worker")) } (running, joinable)
				);
				goto NEXT;
			}

			# считываем заголовки
			%HEAD = ();
			/: (.*?)\r?$/ and $HEAD{$`} = $1 while $_ = <ns> and !/^\r?$/;

			# считываем данные
			$CONTENT_LENGTH = $HEAD{"Content-Length"};
			$POST = {};
			read(ns, $POST, $CONTENT_LENGTH), $POST = utils::param($POST) if $CONTENT_LENGTH;

			# настраиваем сессионное подключение (несколько запросов на соединение, если клиент поддерживает)
			$KEEP_ALIVE = (lc $HEAD{Connection} eq 'keep-alive');

			$RESPONSE = "HTTP/1.1 200 OK\n";
			%OUTHEAD = ("Content-Type" => "text/html; charset=utf-8");
			$OUTHEAD{"Connection"} = "keep-alive" if $KEEP_ALIVE;

			my $len;
			if(defined $EXT) {	# статика
				my $path = $URL eq "/"? "www/index.html": "www$URL";
				open $static_file, "<", $path or do {
					@BODY = "$URL: Error ".($!+0).": $! ", $RESPONSE = "HTTP/1.1 500 Internal Server Error\n", goto NEXT if $! != 2;
					$RESPONSE = "HTTP/1.1 404 Not Found\n"; @BODY = "$URL Not Found"; goto NEXT;
				};
				binmode $static_file;

				$len = -s $static_file;

				package requestTieArray;

				sub TIEARRAY { my $len = (-s $request::static_file) / $ini::server{buf_size}; $len++ if $len > int $len; $len = int $len; bless [$request::static_file, $len], $_[0] }
				sub FETCHSIZE { $_[0]->[1] }
				sub FETCH { my ($self, $i) = @_; my $buf; seek $self->[0], $i*$ini::server{buf_size}, 0; read $self->[0], $buf, $ini::server{buf_size}; $buf }
				sub CLEAR { untie @request::BODY }	# @POST = (); уничтожит
				sub DESTROY { close $_[0]->[0] }

				package request;

				tie @BODY, requestTieArray;
				goto NEXT;
			}


			# парсим параметры
			$GET = utils::param($SEARCH);
			$param = {%$GET, %$POST};
			$cookie = utils::param($HEAD{"Cookie"}, "; ");

			serv::ok();

			# запускаем обработчик запроса
			serv::msg("обработка");
			pages::start($URL);		# устанавливает @BODY

			NEXT:
			serv::ok();

			# отправляем ответ
			serv::msg("ответ");
			unless(defined $len) {
				$len += length $_ for @BODY;
			}
			$OUTHEAD{"Content-Length"} = $len;

			# print не сбрасывает буфера, используем send
			send ns, $RESPONSE, 0;
			send ns, "$a: $b\n", 0 while ($a, $b) = each %OUTHEAD;
			send ns, "\n", 0;
			send ns, $_, 0 for @BODY;

			if($ARGV[0] ne "daemon") {
				serv::ok();
				serv::alltime();

				print $HTTP;
				print MAGENTA.$a.RESET.": ".CYAN.$b.RESET while ($a, $b) = each %HEAD;
				#print while ($a, $b) = each %$param;
				print "";

				chomp $RESPONSE;
				print $RESPONSE;
				print RED."$a".RESET.": ".GREEN."$b" while ($a, $b) = each %OUTHEAD;
				print RESET;
				my $len = 100;
				$\ = "";
				for my $body (@BODY) {
					$len -= length $body;
					if($len < 0) {
						print substr($body, 0, length($body) + $len)."\n".GREEN." ... ".RESET;
						last;
					} else { print $body }
				}
				$\ = "\n";
				print "";
			}

			last unless $KEEP_ALIVE;
		}
		utils::clear_mem("request");	# очищаем память модуля. Только %, @ и $[12~
	}
}

# демонизируемся
if($ARGV[0] eq "daemon") {
	msg "демонизация";
	$pid = fork;
	die "Не могу выполнить fork\n" if $pid<0;
	exit if $pid;	# это родительский процесс - убиваем его
	die "Не удалось отсоединится от терминала\n" if setsid() == -1;
	ok;
	alltime;

	open STDIN, '/dev/null' or die $!;
	open STDOUT, '>/dev/null' or die $!;
	open STDERR, '>/dev/null' or die $!;
}

# создаются потоки-обработчики
msg "создание потоков-обработчиков";
$workers = $ini::server{workers};
for($i = 0; $i < $workers; $i++) {
	threads->create(*worker);
}
ok;

# создаётся крон
msg "создание крона";
$cron = threads->create(*cron::run)->tid();
ok;

# сохраняется pid процесса
msg "сохранение ".RED."pid".RESET;
utils::write("tmp/serv.pid", $$);
ok;

msg "создание ".RED."fifo".RESET." tmp/serv.status";
unlink "tmp/serv.status";
POSIX::mkfifo("tmp/serv.status", 600) or die "невозможно создать FIFO. $!";
ok;


alltime();


# менеджер процессов - восстанавливает завершившиеся процессы
for(;;) {
	sleep 1;
	
	my @joinable = threads->list(threads::joinable);
	for my $thr (@joinable) {		# восстанавливаем завершившиеся процессы
		my $tid = $thr->tid();
		my $error = $thr->error();
		if($tid == $cron) {
			print RED."Завершился крон № $tid\n".RESET."$error";
			$cron = threads->create(*cron::run)->tid();
		} else {
			print RED."Завершился обработчик № $tid\n".RESET."$error";
			threads->create(*worker);
		}
	}
}

return 1;