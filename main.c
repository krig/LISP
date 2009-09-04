#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <glib.h>
#include <ctype.h>
#include <gc.h>
#include "stream.h"

struct word_t;
struct interpreter_t;

typedef struct word_t* sexpr_t;
typedef struct interpreter_t* Lisp;

typedef union {
        unsigned int umask;
        struct word_t* word;
} address_t;

typedef sexpr_t (*ParserFunctionT)(Lisp, sexpr_t, sexpr_t);

typedef union {
        struct word_t* word;
        int num;
        const char* str;
        ParserFunctionT fun;
} decrement_t;

struct word_t {
        address_t a;
        decrement_t d;
};

struct interpreter_t {
        struct instream stream;
        struct word_t t;
        struct word_t nil;
        sexpr_t env; /* assoclist of variables */
        sexpr_t call; /* when in a function, refers to the call form itself */
        sexpr_t macros; /* assoclist of macros */
};

typedef enum SexprType_t {
        T_SEXPR = 0,
        T_NUM = 0x10,
        T_STR = 0x20,
        T_SYMBOL = 0x30,
        T_FUNCTION = 0x40
} SexprType;

#define WordAtomP(w) ((w)->a.umask & 1)
#define WordAtomType(w) ((w)->a.umask & 0xfffffff0)
#define WordNilP(w) ((w) == NULL || ((w)->a.word == NULL && (w)->d.word == NULL))

#define ATOM_STR(w) ((WordAtomType(w)==T_STR || WordAtomType(w)==T_SYMBOL) ? ((w)->d.str) : NULL)
#define ATOM_NUM(w) ((WordAtomType(w)==T_NUM) ? ((w)->d.num) : 0)
#define ATOM_WORD(w) ((WordAtomType(w)==T_SEXPR) ? ((w)->d.word) : NULL)
#define ATOM_FUNCTION(w) ((WordAtomType(w)==T_FUNCTION) ? ((w)->d.fun) : NULL)

#define SetWord(w, ca, cd) do { (w)->a.word = (ca); (w)->d.word = (cd); } while (0)
#define SetCAR(w, ca) do { (w)->a.word = (ca); } while (0)
#define SetCDR(w, cd) do { (w)->d.word = (cd); } while (0)
#define SetAtomWord(w, ww) do { (w)->a.umask = 1+T_SEXPR; (w)->d.word = (ww); } while(0)
#define SetAtomNum(w, n) do { (w)->a.umask = 1+T_NUM; (w)->d.num = (n); } while(0)
#define SetAtomStr(w, s) do { (w)->a.umask = 1+T_STR; (w)->d.str = (s); } while(0)
#define SetAtomSymbol(w, s) do { (w)->a.umask = 1+T_SYMBOL; (w)->d.str = (s); } while(0)
#define SetAtomFunction(w, f) do { (w)->a.umask = 1+T_FUNCTION; (w)->d.fun = (f); } while(0)

#define CAR(w) ((w)->a.word)
#define CDR(w) ((w)->d.word)
#define CAAR(w) ((w)->a.word->a.word)
#define CADR(w) ((w)->d.word->a.word)
#define CDDR(w) ((w)->d.word->d.word)
#define CADDR(w) ((w)->d.word->d.word->a.word)
#define CADAR(w) ((w)->a.word->d.word->a.word)
#define CADDAR(w) ((w)->a.word->d.word->d.word->a.word)

/*
  COND:
  input: list of expressions and associated values
  output: first value whose expression evaluates to true
*/

const char* intern(const char* str) {
        return g_intern_string(str);
}

sexpr_t lisp_cons(Lisp I, sexpr_t a, sexpr_t b);
sexpr_t lisp_list(Lisp I, sexpr_t a, sexpr_t b);
sexpr_t lisp_symbol(Lisp I, const char* symb) {
        sexpr_t ret = lisp_cons(I, NULL, NULL);
        SetAtomSymbol(ret, intern(symb));
        return ret;
}

int get_char(Lisp I) {
        return I->stream.get_char(I->stream.hstream);
}

void put_char(Lisp I, int ch) {
        I->stream.put_char(ch, I->stream.hstream);
}

