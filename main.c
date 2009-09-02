#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <glib.h>
#include <ctype.h>
#include <gc.h>
#include "stream.h"

struct Word;

typedef union {
        unsigned int umask;
        struct Word* word;
} address_t;

typedef union {
        struct Word* word;
        int num;
        const char* str;
} decrement_t;

struct Word {
        address_t a;
        decrement_t d;
};

#define WordAtomP(w) ((w)->a.umask & 1)
#define WordAtomType(w) ((w)->a.umask & 0xfffffff0)

#define WordNilP(w) ((w) == NULL || ((w)->a.word == NULL && (w)->d.word == NULL))

#define WORDATOM_WORD 0
#define WORDATOM_NUM 0x10
#define WORDATOM_STR 0x20

#define ATOM_STR(w) ((WordAtomType(w)==WORDATOM_STR) ? ((w)->d.str) : NULL)
#define ATOM_NUM(w) ((WordAtomType(w)==WORDATOM_NUM) ? ((w)->d.num) : 0)
#define ATOM_WORD(w) ((WordAtomType(w)==WORDATOM_WORD) ? ((w)->d.word) : NULL)

#define SetWord(w, ca, cd) do { (w)->a.word = (ca); (w)->d.word = (cd); } while (0)
#define SetCAR(w, ca) do { (w)->a.word = (ca); } while (0)
#define SetCDR(w, cd) do { (w)->d.word = (cd); } while (0)
#define SetAtomWord(w, ww) do { (w)->a.umask = 1+WORDATOM_WORD; (w)->d.word = (ww); } while(0)
#define SetAtomNum(w, n) do { (w)->a.umask = 1+WORDATOM_NUM; (w)->d.num = (n); } while(0)
#define SetAtomStr(w, s) do { (w)->a.umask = 1+WORDATOM_STR; (w)->d.str = (s); } while(0)

#define CAR(w) ((w)->a.word)
#define CDR(w) ((w)->d.word)
#define CAAR(w) ((w)->a.word->a.word)
#define CADR(w) ((w)->d.word->a.word)
#define CADDR(w) ((w)->d.word->d.word->a.word)
#define CADAR(w) ((w)->a.word->d.word->a.word)
#define CADDAR(w) ((w)->a.word->d.word->d.word->a.word)

/*
  COND:
  input: list of expressions and associated values
  output: first value whose expression evaluates to true
 */

struct interpreter {
        struct instream stream;
        struct Word t;
        struct Word nil;
        struct Word* env;
};

const char* intern(const char* str) {
        return g_intern_string(str);
}

struct Word* lisp_cons(struct interpreter* I, struct Word* a, struct Word* b);

gboolean init_interpreter(struct interpreter* I, const char* filename) {
        memset(I, 0, sizeof(struct interpreter));
        init_file_stream(&I->stream, filename);
        /* set env to () */
        I->t.a.umask = 1;
        I->t.d.num = 1;
        I->nil.a.word = NULL;
        I->nil.d.word = NULL;
        I->env = lisp_cons(I, NULL, NULL);
        return TRUE;
}

int get_char(struct interpreter* I) {
        return I->stream.get_char(I->stream.hstream);
}

void put_char(struct interpreter* I, int ch) {
        I->stream.put_char(ch, I->stream.hstream);
}

void print_atom(struct interpreter* I, struct Word* word) {
        if (WordNilP(word)) {
                puts("nil");
        }
        else {
                switch (WordAtomType(word)) {
                case WORDATOM_WORD:
                        printf("%p", ATOM_WORD(word));
                        break;
                case WORDATOM_NUM:
                        printf("%d", ATOM_NUM(word));
                        break;
                case WORDATOM_STR:
                        printf("%s", ATOM_STR(word));
                        break;
                default:
                        puts("***");
                        break;
                }
        }
}

