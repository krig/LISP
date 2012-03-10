/* -*- c-basic-offset: 8 -*- */
#ifndef _STREAM_H_
#define _STREAM_H_

struct instream {
        void* hstream;
        void (*close_stream)(struct instream*);
        int (*get_char)(struct instream*);
        void (*put_char)(struct instream*, int);
};

int init_file_stream(struct instream* stream, const char* filename);

#endif//_STREAM_H_
