package komplodin

import "base:runtime"
import "core:bufio"
import "core:fmt"
import "core:io"
import "core:mem"
import os "core:os/os2"
import "core:strconv"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

HEAP_SIZE :: 16 * mem.Kilobyte
MAX_ROOTS :: 500
MAX_FRAMES :: 50

Cons :: struct { car, cdr: ^Cons }
Tag :: enum u8 { Cell, Fwd, Builtin, Lambda, Symbol, Int }
Builtin :: #type proc(^Cons) -> ^Cons

TQUOTE, TLAMBDA, TCOND, TDEFINE: string
atom_t, atom_f, tospace, fromspace, allocptr: ^Cons
heap: []Cons
roots: [MAX_ROOTS]^^Cons
rootstack: [MAX_FRAMES]uint
roottop, numroots: uint
interned: strings.Intern
lisp_reader: bufio.Reader

intern_string :: proc(s: string) -> string {
	r, err := strings.intern_get(&interned, s)
	if err != nil {
		os.print_error(os.stderr, err, "intern_string")
		runtime.trap()
	}
	return r
}

cons_tag :: proc(cons: ^Cons) -> Tag { return Tag(uintptr(cons.car) & 0x7) }
tagged_cell :: proc(tag: Tag, data: uintptr) -> Cons { return Cons{(^Cons)(uintptr(tag)), (^Cons)(data)} }
symbol_cell :: proc(ln: u32, s: [^]u8) -> Cons { return Cons{(^Cons)((uintptr(ln) << 32) | uintptr(Tag.Symbol)), (^Cons)(rawptr(s))} }
atom_text :: proc(atom: ^Cons) -> string { return strings.string_from_ptr(([^]u8)(rawptr(atom.cdr)), int(u32(uintptr(atom.car) >> 32))) }

new_atom :: proc(s: string) -> (ret: ^Cons) {
	ret = gc_alloc()
	if match_number(s) {
		ret^ = tagged_cell(.Int, uintptr(strconv.atoi(s)))
	} else {
		is := intern_string(s)
		ret^ = symbol_cell(u32(len(is)), raw_data(is))
	}
	return
}

new_number :: proc(n: int) -> (ret: ^Cons) {
	ret = gc_alloc()
	ret^ = tagged_cell(.Int, uintptr(n))
	return
}

new_cons :: proc(car, cdr: ^Cons) -> ^Cons {
	car, cdr := car, cdr
	gc_protect(&car, &cdr)
	defer gc_pop()
	ret := gc_alloc()
	ret^ = Cons{car, cdr}
	return ret
}

env_set :: proc(env, key, value: ^Cons) -> ^Cons {
	env, key, value := env, key, value
	gc_protect(&env, &key, &value)
	defer gc_pop()
	pair := new_cons(key, value)
	frame := new_cons(pair, env.car)
	env^ = Cons{frame, env.cdr}
	return env
}

env_lookup :: proc(needle, haystack: ^Cons) -> ^Cons {
	for cur := haystack; cur != nil; cur = cur.cdr {
		for item := cur.car; item != nil; item = item.cdr {
			if item.car != nil && lisp_equal(needle, item.car.car) {
				return item.car.cdr
			}
		}
	}
	return nil
}

gc_copy :: proc(root: ^^Cons) {
	if root^ == nil {
		return
	} else if cons_tag(root^) == .Fwd {
		root^ = (root^).cdr
	} else if uintptr(root^) >= uintptr(tospace) && \
		uintptr(root^) < uintptr(tospace) + HEAP_SIZE*size_of(Cons) {
		p := allocptr
		allocptr = mem.ptr_offset(allocptr, 1)
		mem.copy_non_overlapping(p, root^, size_of(Cons))
		root^^ = Cons{(^Cons)(uintptr(Tag.Fwd)), p}
		root^ = p
	}
}

gc_collect :: proc() {
	if !gc_full() { return }
	fromspace, tospace = tospace, fromspace
	allocptr = fromspace
	for i :uint = 0; i < numroots; i += 1 { gc_copy(roots[i]) }
	for scanptr := fromspace; scanptr < allocptr; scanptr = mem.ptr_offset(scanptr, 1) {
		#partial switch cons_tag(scanptr) {
		case .Cell:
			gc_copy(&(scanptr.car))
			gc_copy(&(scanptr.cdr))
		case .Lambda:
			gc_copy(&(scanptr.cdr))
		}
	}
	if gc_full() {
		fmt.eprintln("Out of memory")
		runtime.trap()
	}
}

