/*************************************************************************************************
 **																								**
 **	Authors:	Lucky, Dart Vader																**
 **	E-Mails:	untodocve@gmail.com, darviarush@mail.ru											**
 **	Site:		???, http://darviarush.narod.ru														**
 **	License:	BSD																				**
 **																								**
 ************************************************************************************************/


// http://www.quizful.net/post/java-reflection-api

package my.rpc;

import java;

class RPC {
}

// заглушка
class Stub {
	
	public RPC rpc;
	public int num;
	
	public Stub(RPC rpc, int num) {
		this.rpc = rpc;
		this.num = num;
	}
	
	
	public Variant call(String name, Variant[] args) {
	}
	

}


// Вариантный тип
class Variant {
	
	public int toInt() {
		// Integer.parseInt("1");
	}
	
	public String toString() {
		if(this instanceof IntVariant) return Integer.toString(((IntVariant) this).i);
		if(this instanceof StringVariant) return ((StringVariant) this).s;
		if(this instanceof DoubleVariant) return Double.toString(((DoubleVariant) this).d);
		if(this instanceof BooleanVariant) return ((BooleanVariant) this).b? 'true': 'false';
		if(this instanceof NullVariant) return 'null';
		if(this instanceof StubVariant) return ((StubVariant) this).t.toString();
		if(this instanceof ObjectVariant) return ((ObjectVariant) this).o.toString();
		if(this instanceof ArrayVariant) {
			Variant[] a = ((ArrayVariant) this).a;
			String[] s = "[";
			for(int i = 0, n = a.length();; i++) { s += a[i].toString(); if(i>=n) break; s += ", "; }
			return s + "]";
		}
		if(this instanceof HashVariant) {
			Map<String, Variant> h = ((HashVariant) this).h;

			String[] s = "{";
			
			//Map<Integer, Integer> map = new HashMap<Integer, Integer>();
			for (Map.Entry<String, Variant> entry : map.entrySet()) s += entry.getKey()+": "+entry.getValue().toString() + ", ";
			
			return s + "}";
		}
		
		//throw new VariantException("Невозможно сконвертировать в строку");
	}
	
	public double toDouble() {}
	public boolean toBool() {}
	public boolean isNull() { return this instanceof NullVariant; }
	
}

class IntVariant		extends Variant {	public int					i;	}
class StringVariant		extends Variant {	public String				s;	}
class DoubleVariant		extends Variant {	public double				d;	}
class BooleanVariant	extends Variant {	public boolean				b;	}
class NullVariant		extends Variant {									}
class StubVariant		extends Variant {	public Stub t;					}
class ObjectVariant		extends Variant {	public Object o;				}
class ArrayVariant		extends Variant {	public Variant[]			a;	}
class HashVariant		extends Variant {	public Map<String, Variant>	h;	}
