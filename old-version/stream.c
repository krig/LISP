/* -*- c-basic-offset: 8 -*- */
#include <stdio.h>
#include "stream.h"

void file_close_stream(struct instream* s) {
        fclose((FILE*)s->hstream);
}

int file_get_char(struct instream* s) {
        return fgetc((FILE*)s->hstream);
}

void file_put_char(struct instream* s, int ch) {
        ungetc(ch, (FILE*)s->hstream);
}

int init_file_stream(struct instream* stream, const char* filename) {
        stream->hstream = fopen(filename, "r");
        if (!stream->hstream)
                return 0;
        stream->close_stream = &file_close_stream;
        stream->get_char = &file_get_char;
        stream->put_char = &file_put_char;
        return 1;
}