gc_full :: proc() -> bool {
	next_alloc_pos := uintptr(allocptr) + size_of(^Cons)
	space_end := uintptr(fromspace) + HEAP_SIZE * size_of(^Cons)
	return next_alloc_pos >= space_end
}

gc_alloc :: proc() -> (ret: ^Cons) {
	gc_collect()
	ret, allocptr = allocptr, mem.ptr_offset(allocptr, 1)
	return
}

gc_protect :: proc(ptrs: ..^^Cons) {
	rootstack[roottop] = numroots
	roottop += 1
	for p in ptrs {
		roots[numroots] = p
		numroots += 1
	}
}

gc_pop :: proc() {
	roottop -= 1
	numroots = rootstack[roottop]
}

lisp_equal :: proc(a, b: ^Cons) -> bool {
	if a == b { return true }
	if a != nil && b != nil && cons_tag(a) == cons_tag(b) {
		#partial switch cons_tag(a) {
		case .Cell:
			return lisp_equal(a.car, b.car) && lisp_equal(a.cdr, b.cdr)
		case .Symbol:
			return uintptr(a.car) == uintptr(b.car) && rawptr(a.cdr) == rawptr(b.cdr)
		case .Int:
			return int(uintptr(a.cdr)) == int(uintptr(b.cdr))
		case .Builtin:
			return rawptr(a.cdr) == rawptr(b.cdr)
		case .Lambda:
			return lisp_equal(a.cdr, b.cdr)
		}
	}
	return false
}

builtin_car :: proc(args: ^Cons) -> ^Cons { return args.car.car }
builtin_cdr :: proc(args: ^Cons) -> ^Cons { return args.car.cdr }
builtin_cons :: proc(args: ^Cons) -> ^Cons { return new_cons(args.car, args.cdr.car) }

builtin_equal :: proc(args: ^Cons) -> ^Cons {
	args, cmp := args, args.car
	for args = args.cdr; args != nil; args = args.cdr {
		if !lisp_equal(cmp, args.car) {
			return nil
		}
	}
	return atom_t
}

builtin_pair :: proc(args: ^Cons) -> ^Cons {
	return atom_t if args.car != nil && cons_tag(args.car) == .Cell else nil
}

builtin_null :: proc(args: ^Cons) -> ^Cons {
	return atom_t if args.car == nil else nil
}

builtin_sum :: proc(args: ^Cons) -> ^Cons {
	sum :int = 0
	for i := args; i != nil; i = i.cdr {
		sum += int(uintptr(i.car.cdr))
	}
	return new_number(sum)
}

builtin_sub :: proc(args: ^Cons) -> ^Cons {
	sum := int(uintptr(args.car.cdr))
	if args.cdr == nil {
		sum = -sum
	} else {
		for i := args.cdr; i != nil; i = i.cdr {
			sum -= int(uintptr(i.car.cdr))
		}
	}
	return new_number(sum)
}

builtin_mul :: proc(args: ^Cons) -> ^Cons {
	sum :int = 1
	for cur := args; cur != nil; cur = cur.cdr {
		sum *= int(uintptr(cur.car.cdr))
	}
	return new_number(sum)
}

builtin_display :: proc(args: ^Cons) -> ^Cons {
	lisp_print(args.car)
	return nil
}

builtin_newline :: proc(args: ^Cons) -> ^Cons {
	fmt.println("")
	return nil
}

builtin_read :: proc(args: ^Cons) -> ^Cons {
	obj, err := lisp_read()
	if err != nil {
		fmt.eprintfln("Error: %v", err)
		return nil
	}
	return obj
}

BUILTINS :: []struct { name: string, impl: Builtin } {
	{ "car", builtin_car },
	{ "cdr", builtin_cdr },
	{ "cons", builtin_cons },
	{ "equal?", builtin_equal },
	{ "pair?", builtin_pair },
	{ "null?", builtin_null },
	{ "+", builtin_sum },
	{ "-", builtin_sub },
	{ "*", builtin_mul },
	{ "display", builtin_display },
	{ "newline", builtin_newline },
	{ "read", builtin_read },
}

