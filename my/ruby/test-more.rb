#coding: utf-8

$TestsRun = 0
$TestsFailed = 0
$TestsPlan = -1

at_exit do
	diag("Looks like you failed #{$TestsFailed} test of #{$TestsRun}.") if $TestsFailed != 0
	diag("Looks like you planned #{$TestsPlan} tests but ran #{$TestsRun}.") if $TestsPlan != $TestsRun
end

def plan(n)
	$TestsPlan = n
	puts "1..#{n}"
end

def diag(*av)
	$stderr.puts "# #{av.join("\n# ")}"
end

def ok(cond, msg = nil)
	$TestsRun += 1
	msg = "#{$TestsRun}#{if msg then " - #{msg}" else '' end}"
	if cond
		puts "ok #{msg}"
	else
		$TestsFailed += 1
		puts "not ok #{msg}"
	end
end


def pass(msg = nil)
	ok(true, name)
end

def fail(msg = nil)
	ok(false, name)
end

def is(a, b, msg = nil)
	cond = a==b
	ok(cond, msg)
	if not cond
		diag("         got: '#{data_dumper(a)}'",
             "    expected: '#{data_dumper(b)}'")
	end
end

def isnt(a, b, msg = nil)
	cond = a!=b
	ok(cond, msg)
	if not cond
		diag("         got: '#{a}'",
             "    expected: '#{b}'")
	end
end

def like(a, b, msg = nil)
	cond = b=~a
	ok(cond, msg)
	if not cond
		diag("                  '#{a}'",
             "    doesn't match '#{b}'")
	end
end

def unlike(a, b, msg = nil)
	cond = b=~a
	ok(cond, msg)
	if cond
		diag("                  '#{a}'",
             "    doesn't match '#{b}'")
	end
end

def isa_ok(a, b, msg = nil)
	cond = a.is_a? b
	ok(cond, msg)
	if not cond
		diag("#{a.class.name}->isa(#{b.class.name}) failed")
	end
end

def can_ok(a, b, msg = nil)
	cond = a.respond_to? b
	ok(cond, msg)
	if not cond
		diag("#{a.class.name}->can(#{b}) failed")
	end
end

def data_dumper(a)
	if a.class == Hash
		h = []
		for k, v in a
			h.push "#{k}: #{data_dumper(v)}"
		end
		return "{#{h.join(", ")}}"
	elsif a.class == Array
			h = []
		for i in a
			h.push data_dumper(i)
		end
		return "[#{h.join(", ")}]"
	elsif [Fixnum, String, Float].include? a.class
		return a.to_s.force_encoding(Encoding::UTF_8)
	else
		return "#{a.class.name}=0x#{a.object_id.to_s(16)}"
	end
end
