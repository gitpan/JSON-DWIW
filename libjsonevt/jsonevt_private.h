/* Creation date: 2007-07-18 00:51:42
 * Authors: Don
 */

/*

 Copyright (c) 2007 Don Owens <don@regexguy.com>.  All rights reserved.

 This is free software; you can redistribute it and/or modify it under
 the Perl Artistic license.  You should have received a copy of the
 Artistic license with this distribution, in the file named
 "Artistic".  You may also obtain a copy from
 http://regexguy.com/license/Artistic

 This program is distributed in the hope that it will be useful, but
 WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

*/

/* $Header: /repository/projects/libjsonevt/jsonevt_private.h,v 1.22 2008/01/03 04:40:18 don Exp $ */

#include <string.h>

#include "jsonevt.h"

typedef struct {
    char * buf;
    uint len;
} json_datum;

struct context_flags_struct {
    int have_char:1;
    int pad:7;
};

struct json_extern_ctx {
    char * error;
    uint error_byte_pos;
    uint error_char_pos;
    uint error_line;
    uint error_byte_col;
    uint error_char_col;
    void * cb_data;
    json_string_cb string_cb;
    json_array_begin_cb begin_array_cb;
    json_array_end_cb end_array_cb;
    json_array_begin_element_cb begin_array_element_cb;
    json_array_end_element_cb end_array_element_cb;
    json_hash_begin_cb begin_hash_cb;
    json_hash_end_cb end_hash_cb;
    json_hash_begin_entry_cb begin_hash_entry_cb;
    json_hash_end_entry_cb end_hash_entry_cb;
    json_number_cb number_cb;
    json_bool_cb bool_cb;
    json_null_cb null_cb;
    json_comment_cb comment_cb;

    uint string_count;
    uint longest_string_bytes;
    uint longest_string_chars;
    uint number_count;
    uint bool_count;
    uint null_count;
    uint hash_count;
    uint array_count;
    uint deepest_level;
    uint line;
    uint byte_count;
    uint char_count;

    uint options;
    uint bad_char_policy;
};

typedef struct {
    char * buf;
    uint len;
    uint pos;
    uint char_pos;
    void * cb_data;
    json_string_cb string_cb;
    json_array_begin_cb begin_array_cb;
    json_array_end_cb end_array_cb;
    json_array_begin_element_cb begin_array_element_cb;
    json_array_end_element_cb end_array_element_cb;
    json_hash_begin_cb begin_hash_cb;
    json_hash_end_cb end_hash_cb;
    json_hash_begin_entry_cb begin_hash_entry_cb;
    json_hash_end_entry_cb end_hash_entry_cb;
    json_number_cb number_cb;
    json_bool_cb bool_cb;
    json_null_cb null_cb;
    json_comment_cb comment_cb;

    uint cur_char;
    uint cur_char_len;
    uint cur_byte_pos;
    uint cur_char_pos;
    uint cur_line;
    uint cur_byte_col;
    uint cur_char_col;

    uint options;
    uint bad_char_policy;

    struct context_flags_struct flags;
    jsonevt_ctx * ext_ctx;
} json_context;

struct str_flags_struct {
    int using_orig:1;
    int pad:6;
};

typedef struct {
    char * buf;
    uint len;
    uint pos;
    char * stack_buf;
    uint stack_buf_len;
    struct str_flags_struct flags;
} json_str; /* used to build up string when parsing */

#define JSON_DO_DEBUG 0

#if JSON_DO_DEBUG
#define JSON_DEBUG(...) (printf("%s (%d) - ", __FILE__, __LINE__), printf(__VA_ARGS__), printf("\n"), fflush(stdout))
#else
#define JSON_DEBUG(...) ;
#endif

#if 0
#define PDB(...) fprintf(stderr, "in %s, line %d of %s: ", __func__, __LINE__, __FILE__); \
    fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); fflush(stderr)
#else
#define PDB(...)
#endif

#ifdef JSONEVT_ON_WINDOWS
#define JSONEVT_INLINE_FUNC
#else
#define JSONEVT_INLINE_FUNC inline
#endif