sexpr_t lisp_eq(Lisp I, sexpr_t x, sexpr_t y);

void print_atom(Lisp I, sexpr_t word) {
        if (WordNilP(word)) {
                printf("nil");
        }
        else if (lisp_eq(I, word, &I->t) == &I->t) {
                printf("t");
        }
        else {
                switch (WordAtomType(word)) {
                case T_SEXPR:
                        printf("%p", ATOM_WORD(word));
                        break;
                case T_NUM:
                        printf("%d", ATOM_NUM(word));
                        break;
                case T_STR:
                case T_SYMBOL:
                        printf("%s", ATOM_STR(word));
                        break;
                case T_FUNCTION:
                        printf("fn#%p", ATOM_FUNCTION(word));
                        break;
                default:
                        printf("<STRANGE ATOM>");
                        break;
                }
        }
}

void print_sexpr(Lisp I, sexpr_t word) {
        printf("(");

        if (WordAtomP(CAR(word)) && WordAtomP(CDR(word))) {
                print_atom(I, CAR(word));
                printf(" . ");
                print_atom(I, CDR(word));
        }
        else {
                while (1) {
                        if (WordNilP(CAR(word))) {
                                printf("nil");
                        }
                        else if (WordAtomP(CAR(word))) {
                                print_atom(I, CAR(word));
                        }
                        else {
                                print_sexpr(I, CAR(word));
                        }

                        if (!WordNilP(CDR(word))) {
                                printf(" ");
                        }
                        word = CDR(word);
                        if (WordNilP(word)) {
                                break;
                        }
                }
        }
        printf(")");
}

void print_word_struct(Lisp I, sexpr_t word) {
        if (word) {
                if (WordAtomP(word)) {
                        printf("[%p]:", word);
                } else {
                        printf("[%p->%p]:", word,
                               word->d.word);
                }
        }
        else {
                printf("%p[NULL]", word);
        }
}

void print_sexpr_verbose(Lisp I, sexpr_t word, int depth) {
        int i;
        printf("\n");
        for (i = 0; i < depth; ++i)
                printf("\t");
        if (WordNilP(word)) {
                print_word_struct(I, word);
                printf(" ");
        }
        else if (WordAtomP(word)) {
                print_word_struct(I, word);
                print_atom(I, word);
                printf(" ");
        }
        else {
                while (1) {
                        print_word_struct(I, word);
                        printf("(");

                        print_sexpr_verbose(I, CAR(word), depth+1);

                        word = CDR(word);
                        if (WordNilP(word)) {
                                printf("\n");
                                for (i = 0; i < depth; ++i)
                                        printf("\t");
                                printf(")\n");
                                break;
                        }
                }
        }
}

sexpr_t lisp_eq(Lisp I, sexpr_t x, sexpr_t y) {
        return (WordAtomP(x) && WordAtomP(y) && (x->d.word == y->d.word)) ? &I->t : &I->nil;
}
sexpr_t lisp_streq(Lisp I, sexpr_t x, const char* s) {
        return (WordAtomP(x) && (ATOM_STR(x) == s)) ? &I->t : &I->nil;
}

sexpr_t lisp_eval(Lisp I, sexpr_t e, sexpr_t a);

sexpr_t lisp_cons(Lisp I, sexpr_t a, sexpr_t b) {
        sexpr_t ret = GC_malloc(sizeof(struct word_t));
        SetWord(ret, a, b);
        return ret;
}

sexpr_t lisp_list(Lisp I, sexpr_t a, sexpr_t b) {
        return lisp_cons(I, a, lisp_cons(I, b, NULL));
}

sexpr_t lisp_evlis(Lisp I, sexpr_t m, sexpr_t a) {
        if (WordNilP(m)) {
                return &I->nil;
        }
        else {
                return lisp_cons(I, lisp_eval(I, CAR(m), a), lisp_evlis(I, CDR(m), a));
        }
}

sexpr_t lisp_assoc(Lisp I, sexpr_t m, sexpr_t a) {
tailcall:
        if (lisp_eq(I, CAAR(a), m) != &I->nil) {
                return CADAR(a);
        }
        else {
                a = CDR(a);
                goto tailcall;
                /*return lisp_assoc(I, m, CDR(a));*/
        }
}

