#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <assert.h>
#include <stdarg.h>

typedef enum { T_CONS, T_ATOM, T_CFUNC, T_LAMBDA } object_tag;

struct object_t;
typedef struct object_t *(*cfunc)(struct object_t *);

typedef struct object_t {
	struct object_t *car, *cdr;
	object_tag tag;
} object;

#define TOKEN_MAX 256
#define HASHMAP_SIZE 2048
#define ATOMCHAR(ch) (((ch) >= '!' && (ch) <= '\'') || ((ch) >= '*' && (ch) <= '~'))
#define TEXT(x) (((x) && (x)->tag == T_ATOM) ? ((const char *)((x)->car)) : "")
#define HEAPSIZE 16384
#define MAXROOTS 500
#define MAXFRAMES 50

const char *TQUOTE = NULL, *TLAMBDA = NULL, *TCOND = NULL,
	*TDEFINE = NULL, *TBEGIN = NULL, *TOR = NULL;
char        token_text[TOKEN_MAX];
int         token_peek = 0;
object     *atom_t = NULL;
object *heap, *tospace, *fromspace, *allocptr, *scanptr;
object ** roots[MAXROOTS];
size_t rootstack[MAXFRAMES];
size_t roottop, numroots;
object fwdmarker = { .tag = T_ATOM, .car = 0, .cdr = 0 };

void    gc_init(void);
object *gc_alloc(object_tag tag, object *car, object *cdr);
void    gc_protect(object **r, ...);
void    gc_pop(void);
object *lisp_read_list(const char *tok, FILE *in);
object *lisp_read_obj(const char *tok, FILE *in);
object *lisp_read(FILE *in);
void    lisp_print(object *obj);
object *lisp_eval(object *obj, object *env);

size_t djbhash(const unsigned char *str) {
    size_t hash = 5381;
    for (size_t c = *str++; c; c = *str++)
        hash = (hash << 5) + hash + c;
    return hash;
}

const char *intern_string(const char *str) {
	typedef struct node { struct node *next; char data[]; } node_t;
	static node_t* nodes[HASHMAP_SIZE] = {0};
	size_t hash = djbhash((const unsigned char *)str) % HASHMAP_SIZE;
	for (node_t* is = nodes[hash]; is != NULL; is = is->next)
		if (strcmp(is->data, str) == 0)
			return is->data;
	size_t sz = strlen(str) + 1;
	node_t *item = malloc(sizeof(node_t) + sz);
	memcpy(item->data, str, sz);
	item->next = nodes[hash];
	nodes[hash] = item;
	return item->data;
}

int match_number(const char *s) {
	if (*s == '-' || *s == '+')
		s++;
	do {
		if (*s < '0' || *s > '9')
			return 0;
	} while (*++s != '\0');
	return 1;
}

const char *itos(long n) {
	char ch[TOKEN_MAX];
	snprintf(ch, TOKEN_MAX, "%ld", n);
	return intern_string(ch);
}

object *new_cfunc(cfunc func) {
	return gc_alloc(T_CFUNC, (object *)func, NULL);
}

object *new_atom(const char *str) {
	return gc_alloc(T_ATOM, (object *)intern_string(str), NULL);
}

object *new_cons(object *car, object *cdr) {
	gc_protect(&car, &cdr, NULL);
	object *ret = gc_alloc(T_CONS, car, cdr);
	gc_pop();
	return ret;
}

const char *read_token(FILE *in) {
	int n = 0;
	while (isspace(token_peek))
		token_peek = fgetc(in);
	if (token_peek == '(' || token_peek == ')') {
		token_text[n++] = token_peek;
		token_peek = fgetc(in);
	} else while (ATOMCHAR(token_peek)) {
		if (n == TOKEN_MAX)
			abort();
		token_text[n++] = token_peek;
		token_peek = fgetc(in);
	}
	if (token_peek == EOF)
		exit(0);
	token_text[n] = '\0';
	return intern_string(token_text);
}

object *lisp_read_obj(const char *tok, FILE *in) {
	return (tok[0] != '(') ? new_atom(tok) :
		lisp_read_list(read_token(in), in);
}