#ifdef JSONEVT_ON_WINDOWS
#define _CRT_SECURE_NO_WARNINGS
#endif

#define UNLESS(stuff) if (! stuff)

#define BUF_EQ(buf1, buf2, len) ( strncmp(buf1, buf2, len) == 0 )
#define MEM_EQ(buf1, buf2, len) ( memcmp(buf1, buf2, len) == 0 )

#define STATIC_BUF_SIZE 32

/* linefeed or line separator */
#define JSON_IS_END_OF_LINE(ch) ( (ch) == 0x0a || (ch) == 0x2028)

#define NEXT_CHAR(c) (next_char(c))
#define PEEK_CHAR(ctx) ( (ctx)->flags.have_char ? (ctx)->cur_char : peek_char(ctx) )
#define PEEK_CHAR_LEN(c) (c->cur_char_len);

#define HAVE_MORE_CHARS(ctx) (ctx->pos >= ctx->len ? 0 : 1)
#define GET_BUF(c) ((c)->buf)
#define GET_STACK_BUF(c) ((c)->stack_buf)
#define GET_STACK_BUF_LEN(s) ((s)->stack_buf_len)
#define USING_STACK_BUF(s) ((s)->stack_buf && (s)->buf == (s)->stack_buf)
#define USING_ORIG_BUF(s) ((s)->flags.using_orig)
#define CUR_POS(c) ((c)->cur_byte_pos)
#define CUR_CHAR(c) ( (c)->cur_char )
#define CUR_CHAR_POS(c) ((c)->cur_char_pos)
#define CUR_LINE(ctx) ((ctx)->cur_line)
#define CUR_COL(ctx) ((ctx)->cur_char_col)
#define CUR_BYTE_COL(ctx) ((ctx)->cur_byte_col)
#define CUR_BUF(c) (&c->buf[c->pos])
#define BUF_POS(c) ( (c)->pos )
#define BYTES_LEFT(c) ((c)->len - (c)->pos)
#define INIT_JSON_STR(s) ( memzero(s, sizeof(json_str)) )

#define INCR_DATA_DEPTH(ctx, level) if (level > (ctx)->ext_ctx->deepest_level) \
        { (ctx)->ext_ctx->deepest_level = level; }

#define UPDATE_STATS_STRING_BYTES(ctx, len) if (len > (ctx)->ext_ctx->longest_string_bytes) \
        { (ctx)->ext_ctx->longest_string_bytes = len; }

#define UPDATE_STATS_STRING_CHARS(ctx, len) if (len > (ctx)->ext_ctx->longest_string_chars) \
        { (ctx)->ext_ctx->longest_string_chars = len; }


#define CLEAR_JSON_STR(s) JSON_DEBUG("CLEAR_JSON_STR() called"); \
    if (! (USING_ORIG_BUF(s) || USING_STACK_BUF(s)) ) { free((void *)((s)->buf)); (s)->buf = NULL; }

#define INIT_JSON_STR_STATIC_BUF(s, s_buf, s_len, st_buf, st_buf_len) \
    ( memzero((void *)(s), sizeof(json_str)), (s)->flags.using_orig = 1,  \
        (s)->buf = (s_buf), (s)->len = s_len,\
        (s)->stack_buf = st_buf, (s)->stack_buf_len = st_buf_len )

#define ALLOC_NEW_BUF(s, size) JSON_DEBUG("ALLOC_NEW_BUF() called for size %u", size); (s)->buf = (char *)malloc(size); (s)->len = size

#define DO_REALLOC(buf, size) (buf ? realloc(buf, size) : malloc(size))
#define REALLOC_BUF(s, size) if (USING_STACK_BUF(s)) { switch_from_static_buf(s, size); } else { \
        JSON_DEBUG("reallocing %p", (s)->buf); (s)->buf = (char *)DO_REALLOC((void *)((s)->buf), size); (s)->len = size; }

#define SWITCH_FROM_STATIC(s) JSON_DEBUG("SWITCH_FROM_STATIC() called"); if (USING_ORIG_BUF(s)) { switch_from_static_buf(s, 0); }

