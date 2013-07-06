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
	
	// вызывает удалённый метод
	public Variant call(String name, Variant[] args) {
	}
	
	// возвращает удалённое свойство
	public Variant get(String name) {
	}
	
	// устанавливает удалённое свойство
	public Variant set(String name, Variant val) {
	}

	// регистрирует номер заглушки, для сообщения об освобождении памяти
	protected void finalize() throws Throwable {
	}

}


// Вариантный тип
class Variant {
	
	public int toInt() {
		if(this instanceof IntVariant) return ((IntVariant) this).i;
		if(this instanceof StringVariant) return Integer.parseInt(((StringVariant) this).s);
		if(this instanceof DoubleVariant) return (int)((DoubleVariant) this).d;
		if(this instanceof BooleanVariant) return ((BooleanVariant) this).b? 1: 0;

		throw new VariantException("Невозможно сконвертировать в integer");
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
		
		
	}
	
	public double toDouble() {
		if(this instanceof IntVariant)		return (double)((IntVariant) this).i;
		if(this instanceof StringVariant)	return Double.parseFloat(((StringVariant) this).s);
		if(this instanceof DoubleVariant)	return ((DoubleVariant) this).d;
		if(this instanceof BooleanVariant)	return ((BooleanVariant) this).b? 1.0: 0.0;

		throw new VariantException("Невозможно сконвертировать в double");
	}
	
	public boolean toBool() {
		if(this instanceof IntVariant)		return ((IntVariant) this).i != 0;
		if(this instanceof StringVariant)	return ((StringVariant) this).s.length() != 0;
		if(this instanceof DoubleVariant)	return ((DoubleVariant) this).d != 0.0;
		if(this instanceof BooleanVariant)	return ((BooleanVariant) this).b;
		if(this instanceof NullVariant)		return false;
		if(this instanceof ArrayVariant)	return ((ArrayVariant) this).a.length() != 0;
		if(this instanceof HashVariant)		return ((HashVariant) this).h.length() != 0;
		
		throw new VariantException("Невозможно сконвертировать в boolean");
	}
	
	public boolean isInt()		{ return this instanceof IntVariant;		}
	public boolean isString()	{ return this instanceof StringVariant;		}
	public boolean isDouble()	{ return this instanceof DoubleVariant;		}
	public boolean isBool()		{ return this instanceof BooleanVariant;	}
	public boolean isNull()		{ return this instanceof NullVariant;		}
	public boolean isStub()		{ return this instanceof StubVariant;		}
	public boolean isObject()	{ return this instanceof ObjectVariant;		}
	public boolean isArray()	{ return this instanceof ArrayVariant;		}
	public boolean isHash()		{ return this instanceof HashVariant;		}

	// возвращет элемент массива или хеша
	public Variant at(int i) {
		if(this instanceof ArrayVariant) return ((ArrayVariant) this).a[i];
		if(this instanceof HashVariant) return ((HashVariant) this).h[Integer.toString(i)];
		throw new RPCException("Это не массив");
	}
	public Variant at(String i) {
		if(this instanceof HashVariant) return ((HashVariant) this).h[i];
		throw new RPCException("Это не ассоциативный массив");
	}
	public Variant at(Variant i) {
		if(this instanceof ArrayVariant) return ((ArrayVariant) this).a[i];
		if(this instanceof HashVariant) return ((HashVariant) this).h[i];
		throw new RPCException("Это не ассоциативный массив");
	}
	
	// устанавливает элемент массива или хеша
	public Variant put(int i, Variant val) {}
	public Variant put(String i, Variant val) {}
	public Variant put(Variant i, Variant val) {}
	
}

class IntVariant		extends Variant {	public int					i;	public IntVariant(int i)					{ this.i = i; }	}
class StringVariant		extends Variant {	public String				s;	public StringVariant(String s)				{ this.s = s; }	}
class DoubleVariant		extends Variant {	public double				d;	public DoubleVariant(double d)				{ this.d = d; }	}
class BooleanVariant	extends Variant {	public boolean				b;	public BooleanVariant(boolean b)			{ this.b = b; }	}
class NullVariant		extends Variant {																								}
class StubVariant		extends Variant {	public Stub					t;	public StubVariant(Stub t)					{ this.t = t; }	}
class ObjectVariant		extends Variant {	public Object				o;	public ObjectVariant(Object o)				{ this.o = o; }	}
class ArrayVariant		extends Variant {	public Variant[]			a;	public ArrayVariant(Variant[] a = [])		{ this.a = a; }	}
class HashVariant		extends Variant {	public Map<String, Variant>	h;	public HashVariant(Map<String, Variant>	h)	{ this.h = h; }	}


class RPCException extends Exception {}