object *lisp_read_list(const char *tok, FILE *in) {
	if (tok[0] == ')')
		return NULL;
	object *obj = NULL, *tmp = NULL, *obj2 = NULL;
	gc_protect(&obj, &tmp, &obj2, NULL);
	obj = lisp_read_obj(tok, in);
	tok = read_token(in);
	if (tok[0] == '.' && tok[1] == '\0') {
		tok = read_token(in);
		tmp = lisp_read_obj(tok, in);
		obj2 = new_cons(obj, tmp);
		tok = read_token(in);
		gc_pop();
		if (tok[0] == ')')
			return obj2;
		fprintf(stderr, "Error: Malformed dotted cons\n");
		return NULL;
	}
	tmp = lisp_read_list(tok, in);
	obj2 = new_cons(obj, tmp);
	gc_pop();
	return obj2;
}

object *lisp_read(FILE *in) {
	const char *tok = read_token(in);
	if (tok == NULL)
		return NULL;
	if (tok[0] != ')')
		return lisp_read_obj(tok, in);
	fprintf(stderr, "Error: Unexpected )\n");
	return NULL;
}

int lisp_equal(object *a, object *b) {
	if (a == b)
		return 1;
	if (a == NULL || b == NULL || a->tag != b->tag)
		return 0;
	if (a->tag != T_CONS)
		return a->car == b->car;
	return lisp_equal(a->car, b->car) && lisp_equal(a->cdr, b->cdr);
}

object *list_find_pair(object *needle, object *haystack) {
	for (; haystack != NULL; haystack = haystack->cdr)
		if (haystack->car != NULL && lisp_equal(needle, haystack->car->car))
			return haystack->car;
	return NULL;
}

object *env_lookup(object *needle, object *haystack) {
	for (object *pair; haystack != NULL; haystack = haystack->cdr)
		if ((pair = list_find_pair(needle, haystack->car)) != NULL)
			return pair->cdr;
	return NULL;
}

object *env_set(object *env, object *key, object *value) {
	object *pair = NULL, *frame = NULL;
	gc_protect(&env, &key, &value, &pair, &frame, NULL);
	pair = new_cons(key, value);
	frame = new_cons(pair, env->car);
	env->car = frame;
	gc_pop();
	return env;
}

object *new_env(object *env) {
	return new_cons(NULL, env);
}

object *list_reverse(object *lst) {
	if (lst == NULL)
		return NULL;
	object *prev = NULL, *curr = lst, *next = lst->cdr;
	while (curr) {
		curr->cdr = prev;
		prev = curr;
		curr = next;
		if (next != NULL)
			next = next->cdr;
	}
	return prev;
}

object *lisp_eval(object *expr, object *env) {
restart:
	if (expr == NULL)
		return expr;
	if (expr->tag == T_ATOM && match_number(TEXT(expr)))
		return expr;
	if (expr->tag == T_ATOM)
		return env_lookup(expr, env);
	if (expr->tag != T_CONS)
		return expr;
	object *head = expr->car;
	if (TEXT(head) == TQUOTE) {
		return expr->cdr->car;
	} else if (TEXT(head) == TCOND) {
		object *item = NULL, *cond = NULL;
		gc_protect(&expr, &env, &item, &cond, NULL);
		for (item = expr->cdr; item != NULL; item = item->cdr) {
			cond = item->car;
			if (lisp_eval(cond->car, env) != NULL) {
				expr = cond->cdr->car;
				gc_pop();
				goto restart;
			}
		}
		abort();
		return NULL;
	} else if (TEXT(head) == TBEGIN) {
		object *item = NULL;
		gc_protect(&expr, &env, &item, NULL);
		for (item = expr->cdr; item != NULL; item = item->cdr) {
			if (item->cdr == NULL) {
				expr = item->car;
				gc_pop();
				goto restart;
			}
			lisp_eval(item->car, env);
		}
		gc_pop();
		return NULL;
	} else if (TEXT(head) == TOR) {
		object *item = NULL, *it = NULL;
		gc_protect(&env, &item, &it, NULL);
		for (item = expr->cdr; item != NULL; item = item->cdr) {
			it = lisp_eval(item->car, env);
			if (it != NULL)
				break;
		}
		gc_pop();
		return it;
	} else if (TEXT(head) == TDEFINE) {
		object *name = NULL;
		object *value = NULL;
		gc_protect(&env, &name, &value, NULL);
		name = expr->cdr->car;
		value = lisp_eval(expr->cdr->cdr->car, env);
		env_set(env, name, value);
		gc_pop();
		return value;
	} else if (TEXT(head) == TLAMBDA) {
		expr->cdr->tag = T_LAMBDA;
		return expr->cdr;
	}

