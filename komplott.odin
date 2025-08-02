package main

import "base:runtime"
import "core:bufio"
import "core:bytes"
import "core:fmt"
import "core:io"
import "core:os"
import "core:reflect"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

TQUOTE: string
TLAMBDA: string
TCOND: string
TDEFINE: string
atom_t: ^Object
atom_f: ^Object

Cons :: struct {
	car: ^Object,
	cdr: ^Object,
}

Atom :: string

Builtin :: proc(args: ^Object) -> ^Object

Lambda :: struct {
	args: ^Object,
	body: ^Object,
}

Object :: union {
	Cons,
	Atom,
	Builtin,
	Lambda,
}

interned: strings.Intern
lisp_reader: bufio.Reader

intern_string :: proc(s: string) -> (ret: string, err: runtime.Allocator_Error) #optional_allocator_error {
	ret = strings.intern_get(&interned, s) or_return
	return
}

new_atom :: proc(s: string) -> (ret: ^Object, err: runtime.Allocator_Error) #optional_allocator_error {
	ret = new(Object) or_return
	atom := intern_string(s) or_return
	ret^ = Atom(atom)
	return
}

new_cons :: proc(car, cdr: ^Object) -> (ret: ^Object, err: runtime.Allocator_Error) #optional_allocator_error {
	ret = new(Object) or_return
	ret^ = Cons{car, cdr}
	return
}

env_set :: proc(env, key, value: ^Object) -> (ret: ^Object, err: runtime.Allocator_Error) #optional_allocator_error {
	econs := env.(Cons)
	pair := new_cons(key, value) or_return
	frame := new_cons(pair, econs.car) or_return
	econs.car = frame
	env^ = econs
	ret = env
	return
}

list_find_pair :: proc(needle, haystack: ^Object) -> ^Object {
	haystack := haystack
	for haystack != nil {
		if car(haystack) != nil && lisp_equal(needle, car(car(haystack))) {
			return car(haystack)
		}
		haystack = cdr(haystack)
	}
	return nil
}

env_lookup :: proc(needle, haystack: ^Object) -> ^Object {
	haystack := haystack
	for haystack != nil {
		pair := list_find_pair(needle, car(haystack))
		if pair != nil {
			return cdr(pair)
		}
		haystack = cdr(haystack)
	}
	return nil
}

BuiltinSignature :: proc(^Object) -> ^Object

car :: proc(obj: ^Object) -> ^Object {
	return (obj.(Cons)).car
}

cdr :: proc(obj: ^Object) -> ^Object {
	return (obj.(Cons)).cdr
}


lisp_equal :: proc(a, b: ^Object) -> bool {
	if a == b { return true }
	if a == nil || b == nil || reflect.get_union_variant_raw_tag(a^) != reflect.get_union_variant_raw_tag(b^) {
		return false
	}
	switch av in a^ {
	case Cons:
		return lisp_equal(car(a), car(b)) && lisp_equal(cdr(a), cdr(b))
	case Atom:
		return av == b.(Atom)
	case Builtin:
		return av == b.(Builtin)
	case Lambda:
		return lisp_equal(av.args, (b.(Lambda)).args) && lisp_equal(av.body, (b.(Lambda)).body)
	case:
		return false
	}
}

builtin_car :: proc(args: ^Object) -> ^Object {
	return car(car(args))
}

builtin_cdr :: proc(args: ^Object) -> ^Object {
	return cdr(car(args))
}

builtin_cons :: proc(args: ^Object) -> ^Object {
	return new_cons(car(args), car(cdr(args)))
}

builtin_equal :: proc(args: ^Object) -> ^Object {
	cmp := car(args)
	for args := cdr(args); args != nil; args = cdr(args) {
		if !lisp_equal(cmp, car(args)) {
			return nil
		}
	}
	return atom_t
}

builtin_pair :: proc(args: ^Object) -> ^Object {
	if car(args) != nil {
		_, ok := car(args).(Cons)
		if ok {
			return atom_t
		}
	}
	return nil
}

builtin_null :: proc(args: ^Object) -> ^Object {
	return car(args) == nil ? atom_t : nil
}

builtin_sum :: proc(args: ^Object) -> ^Object {
	return new_atom("0")
}

builtin_sub :: proc(args: ^Object) -> ^Object {
	return new_atom("0")
}

builtin_mul :: proc(args: ^Object) -> ^Object {
	return new_atom("0")
}

builtin_display :: proc(args: ^Object) -> ^Object {
	lisp_print(car(args))
	return nil
}