define_builtins :: proc(env: ^Cons) {
	key, val: ^Cons
	env := env
	gc_protect(&key, &val, &env)
	defer gc_pop()

	for def in BUILTINS {
		key, val = new_atom(def.name), gc_alloc()
		val^ = tagged_cell(.Builtin, uintptr(rawptr(def.impl)))
		env_set(env, key, val)
	}
}

token_peek: rune = ' '
token_builder: strings.Builder

read_rune :: proc() -> (ret: rune, err: io.Error) {
	r, _ := bufio.reader_read_rune(&lisp_reader) or_return
	ret = r
	return
}

is_atomchar :: proc(r: rune) -> bool {
	return (u32(r) >= '!' && u32(r) <= '\'') ||
		(u32(r) >= '*' && u32(r) <= '~') ||
		unicode.is_alpha(r)
}

match_number :: proc(s: string) -> bool {
	start := 1 if len(s) > 1 && (s[0] == '+' || s[0] == '-') else 0
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
	} else {
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
	tok = intern_string(strings.to_string(token_builder))
	return
}

lisp_read_obj :: proc(tok: string) -> (obj: ^Cons, err: io.Error) {
	if tok[0] != '(' {
		obj = new_atom(tok)
	} else {
		next := read_token() or_return
		obj = lisp_read_list(next) or_return
	}
	return
}

lisp_read_list :: proc(tok: string) -> (ret: ^Cons, err: io.Error) {
	tok := tok
	if tok[0] == ')' {
		ret = nil
		return
	}
	obj, obj2, tmp: ^Cons
	gc_protect(&obj, &obj2, &tmp)
	defer gc_pop()
	obj = lisp_read_obj(tok) or_return
	tok = read_token() or_return
	if len(tok) == 1 && tok[0] == '.' {
		tok = read_token() or_return
		tmp = lisp_read_obj(tok) or_return
		obj2 = new_cons(obj, tmp)
		tok = read_token() or_return
		if tok[0] == ')' {
			ret = obj2
			return
		}
		fmt.eprintln("Error: Malformed dotted cons")
		return nil, .Unknown
	}
	tmp = lisp_read_list(tok) or_return
	ret = new_cons(obj, tmp)
	return
}

lisp_read :: proc() -> (obj: ^Cons, err: io.Error) {
	tok := read_token() or_return
	if len(tok) == 0 {
		obj = nil
		return
	}
	if tok[0] != ')' {
		return lisp_read_obj(tok)
	}
	fmt.eprintln("Error: unexpected )")
	return nil, .Unknown
}

list_reverse :: proc(lst: ^Cons) -> ^Cons {
	if lst == nil {
		return nil
	}
	curr, prev, next: ^Cons = lst, nil, lst.cdr
	for curr != nil {
		curr.cdr = prev
		prev, curr = curr, next
		if next != nil {
			next = next.cdr
		}
	}
	return prev
}

lisp_eval :: proc(expr, env: ^Cons) -> ^Cons {
	expr, env := expr, env
	restart: for {
		if expr == nil {
			return expr
		}
		tag := cons_tag(expr)
		if tag == .Int {
			return expr
		} else if tag == .Symbol {
			return env_lookup(expr, env)
		} else if tag != .Cell {
			return expr
		}

		head := expr.car
		symbol := atom_text(head)
		if symbol == TQUOTE {
			return expr.cdr.car
		} else if symbol == TCOND {
			item, cond: ^Cons
			gc_protect(&expr, &env, &item, &cond)
			defer gc_pop()
			for item = expr.cdr; item != nil; item = item.cdr {
				cond = item.car
				if lisp_eval(cond.car, env) != nil {
					expr = cond.cdr.car
					continue restart
				}
			}
			return nil
		} else if symbol == TDEFINE {
			name, value: ^Cons
			gc_protect(&expr, &env, &name, &value)
			defer gc_pop()
			name = expr.cdr.car
			value = lisp_eval(expr.cdr.cdr.car, env)
			env_set(env, name, value)
			return value
		} else if symbol == TLAMBDA {
			lamb: ^Cons
			gc_protect(&expr, &env, &lamb)
			defer gc_pop()
			lamb = gc_alloc()
			lamb^ = Cons{
				(^Cons)(uintptr(Tag.Lambda)),
				expr.cdr,
			}
			return lamb
		}


		fn := lisp_eval(head, env)
		gc_protect(&expr, &env, &fn)
		defer gc_pop()
		funtag := cons_tag(fn)
		if funtag == .Builtin {
			args, params, param: ^Cons
			gc_protect(&args, &params, &param)
			defer gc_pop()
			for params = expr.cdr; params != nil; params = params.cdr {
				param = lisp_eval(params.car, env)
				args = new_cons(param, args)
			}
			return ((Builtin)(rawptr(fn.cdr)))(list_reverse(args))
		} else if funtag == .Lambda {
			args, callenv, params, param, item: ^Cons
			args, item = fn.cdr.car, fn.cdr.cdr
			gc_protect(&args, &callenv, &params, &param, &item)
			defer gc_pop()
			callenv = new_cons(nil, env)
			for params = expr.cdr; params != nil; {
				param = lisp_eval(params.car, env)
				env_set(callenv, args.car, param)

				params = params.cdr
				args = args.cdr
			}
			for ; item != nil; item = item.cdr {
				if item.cdr == nil {
					expr, env = item.car, callenv
					continue restart
				}
				lisp_eval(item.car, callenv)
			}
		}
		return nil
	}
}