	object *fn = NULL, *args = NULL, *params = NULL, *param = NULL;
	gc_protect(&expr, &env, &fn, &args, &params, &param, NULL);
	fn = lisp_eval(head, env);
	if (fn->tag == T_CFUNC) {
		for (params = expr->cdr; params != NULL; params = params->cdr) {
			param = lisp_eval(params->car, env);
			args = new_cons(param, args);
		}
		object *ret = ((cfunc)fn->car)(list_reverse(args));
		gc_pop();
		return ret;
	} else if (fn->tag == T_LAMBDA) {
		object *callenv = new_env(env);
		args = fn->car;
		object *item = NULL;
		gc_protect(&callenv, &item, NULL);
		for (params = expr->cdr; params != NULL; params = params->cdr, args = args->cdr) {
			param = lisp_eval(params->car, env);
			env_set(callenv, args->car, param);
		}
		for (item = fn->cdr; item != NULL; item = item->cdr) {
			if (item->cdr == NULL) {
				expr = item->car;
				env = callenv;
				gc_pop();
				gc_pop();
				goto restart;
			}
			lisp_eval(item->car, callenv);
		}
		gc_pop();
		gc_pop();
	}
	return NULL;
}

void lisp_print(object *obj) {
	if (obj == NULL) {
		printf("()");
	} else if (obj->tag == T_ATOM) {
		printf("%s", TEXT(obj));
	} else if (obj->tag == T_CFUNC) {
		printf("<C@%p>", (void *)obj);
	} else if (obj->tag == T_LAMBDA) {
		printf("<lambda ");
		lisp_print(obj->car);
		printf(">");
	} else if (obj->tag == T_CONS) {
		printf("(");
		for (;;) {
			lisp_print(obj->car);
			if (obj->cdr == NULL)
				break;
			printf(" ");
			if (obj->cdr->tag != T_CONS) {
				printf(". ");
				lisp_print(obj->cdr);
				break;
			}
			obj = obj->cdr;
		}
		printf(")");
	}
}

object *builtin_car(object *args) {
	return args->car->car;
}

object *builtin_cdr(object *args) {
	return args->car->cdr;
}

object *builtin_cons(object *args) {
	return new_cons(args->car, args->cdr->car);
}

object *builtin_list(object *args) {
	return args;
}

object *builtin_equal(object *args) {
	object *cmp = args->car;
	for (args = args->cdr; args != NULL; args = args->cdr)
		if (!lisp_equal(cmp, args->car))
			return NULL;
	return atom_t;
}

object *builtin_pair(object *args) {
	return (args->car != NULL && args->car->tag == T_CONS) ? atom_t : NULL;
}

object *builtin_null(object *args) {
	return (args->car == NULL) ? atom_t : NULL;
}

object *builtin_sum(object *args) {
	long sum = 0;
	for (; args != NULL; args = args->cdr)
		sum += atol(TEXT(args->car));
	return new_atom(itos(sum));
}

object *builtin_sub(object *args) {
	long n;
	if (args->cdr == NULL) {
		n = -atol(TEXT(args->car));
	} else {
		n = atol(TEXT(args->car));
		for (args = args->cdr; args != NULL; args = args->cdr)
			n = n - atol(TEXT(args->car));
	}
	return new_atom(itos(n));
}

object *builtin_mul(object *args) {
	long sum = 1;
	for (; args != NULL; args = args->cdr)
		sum *= atol(TEXT(args->car));
	return new_atom(itos(sum));
}

object *builtin_display(object *args) {
	lisp_print(args->car);
	return NULL;
}

object *builtin_newline(object *args) {
	printf("\n");
	return NULL;
}

