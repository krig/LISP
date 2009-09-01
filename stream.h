#ifndef _STREAM_H_
#define _STREAM_H_

struct instream {
        void* hstream;
        void (*close_stream)(void*);
        int (*get_char)(void*);
        void (*put_char)(int, void*);
};

gboolean init_file_stream(struct instream* stream, const char* filename);

#endif//_STREAM_H_