sexpr_t lisp_append(Lisp I, sexpr_t x, sexpr_t y) {
        if (WordNilP(x))
                return y;
        else
                return lisp_cons(I, CAR(x), lisp_append(I, CDR(x), y));
}

sexpr_t lisp_pair(Lisp I, sexpr_t x, sexpr_t y) {
        if (WordNilP(x) && WordNilP(y)) {
                return lisp_cons(I, NULL, NULL);
        }
        else if (!WordAtomP(x) && !WordAtomP(y)) {
                return lisp_cons(I, lisp_list(I, CAR(x), CAR(y)),
                                 lisp_pair(I, CDR(x), CDR(y)));
        }
        else {
                return &I->nil;
        }
}

sexpr_t lisp_eval(Lisp I, sexpr_t e, sexpr_t a) {
        static const char* squote = NULL;
        static const char* scar = NULL;
        static const char* scdr = NULL;
        static const char* satom = NULL;
        static const char* scond = NULL;
        static const char* scons = NULL;
        static const char* seq = NULL;
        static const char* slabel = NULL;
        static const char* sfn = NULL;
        static const char* ssetq = NULL;

        if (squote == NULL) {
                squote = intern("quote");
                scar = intern("car");
                scdr = intern("cdr");
                satom = intern("atom");
                scond = intern("cond");
                scons = intern("cons");
                seq = intern("eq");
                slabel = intern("label");
                sfn = intern("fn");
                ssetq = intern("setq");
        }

        if (WordNilP(e)) {
                return &I->nil;
        } else if (WordAtomP(e)) {
                if (WordAtomType(e) == T_SYMBOL) {
                        return lisp_assoc(I, e, a);
                }
                else {
                        return e;
                }
        }
        else if (WordAtomP(CAR(e))) {
                if (WordAtomType(CAR(e)) == T_FUNCTION) {
                        I->call = e;
                        return ATOM_FUNCTION(CAR(e))(I, lisp_evlis(I, CDR(e), a), a);
                }
                else if (WordAtomType(CAR(e)) == T_SYMBOL) {
                        // todo: apply
                        const char* astr = ATOM_STR(CAR(e));
                        if (astr == squote) {
                                return CADR(e);
                        }
                        else if (astr == satom) {
                                sexpr_t ret = lisp_eval(I, CADR(e), a);
                                if (WordAtomP(ret))
                                        return ret;
                                else
                                        return &I->nil;
                        }
                        else if (astr == seq) {
                                return lisp_eq(I, lisp_eval(I, CADR(e), a), lisp_eval(I, CADDR(e), a));
                        }
                        else if (astr == scond) {
                                sexpr_t c = CDR(e);
                                while (!WordNilP(c)) {
                                        sexpr_t r = lisp_eval(I, CAAR(c), a);
                                        if (!WordNilP(r)) {
                                                return lisp_eval(I, CADAR(c), a);
                                        }
                                        else {
                                                c = CDR(c);
                                        }
                                }
                                printf("Cond error:");
                                print_sexpr(I, e);
                                return &I->nil;
                        }
                        else if (astr == scar) {
                                return CAR(lisp_eval(I, CADR(e), a));
                        }
                        else if (astr == scdr) {
                                return CDR(lisp_eval(I, CADR(e), a));
                        }
                        else if (astr == scons) {
                                return lisp_cons(I, lisp_eval(I, CADR(e), a), lisp_eval(I, CADDR(e), a));
                        }
                        else if (astr == ssetq) {
                                sexpr_t v1 = CADR(e);
                                do {
                                        I->env = lisp_cons(I, lisp_list(I, CADR(e), lisp_eval(I, CADDR(e), a)), I->env);
                                        e = CDDR(e);
                                } while(!WordNilP(CDR(e)));
                                return v1;
                        }
                        else {
                                return lisp_eval(I, lisp_cons(I, lisp_assoc(I, CAR(e), a), CDR(e)), a);
                        }
                }
        }
        else if (lisp_streq(I, CAAR(e), slabel) != &I->nil) {
                return lisp_eval(I, lisp_cons(I, CADDAR(e), CDR(e)),
                                 lisp_cons(I, lisp_list(I, CADAR(e), CAR(e)), a));
        }
        else if (lisp_streq(I, CAAR(e), sfn) != &I->nil) {
                /*print_sexpr_verbose(I, e, 0);*/
                return lisp_eval(I, CADDAR(e),
                                 lisp_append(I, lisp_pair(I, CADAR(e),
                                                          lisp_evlis(I, CDR(e), a)), a));
        }

        printf("Eval error:");
        print_sexpr(I, e);
        return &I->nil;
}


