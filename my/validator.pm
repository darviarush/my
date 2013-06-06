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
#		fn_ret - функция perl, возвращает message в случае ошибки, или 1 - тогда подставляется message
#		fn_replace - функция, через которую пропускается значение
#		js - код на javascript. x - значение. Может быть изменено.
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
		fn_replace => \&int;
		js_replace => "parseInt"
	},
	double => {
		fn => sub { $_[0]+=0 },
		js => 'x = parseFloat(x); return true'
	}
);

add(%VALIDATOR);

sub add {
	for(my $k = 0; $k<@_; $k+=2) {
		my $name = $k;
		my $u = $_[$k+1];
		
		$VALIDATOR{$name} = $u;
		my $message = $u->{message} // "Нет параметра";
		if($u->{regex}) { 
			$message =~ s/['\\]/\\$&/g;
			eval "sub $name { \$@ = '$message' unless \$_[0] =~ m{$u->{regex}} }";
		}
		elsif($u->{fn}) { *{"validator::$name"}{CODE} = $u->{fn} }
		else {
			die "Нет параметра для валидации. Валидатор `$name`";
		}
	}
}

# генерирует JavaScript-валидаторы
sub add_js {
	
}

1;