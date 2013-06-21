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
	$self->pack("ok", []);
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
	my ($self, $cmd, $data) = @_;
	local ($,, $\) = ();
	my $pipe = $self->{w};
	my ($so, $flag, @json) = (0, 1);
	
	#s->pack eval 0 
	#c->pack destroy 0 0
	#s-> destroy 0 0 []
	#s->pack ok
	#c-> testok
	
	#warn "$self->{role} pack: `$cmd` $data";#.Dumper($data);
	#print $pipe $cmd if defined $cmd;
	
	utils::walk_data($data, sub {
		my ($ref, $key) = @_;
		push @json, "," if $flag and $so;
		$flag = 1;
		push @json, utils::json_quote($key), ":" if defined $key;
		push @json, $self->json_quote($$ref);
	}, sub {
		my ($ref, $key, $class) = @_;
		push @json, "," if $so++ and $flag;
		push @json, utils::json_quote($key), ":" if defined $key;
		push @json, $class == 0? "[": "{";
		$flag = 0;
	}, sub {
		my ($ref, $key, $class) = @_;
		push @json, $class == 0? "]": "}";
		$so--;
		$flag = 1;
	});
	
	print $pipe $cmd, "\n", @json, "\n";
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
	$self->pack("call $name ".(wantarray?1:0), \@args)->ret;
}

# вызывает метод
sub apply {
	my ($self, $class, $name, @args) = @_;
	$self->pack("apply $class $name ".(wantarray?1:0), \@args)->ret;
}

# выполняет код
sub eval {
	my ($self, @args) = @_;
	$self->pack("eval ".(wantarray?1:0), \@args)->ret;
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
				if($arg3) { @ret = $self->{objects}->{$arg1}->$arg2(@$args); $self->pack("ok", \@ret) }
				else { $self->pack("ok", scalar $self->{objects}->{$arg1}->$arg2(@$args)) }
			}
			elsif($cmd eq "get") {
				$self->pack("ok", $self->{objects}->{$arg1}->{$args->[0]})
			}
			elsif($cmd eq "set") {
				$self->{objects}->{$arg1}->{$args->[0]} = $args->[1];
				$self->pack("ok", 1)
			}
			elsif($cmd eq "destroy") {
				delete $self->{objects}->{$arg1};
				$self->pack("ok", undef);
			}
			elsif($cmd eq "apply") {
				if($arg3) { @ret = $arg1->$arg2(@$args); $self->pack("ok", \@ret) }
				else { $self->pack("ok", scalar $arg1->$arg2(@$args)) }
				die $@ // $! if $@ // $!;
			}
			elsif($cmd eq "call") {
				if($arg2) { @ret = eval $arg1.'(@$args)'; $self->pack("ok", \@ret) }
				else { $self->pack("ok", scalar eval($arg1.'(@$args)')) }
			}
			elsif($cmd eq "eval") {
				my $eval = shift @$args;
				if($arg1) { @ret = eval $eval }
				else { @ret = scalar eval $eval }
				die $@ // $! if $@ // $!;
				$self->pack("ok", $arg1? \@ret: $ret[0]);
			}
			else {
				die "$self->{role} Неизвестная команда `$cmd` `$ret` `$arg`";
			}
		};
		$self->pack("error", $@ // $!) if $@ // $!;
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
	$self->{rpc}->pack("stub $self->{num} $name ".(wantarray?1:0), \@param)->ret;
}

sub DESTROY {
	my ($self, @param) = @_;
	$self = tied %$self;
	$self->{rpc}->pack("destroy $self->{num} ".(wantarray?1:0), \@param)->ret;
}

package rpc::prestub;

use Data::Dumper;

sub send {
	my ($self, $cmd, $args) = @_;
	warn "$cmd=".Dumper($args);
	$self->{rpc}->pack("$cmd $self->{num}", $args)->ret
}

sub TIEHASH { my ($cls, $rpc, $num) = @_; bless {rpc => $rpc, num => $num}, $cls }
sub FETCH { my ($self, $key) = @_; $self->send("get", [$key]) }
sub STORE { my ($self, $key, $val) = @_; $self->send("set", [$key, $val]) }
#sub DELETE { my ($self, $key) = @_; $self->send("del", {key=>$key}) }
#sub CLEAR { my ($self) = @_; $self->send("clear", {}) }
#sub EXISTS { my ($self, $key) = @_; $self->send("in", {key=>$key}) }
#sub SCALAR { my ($self) = @_; $self->send("len", {}) }

#    FIRSTKEY this
#    NEXTKEY this, lastkey
#    DESTROY this
#    UNTIE this
