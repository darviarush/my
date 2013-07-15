#!/usr/bin/env ruby
#coding: utf-8


require "ruby/test-more.rb"
plan(23)

require "rpc.rb"
require 'stringio'

f = StringIO.new("".encode(Encoding::BINARY), "rb+")
ok(f)

rpc = RPC.new(-1, f, f)


class TestClass1; end; obj1 = TestClass1.new
class TestClass2 < TestClass1; end; obj2 = TestClass2.new
class TestClass_for_stub < TestClass1; end; obj3 = TestClass_for_stub.new

rpc.objects[0] = obj3
stub3 = rpc.stub(0)

data_x = [1, 3.0, obj1, 4, "1", true]
data = {"f"=> [0, stub3, [data_x], 33.1, {"data_x" => data_x, "obj2" => obj2}, "pp", 33], "g"=> "Привет!"}

rpc.pack(data)

#$_ = $file;
#s/[\x0-\x1f]/ /g;
#print "$_\n";

is(rpc.objects.length, 3)

fsize = f.tell
f.seek(0, 0)

code = f.string
code = code.gsub /[\x0-\x1f]/, ' '
puts code

f.seek(0, 0)

unpack = rpc.unpack

dx2 = unpack["f"][2][0]

ok(dx2 == unpack["f"][4]["data_x"])
isa_ok(dx2[2], RPCstub)
isa_ok(unpack["f"][4]["obj2"], RPCstub)
ok(dx2[5] == true, "dx2[5] == true")
is(unpack["f"][1], obj3)
is(dx2[0], 1)
is(unpack["f"][0], 0, "end")

data_x[2] = dx2[2]
data["f"][1] = obj3
data["f"][2][0] = data_x
data["f"][4]["data_x"] = data_x
data["f"][4]["obj2"] = unpack["f"][4]["obj2"]

is(data, unpack, "end2")


rpc = RPC.new('ruby')

rpc.warn(0)

A = rpc.eval('args.reverse', 1,array(2,4),array("f"=>"p"),3);
is(A, [3,{"f"=>"p"},[2,4],1])


#A = rpc.call('reverse', [1,[2,4],{"f"=>"p"},3)])
#is A, [3, {"f"=>"p"}, [2,4], 1]


begin
	rpc.eval("raise Exception, 'test exception'") 
rescue Exception => e
	msg = e.message
end
like(msg, /test exception/)

class MyClass
	def ex(a, b)
		return a+b+@x10
	end
end
myobj = MyClass.new

ret = rpc.eval("args[0]['x10'] = 10", myobj)
is(ret, 10)
is(myobj.x10, 10)

ret = rpc.eval("args[0]['x10']", myobj)
is(ret, 10)

ret = rpc.eval("args[0].ex args[1], args[2]", myobj, 20, 30)
is(ret, 60)

stub = rpc.eval('class A; def ex(a, b=0); return a+b+@c; end; A.new')
isa_ok(stub, "RPCstub")

stub[c] = 30
is(stub[c], 30)

ret = stub.ex(10)
is(ret, 40)

ret = stub.ex(10, 20)
is(ret, 60, "end3")


rpc.close