#define GROW_JSON_STR(s, min_size) if (min_size > (s)->len) { \
        if (USING_ORIG_BUF(s)) { SWITCH_FROM_STATIC(s); REALLOC_BUF((s), min_size); } \
        else { REALLOC_BUF((s), min_size); } }

/*
#define GROW_JSON_STR(s, min_size) (min_size > (s)->len ? (USING_ORIG_BUF(s) ? \
            (SWITCH_TO_DYNAMIC(s), REALLOC_BUF((s), min_size)) : REALLOC_BUF((s), min_size)) : 0)
            */

#define APPEND_BYTES(s, bytes, len) GROW_JSON_STR(s, len);          \
    memcpy(&((s)->buf[(s)->pos]), bytes, len); (s)->pos += len

#define MAYBE_APPEND_BYTES(s, bytes, len) if (USING_ORIG_BUF(s)) {      \
        (s)->pos += len; } else { APPEND_BYTES(s, bytes, len); }

#define EAT_WHITESPACE(s, f) eat_whitespace(s, f, __LINE__)

#define CB_OK_VAL 0
#define CB_IS_TERM(the_call) (the_call ? 1 : 0)

#define DO_GEN_CALLBACK(ctx, c_name, flags, level) ( (ctx)->c_name ? \
        (ctx)->c_name((ctx)->cb_data, flags, level) : CB_OK_VAL)

#define DO_BOOL_CALLBACK(ctx, val, flags, level) ( (ctx)->bool_cb ?  \
        (ctx)->bool_cb((ctx)->cb_data, val, flags, level) : CB_OK_VAL)

#define SET_CB_ERROR(ctx, cb_name) set_error(ctx, __FILE__, __LINE__, \
            "early termination from %s callback", cb_name)

#define RET_CB_TERM(ctx, cb_name) SET_CB_ERROR(ctx, cb_name); return 0

/* return with early-termination code if the callback indicated we should do so */
#define DO_CB_WITH_RET(ctx, cb_name, the_call) if (CB_IS_TERM(the_call)) { RET_CB_TERM(ctx, cb_name); }

#define DO_BOOL_CALLBACK_WITH_RET(ctx, val, flags, level) \
    DO_CB_WITH_RET(ctx, "bool", DO_BOOL_CALLBACK(ctx, val, flags, level))

#define DO_GEN_CALLBACK_WITH_RET(ctx, c_name, flags, level, c_name_str) \
    DO_CB_WITH_RET(ctx, c_name_str, DO_GEN_CALLBACK(ctx, c_name, flags, level))

#define DO_COMMENT_CALLBACK(ctx, data, data_len, flags) ( (ctx)->comment_cb ? \
        (ctx)->comment_cb((ctx)->cb_data, data, data_len, flags, 0) : CB_OK_VAL )

#define DO_COMMENT_CALLBACK_WITH_RET(ctx, data, data_len, flags) \
    DO_CB_WITH_RET(ctx, "comment", DO_COMMENT_CALLBACK(ctx, data, data_len, flags))

 /* Portions of the code below were taken from the Perl source */

#ifndef JSONEVT_PRIVATE_H
#define JSONEVT_PRIVATE_H

#include "jsonevt.h"

JSON_DO_CPLUSPLUS_WRAP_BEGIN

typedef unsigned char U8;

/* utf8 macros from Perl source */
#define NATIVE_TO_ASCII(ch)      (ch)
#define ASCII_TO_NATIVE(ch)      (ch)
#define NATIVE_TO_UTF(ch)        (ch)
#define UTF_TO_NATIVE(ch)        (ch)
#define UNI_IS_INVARIANT(c)		(((uint)c) <  0x80)
#define UTF8_IS_INVARIANT(c)		UNI_IS_INVARIANT(NATIVE_TO_UTF(c))
#define NATIVE_IS_INVARIANT(c)		UNI_IS_INVARIANT(NATIVE_TO_ASCII(c))
#define UTF8_IS_START(c)		(((U8)c) >= 0xc0 && (((U8)c) <= 0xfd))
#define UTF8_IS_CONTINUATION(c)		(((U8)c) >= 0x80 && (((U8)c) <= 0xbf))
#define UTF8_IS_CONTINUED(c) 		(((U8)c) &  0x80)
#define UTF8_IS_DOWNGRADEABLE_START(c)	(((U8)c & 0xfc) == 0xc0)

