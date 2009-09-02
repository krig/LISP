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
#define WordAtomType(w) ((w)->address.umask & 0x00000006)

#define WORDATOM_WORD 0
#define WORDATOM_NUM 2
#define WORDATOM_STR 6

/*
  COND:
  input: list of expressions and associated values
  output: first value whose expression evaluates to true
 */

struct slot { /* represents a value */
        unsigned int type;
        union {
                int number;
                const char* str;
                void* voidp;
        } data;
};

#define SLOT_SYMBOL 0
#define SLOT_NUMBER 1
#define SLOT_STRING 2
#define SLOT_DATA 3

typedef union {
        struct slot* atom;
        struct pair* pair;
} pair_entry_t;

struct pair {
        pair_entry_t car;
        pair_entry_t cdr;
        unsigned int meta;
};

#define car_atom_p(p) (((p)->meta)&1)
#define car_pair_p(p) ((((p)->meta)&1) == 0)
#define cdr_atom_p(p) (((p)->meta)&2)
#define cdr_pair_p(p) ((((p)->meta)&2) == 0)
#define car_atom(p) ((p)->car.atom)
#define car_pair(p) ((p)->car.pair)
#define cdr_atom(p) ((p)->cdr.atom)
#define cdr_pair(p) ((p)->cdr.pair)
#define car_nil_p(p) ((p)->car.pair == NULL)
#define set_car_atom(p, a) do { struct pair* _setptr = (p); _setptr->meta |= 1; _setptr->car.atom = (a); } while(0)
#define set_cdr_atom(p, a) do { struct pair* _setptr = (p); _setptr->meta |= 2; _setptr->cdr.atom = (a); } while(0)
#define set_car_pair(p, r) do { struct pair* _setptr = (p); _setptr->meta &= ~1; _setptr->car.pair = (r); } while(0)
#define set_cdr_pair(p, r) do { struct pair* _setptr = (p); _setptr->meta &= ~2; _setptr->cdr.pair = (r); } while(0)
#define set_nil_pair(p) do { struct pair* _setptr = (p); _setptr->meta = 0; _setptr->car.pair = _setptr->cdr.pair = NULL; } while(0)

struct interpreter {
        struct instream stream;
        struct slot* T;
};

const char* intern(const char* str) {
        return g_intern_string(str);
}

gboolean init_interpreter(struct interpreter* I, const char* filename) {
        memset(I, 0, sizeof(struct interpreter));
        init_file_stream(&I->stream, filename);
        I->T = GC_MALLOC(sizeof(struct slot));
        I->T->type = SLOT_SYMBOL;
        I->T->data.str = intern("true");
        return TRUE;
}

int get_char(struct interpreter* I) {
        return I->stream.get_char(I->stream.hstream);
}

void put_char(struct interpreter* I, int ch) {
        I->stream.put_char(ch, I->stream.hstream);
}

int main(int argc, char* argv[]) {
        struct interpreter i;
        struct interpreter* I = &i;
        init_interpreter(I, argv[1]);
        printf("%c\n", get_char(I));

        struct slot* s1 = GC_MALLOC(sizeof(struct slot));
        struct slot* s2 = GC_MALLOC(sizeof(struct slot));

        struct pair* p1 = GC_MALLOC(sizeof(struct pair));
        struct pair* p2 = GC_MALLOC(sizeof(struct pair));

        set_nil_pair(p1);
        set_nil_pair(p2);
        set_car_pair(p1, p2);
        set_cdr_atom(p1, s1);
        set_car_atom(p2, s2);
        set_cdr_pair(p2, NULL);

        printf("(car %d/%d) (cdr %d/%d) (%u)\n",
               car_atom_p(p1),
               car_pair_p(p1),
               cdr_atom_p(p1),
               cdr_pair_p(p1),
               p1->meta);
        printf("(car %d/%d) (cdr %d/%d) (%u)\n",
               car_atom_p(p2),
               car_pair_p(p2),
               cdr_atom_p(p2),
               cdr_pair_p(p2),
               p2->meta);
        
        return 0;
}
