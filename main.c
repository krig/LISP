#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <glib.h>
#include <gc/gc.h>
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
        address_t address;
        decrement_t decrement;
};

#define WordAtomP(w) ((w)->address.umask &= 1)
#define WordAtomType(w) ((w)->address.umask & 0xfffffff0)

#define WordNilP(w) ((w)->address.word == NULL && (w)->decrement.word == NULL)

#define WORDATOM_WORD 0
#define WORDATOM_NUM 0x10
#define WORDATOM_STR 0x20

#define ATOM_STR(w) ((WordAtomType(w)==WORDATOM_STR) ? ((w)->decrement.str) : NULL)
#define ATOM_NUM(w) ((WordAtomType(w)==WORDATOM_NUM) ? ((w)->decrement.num) : 0)
#define ATOM_WORD(w) ((WordAtomType(w)==WORDATOM_WORD) ? ((w)->decrement.word) : NULL)

#define CAR(w) ((w)->address.word)
#define CDR(w) ((w)->decrement.word)

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

gboolean init_interpreter(struct interpreter* I, const char* filename) {
        memset(I, 0, sizeof(struct interpreter));
        init_file_stream(&I->stream, filename);
        /* set env to () */
        I->t.address.umask = 1;
        I->t.decrement.num = 1;
        I->nil.address.word = NULL;
        I->nil.decrement.word = NULL;
        I->env = &I->nil;
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
        puts("(");
        if (WordAtomP(CAR(word))) {
                print_atom(I, CAR(word));
        }
        else {
                print_sexpr(I, CAR(word));
        }
        puts(" ");
        if (WordAtomP(CDR(word))) {
                print_atom(I, CDR(word));
        }
        else {
                print_sexpr(I, CDR(word));
        }
        puts(")");
}

struct Word* eq(struct interpreter* I, struct Word* x, struct Word* y) {
        return (WordAtomP(x) && WordAtomP(y) && (x->decrement.word == y->decrement.word)) ? &I->t : &I->nil;
}

struct Word* cond(struct interpreter* I, struct Word* e) {
        return &I->nil;
}

struct Word* eval(struct interpreter* I, struct Word* e) {
        return e;
}

struct Word* read(struct interpreter* I) {
        return NULL;
}

void loop(struct interpreter* I, struct Word* word) {
        const char* STOP = intern("stop");
        const char* QUOTE = intern("quote");
        while (1) {
                if (word == NULL) {
                        return;
                }
                else if (WordNilP(word)) {
                        print_atom(I, word);
                        word = eval(I, read(I));
                }
                else if (WordAtomP(word)) {
                        if (ATOM_STR(word) == STOP)
                                return;
                        print_atom(I, word);
                        word = eval(I, read(I));
                }
                else if (WordAtomP(CAR(word)) && ATOM_STR(CAR(word)) == QUOTE) {
                        print_sexpr(I, word);
                        word = eval(I, read(I));
                }
                else {
                        word = eval(I, word);
                }
        }
}

int main(int argc, char* argv[]) {
        struct interpreter i;
        struct interpreter* I = &i;
        init_interpreter(I, argv[1]);

        print_atom(I, I->env);

        loop(I, eval(I, read(I)));

        return 0;
}
