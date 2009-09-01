#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <glib.h>
#include "stream.h"

/*
  COND:
  input: list of expressions and associated values
  output: first value whose expression evaluates to true
 */

struct cons_cell {
        struct cons_cell* car;
        struct cons_cell* cdr;
};

struct interpreter {
        struct instream stream;
};

gboolean init_interpreter(struct interpreter* I, const char* filename) {
        memset(I, 0, sizeof(struct interpreter));
        init_file_stream(&I->stream, filename);
        return TRUE;
}

const char* intern(const char* str) {
        return g_intern_string(str);
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
        return 0;
}
