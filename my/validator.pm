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


sub email {	$@ = "Это не e-mail" unless $_[0] =~ m![\w\x80-\xFF]+\@(?:[a-z0-9\-\x80-\xFF]+\.)+[a-z\x80-\xFF]+!i }
sub passwd { $@ = "пароль должен быть не менее 6 и не более 32 символов" unless $_[0] =~ /^.{6,32}\z/ }
sub int { $_[0] = int $_[0] }
sub double { $_[0] += 0 }


1;