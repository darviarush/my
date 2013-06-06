use threads ('yield',
'stack_size' => 64*4096,
'exit' => 'threads_only',
'stringify');
use threads::shared;

$x = [10];
share $x;



for($i=0; $i<10; $i++) {
	($th) = threads->create(sub {sleep 1; print "param=@$x\n"; $r = [1, 2]; share $r; push @$x, $r;}, "a", 1);
	#print "tid=`".$th->tid()."`\n";
	$th->join();
}