sexpr_t lisp_read(Lisp I);

sexpr_t lisp_read_atom(Lisp I);
sexpr_t lisp_read_list(Lisp I);

int num_objects_created = 0;

sexpr_t lisp_read(Lisp I) {
        int ch;
        sexpr_t ret;
        ch = get_char(I);
        while (ch) {
                if (isspace(ch)) {
                }
                else if (ch == '(') {
                        put_char(I, ch);
                        ret = lisp_read_list(I);
                        break;
                }
                else if (ch == '\'') {
                        static const char* squote = NULL;
                        sexpr_t name;
                        if (!squote) {
                                squote = intern("quote");
                        }
                        name = lisp_cons(I, NULL, NULL);
                        SetAtomSymbol(name, squote);
                        ret = lisp_cons(I, name, lisp_cons(I, lisp_read(I), NULL));
                        break;
                }
                else {
                        put_char(I, ch);
                        ret = lisp_read_atom(I);
                        break;
                }

                ch = get_char(I);
        }

        if (ret) {
                /*print_sexpr_verbose(I, ret, 0);*/
        }
        return ret;
}

static int issymbol(int ch) {
        return isalnum(ch) ||
                (ch == '!') ||
                (ch == '%') ||
                (ch == '*') ||
                (ch == '+') ||
                (ch == '-') ||
                (ch == '_') ||
                (ch == '/') ||
                (ch == ':') ||
                (ch == '<') ||
                (ch == '>') ||
                (ch == '=') ||
                (ch == '?');
}

sexpr_t lisp_read_atom(Lisp I) {
        int ch;
        char buf[128];

        ch = get_char(I);
        if (isdigit(ch)) {
                /* parse number */
                int i = 0;
                while (isdigit(ch)) {
                        buf[i++] = ch;
                        ch = get_char(I);
                }
                buf[i] = 0;
                put_char(I, ch); // rewind
                num_objects_created++;
                sexpr_t atom = lisp_cons(I, NULL, NULL);
                SetAtomNum(atom, atoi(buf));
                return atom;
        }
        else if (issymbol(ch)) {
                /* parse symbol */
                int i = 0;
                while (issymbol(ch)) {
                        buf[i++] = ch;
                        ch = get_char(I);
                }
                buf[i] = 0;
                put_char(I, ch); // rewind
                num_objects_created++;
                sexpr_t atom = lisp_cons(I, NULL, NULL);
                SetAtomSymbol(atom, intern(buf));
                return atom;
        }
        else if (ch == '"') {
                /* parse string */
                int i = 0;
                memset(buf, 0, sizeof(buf));
                ch = get_char(I);
                while (ch != '"') {
                        if (ch == '\\') {
                                switch (get_char(I)) {
                                case 'n': buf[i++] = '\n'; break;
                                case 'r': buf[i++] = '\r'; break;
                                case '\\': buf[i++] = '\\'; break;
                                case '"': buf[i++] = '"'; break;
                                case 't': buf[i++] = '\t'; break;
                                default: buf[i++] = ch; break;
                                }
                        } else {
                                buf[i++] = ch;
                        }
                        ch = get_char(I);
                }
                buf[i] = 0;
                num_objects_created++;
                sexpr_t atom = lisp_cons(I, NULL, NULL);
                char* str = GC_malloc(i);
                strcpy(str, buf);
                SetAtomStr(atom, str);
                return atom;
        }
        else {
                if (isgraph(ch))
                        printf("Unknown token: %c\n", ch);
                return NULL;
        }
}

