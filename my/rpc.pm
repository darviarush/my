# заглушка
package rpc;

use IPC::Open2;
use Data::Dumper;

use utils;


%prog = (
"perl" => "perl -e 'require \"%s/rpc.pm\"; rpc->new'",
"php" => "php -r 'require_once \"%s/rpc.php\"; new rpc();'",
"python" => "",
"ruby" => ""
);



# конструктор. Создаёт соединение
sub new {
	my ($cls, $prog) = @_;
	
	goto &client unless defined $prog;
	
	#open2 my($reader), my($writer), $prog{$prog} // $prog or die "Ошибка создания канала. $!";
	my ($reader, $ch_writer, $ch_reader, $writer);
	
	pipe $ch_reader, $writer;
	pipe $reader, $ch_writer;
	
	binmode $reader; binmode $writer; binmode $ch_reader; binmode $ch_writer;
	select $reader; $|=1;
	select $writer; $|=1;
	
	unless(fork) {
		require POSIX;
		my $lp = $prog{$prog};
		$prog = sprintf $prog{$prog}, $INC{'rpc.pm'} =~ /\/rpc.pm$/ && $` if defined $lp;
		my $ch4 = fileno $ch_reader;
		my $ch5 = fileno $ch_writer;
		POSIX::dup2($ch4, 4) if $ch4 != 4;
		POSIX::dup2($ch5, 5) if $ch5 != 5;
		exec $prog or die "Ошибка создания канала. $!";
	}
		
	bless {r => $reader, w => $writer, prog => $prog, objects => {}, bless => "\0bless\0", stub => "\0stub\0", role => "SERVER"}, $cls;
}

# закрывает соединение
sub close {
	my ($self) = @_;
	local ($,, $\) = ();
	$self->pack([], "ok\n");
	close $self->{w} or die "Не закрыт поток записи";
	close $self->{r} or die "Не закрыт поток чтения";
}

# создаёт клиента
sub client {
	my ($cls) = @_;
	open my $r, "<&=4" or die "NOT ASSIGN IN: $!";
	open my $w, ">&=5" or die "NOT ASSIGN OUT: $!";
	#open my $r, "<&STDIN" or die "NOT DUP STDIN: $!";
	#open my $w, ">&STDOUT" or die "NOT DUP STDOUT: $!";
	my $self = bless {r => $r, w => $w, objects => {}, bless => "\0stub\0", stub => "\0bless\0", role => "CLIENT"}, $cls;
	select $r; $| = 1;
	select $w; $| = 1;
	#open STDIN, "/dev/null";
	#open STDOUT, "< /dev/null";
	$self->ret;
	#bless($_, 'HASH') for values %{$self->{objects}};
}

# квотирует для передачи
sub json_quote {
	my ($self, $val) = @_;
	if(ref $val eq "rpc::stub") {
		my $stub = tied %$val;
		$val = "{".utils::json_quote($self->{stub}).":$stub->{num}}";
	} elsif(ref $val eq "utils::boolean") {
		$val = "$val";
	} elsif(ref $val) {
		my $objects = $self->{objects};
		my $num = %$objects + 0;
		$objects->{$num} = $val;
		$val = "{".utils::json_quote($self->{bless}).":$num}";
	}
	else { $val = utils::json_quote($val) }
	return $val;
}

# превращает в json и сразу отправляет. Объекты складирует в $self->{objects}
sub pack {
	my ($self, $data, $cmd) = @_;
	local ($,, $\) = ();
	my $pipe = $self->{w};
	my ($so, $flag) = (0, 1);
	
	print $pipe $cmd if defined $cmd;
	
	utils::walk_data($data, sub {
		my ($ref, $key) = @_;
		print $pipe "," if $flag and $so;
		$flag = 1;
		print $pipe utils::json_quote($key), ":" if defined $key;
		print $pipe $self->json_quote($$ref);
	}, sub {
		my ($ref, $key, $class) = @_;
		print $pipe "," if $so++ and $flag;
		print $pipe utils::json_quote($key), ":" if defined $key;
		print $pipe $class == 0? "[": "{";
		$flag = 0;
	}, sub {
		my ($ref, $key, $class) = @_;
		print $pipe $class == 0? "]": "}";
		$so--;
		$flag = 1;
	});
	
	print $pipe "\n";
	return $self;
}

# распаковывает
sub unpack {
	my ($self, $data) = @_;

	$data = utils::from_json($data);
	my $objects = $self->{objects};
	my $bless = $self->{bless};
	my $stub = $self->{stub};
	
	utils::walk_data($data, sub {}, sub {
		my ($ref, $key, $hash) = @_;
		return unless $hash;
		
		my $num;
		my $val = $$ref;
		
		if(defined($num = $val->{$stub})) {
			$$ref = $self->stub($num);
		}
		elsif(defined($num = $val->{$bless})) {
			$$ref = $objects->{$num};
		}		
	});
	
	return $data;
}

# вызывает функцию
sub call {
	my ($self, $name, @args) = @_;
	$self->pack(\@args, "call $name ".(wantarray?1:0)."\n")->ret;
}

# вызывает метод
sub apply {
	my ($self, $class, $name, @args) = @_;
	$self->pack(\@args, "apply $class $name ".(wantarray?1:0)."\n")->ret;
}

# выполняет код
sub eval {
	my ($self, $eval, @args) = @_;
	local ($,, $\) = ();
	my $pipe = $self->{w};
	$self->pack(\@args, "eval ".(wantarray?1:0)."\n");
	print $pipe pack("L", length $eval), $eval;
	$self->ret;
}

# получает и возвращает данные и устанавливает ссылочные параметры
sub ret {
	my ($self) = @_;
	local ($,, $\) = ();
	my $pipe = $self->{r};
	my (@ret, $args);
	
	for(;;) {	# клиент послал запрос
		my $ret = <$pipe>;
		#warn("$self->{role} closed: ".Dumper([caller(1)])), 
		return unless defined $ret;	# закрыт канал
		my $arg = scalar <$pipe>;
		$args = $self->unpack($arg);
		
		#warn "$self->{role} $ret $arg\n";
		
		last if $ret eq "ok\n";
		die $args if $ret eq "error\n";
	
		chop $ret;
		
		eval {
		
			my ($cmd, $arg1, $arg2, $arg3) = split / /, $ret;
			if($cmd eq "stub") {
				if($arg3) { @ret = $self->{objects}->{$arg1}->$arg2(@$args); $self->pack(\@ret, "ok\n") }
				else { $self->pack(scalar $self->{objects}->{$arg1}->$arg2(@$args), "ok\n") }
			}
			elsif($cmd eq "get") {
				$self->pack($self->{objects}->{$arg1}->{$args->{key}}, "ok\n")
			}
			elsif($cmd eq "set") {
				$self->{objects}->{$arg1}->{$args->{key}} = $args->{val};
				$self->pack(1, "ok\n")
			}
			elsif($cmd eq "del") {
				delete $self->{objects}->{$arg1}->{$args->{key}};
				$self->pack(1, "ok\n");
			}
			elsif($cmd eq "clear") {
				%{$self->{objects}->{$arg1}} = ();
				$self->pack(1, "ok\n");
			}
			elsif($cmd eq "in") {
				$self->pack(exists $self->{objects}->{$arg1}->{$args->{key}}, "ok\n")
			}
			elsif($cmd eq "len") {
				$self->pack(%{$self->{objects}->{$arg1}}+0, "ok\n")
			}
			elsif($cmd eq "destroy") {
				delete $self->{objects}->{$arg1};
				$self->pack(undef, "ok\n");
			}
			elsif($cmd eq "apply") {
				if($arg3) { @ret = $arg1->$arg2(@$args); $self->pack(\@ret, "ok\n") }
				else { $self->pack(scalar $arg1->$arg2(@$args), "ok\n") }
				die $@ // $! if $@ // $!;
			}
			elsif($cmd eq "call") {
				if($arg2) { @ret = eval $arg1.'(@$args)'; $self->pack(\@ret, "ok\n") }
				else { $self->pack(scalar eval($arg1.'(@$args)'), "ok\n") }
			}
			elsif($cmd eq "eval") {
				my $buf;
				die "Разрыв соединения" if read($pipe, $buf, 4) != 4;
				my $len = unpack("L", $buf);
				die "Разрыв соединения" if read($pipe, $buf, $len) != $len;
				if($arg1) { @ret = eval $buf }
				else { @ret = scalar eval $buf }
				die $@ // $! if $@ // $!;
				$self->pack($arg1? \@ret: $ret[0], "ok\n");
			}
			else {
				die "$self->{role} Неизвестная команда `$cmd` `$ret` `$arg`";
			}
		};
		$self->pack($@ // $!, "error\n") if $@ // $!;
	}

	return wantarray && ref $args eq "ARRAY"? @$args: $args;
}

# создаёт заглушку, для удалённого объекта
sub stub {
	my ($self, $num) = @_;
	my %x;
	tie %x, "rpc::prestub", $self, $num; 
	bless \%x, "rpc::stub";
}


# заглушка
package rpc::stub;

sub AUTOLOAD {
	my ($self, @param) = @_;
	local ($&, $`, $');
	$AUTOLOAD =~ /\w+$/;
	my $name = $&;
	$self = tied %$self;
	$self->{rpc}->pack(\@param, "stub $self->{num} $name ".(wantarray?1:0)."\n")->ret;
}

sub DESTROY {
	my ($self, @param) = @_;
	$self = tied %$self;
	$self->{rpc}->pack(\@param, "destroy $self->{num} ".(wantarray?1:0)."\n")->ret;
}

package rpc::prestub;

use Data::Dumper;

sub send {
	my ($self, $cmd, $args) = @_;
	warn "$cmd=".Dumper($args);
	$self->{rpc}->pack($args, "$cmd $self->{num}\n")->ret
}

sub TIEHASH { my ($cls, $rpc, $num) = @_; bless {rpc => $rpc, num => $num}, $cls }
sub FETCH { my ($self, $key) = @_;  $self->send("get", {key=>$key}) }
sub STORE { my ($self, $key, $val) = @_; $self->send("set", {key=>$key, val=>$val}) }
sub DELETE { my ($self, $key) = @_; $self->send("del", {key=>$key}) }
sub CLEAR { my ($self) = @_; $self->send("clear", {}) }
sub EXISTS { my ($self, $key) = @_; $self->send("in", {key=>$key}) }
sub SCALAR { my ($self) = @_; $self->send("len", {}) }

#    FIRSTKEY this
#    NEXTKEY this, lastkey
#    DESTROY this
#    UNTIE this
