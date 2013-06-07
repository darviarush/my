package validator;

@ISA = qw(Exporter);

@EXPORT = qw(valid);


sub valid (@) {
	my ($package) = caller(0);
	
	for(my $i = 0; $i<@_; $i+=2) {
		my ($key, $type) = @_[$i..$i+1];
		my $val = $request::param->{$key};

		my $valid = *{"validator::$key"}{CODE};
		die "Неизвестный тип $_" unless defined $valid;
		$valid->($val);
		die $@ if $@;
		${"${package}::$key"} = $val;
	}
}

# массив с валидаторами
#	валидаторы могут генерировать perl и js
#	Параметры валидаторов:
#		regex - регулярное выражение
#		message - сообщение
#		fn - функция perl, должна установить $@ в сообщение в случае ошибки, может модифицировать 1-й параметр
#		fn_replace - функция, через которую пропускается значение
#		js - код на javascript. a - значение. Может быть изменено. Сообщение об ошибке оставлять в msg
#		js_replace - функция, через которую нужно пропустить значение
#		
%VALIDATOR = (
	email => {
		regex => qr![\w\x80-\xFF]+\@(?:[a-z0-9\-\x80-\xFF]+\.)+[a-z\x80-\xFF]+!i,
		message => "E-Mail должен иметь вид ящик@домен.домен. Исправьте"
	},
	password => {
		regex => qr/^.{6,32}\z/,
		message => "Пароль должен быть не менее 6 и не более 32 символов"
	},
	int => {
		fn_replace => \&int,
		js_replace => "parseInt"
	},
	double => {
		fn => sub { $_[0]+=0 },
		js => 'a = parseFloat(a); msg = true'
	}
);

validator->add(%VALIDATOR);

# добавляет валидаторы в %VALIDATOR
sub add {
	for(my $k = 1; $k<@_; $k+=2) {	# пропускаем класс
		my $name = $_[$k];
		my $v = $_[$k+1];
		
		print STDERR "$name $v $k\n";
		
		$VALIDATOR{$name} = $v;
		my $message = $v->{message} // "Нет параметра";
		my $regex = $v->{regex};
		my $replace = $v->{fn_replace};
		my $fn = $v->{fn};
		if($regex and $replace and $fn) {
			my $adder = sub {
				my ($regex, $replace, $fn, $message) = @_;
				sub {
					$_[0] = $replace->($_[0]);
					$fn->($_[0]);
					$@ = $message unless $_[0] =~ $regex;
				}
			};
			$validator = $adder->($regex, $replace, $fn, $message);
		}
		elsif($regex and $replace) {
			my $adder = sub {
				my ($regex, $replace, $message) = @_;
				sub {
					$_[0] = $replace->($_[0]);
					$@ = $message unless $_[0] =~ $regex;
				}
			};
			$validator = $adder->($regex, $replace, $message);
		}
		elsif($regex and $fn) {
			my $adder = sub {
				my ($regex, $fn, $message) = @_;
				sub {
					$fn->($_[0]);
					$@ = $message unless $_[0] =~ $regex;
				}
			};
			$validator = $adder->($regex, $fn, $message);
		}
		if($replace and $fn) {
			my $adder = sub {
				my ($replace, $fn) = @_;
				sub {
					$_[0] = $replace->($_[0]);
					$fn->($_[0]);
				}
			};
			$validator = $adder->($replace, $fn);
		}
		elsif($fn) { $validator = $fn }
		elsif($replace) {
			my $adder = sub {
				my ($replace) = @_;
				sub { $_[0] = $replace->($_[0]) }
			};
			$validator = $adder->($replace);
		}
		elsif($regex) {
			my $adder = sub {
				my ($regex, $message) = @_;
				sub { $@ = $message unless $_[0] =~ $regex }
			};
			$validator = $adder->($regex, $message);
		}
		else {
			die "Нет параметра для валидации. Валидатор `$name`";
		}
		
		*{"validator::$name"} = $validator;
	}
}

# генерирует JavaScript-валидатор
sub for_js {
	my ($cls, $name) = @_;
	my $v = $VALIDATOR{$name};
	
}

1;