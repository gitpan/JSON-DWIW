/* Creation date: 2008-04-06T19:52:02Z
 * Authors: Don
 */

/*
Copyright (c) 2007-2008 Don Owens <don@regexguy.com>.  All rights reserved.

 This is free software; you can redistribute it and/or modify it under
 the Perl Artistic license.  You should have received a copy of the
 Artistic license with this distribution, in the file named
 "Artistic".  You may also obtain a copy from
 http://regexguy.com/license/Artistic

 This program is distributed in the hope that it will be
 useful, but WITHOUT ANY WARRANTY; without even the implied
 warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
 PURPOSE.
*/

/* $Header: /repository/owens_lib/cpan/JSON/DWIW/old_parse.h,v 1.1 2008/04/15 03:47:02 don Exp $ */

#ifndef OLD_PARSE_H
#define OLD_PARSE_H

#include "old_common.h"

/* for converting from JSON */
typedef struct {
    STRLEN len;
    char * data;
    STRLEN pos;
    SV * error;
    SV * error_data;
    SV * self;
    int flags;
    UV bad_char_policy;
    unsigned int line;
    unsigned int col;
    unsigned int char_pos;
    unsigned int char_col;
    UV cur_char;
    unsigned int cur_char_len;

    unsigned int error_pos;
    unsigned int error_char_pos;
    unsigned int error_line;
    unsigned int error_col;
    unsigned int error_char_col;
    
    unsigned int string_count;
    unsigned int longest_string_bytes;
    unsigned int longest_string_chars;
    unsigned int number_count;
    unsigned int bool_count;
    unsigned int null_count;
    unsigned int hash_count;
    unsigned int array_count;
    unsigned int deepest_level;
} json_context;


#ifdef __GNUC__

#if JSON_DO_EXTENDED_ERRORS

#define JSON_PARSE_ERROR(ctx, ...) json_parse_error(ctx, __FILE__, __LINE__, __VA__ARGS__)

#else

#define JSON_PARSE_ERROR(ctx, ...) json_parse_error(ctx, NULL, 0, __VA_ARGS__)

#endif

SV * json_parse_error(json_context * ctx, const char * file, unsigned int line_num,
    const char * fmt, ...);

#else

SV * JSON_PARSE_ERROR(json_context * ctx, const char * fmt, ...);

#endif


SV * from_json(SV * self, char * data_str, STRLEN data_str_len, SV ** error_msg,
    int *throw_exception, SV * error_data_ref, SV * stats_data_ref);


#endif /* OLD_PARSE_H */