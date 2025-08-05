package komplott

import "base:intrinsics"
import "base:runtime"
import "core:bufio"
import "core:fmt"
import "core:io"
import "core:mem"
import "core:os"
import "core:reflect"
import "core:strconv"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

import back "vendor/back"


ITOS_BYTES :: 40
HEAP_SIZE :: 16 * mem.Kilobyte
MAX_ROOTS :: 500
MAX_FRAMES :: 50

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

heap: []Object
tospace, fromspace, allocptr: ^Object
roots: [MAX_ROOTS]^^Object
rootstack: [MAX_FRAMES]uint
roottop: uint
numroots: uint
FWDMARKER: Object = ""


interned: strings.Intern
lisp_reader: bufio.Reader

intern_string :: proc(s: string) -> (ret: string, err: runtime.Allocator_Error) #optional_allocator_error {
	return strings.intern_get(&interned, s)
}

new_atom :: proc(s: string) -> (ret: ^Object, err: runtime.Allocator_Error) #optional_allocator_error {
	ret = gc_alloc()
	atom := intern_string(s) or_return
	ret^ = Atom(atom)
	return
}

new_cons :: proc(car, cdr: ^Object) -> (ret: ^Object, err: runtime.Allocator_Error) #optional_allocator_error {
	car, cdr := car, cdr
	gc_protect(&car, &cdr)
	defer gc_pop()
	ret = gc_alloc()
	ret^ = Cons{car, cdr}
	return
}

env_set :: proc(env, key, value: ^Object) -> (ret: ^Object, err: runtime.Allocator_Error) #optional_allocator_error {
	env, key, value := env, key, value
	gc_protect(&env, &key, &value)
	defer gc_pop()
	pair := new_cons(key, value) or_return
	frame := new_cons(pair, car(env)) or_return
	econs := env.(Cons)
	econs.car = frame
	env^ = econs
	ret = env
	return
}

list_find_pair :: proc(needle, haystack: ^Object) -> ^Object {
	for cur := haystack; cur != nil; cur = cdr(cur) {
		pair := car(cur)
		if pair != nil && lisp_equal(needle, car(pair)) {
			return pair
		}
	}
	return nil
}

env_lookup :: proc(needle, haystack: ^Object) -> ^Object {
	for cur := haystack; cur != nil; cur = cdr(cur) {
		if pair := list_find_pair(needle, car(cur)); pair != nil {
			return cdr(pair)
		}
	}
	return nil
}

BuiltinSignature :: proc(^Object) -> ^Object

car :: proc(obj: ^Object) -> ^Object {
	c: Cons
	l: Lambda
	ok: bool
	if obj == nil { return nil }
	c, ok = obj.(Cons)
	if ok { return c.car }
	l, ok = obj.(Lambda)
	if ok { return l.args }
	return nil
}

cdr :: proc(obj: ^Object) -> ^Object {
	c: Cons
	l: Lambda
	ok: bool
	if obj == nil { return nil }
	c, ok = obj.(Cons)
	if ok { return c.cdr }
	l, ok = obj.(Lambda)
	if ok { return l.body }
	return nil
}


gc_init :: proc() -> (err: runtime.Allocator_Error) {
	heap = make([]Object, HEAP_SIZE * 2) or_return
	fromspace = &heap[0]
	allocptr = fromspace
	tospace = &heap[HEAP_SIZE]
	numroots = 0
	roottop = 0
	return
}

gc_destroy :: proc() {
	delete(heap)
}

in_tospace :: proc(p: ^Object) -> bool {
	return uintptr(p) >= uintptr(tospace) && uintptr(p) < uintptr(tospace) + HEAP_SIZE*size_of(Object)
}

gc_copy :: proc(root: ^^Object) {
	if root^ == nil {
		return
	}

	if car(root^) == &FWDMARKER {
		root^ = cdr(root^)
	} else if in_tospace(root^) {
		p := allocptr
		allocptr = mem.ptr_offset(allocptr, 1)
		mem.copy_non_overlapping(p, root^, size_of(Object))
		root^^ = Cons{&FWDMARKER, p}
		root^ = p
	}
}