builtin_newline :: proc(args: ^Object) -> ^Object {
	fmt.println("")
	return nil
}

builtin_read :: proc(args: ^Object) -> ^Object {
	obj, err := lisp_read()
	if err != nil {
		fmt.printf("Error: %v", err)
		return nil
	}
	return obj
}

define_builtin :: proc(env: ^Object, name: string, impl: BuiltinSignature) -> (runtime.Allocator_Error) {
	return nil
}

token_peek: rune = ' '
token_builder: strings.Builder

read_rune :: proc() -> (ret: rune, err: io.Error) {
	r, n := bufio.reader_read_rune(&lisp_reader) or_return
	ret = r
	return
}

is_atomchar :: proc(r: rune) -> bool {
	return (u32(r) >= '!' && u32(r) <= '\'') ||
		(u32(r) >= '*' && u32(r) <= '~') ||
		unicode.is_alpha(r);
}

match_number :: proc(s: string) -> bool {
	start := 0
	if len(s) > 0 && (s[0] == '+' || s[1] == '-') {
		start = 1
	}
	for ch in s[start:] {
		if !unicode.is_digit(ch) {
			return false
		}
	}
	return true
}

read_token :: proc() -> (tok: string, err: io.Error) {
	strings.builder_reset(&token_builder)
	for unicode.is_space(token_peek) {
		token_peek = read_rune() or_return
	}
	if token_peek == '(' || token_peek == ')' {
		strings.write_rune(&token_builder, token_peek)
		token_peek = read_rune() or_return
	}
	else {
		for is_atomchar(token_peek) {
			strings.write_rune(&token_builder, token_peek)
			token_peek = read_rune() or_return
			if strings.builder_len(token_builder) > 256 {
				return "", .EOF
			}
		}
	}
	if token_peek == utf8.RUNE_ERROR {
		return "", .EOF
	}
	tokk, aerr := intern_string(strings.to_string(token_builder))
	if aerr != nil {
		fmt.printf("Error: %v\n", aerr)
		return tokk, .Unknown
	}
	tok = tokk
	return
}

lisp_read_obj :: proc(tok: string) -> (obj: ^Object, err: io.Error) {
	if tok[0] != '(' {
		obj = new_atom(tok)
	} else {
		next := read_token() or_return
		obj = lisp_read_list(next) or_return
	}
	return
}

lisp_read_list :: proc(tok: string) -> (ret: ^Object, err: io.Error) {
	if tok[0] == ')' {
		ret = nil
		return
	}
	obj, obj2, tmp: ^Object = ---, ---, ---
	obj = lisp_read_obj(tok) or_return
	tok := read_token() or_return
	if len(tok) == 1 && tok[0] == '.' {
		tok = read_token() or_return
		tmp = lisp_read_obj(tok) or_return
		obj2 = new_cons(obj, tmp)
		tok = read_token() or_return
		if tok[0] == ')' {
			ret = obj2
			return
		}
		fmt.println("Error: Malformed dotted cons")
		return nil, .Unknown
	}
	tmp = lisp_read_list(tok) or_return
	obj2 = new_cons(obj, tmp)
	ret = obj2
	return
}

lisp_read :: proc() -> (obj: ^Object, err: io.Error) {
	tok := read_token() or_return
	if len(tok) == 0 {
		obj = nil
		return
	}
	if tok[0] != ')' {
		return lisp_read_obj(tok)
	}
	fmt.println("Error: unexpected )")
	return nil, .Unknown
}

atom_text :: proc(atom: ^Object) -> string {
	return atom.(Atom)
}

list_reverse :: proc(lst: ^Object) -> ^Object {
	if lst == nil {
		return nil
	}
	curr: ^Object = lst
	prev: ^Object = nil
	next: ^Object = cdr(lst)
	for curr != nil {
		ccons := curr.(Cons)
		ccons.cdr = prev
		curr^ = ccons
		prev = curr
		curr = next
		if next != nil {
			next = cdr(next)
		}
	}
	return prev
}

