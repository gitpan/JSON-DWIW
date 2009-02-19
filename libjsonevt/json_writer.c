/* Creation date: 2008-11-27T07:33:50Z
 * Authors: Don
 */

/*

 Copyright (c) 2008 Don Owens <don@regexguy.com>.  All rights reserved.

 This is free software; you can redistribute it and/or modify it under
 the Perl Artistic license.  You should have received a copy of the
 Artistic license with this distribution, in the file named
 "Artistic".  You may also obtain a copy from
 http://regexguy.com/license/Artistic

 This program is distributed in the hope that it will be useful, but
 WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

*/

/* $Header: /repository/projects/libjsonevt/json_writer.c,v 1.2 2008/11/27 11:51:13 don Exp $ */

#include "jsonevt_private.h"

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <sys/types.h>



typedef enum { unknown, str, array, hash } jsonevt_data_type;

struct jsonevt_writer_data_struct {
    jsonevt_data_type type;
};

struct jsonevt_str_struct {
    jsonevt_data_type type;
    size_t max_size;
    size_t used_size;
    char * str;
};

/* typedef struct jsonevt_str_struct json_str_ctx; */


struct json_array_flags {
    int started:1;
    int ended: 1;
    int pad:30;
};

struct jsonevt_array_struct {
    jsonevt_data_type type;
    jsonevt_str * str_ctx;
    size_t count;
    struct json_array_flags flags;
};

struct json_hash_flags {
    int started:1;
    int ended: 1;
    int pad:30;
};

struct jsonevt_hash_struct {
    jsonevt_data_type type;
    jsonevt_str * str_ctx;
    size_t count;
    struct json_hash_flags flags;
};


static void *
_json_malloc(size_t size) {
    return malloc(size);
}

static void *
_json_realloc(void *buf, size_t size) {
    return realloc(buf, size);
}

static char *
json_ensure_buf_size(jsonevt_str * ctx, size_t size) {
    if (size == 0) {
        size = 1;
    }

    if (ctx->str == 0) {
        ctx->str = _json_malloc(size);
        ctx->max_size = size;
    }
    else if (size > ctx->max_size) {
        ctx->str = _json_realloc(ctx->str, size);
        ctx->max_size = size;
    }

    return ctx->str;
}

static jsonevt_str *
json_new_str(size_t size) {
    jsonevt_str * ctx = _json_malloc(sizeof(jsonevt_str));
    
    memset(ctx, 0, sizeof(jsonevt_str));

    if (size > 0) {
        json_ensure_buf_size(ctx, size + 1);
    }

    return ctx;
}

static void
json_free_str(jsonevt_str * ctx) {

    if (! ctx) {
        return;
    }

    if (ctx->str) {
        free(ctx->str);
    }

    free(ctx);
}

static void
json_str_disown_buffer(jsonevt_str *ctx) {
    if (ctx) {
        memset(ctx, 0, sizeof(jsonevt_str));
    }
}

static int
json_append_bytes(jsonevt_str * ctx, char * str, size_t length) {
    size_t new_size;

    if (ctx->max_size - ctx->used_size < length + 1) {
        new_size = length + 1 + ctx->used_size;
        json_ensure_buf_size(ctx, new_size);
    }

    memcpy(&(ctx->str[ctx->used_size]), str, length);
    ctx->used_size += length;
    ctx->str[ctx->used_size] = '\x00';

    return 1;
}

static int
json_append_one_byte(jsonevt_str * ctx, char to_append) {
    return json_append_bytes(ctx, &to_append, 1);
}

static int
json_append_unicode_char(jsonevt_str * ctx, uint32_t code_point)  {
    uint32_t size = 0;
    uint8_t bytes[4];

    size = utf8_unicode_to_bytes(code_point, bytes);
    
    return json_append_bytes(ctx, (char *)bytes, size);
}

static char *
json_get_str_buffer(jsonevt_str * ctx, size_t * size) {
    if (size) {
        *size = ctx->used_size;
    }
    
    return ctx->str;
}