gc_collect :: proc() {
	if !gc_full() {
		return
	}

	fmt.println("==== GC ====")
	fmt.printfln("fromspace: %p", fromspace)
	fmt.printfln("tospace: %p", tospace)
	fmt.printfln("allocptr - fromspace: %v", (uintptr(allocptr) - uintptr(fromspace)) / size_of(Object))
	fmt.printfln("*** SWAP ***")

	fromspace, tospace = tospace, fromspace
	allocptr = fromspace

	fmt.printfln("fromspace: %p", fromspace)
	fmt.printfln("tospace: %p", tospace)
	fmt.printfln("allocptr: %p", allocptr)

	fmt.printfln("Copying %v roots...", numroots)
	for i :uint = 0; i < numroots; i += 1 {
		gc_copy(roots[i])
	}

	fmt.println("Scanning fromspace...")
	for scanptr := fromspace; scanptr < allocptr; scanptr = mem.ptr_offset(scanptr, 1) {
		#partial switch _ in scanptr^ {
		case Cons:
			p: ^Cons = cast(^Cons)(scanptr)
			gc_copy(&p.car)
			gc_copy(&p.cdr)
		case Lambda:
			p: ^Lambda = cast(^Lambda)(scanptr)
			gc_copy(&p.args)
			gc_copy(&p.body)
		}
	}


	fmt.println("==== GC COMPLETE ====")
	fmt.printfln("allocptr - fromspace: %v", (uintptr(allocptr) - uintptr(fromspace)) / size_of(Object))
	fmt.println("==== GC COMPLETE ====")
	if gc_full() {
		fmt.eprintln("Out of memory")
		runtime.trap()
	}
}

gc_full :: proc() -> bool {
	next_alloc_pos := uintptr(allocptr) + size_of(^Object)
	space_end := uintptr(fromspace) + HEAP_SIZE * size_of(^Object)
	return next_alloc_pos >= space_end
}

in_live :: proc(p: ^Object) -> bool {
	if p == nil { return true }
	return uintptr(p) >= uintptr(fromspace) && uintptr(p) < uintptr(allocptr)
}

gc_validate :: proc() {
	// check the heap consistency
	allocpos := (uintptr(allocptr) - uintptr(fromspace)) / size_of(Object)
	assert(allocpos >= 0, "allocpos is negative")

	offs :uintptr = 0 if uintptr(allocptr) < (uintptr)(&heap[HEAP_SIZE]) else HEAP_SIZE

	for i :uintptr = offs; i < offs + allocpos; i += 1 {
		o := heap[i]
		switch v in o {
		case Cons:
			assert(in_live(v.car), "bad car")
			assert(in_live(v.cdr), "bad cdr")
		case Lambda:
			assert(in_live(v.args), "bad args")
			assert(in_live(v.body), "bad body")
		case Atom:
			// check that atom is interned
			assert(v in interned.entries, "not interned")
		case Builtin:
			// check that builtin is in BUILTINS.impl
			found := false
			for def in BUILTINS {
				if v == def.impl {
					found = true
					break
				}
			}
			assert(found, "valid builtin")
		}
	}
}

gc_alloc :: proc() -> (ret: ^Object) {
	gc_validate()
	gc_collect()
	ret, allocptr = allocptr, mem.ptr_offset(allocptr, 1)
	return
}

gc_protect :: proc(ptrs: ..^^Object) {
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
	args := args
	cmp := car(args)
	for args = cdr(args); args != nil; args = cdr(args) {
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
	return atom_t if car(args) == nil else nil
}

builtin_sum :: proc(args: ^Object) -> ^Object {
	sum :i64 = 0
	for i := args; i != nil; i = cdr(i) {
		n, ok := strconv.parse_i64(atom_text(car(i)))
		sum += n if ok else 0
	}
	buf: [ITOS_BYTES]byte
	return new_atom(strconv.write_int(buf[:], sum, 10))
}

builtin_sub :: proc(args: ^Object) -> ^Object {
	sum: i64 = 0
	if cdr(args) == nil {
		n, ok := strconv.parse_i64(atom_text(car(args)))
		sum = -n if ok else 0
	} else {
		n, ok := strconv.parse_i64(atom_text(car(args)))
		sum = n if ok else 0
		for i := cdr(args); i != nil; i = cdr(i) {
			n, ok = strconv.parse_i64(atom_text(car(i)))
			sum -= n if ok else 0
		}
	}
	buf: [ITOS_BYTES]byte
	return new_atom(strconv.write_int(buf[:], sum, 10))
}

builtin_mul :: proc(args: ^Object) -> ^Object {
	sum :i64 = 1
	for cur := args; cur != nil; cur = cdr(cur) {
		n, ok := strconv.parse_i64(atom_text(car(cur)))
		sum *= n if ok else 0
	}
	buf: [ITOS_BYTES]byte
	return new_atom(strconv.write_int(buf[:], sum, 10))
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
		fmt.eprintf("Error: %v", err)
		return nil
	}
	return obj
}

BuiltinDef :: struct {
	name: string,
	impl: BuiltinSignature,
}