lisp_eval :: proc(expr, env: ^Object) -> ^Object {
	expr := expr
	env := env
	restart: for {
		if expr == nil {
			return expr
		}
		_, isatom := expr.(Atom)
		_, iscons := expr.(Cons)
		if isatom {
			if match_number(atom_text(expr)) {
				return expr
			}
			return env_lookup(expr, env)
		}
		if !iscons {
			return expr
		}

		head := car(expr)
		if atom_text(head) == TQUOTE {
			return car(cdr(expr))
		} else if atom_text(head) == TCOND {
			for item := cdr(expr); item != nil; item = cdr(item) {
				cond := car(item)
				if lisp_eval(car(cond), env) != nil {
					expr = car(cdr(cond))
					continue restart
				}
			}
			return nil
		} else if atom_text(head) == TDEFINE {
			name := car(cdr(expr))
			value := lisp_eval(car(cdr(cdr(expr))), env)
			env_set(env, name, value)
			return value
		} else if atom_text(head) == TLAMBDA {
			// turn cdr(expr) into a lambda
			ldata := cdr(expr).(Cons)
			ret := new(Object)
			ret^ = Lambda{ldata.car, ldata.cdr}
			return ret
		}


		fn := lisp_eval(head, env)
		switch tv in fn {
		case Builtin:
			args: ^Object = nil
			for params := cdr(expr); params != nil; params = cdr(params) {
				param := lisp_eval(car(params), env)
				args = new_cons(param, args)
			}
			return tv(list_reverse(args))
		case Lambda:
			callenv := new_cons(nil, env)
			args := tv.args
			for params := cdr(expr); params != nil; params = cdr(params) {
				args = cdr(args)
				param := lisp_eval(car(params), env)
				env_set(callenv, car(args), param)
			}
			item: ^Object = nil
			for item = cdr(fn); item != nil; item = cdr(item) {
				if cdr(item) == nil {
					expr = car(item)
					env = callenv
					continue restart
				}
			}
			lisp_eval(car(item), callenv)
		case Cons, Atom:
			fmt.println("Error: calling non-function as function")
		}
		return nil
	}
}

lisp_print :: proc(obj: ^Object) {
	obj := obj
	if obj == nil {
		fmt.print("()")
		return
	}
	switch v in obj^ {
	case Atom:
		fmt.printf("%s", v)
	case Builtin:
		fmt.printf("<C@%v>", v)
	case Lambda:
		fmt.print("<lambda")
		lisp_print(v.args)
		fmt.print(">")
	case Cons:
		fmt.print("(")
		for {
			lisp_print(v.car)
			if v.cdr == nil {
				break
			}
			fmt.print(" ")
			_, iscons := v.cdr.(Cons)
			if !iscons {
				fmt.print(". ")
				lisp_print(v.cdr)
				break
			}
			obj = v.cdr
		}
		fmt.print(")")
	}
}

intern_names :: proc() -> (err: runtime.Allocator_Error) {
	TQUOTE = intern_string("quote") or_return
	TLAMBDA = intern_string("lambda") or_return
	TCOND = intern_string("cond") or_return
	TDEFINE = intern_string("define") or_return
	return
}

main :: proc() {
	token_builder = strings.builder_make()
	strings.intern_init(&interned)
	defer strings.intern_destroy(&interned)
	intern_names()

	env := new_cons(nil, nil)
	atom_t = new_atom("#t")
	atom_f = new_atom("#f")

	env_set(env, atom_t, atom_t)
	env_set(env, atom_f, nil)

	define_builtin(env, "car", builtin_car);
	define_builtin(env, "cdr", builtin_cdr);
	define_builtin(env, "cons", builtin_cons);
	define_builtin(env, "equal?", builtin_equal);
	define_builtin(env, "pair?", builtin_pair);
	define_builtin(env, "null?", builtin_null);
	define_builtin(env, "+", builtin_sum);
	define_builtin(env, "-", builtin_sub);
	define_builtin(env, "*", builtin_mul);
	define_builtin(env, "display", builtin_display);
	define_builtin(env, "newline", builtin_newline);
	define_builtin(env, "read", builtin_read);

	f: os.Handle
	buffer: [1024]byte

	if len(os.args) > 1 {
		ff, ferr := os.open(os.args[1])
		if ferr != 0 {
			// handle error appropriately
			fmt.println("Error: failed to open file")
			return
		}
		f = ff
		bufio.reader_init_with_buf(&lisp_reader, os.stream_from_handle(f), buffer[:])
	} else {
		bufio.reader_init_with_buf(&lisp_reader, os.stream_from_handle(os.stdin), buffer[:])
	}

	defer os.close(f)
	defer bufio.reader_destroy(&lisp_reader)

	for {
		obj, err := lisp_read()
		if err != nil {
			break
		}
		obj = lisp_eval(obj, env)
		lisp_print(obj)
		fmt.println()
	}
}