static jsonevt_str *
json_escape_c_buffer(char * str, size_t length, unsigned long options) {
    jsonevt_str * ctx = json_new_str(length + 1);
    size_t i;
    uint32_t this_char;
    char * tmp_buf = NULL;
    uint32_t char_len = 0;

    /* opening quotes */
    json_append_one_byte(ctx, '"');

    for (i = 0; i < length;) {
        this_char = utf8_bytes_to_unicode((uint8_t *)str + i, length - i - 1, &char_len);
        if (char_len == 0) {
            /* bad utf-8 sequence */
            /* for now, assume latin-1 and convert to utf-8 */
            char_len = 1;
            this_char = str[i];
        }

        i += char_len;

        switch (this_char) {
          case '\\':
              json_append_bytes(ctx, "\\\\", 2);
              break;

          case '"':
              json_append_bytes(ctx, "\\\"", 2);
              break;

          case '/':
              json_append_bytes(ctx, "\\/", 2);
              break;
              
          case 0x08:
              json_append_bytes(ctx, "\\b", 2);
              break;
              
          case 0x0c:
              json_append_bytes(ctx, "\\f", 2);
              break;
              
          case 0x0a:
              json_append_bytes(ctx, "\\n", 2);
              break;
              
          case 0x0d:
              json_append_bytes(ctx, "\\r", 2);
              break;
              
          case 0x09:
              json_append_bytes(ctx, "\\t", 2);
              break;
              

          default:
              if (this_char < 0x1f || ( this_char >= 0x80 && (options & JSON_EVT_OPTION_ASCII) ) ) {
                  js_asprintf(&tmp_buf, "\\u%04x", this_char);
                  json_append_bytes(ctx, tmp_buf, strlen(tmp_buf));
                  free(tmp_buf); tmp_buf = NULL;
              }
              else {
                  json_append_unicode_char(ctx, this_char);
              }

              break;
        }
    }

    /* closing quotes */
    json_append_one_byte(ctx, '"');

    return ctx;
}

char *
jsonevt_escape_c_buffer(char * in_buf, size_t length_in, size_t *length_out,
    unsigned long options) {

    jsonevt_str *str = json_escape_c_buffer(in_buf, length_in, options);
    char *ret_buf;

    ret_buf = json_get_str_buffer(str, length_out);
    json_str_disown_buffer(str);
    json_free_str(str);

    return ret_buf;
}

jsonevt_array *
jsonevt_new_array() {
    jsonevt_array * ctx = _json_malloc(sizeof(jsonevt_array));
    memset(ctx, 0, sizeof(jsonevt_array));

    return ctx;
}

void
jsonevt_free_array(jsonevt_array * ctx) {
     UNLESS (ctx) {
        return;
    }

    if (ctx->str_ctx) {
        json_free_str(ctx->str_ctx);
    }

    free(ctx);
}

void
jsonevt_array_start(jsonevt_array * ctx) {
    UNLESS (ctx->flags.started) {
        ctx->str_ctx = json_new_str(1);
        json_append_one_byte(ctx->str_ctx, '[');

        ctx->flags.started = 1;
    }
}

void
jsonevt_array_end(jsonevt_array * ctx) {
    json_append_one_byte(ctx->str_ctx, ']');
    ctx->flags.ended = 1;
}


char *
jsonevt_array_get_string(jsonevt_array * ctx, size_t * length_ptr) {
    UNLESS (ctx->str_ctx) {
        return NULL;
    }

    if (length_ptr) {
        *length_ptr = ctx->str_ctx->used_size;
    }

    return ctx->str_ctx->str;
}


int
jsonevt_array_append_raw_element(jsonevt_array * ctx, char * buf, size_t length) {
    UNLESS (ctx->flags.started) {
        ctx->str_ctx = json_new_str(1 + length);
        json_append_one_byte(ctx->str_ctx, '[');
        ctx->flags.started = 1;
    }
    else if (ctx->count > 0) {
        json_append_one_byte(ctx->str_ctx, ',');
    }

    json_append_bytes(ctx->str_ctx, buf, length);
    ctx->count++;

    return 1;
}