object *builtin_read(object *args) {
	return lisp_read(stdin);
}

void defun(object *env, const char *name, cfunc fn) {
	object *key = NULL, *val = NULL;
	gc_protect(&env, &key, &val, NULL);
	key = new_atom(name);
	val = new_cfunc(fn);
	env_set(env, key, val);
	gc_pop();
}

void gc_copy(object **root) {
	if (*root == NULL)
		return;
	if ((*root)->car == &fwdmarker) {
		*root = (*root)->cdr;
	} else if (*root < fromspace || *root >= (fromspace + HEAPSIZE)) {
		object *p = allocptr++;
		memcpy(p, *root, sizeof(object));
		(*root)->car = &fwdmarker;
		(*root)->cdr = p;
		*root = p;
	}
}

void gc_collect(void) {
	object *tmp = fromspace;
	fromspace = tospace;
	tospace = tmp;
	allocptr = scanptr = fromspace;

	for (size_t i = 0; i < numroots; ++i)
		gc_copy(roots[i]);

	for (; scanptr < allocptr; ++scanptr)
		if (scanptr->tag == T_CONS || scanptr->tag == T_LAMBDA) {
			gc_copy(&(scanptr->car));
			gc_copy(&(scanptr->cdr));
		}
}

void gc_init(void) {
	allocptr = fromspace = heap = malloc(sizeof(object) * HEAPSIZE * 2);
	scanptr = tospace = heap + HEAPSIZE;
	numroots = roottop = 0;
}

object *gc_alloc(object_tag tag, object *car, object *cdr) {
	if (allocptr + 1 > fromspace + HEAPSIZE) {
		if (tag == T_CONS)
			gc_protect(&car, &cdr, NULL);
		gc_collect();
		if (tag == T_CONS)
			gc_pop();
	}
	if (allocptr + 1 > fromspace + HEAPSIZE) {
		fprintf(stderr, "Out of memory\n");
		abort();
	}
	allocptr->tag = tag;
	allocptr->car = car;
	allocptr->cdr = cdr;
	return allocptr++;
}

void gc_protect(object **r, ...) {
	assert(roottop < MAXFRAMES);
	rootstack[roottop++] = numroots;
	va_list args;
	va_start(args, r);
	for (object ** p = r; p != NULL; p = va_arg(args, object **)) {
		assert(numroots < MAXROOTS);
		roots[numroots++] = p;
	}
	va_end(args);
}

void gc_pop(void) {
	numroots = rootstack[--roottop];
}

int main(int argc, char* argv[]) {
	gc_init();
	TQUOTE = intern_string("quote");
	TLAMBDA = intern_string("lambda");
	TCOND = intern_string("cond");
	TDEFINE = intern_string("define");
	TBEGIN = intern_string("begin");
	TOR = intern_string("or");
	memset(token_text, 0, TOKEN_MAX);
	token_peek = ' ';

	object *env = NULL, *atom_f = NULL, *obj = NULL;
	gc_protect(&env, &atom_t, &atom_f, &obj, NULL);
	env = new_env(NULL);
	atom_t = new_atom("#t");
	atom_f = new_atom("#f");
	env_set(env, atom_t, atom_t);
	env_set(env, atom_f, NULL);
	defun(env, "car", &builtin_car);
	defun(env, "cdr", &builtin_cdr);
	defun(env, "cons", &builtin_cons);
	defun(env, "list", &builtin_list);
	defun(env, "equal?", &builtin_equal);
	defun(env, "pair?", &builtin_pair);
	defun(env, "null?", &builtin_null);
	defun(env, "+", &builtin_sum);
	defun(env, "-", &builtin_sub);
	defun(env, "*", &builtin_mul);
	defun(env, "display", &builtin_display);
	defun(env, "newline", &builtin_newline);
	defun(env, "read", &builtin_read);
	FILE *in = (argc > 1) ? fopen(argv[1], "r") : stdin;
	for (;;) {
		obj = lisp_read(in);
		obj = lisp_eval(obj, env);
		if (in == stdin) {
			lisp_print(obj);
			printf("\n");
		}
	}
	return 0;
}
