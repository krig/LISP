#include <glib.h>
#include <stdio.h>

#include "stream.h"

void file_close_stream(void* hstream) {
        fclose((FILE*)hstream);
}

int file_get_char(void* hstream) {
        return fgetc((FILE*)hstream);
}

void file_put_char(int ch, void* hstream) {
        ungetc(ch, (FILE*)hstream);
}

gboolean init_file_stream(struct instream* stream, const char* filename) {
        stream->hstream = fopen(filename, "r");
        if (!stream->hstream)
                return FALSE;
        stream->close_stream = &file_close_stream;
        stream->get_char = &file_get_char;
        stream->put_char = &file_put_char;
        return TRUE;
}
