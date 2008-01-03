/* Creation date: 2007-07-13 20:56:30
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

/* $Header: /repository/projects/libjsonevt/jsonevt.h,v 1.15 2007/12/19 05:03:26 don Exp $ */

#ifndef JSONEVT_H
#define JSONEVT_H

#include <sys/types.h>

#ifdef __cplusplus
#define JSON_DO_CPLUSPLUS_WRAP_BEGIN extern "C" {
#define JSON_DO_CPLUSPLUS_WRAP_END }
#else
#define JSON_DO_CPLUSPLUS_WRAP_BEGIN
#define JSON_DO_CPLUSPLUS_WRAP_END
#endif

JSON_DO_CPLUSPLUS_WRAP_BEGIN

#if defined(__WIN32) || defined(WIN32) || defined(_WIN32)
#define JSONEVT_ON_WINDOWS
#endif

#ifdef JSONEVT_ON_WINDOWS
typedef unsigned int uint;
#endif

typedef struct json_extern_ctx jsonevt_ctx;

jsonevt_ctx * jsonevt_new_ctx();
void jsonevt_free_ctx(jsonevt_ctx * ctx);
char * jsonevt_get_error(jsonevt_ctx * ctx);
int jsonevt_parse(jsonevt_ctx * ctx, char * buf, uint len);
int jsonevt_parse_file(jsonevt_ctx * ctx, char * file);

typedef int (*json_gen_cb)(void * cb_data, uint flags, uint level);

typedef int (*json_string_cb)(void * cb_data, char * data, uint data_len, uint flags, uint level);
typedef int (*json_number_cb)(void * cb_data, char * data, uint data_len, uint flags, uint level);
typedef int (*json_bool_cb)(void * cb_data, uint bool_val, uint flags, uint level);
typedef int (*json_comment_cb)(void * cb_data, char * data, uint data_len, uint flags, uint level);

typedef json_gen_cb json_array_begin_cb;
typedef json_gen_cb json_array_end_cb;
typedef json_gen_cb json_array_begin_element_cb;
typedef json_gen_cb json_array_end_element_cb;
typedef json_gen_cb json_hash_begin_cb;
typedef json_gen_cb json_hash_end_cb;
typedef json_gen_cb json_hash_begin_entry_cb;
typedef json_gen_cb json_hash_end_entry_cb;
typedef json_gen_cb json_null_cb;

int jsonevt_set_cb_data(jsonevt_ctx * ctx, void * data);

int jsonevt_set_string_cb(jsonevt_ctx * ctx, json_string_cb callback);
int jsonevt_set_number_cb(jsonevt_ctx * ctx, json_number_cb callback);
int jsonevt_set_begin_array_cb(jsonevt_ctx * ctx, json_array_begin_cb callback);
int jsonevt_set_end_array_cb(jsonevt_ctx * ctx, json_array_end_cb callback);
int jsonevt_set_begin_array_element_cb(jsonevt_ctx * ctx, json_array_begin_element_cb callback);
int jsonevt_set_end_array_element_cb(jsonevt_ctx * ctx, json_array_end_element_cb callback);
int jsonevt_set_begin_hash_cb(jsonevt_ctx * ctx, json_hash_begin_cb callback);
int jsonevt_set_end_hash_cb(jsonevt_ctx * ctx, json_hash_end_cb callback);
int jsonevt_set_begin_hash_entry_cb(jsonevt_ctx * ctx, json_hash_begin_entry_cb callback);
int jsonevt_set_end_hash_entry_cb(jsonevt_ctx * ctx, json_hash_end_entry_cb callback);
int jsonevt_set_bool_cb(jsonevt_ctx * ctx, json_bool_cb callback);
int jsonevt_set_null_cb(jsonevt_ctx * ctx, json_null_cb callback);
int jsonevt_set_comment_cb(jsonevt_ctx * ctx, json_comment_cb callback);

/* int jsonevt_set_options(jsonevt_ctx * ctx, uint options); */
int jsonevt_set_bad_char_policy(jsonevt_ctx * ctx, uint policy);

/* use these to find out where an error occurred or where a callback
   terminated the parse early
*/
uint jsonevt_get_error_line(jsonevt_ctx * ctx);
uint jsonevt_get_error_char_col(jsonevt_ctx * ctx);
uint jsonevt_get_error_byte_col(jsonevt_ctx * ctx);
uint jsonevt_get_error_char_pos(jsonevt_ctx * ctx);
uint jsonevt_get_error_byte_pos(jsonevt_ctx * ctx);

uint jsonevt_get_stats_string_count(jsonevt_ctx * ctx);
uint jsonevt_get_stats_longest_string_bytes(jsonevt_ctx * ctx);
uint jsonevt_get_stats_longest_string_chars(jsonevt_ctx * ctx);
uint jsonevt_get_stats_number_count(jsonevt_ctx * ctx);
uint jsonevt_get_stats_bool_count(jsonevt_ctx * ctx);
uint jsonevt_get_stats_null_count(jsonevt_ctx * ctx);
uint jsonevt_get_stats_hash_count(jsonevt_ctx * ctx);
uint jsonevt_get_stats_array_count(jsonevt_ctx * ctx);
uint jsonevt_get_stats_deepest_level(jsonevt_ctx * ctx);
uint jsonevt_get_stats_line_count(jsonevt_ctx * ctx);
uint jsonevt_get_stats_byte_count(jsonevt_ctx * ctx);
uint jsonevt_get_stats_char_count(jsonevt_ctx * ctx);

/* Use these inside a callback to find out where the parser is in the buffer/file. */
/* These will be implemented later. */
/*
uint jsonevt_get_line_num(jsonevt_ctx * ctx);
uint jsonevt_get_char_col(jsonevt_ctx * ctx);
uint jsonevt_get_byte_col(json_ctx * ctx);
uint jsonevt_get_char_pos(json_ctx * ctx);
uint jsonevt_get_byte_pos(json_ctx * ctx);
*/


#define JSON_EVT_PARSE_NUMBER_HAVE_SIGN     1
#define JSON_EVT_PARSE_NUMBER_HAVE_DECIMAL  (1 << 1)
#define JSON_EVT_PARSE_NUMBER_HAVE_EXPONENT (1 << 2)

#define JSON_EVT_IS_HASH_KEY          (1 << 3)
#define JSON_EVT_IS_HASH_VALUE        (1 << 4)
#define JSON_EVT_IS_ARRAY_ELEMENT     (1 << 5)
#define JSON_EVT_IS_C_COMMENT         (1 << 6)
#define JSON_EVT_IS_CPLUSPLUS_COMMENT (1 << 7)
#define JSON_EVT_IS_PERL_COMMENT      (1 << 8)


#define JSON_EVT_OPTION_NONE                    0

#define JSON_EVT_OPTION_BAD_CHAR_POLICY_ERROR   0
#define JSON_EVT_OPTION_BAD_CHAR_POLICY_CONVERT 1
#define JSON_EVT_OPTION_BAD_CHAR_POLICY_PASS    (1 << 1)

/* #define JSON_EVT_OPTION_CONVERT_BOOL             1 */

#define JSON_EVT_MAJOR_VERSION 0
#define JSON_EVT_MINOR_VERSION 0
#define JSON_EVT_PATCH_LEVEL 2

JSON_DO_CPLUSPLUS_WRAP_END

#endif