void print_sexpr(struct interpreter* I, struct Word* word) {
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

void print_word_struct(struct interpreter* I, struct Word* word) {
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

void print_sexpr_verbose(struct interpreter* I, struct Word* word, int depth) {
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

struct Word* lisp_eq(struct interpreter* I, struct Word* x, struct Word* y) {
        return (WordAtomP(x) && WordAtomP(y) && (x->d.word == y->d.word)) ? &I->t : &I->nil;
}
struct Word* lisp_streq(struct interpreter* I, struct Word* x, const char* s) {
        return (WordAtomP(x) && (ATOM_STR(x) == s)) ? &I->t : &I->nil;
}

struct Word* lisp_eval(struct interpreter* I, struct Word* e);
struct Word* lisp_cond(struct interpreter* I, struct Word* e);


struct Word* lisp_cond(struct interpreter* I, struct Word* e) {
        while (e) {
                struct Word* cond0 = CAR(e);
                struct Word* e0 = CAR(cond0);
                struct Word* s1 = CDR(cond0);

                if (e0) {
                        e0 = lisp_eval(I, e0);
                        if (e0)
                                return s1;
                }
                e = CDR(e);
        }
        return &I->nil;
}

struct Word* lisp_cons(struct interpreter* I, struct Word* a, struct Word* b) {
        struct Word* ret = GC_malloc(sizeof(struct Word));
        SetWord(ret, a, b);
        return ret;
}

struct Word* lisp_list(struct interpreter* I, struct Word* a, struct Word* b) {
        return lisp_cons(I, a, lisp_cons(I, b, NULL));
}

struct Word* lisp_evlis(struct interpreter* I, struct Word* m) {
        if (WordNilP(m)) {
                return &I->nil;
        }
        else {
                return lisp_cons(I, lisp_eval(I, CAR(m)), lisp_evlis(I, CDR(m)));
        }
}

struct Word* lisp_assoc(struct interpreter* I, struct Word* m, struct Word* a) {
        if (lisp_eq(I, CAAR(a), m) != &I->nil) {
                return CADAR(a);
        }
        else {
                return lisp_assoc(I, m, CDR(a));
        }
}

struct Word* lisp_append(struct interpreter* I, struct Word* x, struct Word* y) {
        if (WordNilP(x))
                return y;
        else
                return lisp_cons(I, CAR(x), lisp_append(I, CDR(x), y));
}

struct Word* lisp_pair(struct interpreter* I, struct Word* x, struct Word* y) {
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

struct Word* lisp_eval(struct interpreter* I, struct Word* e) {
        static const char* squote = NULL;
        static const char* scar = NULL;
        static const char* scdr = NULL;
        static const char* satom = NULL;
        static const char* scond = NULL;
        static const char* scons = NULL;
        static const char* seq = NULL;
        static const char* slabel = NULL;
        static const char* slambda = NULL;

        if (squote == NULL) {
                squote = intern("quote");
                scar = intern("car");
                scdr = intern("cdr");
                satom = intern("atom");
                scond = intern("cond");
                scons = intern("cons");
                seq = intern("eq");
                slabel = intern("label");
                slambda = intern("lambda");
        }

        if (WordNilP(e)) {
                return &I->nil;
        } else if (WordAtomP(e)) {
                return e;
        }
        else if (WordAtomP(CAR(e))) {
                // todo: apply
                struct Word* car = lisp_eval(I, CAR(e));
                const char* astr = ATOM_STR(car);
                if (astr == squote) {
                        return CADR(e);
                }
                else if (astr == satom) {
                        struct Word* ret = lisp_eval(I, CADR(e));
                        if (WordAtomP(ret))
                                return ret;
                        else
                                return &I->nil;
                }
                else if (astr == seq) {
                        return lisp_eq(I, lisp_eval(I, CADR(e)), lisp_eval(I, CADDR(e)));
                }
                else if (astr == scond) {
                        struct Word* c = CDR(e);
                        while (!WordNilP(c)) {
                                struct Word* r = lisp_eval(I, CAAR(c));
                                if (!WordNilP(r)) {
                                        return lisp_eval(I, CADAR(c));
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
                        return CAR(lisp_eval(I, CADR(e)));
                }
                else if (astr == scdr) {
                        return CDR(lisp_eval(I, CADR(e)));
                }
                else if (astr == scons) {
                        return lisp_cons(I, lisp_eval(I, CADR(e)), lisp_eval(I, CADDR(e)));
                }
                else {
                        return lisp_eval(I, lisp_cons(I, lisp_assoc(I, CAR(e), I->env), CDR(e)));
                }
        }
        else if (lisp_streq(I, CAAR(e), slabel) != &I->nil) {
                I->env = lisp_cons(I, lisp_list(I, CADAR(e), CAR(e)), I->env);
                return lisp_eval(I, lisp_cons(I, CADDAR(e), CDR(e)));
        }
        else if (lisp_streq(I, CAAR(e), slambda) != &I->nil) {
                I->env = lisp_append(I, lisp_pair(I, CADAR(e), lisp_evlis(I, CDR(e))), I->env);
                return lisp_eval(I, CADDAR(e));
        }
        else {
                printf("Eval error:");
                print_sexpr(I, e);
                return &I->nil;
        }
}


struct Word* lisp_read(struct interpreter* I);

struct Word* lisp_read_atom(struct interpreter* I);
struct Word* lisp_read_list(struct interpreter* I);

int num_objects_created = 0;

struct Word* lisp_read(struct interpreter* I) {
        int ch;
        struct Word* ret;
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
                        struct Word* name;
                        if (!squote) {
                                squote = intern("quote");
                        }
                        name = lisp_cons(I, NULL, NULL);
                        SetAtomStr(name, squote);
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

struct Word* lisp_read_atom(struct interpreter* I) {
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
                struct Word* atom = lisp_cons(I, NULL, NULL);
                SetAtomNum(atom, atoi(buf));
                return atom;
        }
        else if (isalpha(ch)) {
                /* parse symbol */
                int i = 0;
                while (isalnum(ch)) {
                        buf[i++] = ch;
                        ch = get_char(I);
                }
                buf[i] = 0;
                put_char(I, ch); // rewind
                num_objects_created++;
                struct Word* atom = lisp_cons(I, NULL, NULL);
                SetAtomStr(atom, intern(buf));
                return atom;
        }
        else if (ch == '"') {
                /* parse string */
                return NULL;
        }
        else {
                if (isgraph(ch))
                        printf("Unknown token: %c\n", ch);
                return NULL;
        }
}

struct Word* lisp_read_list(struct interpreter* I) {
        int ch;
        ch = get_char(I);
        if (ch != '(')
                return NULL;

        num_objects_created++;

        struct Word* head = lisp_cons(I, NULL, NULL);
        struct Word* prev = NULL;
        struct Word* curr = head;

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

void lisp_loop(struct interpreter* I, struct Word* word) {
        const char* STOP = intern("stop");
        while (1) {
                if (WordNilP(word)) {
                        print_atom(I, word);
                        puts("");
                        word = lisp_read(I);
                        if (word == NULL)
                                return;
                        word = lisp_eval(I, word);
                }
                else if (WordAtomP(word)) {
                        if (ATOM_STR(word) == STOP)
                                return;
                        print_atom(I, word);
                        puts("");
                        word = lisp_read(I);
                        if (word == NULL)
                                return;
                        word = lisp_eval(I, word);
                }
                else {
                        print_sexpr(I, word);
                        puts("");
                        word = lisp_read(I);
                        if (word == NULL)
                                return;
                        word = lisp_eval(I, word);
                }
        }
}

int main(int argc, char* argv[]) {
        struct interpreter i;
        struct interpreter* I = &i;
        GC_INIT();
        init_interpreter(I, argv[1]);

        num_objects_created = 0;
        struct Word* lst = lisp_read(I);
        /*printf("read %d objects\n", num_objects_created);*/

        lst = lisp_eval(I, lst);

        /*print_sexpr_verbose(I, lst, 0);*/
        lisp_loop(I, lst);

        printf("\n");
        return 0;
}