#define UTF_START_MARK(len) ((len >  7) ? 0xFF : (0xFE << (7-len)))
#define UTF_START_MASK(len) ((len >= 7) ? 0x00 : (0x1F >> (len-2)))

#define UTF_CONTINUATION_MARK		0x80
#define UTF_ACCUMULATION_SHIFT		6
#define UTF_CONTINUATION_MASK		((U8)0x3f)
#define UTF8_ACCUMULATE(old, new)	(((old) << UTF_ACCUMULATION_SHIFT) | (((U8)new) & UTF_CONTINUATION_MASK))

#define UTF8_EIGHT_BIT_HI(c)	((((U8)(c))>>UTF_ACCUMULATION_SHIFT)|UTF_START_MARK(2))
#define UTF8_EIGHT_BIT_LO(c)	(((((U8)(c)))&UTF_CONTINUATION_MASK)|UTF_CONTINUATION_MARK)

#define UNISKIP(uv) ( (uv) < 0x80           ? 1 : \
		      (uv) < 0x800          ? 2 : \
		      (uv) < 0x10000        ? 3 : \
		      (uv) < 0x200000       ? 4 : \
		      (uv) < 0x4000000      ? 5 : \
		      (uv) < 0x80000000     ? 6 : 7 )

#define UTF8_ALLOW_EMPTY		0x0001
#define UTF8_ALLOW_CONTINUATION		0x0002
#define UTF8_ALLOW_NON_CONTINUATION	0x0004
#define UTF8_ALLOW_FE_FF		0x0008
#define UTF8_ALLOW_SHORT		0x0010
#define UTF8_ALLOW_SURROGATE		0x0020
#define UTF8_ALLOW_FFFF			0x0040 /* Allows also FFFE. */
#define UTF8_ALLOW_LONG			0x0080
#define UTF8_ALLOW_ANYUV		(UTF8_ALLOW_EMPTY|UTF8_ALLOW_FE_FF|\
					 UTF8_ALLOW_SURROGATE|UTF8_ALLOW_FFFF)
#define UTF8_ALLOW_ANY			0x00FF
#define UTF8_CHECK_ONLY			0x0200

#define UNICODE_SURROGATE_FIRST		0xD800
#define UNICODE_SURROGATE_LAST		0xDFFF
#define UNICODE_REPLACEMENT		0xFFFD
#define UNICODE_BYTE_ORDER_MARK		0xFEFF
#define UNICODE_ILLEGAL			0xFFFF

#define UNICODE_ALLOW_SURROGATE 0x0001	/* Allow UTF-16 surrogates (EVIL) */
#define UNICODE_ALLOW_FDD0	0x0002	/* Allow the U+FDD0...U+FDEF */
#define UNICODE_ALLOW_FFFF	0x0004	/* Allow 0xFFF[EF], 0x1FFF[EF], ... */
#define UNICODE_ALLOW_SUPER	0x0008	/* Allow past 10xFFFF */
#define UNICODE_ALLOW_ANY	0x000F


#define UNICODE_IS_SURROGATE(c)		((c) >= UNICODE_SURROGATE_FIRST && \
					 (c) <= UNICODE_SURROGATE_LAST)
#define UNICODE_IS_REPLACEMENT(c)	((c) == UNICODE_REPLACEMENT)
#define UNICODE_IS_BYTE_ORDER_MARK(c)	((c) == UNICODE_BYTE_ORDER_MARK)
#define UNICODE_IS_ILLEGAL(c)		((c) == UNICODE_ILLEGAL)


JSON_DO_CPLUSPLUS_WRAP_END

#endif