int
jsonevt_array_append_element(jsonevt_array * ctx, char * buf, size_t length) {
    jsonevt_str * str_ctx = json_escape_c_buffer(buf, length, JSON_EVT_OPTION_NONE);
    int rv;

    rv = jsonevt_array_append_raw_element(ctx, str_ctx->str, str_ctx->used_size);
    json_free_str(str_ctx);
    return rv;
}

int
jsonevt_array_append_string_element(jsonevt_array * array, char * buf) {
    return jsonevt_array_append_element(array, buf, strlen(buf));
}

void
jsonevt_array_disown_buffer(jsonevt_array *array) {
    json_str_disown_buffer(array->str_ctx);
}

jsonevt_hash *
jsonevt_new_hash() {
    jsonevt_hash * hash = (jsonevt_hash *)_json_malloc(sizeof(jsonevt_hash));
    memset(hash, 0, sizeof(jsonevt_hash));

    return hash;
}

void
jsonevt_free_hash(jsonevt_hash * ctx) {
    UNLESS (ctx) {
        return;
    }

    if (ctx->str_ctx) {
        json_free_str(ctx->str_ctx);
    }

    free(ctx);
}

void
jsonevt_hash_start(jsonevt_hash * ctx) {
    if (! ctx->flags.started) {
        ctx->str_ctx = json_new_str(0);
        json_append_one_byte(ctx->str_ctx, '{');
        ctx->flags.started = 1;
    }
}

void
jsonevt_hash_end(jsonevt_hash * ctx) {
    json_append_one_byte(ctx->str_ctx, '}');
}

char *
jsonevt_hash_get_string(jsonevt_hash * ctx, size_t * length_ptr) {
    if (! ctx->str_ctx) {
        return NULL;
    }

    if (length_ptr) {
        *length_ptr = ctx->str_ctx->used_size;
    }

    return ctx->str_ctx->str;
}

char *
jsonevt_get_data_string(jsonevt_writer_data *ctx, size_t *length_ptr) {
    UNLESS (ctx) {
        *length_ptr = 0;
        return NULL;
    }

    if (ctx->type == array) {
        return jsonevt_array_get_string((jsonevt_array *)ctx, length_ptr);
    }
    else if (ctx->type == hash) {
        return jsonevt_hash_get_string((jsonevt_hash *)ctx, length_ptr);
    }
    else if (ctx->type == str) {
        return json_get_str_buffer((jsonevt_str *)ctx, length_ptr);
    }

    *length_ptr = 0;
    return NULL;
}

int
jsonevt_hash_append_raw_entry(jsonevt_hash * ctx, char * key, size_t key_size, char * val,
    size_t val_size) {
    jsonevt_str * key_ctx = json_escape_c_buffer(key, key_size, JSON_EVT_OPTION_NONE);

    if (! ctx->flags.started) {
        /* add 3 -- 1 for open brace, 1 for closing brace, one for the colon */
        ctx->str_ctx = json_new_str(3 + key_ctx->used_size + val_size);
        json_append_one_byte(ctx->str_ctx, '{');
        ctx->flags.started = 1;
    }
    else if (ctx->count > 0) {
        json_append_one_byte(ctx->str_ctx, ',');
    }

    json_append_bytes(ctx->str_ctx, key_ctx->str, key_ctx->used_size);
    json_append_one_byte(ctx->str_ctx, ':');
    json_append_bytes(ctx->str_ctx, val, val_size);
    ctx->count++;

    json_free_str(key_ctx);

    return 1;
}

int
jsonevt_hash_append_entry(jsonevt_hash * ctx, char * key, size_t key_size, char * val,
    size_t val_size) {
    jsonevt_str * val_ctx = json_escape_c_buffer(val, val_size, JSON_EVT_OPTION_NONE);
    int rv;

    rv = jsonevt_hash_append_raw_entry(ctx, key, key_size, val_ctx->str, val_ctx->used_size);
    json_free_str(val_ctx);
    return rv;
}

int
jsonevt_hash_append_string_entry(jsonevt_hash * hash, char * key, char * val) {
    return jsonevt_hash_append_entry(hash, key, strlen(key), val, strlen(val));
}

void
jsonevt_hash_disown_buffer(jsonevt_hash *hash) {
    json_str_disown_buffer(hash->str_ctx);
}