lisp_print :: proc(obj: ^Cons) {
	obj := obj
	if obj == nil {
		fmt.print("()")
		return
	}
	inlist := false
	outer: for {
		tag := cons_tag(obj)
		switch tag {
		case .Fwd:
			fmt.printf("<fwd:%p>", obj.cdr)
		case .Symbol:
			fmt.printf("%s", atom_text(obj))
		case .Int:
			fmt.printf("%d", int(uintptr(obj.cdr)))
		case .Builtin:
			fmt.printf("<C@%p>", Builtin(rawptr(obj.cdr)))
		case .Lambda:
			fmt.print("<lambda ")
			lisp_print(obj.cdr.car)
			fmt.print(" ")
			lisp_print(obj.cdr.cdr)
			fmt.print(">")
		case .Cell:
			if !inlist {
				fmt.print("(")
				inlist = true
			}
			lisp_print(obj.car)
			if obj.cdr == nil {
				break outer
			}
			fmt.print(" ")
			if cons_tag(obj.cdr) != .Cell {
				fmt.print(". ")
				lisp_print(obj.cdr)
				break outer
			}
			obj = obj.cdr
			continue outer
		}
		break outer
	}
	if inlist {
		fmt.print(")")
	}
}

main :: proc() {
	heap = make([]Cons, HEAP_SIZE * 2)
	defer delete(heap)
	fromspace, tospace = &heap[0], &heap[HEAP_SIZE]
	allocptr = fromspace
	numroots, roottop = 0, 0

	token_builder = strings.builder_make()
	defer strings.builder_destroy(&token_builder)
	strings.intern_init(&interned)
	defer strings.intern_destroy(&interned)
	TQUOTE, _ = strings.intern_get(&interned, "quote")
	TLAMBDA, _ = strings.intern_get(&interned, "lambda")
	TCOND, _ = strings.intern_get(&interned, "cond")
	TDEFINE, _ = strings.intern_get(&interned, "define")

	env: ^Cons
	gc_protect(&env, &atom_t, &atom_f)
	defer gc_pop()

	env, atom_t, atom_f = new_cons(nil, nil), new_atom("#t"), new_atom("#f")

	env_set(env, atom_t, atom_t)
	env_set(env, atom_f, nil)

	define_builtins(env)

	f := os.stdin
	buffer: [1024]byte

	if len(os.args) > 1 {
		ferr: os.Error
		f, ferr = os.open(os.args[1])
		if ferr != nil {
			fmt.eprintfln("Error: failed to open file (Error: %v)", ferr)
			return
		}
	}

	bufio.reader_init_with_buf(&lisp_reader, f.stream, buffer[:])
	defer if f != os.stdin { os.close(f) }
	defer bufio.reader_destroy(&lisp_reader)

	for {
		obj, err := lisp_read()
		if err != nil {
			break
		}
		obj = lisp_eval(obj, env)
		if f == os.stdin || ODIN_DEBUG {
			lisp_print(obj)
			fmt.println()
		}
	}
}