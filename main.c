#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "stream.h"

struct cons_cell {
        struct cons_cell* car;
        struct cons_cell* cdr;
};

struct interpreter {
        struct instream stream;
};

int init_interpreter(struct interpreter* I) {
        memset(I, 0, sizeof(struct interpreter));
}

int main(int argc, char* argv[]) {
        struct interpreter i;
        init_interpreter(&i);
        init_file_stream(&i.stream, argv[1]);
        printf("%c\n", i.stream.get_char(i.stream.hstream));
        return 0;
}
