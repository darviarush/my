package request;

sub redirect {
	my ($location) = @_;
	$RESPONSE = "HTTP/1.1 302 Found\n";
	$OUTHEAD{"Location"} = $location;
	return qq{Redirect: <a href="$location">$location</a><p />Если вы видите эту страницу, это означает что ваш браузер не поддерживает автоматическое перенаправление.<p />
Чтобы продолжить, нажмите на <a href="$location">эту ссылку</a>};
}

1;