BUILTINS :: []BuiltinDef {
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

define_builtins :: proc(env: ^Object) -> (runtime.Allocator_Error) {
	key: ^Object
	val: ^Object
	env := env
	gc_protect(&key, &val, &env)
	defer gc_pop()

	for def in BUILTINS {
		key = new_atom(def.name)
		val = gc_alloc()
		val^ = def.impl
		_, err := env_set(env, key, val)
		if err != nil {
			return err
		}
	}
	return nil
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
	start := 0
	if len(s) > 1 && (s[0] == '+' || s[0] == '-') {
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
	tokk, aerr := intern_string(strings.to_string(token_builder))
	if aerr != nil {
		fmt.eprintf("Error: %v\n", aerr)
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
	obj, obj2, tmp: ^Object
	gc_protect(&obj, &obj2, &tmp)
	defer gc_pop()
	obj = lisp_read_obj(tok) or_return
	tok := tok
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
	fmt.eprintln("Error: unexpected )")
	return nil, .Unknown
}

atom_text :: proc(atom: ^Object) -> string {
	v, ok := atom.(Atom)
	return v if ok else ""
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
		assert(in_live(expr), "live expr")
		assert(in_live(env), "live env")
		if expr == nil {
			return expr
		}
		_, isatom := expr.(Atom)
		_, iscons := expr.(Cons)
		if isatom {
			if match_number(expr.(Atom)) {
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
			item, cond: ^Object
			gc_protect(&expr, &env, &item, &cond)
			defer gc_pop()
			for item = cdr(expr); item != nil; item = cdr(item) {
				cond = car(item)
				if lisp_eval(car(cond), env) != nil {
					expr = car(cdr(cond))
					continue restart
				}
			}
			return nil
		} else if atom_text(head) == TDEFINE {
			name, value: ^Object
			gc_protect(&expr, &env, &name, &value)
			defer gc_pop()
			name = car(cdr(expr))
			value = lisp_eval(car(cdr(cdr(expr))), env)
			env_set(env, name, value)
			return value
		} else if atom_text(head) == TLAMBDA {
			cd := cdr(expr)
			cd^ = Lambda{ car(cd), cdr(cd) }
			return cd
		}


		fn := lisp_eval(head, env)
		gc_protect(&expr, &env, &fn)
		defer gc_pop()
		if fn == nil {
			fmt.eprintln("Error: cannot evaluate head in current env!")
			return nil
		}
		switch tv in fn {
		case Builtin:
			args, params, param: ^Object
			gc_protect(&args, &params, &param)
			defer gc_pop()
			for params = cdr(expr); params != nil; params = cdr(params) {
				param = lisp_eval(car(params), env)
				args = new_cons(param, args)
			}
			return tv(list_reverse(args))
		case Lambda:
			args, callenv, params, param, item: ^Object
			args, item = tv.args, tv.body
			gc_protect(&args, &callenv, &params, &param, &item)
			defer gc_pop()
			callenv = new_cons(nil, env)
			for params = cdr(expr); params != nil; {
				param = lisp_eval(car(params), env)
				env_set(callenv, car(args), param)

				params = cdr(params)
				args = cdr(args)
			}
			for ; item != nil; item = cdr(item) {
				if cdr(item) == nil {
					expr = car(item)
					env = callenv
					continue restart
				}
				lisp_eval(car(item), callenv)
			}
		case Cons, Atom:
			fmt.eprintln("Error: calling non-function as function")
			runtime.trap()
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
	inlist := false
	outer: for {
		switch v in obj^ {
		case Atom:
			fmt.printf("%s", v)
		case Builtin:
			fmt.printf("<C@%v>", v)
		case Lambda:
			fmt.print("<lambda ")
			lisp_print(v.args)
			fmt.print(" ")
			lisp_print(v.body)
			fmt.print(">")
		case Cons:
			if !inlist {
				fmt.print("(")
				inlist = true
			}
			lisp_print(v.car)
			if v.cdr == nil {
				break outer
			}
			fmt.print(" ")
			_, iscons := v.cdr.(Cons)
			if !iscons {
				fmt.print(". ")
				lisp_print(v.cdr)
				break outer
			}
			obj = v.cdr
			continue outer
		}
		break outer
	}
	if inlist {
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
	track: back.Tracking_Allocator
	back.tracking_allocator_init(&track, context.allocator)
	defer back.tracking_allocator_destroy(&track)
	back.register_segfault_handler()
	context.assertion_failure_proc = back.assertion_failure_proc

	context.allocator = back.tracking_allocator(&track)
	defer back.tracking_allocator_print_results(&track)

	gc_init()
	defer gc_destroy()

	token_builder = strings.builder_make()
	defer strings.builder_destroy(&token_builder)
	strings.intern_init(&interned)
	defer strings.intern_destroy(&interned)
	intern_names()

	env: ^Object
	gc_protect(&env, &atom_t, &atom_f)
	defer gc_pop()

	env = new_cons(nil, nil)
	atom_t = new_atom("#t")
	atom_f = new_atom("#f")

	env_set(env, atom_t, atom_t)
	env_set(env, atom_f, nil)

	define_builtins(env)

	f: os.Handle
	buffer: [1024]byte

	if len(os.args) > 1 {
		ferr: os.Error
		f, ferr = os.open(os.args[1])
		if ferr != nil {
			// handle error appropriately
			fmt.eprintfln("Error: failed to open file (Error: %v)", ferr)
			return
		}
	} else {
		f = os.stdin
	}

	bufio.reader_init_with_buf(&lisp_reader, os.stream_from_handle(f), buffer[:])
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