sexpr_t lisp_read_list(Lisp I) {
        int ch;
        ch = get_char(I);
        if (ch != '(')
                return NULL;

        num_objects_created++;

        sexpr_t head = lisp_cons(I, NULL, NULL);
        sexpr_t prev = NULL;
        sexpr_t curr = head;

        ch = get_char(I);
        while (ch) {
                if (isspace(ch)) {
                }
                else if (ch == ')') {
                        break;
                }
                else {
                        prev = curr;
                        put_char(I, ch);
                        SetCAR(prev, lisp_read(I));
                        num_objects_created++;
                        curr = lisp_cons(I, NULL, NULL);
                        SetCDR(prev, curr);
                }

                ch = get_char(I);
        }
        return head;
}

void lisp_loop(Lisp I, sexpr_t word) {
        const char* STOP = intern("stop");
        while (1) {
                if (WordNilP(word)) {
                        print_atom(I, word);
                        puts("");
                        word = lisp_read(I);
                        if (word == NULL)
                                return;
                        word = lisp_eval(I, word, I->env);
                }
                else if (WordAtomP(word)) {
                        if (ATOM_STR(word) == STOP)
                                return;
                        print_atom(I, word);
                        puts("");
                        word = lisp_read(I);
                        if (word == NULL)
                                return;
                        word = lisp_eval(I, word, I->env);
                }
                else {
                        print_sexpr(I, word);
                        puts("");
                        word = lisp_read(I);
                        if (word == NULL)
                                return;
                        word = lisp_eval(I, word, I->env);
                }
        }
}


static void register_function(Lisp I, const char* name, ParserFunctionT fun) {
        sexpr_t nm, fn, cs;
        nm = lisp_cons(I, NULL, NULL);
        SetAtomStr(nm, intern(name));
        fn = lisp_cons(I, NULL, NULL);
        SetAtomFunction(fn, fun);
        cs = lisp_list(I, nm, fn);
        I->env = lisp_cons(I, cs, I->env);
}

static sexpr_t
fn_strjoin(Lisp I, sexpr_t args, sexpr_t env) {
        sexpr_t ret;
        const char* a;
        const char* b;
        char* join;
        int na, nb;
next:
        a = ATOM_STR(CAR(args));
        b = ATOM_STR(CADR(args));
        na = strlen(a);
        nb = strlen(b);
        join = GC_malloc(na + nb + 1);
        strcpy(join, a);
        strcpy(join+na, b);
        ret = lisp_cons(I, NULL, NULL);
        SetAtomStr(ret, join);
        if (!WordNilP(CDDR(args))) {
                args = lisp_cons(I, ret, CDDR(args));
                goto next;
        }
        return ret;
}

static sexpr_t
fn_macro(Lisp I, sexpr_t args, sexpr_t env) {
        sexpr_t name;
        sexpr_t plist;
        sexpr_t body;
        name = CAR(args);
        plist = CADR(args);
        body = CDDR(args);
        printf("Defining macro: ");
        print_atom(I, name);
        printf("\nArgument list: ");
        print_sexpr(I, plist);
        printf("\nBody: ");
        print_sexpr(I, body);
        printf("\n");
        return name;
}

gboolean init_interpreter(Lisp I, const char* filename) {
        memset(I, 0, sizeof(struct interpreter_t));
        init_file_stream(&I->stream, filename);
        /* set env to () */
        I->t.a.umask = 1;
        I->t.d.num = 1;
        I->nil.a.word = NULL;
        I->nil.d.word = NULL;

        I->env = lisp_cons(I, lisp_list(I, lisp_symbol(I, "nil"), &I->nil), lisp_cons(I, lisp_list(I, lisp_symbol(I, "t"), &I->t), &I->nil));

        I->call = &I->nil;
        I->macros = &I->nil;

        register_function(I, "str+", fn_strjoin);
        register_function(I, "macro", fn_macro);
        return TRUE;
}

int main(int argc, char* argv[]) {
        struct interpreter_t i;
        Lisp I = &i;
        GC_INIT();
        init_interpreter(I, argv[1]);

        num_objects_created = 0;
        sexpr_t lst = lisp_read(I);
        /*printf("read %d objects\n", num_objects_created);*/

        lst = lisp_eval(I, lst, I->env);

        /*print_sexpr_verbose(I, lst, 0);*/
        lisp_loop(I, lst);

        printf("\n");
        return 0;
}
