package request;

sub redirect {
	my ($location) = @_;
	$RESPONSE = "HTTP/1.1 302 Found\n";
	$OUTHEAD{"Location"} = $location;
	return qq{Redirect: <a href="$location">$location</a><p />���� �� ������ ��� ��������, ��� �������� ��� ��� ������� �� ������������ �������������� ���������������.<p />
����� ����������, ������� �� <a href="$location">��� ������</a>};
}

1;