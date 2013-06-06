package widget;

use utils;

sub run {
	my ($col, $sequence) = @_;
	my $context = bless {col=>$col, sequence=>$sequence}, "widget";
	$col->{widget}->($context);
}

sub id {
	my ($self) = @_;
	my $col = $self->{col};
	($self->{sequence}? "$self->{sequence}-": "")."$col->{model}-$col->{key}"
}

sub label {
	my ($self) = @_;
	"<label for=".$self->id.">".utils::escapeHTML($self->{col}{key})."</label>";
}

sub input {
	my ($self) = @_;
	"<input id=".$self->id." name=".$col->{col}{key}.">";
}

sub error {
	my ($self) = @_;
	"<div class=error id=".$self->id."-error>\$$self->{key}</div>";
}

sub textarea {
	my ($self) = @_;
	"<textarea id=".$self->id."></textarea>";
}


sub by_model_type {
	my ($col) = @_;
	return if defined $col->{widget};
	my $type = $col->{type};
	$col->{widget} = *widget::input;
}

1;