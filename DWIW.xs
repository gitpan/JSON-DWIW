/*
Copyright (c) 2007 Don Owens <don@regexguy.com>.  All rights reserved.

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

/* #define PERL_NO_GET_CONTEXT */

#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#ifdef __cplusplus
}
#endif

#if PERL_VERSION >= 8
#define IS_PERL_5_8
#else
#if PERL_VERSION <= 5
#error "This module requires at least Perl 5.6"
#else
#define IS_PERL_5_6
#endif
#endif

#define DEBUG_UTF8 0
#define JSON_DO_DEBUG 0
#define JSON_DO_TRACE 0
#define JSON_DUMP_OPTIONS 0
#define JSON_DO_EXTENDED_ERRORS 0

#include <stdarg.h>

#define MAYBE_USE_MMAP 0

#if MAYBE_USE_MMAP
#ifdef HAS_MMAP
#define USE_MMAP 1
#else
#define USE_MMAP 0
#endif
#else
#define USE_MMAP 0
#endif

#if USE_MMAP
#include <unistd.h>
#include <sys/types.h>
#include <sys/mman.h>
#endif

#define debug_level 9

#ifndef PERL_MAGIC_tied
#define PERL_MAGIC_tied            'P' /* Tied array or hash */
#endif

#define MOD_NAME "JSON::DWIW"
#define MOD_VERSION VERSION

#ifdef __GNUC__
#if JSON_DO_DEBUG
#define JSON_DEBUG(...) printf("%s (%d) - ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); fflush(stdout)
#else
#define JSON_DEBUG(...)
#endif
#else

static void
JSON_DEBUG(char *fmt, ...) {
#if JSON_DO_DEBUG
    va_list ap;

    va_start(ap, fmt);
    vprintf(fmt, ap);
    printf("\n");
    va_end(ap);
#endif

}
#endif

#ifdef __GNUC__
#if JSON_DO_TRACE
#define JSON_TRACE(...) printf("%s (%d) - ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); fflush(stdout)
#else
#define JSON_TRACE(...)
#endif
#else

static void
JSON_TRACE(char *fmt, ...) {
#if JSON_DO_TRACE
    va_list ap;

    va_start(ap, fmt);
    vprintf(fmt, ap);
    printf("\n");
    va_end(ap);
#endif

}
#endif

#ifndef UTF8_IS_INVARIANT
#define UTF8_IS_INVARIANT(c) (((UV)c) < 0x80)
#endif

#define kCommasAreWhitespace 1

#define UNLESS(stuff) if (! (stuff))

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

/* a single set of flags for json_context and self_context */
#define kUseExceptions 1
#define kDumpVars (1 << 1)
#define kPrettyPrint (1 << 2)
#define kEscapeMultiByte (1 << 3)
#define kConvertBool (1 << 4)

#define kBadCharError 0
#define kBadCharConvert 1
#define kBadCharPassThrough 2

/* for converting to JSON */
typedef struct {
    SV * error;
    SV * error_data;
    int bare_keys;
    UV bad_char_policy;
    int use_exceptions;
    int flags;

    unsigned int string_count;
    unsigned int longest_string_bytes;
    unsigned int longest_string_chars;
    unsigned int number_count;
    unsigned int bool_count;
    unsigned int null_count;
    unsigned int hash_count;
    unsigned int array_count;
    unsigned int deepest_level;
} self_context;


static SV *
vjson_parse_error(json_context * ctx, const char * file, unsigned int line_num, const char * fmt,
    va_list ap) {
    SV * error = Nullsv;
    bool junk = 0;
    HV * error_data;

    if (ctx->error) {
        return ctx->error;
    }

    error = newSVpv("", 0);

    sv_setpvf(error, "%s v%s ", MOD_NAME, MOD_VERSION);
    if (file && line_num) {
        sv_catpvf(error, "line %u of %s ", line_num, file);
    }
    
    sv_catpvn(error, " - ", 3);
    sv_vcatpvfn(error, fmt, strlen(fmt), &ap, (SV **)0, 0, &junk);
    sv_catpvf(error, " - at char %u (byte %u), line %u, col %u (byte col %u)", ctx->char_pos,
        ctx->pos, ctx->line, ctx->char_col, ctx->col);

    ctx->error_pos = ctx->pos;
    ctx->error_line = ctx->line;
    ctx->error_col = ctx->col;
    ctx->error_char_col = ctx->char_col;

    error_data = newHV();
    ctx->error_data = newRV_noinc((SV *)error_data);

    hv_store(error_data, "version", 7, newSVpvf("%s", MOD_VERSION), 0);
    hv_store(error_data, "char", 4, newSVuv(ctx->char_pos), 0);
    hv_store(error_data, "byte", 4, newSVuv(ctx->pos), 0);
    hv_store(error_data, "line", 4, newSVuv(ctx->line), 0);
    hv_store(error_data, "col", 3, newSVuv(ctx->char_col), 0);
    hv_store(error_data, "byte_col", 8, newSVuv(ctx->col), 0);

    ctx->error = error;
    
    return error;
}

static SV *
json_parse_error(json_context * ctx, const char * file, unsigned int line_num,
    const char * fmt, ...) {
    SV * error;
    va_list ap;

    va_start(ap, fmt);
    error = vjson_parse_error(ctx, file, line_num, fmt, ap);
    va_end(ap);

    return error;
}

static SV *
vjson_encode_error(self_context * ctx, const char * file, int line_num, const char * fmt, va_list ap) {
    SV * error = newSVpv("", 0);
    bool junk = 0;
    HV * error_data = Nullhv;

    sv_setpvf(error, "JSON::DWIW v%s - ", MOD_VERSION);

    sv_vcatpvfn(error, fmt, strlen(fmt), &ap, (SV **)0, 0, &junk);

    error_data = newHV();
    ctx->error_data = newRV_noinc((SV *)error_data);

    hv_store(error_data, "version", 7, newSVpvf("%s", MOD_VERSION), 0);

    return error;
}

static SV *
json_encode_error(self_context * ctx, const char * file, int line_num, const char * fmt, ...) {
    va_list ap;
    SV * error;
    
    va_start(ap, fmt);
    error = vjson_encode_error(ctx, file, line_num, fmt, ap);
    va_end(ap);

    return error;
}

#ifdef __GNUC__

#if JSON_DO_EXTENDED_ERRORS

/*
static SV *
_build_error_str(const char *file, STRLEN line_num, SV *error_str) {
    SV * where_str = newSVpvf(" (%s line %d)", file, line_num);
    sv_catsv(error_str, where_str);
    SvREFCNT_dec(where_str);
    
    return error_str;
}


static SV *
build_parse_error_str(ctx, ...) {
    SV * error = NULL;
    va_list ap;

    va_start(ap, ctx);

    va_end(ap);

    return error;
}
*/

/*
#define JSON_ERROR(...) _build_error_str(__FILE__, __LINE__, newSVpvf(__VA_ARGS__))
*/

#define JSON_PARSE_ERROR(ctx, ...) json_parse_error(ctx, __FILE__, __LINE__, __VA__ARGS__)
#define JSON_ENCODE_ERROR(ctx, ...) json_encode_error(ctx, __FILE__, __LINE__, __VA_ARGS__)
#else

/*
#define JSON_ERROR(...) newSVpvf(__VA_ARGS__)
*/

#define JSON_PARSE_ERROR(ctx, ...) json_parse_error(ctx, NULL, 0, __VA_ARGS__)
#endif

#define JSON_ENCODE_ERROR(ctx, ...) json_encode_error(ctx, NULL, 0, __VA_ARGS__)

#else

static SV *
JSON_PARSE_ERROR(json_context * ctx, const char * fmt, ...) {
    SV * error;
    va_list ap;

    va_start(ap, fmt);
    error = vjson_parse_error(ctx, NULL, 0, fmt, ap);
    va_end(ap);

    return error;
}

static SV *
JSON_ENCODE_ERROR(self_context * ctx, const char * fmt, ...) {
    va_list ap;
    SV * error;

    va_start(ap, fmt);
    error = vjson_encode_error(ctx, NULL, 0, fmt, ap);
    va_end(ap);

    return error;
}

/*
static SV *
JSON_ERROR(char * fmt, ...) {
    va_list ap;
    SV * error = newSVpv("", 0);
    bool junk = 0;

    va_start(ap, fmt);
    sv_vsetpvfn(error, fmt, strlen(fmt), &ap, NULL, 0, &junk);
    va_end(ap);

    return error;
}
*/

#endif

#define UPDATE_CUR_LEVEL(ctx, cur_level) (cur_level > ctx->deepest_level ? (ctx->deepest_level = cur_level) : cur_level )

#if DEBUG_UTF8
static STRLEN
print_hex(FILE * fp, const unsigned char * buf, STRLEN buf_len) {
    STRLEN i;
    UV c;

    for (i = 0; i < buf_len; i++) {
        c = buf[i];
        if (c & 0x80) {
            fprintf(fp, "\\x{%02"UVxf"}", c);
        }
        else {
            fwrite(&buf[i], 1, 1, fp);
        }
    }

    return i;
}

static STRLEN
print_hex_line(FILE * fp, const unsigned char * buf, STRLEN buf_len) {
    STRLEN i = print_hex(fp, buf, buf_len);
    
    fwrite("\n", 1, 1, fp);
    i++;

    return i;
}
#endif

static SV * json_parse_value(json_context *ctx, int is_identifier, unsigned int cur_level);
static SV * to_json(self_context * self, SV * data_ref, int indent_level, unsigned int cur_level);

static UV
get_bad_char_policy(HV * self_hash) {
    SV ** ptr = NULL;
    U8 * data_str = NULL;
    STRLEN data_str_len = 0;

    ptr = hv_fetch((HV *)self_hash, "bad_char_policy", 15, 0);
    if (ptr && SvTRUE(*ptr)) {
        data_str = (U8 *)SvPV(*ptr, data_str_len);
        if (data_str && data_str_len) {
            if (strnEQ("error", (char *)data_str, data_str_len)) {
                return kBadCharError;
            }
            else if (strnEQ("convert", (char *)data_str, data_str_len)) {
                return kBadCharConvert;
            }
            else if (strnEQ("pass_through", (char *)data_str, data_str_len)) {
                return kBadCharPassThrough;
            }
        }
    }

    return kBadCharError;
}

#define kHaveModuleNotChecked 0
#define kHaveModule 1
#define kHaveModuleDontHave 2

static int g_have_big_int = kHaveModuleNotChecked;
static int g_have_big_float = kHaveModuleNotChecked;

static int
have_bigint() {
    SV *rv;
    
    if (g_have_big_int != kHaveModuleNotChecked) {
        if (g_have_big_int == kHaveModule) {
            return 1;
        }
        else {
            return 0;
        }
    }

    rv = eval_pv("require Math::BigInt", 0);
    if (rv && SvTRUE(rv)) {
        /* module loaded successfully */
        g_have_big_int = kHaveModule;
        return 1;
    }
    else {
        /* we don't have it */
        g_have_big_int = kHaveModuleDontHave;
        return 0;
    }

    return 0;
    
}

static int
have_bigfloat() {
    SV *rv;
    
    if (g_have_big_float != kHaveModuleNotChecked) {
        if (g_have_big_float == kHaveModule) {
            return 1;
        }
        else {
            return 0;
        }
    }

    rv = eval_pv("require Math::BigFloat", 0);
    if (rv && SvTRUE(rv)) {
        /* module loaded successfully */
        g_have_big_float = kHaveModule;
        return 1;
    }
    else {
        /* we don't have it */
        g_have_big_float = kHaveModuleDontHave;
        return 0;
    }

    return 0;
    
}

static void
_json_call_method_one_arg_one_return(SV * obj_or_class, char * method, SV * arg, SV ** rv_ptr) {
    dSP;

    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    XPUSHs(obj_or_class);
    XPUSHs(arg);
    PUTBACK;

    call_method(method, G_SCALAR);

    SPAGAIN;

    *rv_ptr = POPs;
    if (SvOK(*rv_ptr)) {
        SvREFCNT_inc(*rv_ptr);
    }

    PUTBACK;
    FREETMPS;
    LEAVE;
}

static void
_json_call_method_no_arg_one_return(SV * obj_or_class, char * method, SV ** rv_ptr) {
    dSP;

    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    XPUSHs(obj_or_class);
    PUTBACK;

    call_method(method, G_SCALAR);

    SPAGAIN;

    *rv_ptr = POPs;
    if (SvOK(*rv_ptr)) {
        SvREFCNT_inc(*rv_ptr);
    }

    PUTBACK;
    FREETMPS;
    LEAVE;
}

static SV *
json_call_method_one_arg_one_return(SV * obj_or_class, char * method, SV * arg) {
    SV * rv = NULL;
    _json_call_method_one_arg_one_return(obj_or_class, method, arg, &rv);

    return rv;
}

static SV *
json_call_method_no_arg_one_return(SV * obj_or_class, char * method) {
    SV * rv = NULL;
    _json_call_method_no_arg_one_return(obj_or_class, method, &rv);

    return rv;
}

static SV *
get_new_big_int(SV * num_string) {
    SV * class_name = newSVpv("Math::BigInt", 12);
    SV * rv = NULL;

    rv = json_call_method_one_arg_one_return(class_name, "new", num_string);
    SvREFCNT_dec(class_name);
    return rv;
}

static SV *
get_new_big_float(SV * num_string) {
    SV * class_name = newSVpv("Math::BigFloat", 14);
    SV * rv = NULL;

    rv = json_call_method_one_arg_one_return(class_name, "new", num_string);
    SvREFCNT_dec(class_name);
    return rv;
}

static SV *
get_new_bool_obj(int bool_val) {
    SV * class_name = newSVpv("JSON::DWIW::Boolean", 19);
    SV * obj;

    if (bool_val) {
        obj = json_call_method_no_arg_one_return(class_name, "true");
    }
    else {
        obj = json_call_method_no_arg_one_return(class_name, "false");
    }
    
    SvREFCNT_dec(class_name);

    return obj;
}

#define JsSvLen(val) sv_len(val)

#define JsDumpSv(sv, flags) ( (flags & kDumpVars) ? sv_dump(sv) : 0 )

#ifdef IS_PERL_5_6
#define convert_utf8_to_uv(utf8, len_ptr) utf8_to_uv_simple(utf8, len_ptr)
#else
#define convert_utf8_to_uv(utf8, len_ptr)  utf8_to_uvuni(utf8, len_ptr)
#endif

#ifdef IS_PERL_5_6
#define convert_uv_to_utf8(buf, uv) uv_to_utf8(buf, uv)
#else
#define convert_uv_to_utf8(buf, uv) uvuni_to_utf8(buf, uv)
#endif

#define JsHaveMoreChars(ctx) ( (ctx)->pos < (ctx)->len )

#define JsCurChar(ctx) ( JsHaveMoreChars(ctx) ? ( UTF8_IS_INVARIANT(ctx->data[ctx->pos]) ? (ctx->data[ctx->pos]) : ( convert_utf8_to_uv((unsigned char *)&(ctx->data[ctx->pos]), NULL))) : 0 )

#define JsNextChar(ctx) ( JsHaveMoreChars(ctx) ? (UTF8_IS_INVARIANT(ctx->data[ctx->pos]) ? (ctx->col++, ctx->char_pos++, ctx->char_col++, ctx->data[ctx->pos++]) : json_next_multibyte_char(ctx)) : 0 )

#define JsNextCharWithArg(ctx, uv, len) ( JsHaveMoreChars(ctx) ? (UTF8_IS_INVARIANT(ctx->data[ctx->pos]) ? (ctx->col++, ctx->char_pos++, ctx->char_col++, ctx->data[ctx->pos++]) : (uv = convert_utf8_to_uv((unsigned char *)&(ctx->data[ctx->pos]), &len), ctx->pos += len, ctx->col += len, ctx->char_pos++, ctx->char_col++, uv) ) : 0 )

static UV
json_next_multibyte_char(json_context * ctx) {
    UV uv = 0;
    STRLEN len = 0;

    /* FIXME: should use is_utf8_char() so we know whether we got a NULL char back or an error */
    uv = convert_utf8_to_uv((unsigned char *)&(ctx->data[ctx->pos]), &len);
    ctx->pos += len;
    ctx->col += len;
    ctx->char_pos++;
    ctx->char_col++;

    return uv;
}

/*
static UV
json_next_char(json_context *ctx) {
    UV uv = 0;
    STRLEN len = 0;

    if (UTF8_IS_INVARIANT(ctx->data[ctx->pos])) {
        uv = ctx->data[ctx->pos];
        ctx->pos++;
        ctx->col++;
    }
    else {
        uv = convert_utf8_to_uv((unsigned char *)&(ctx->data[ctx->pos]), &len);
        ctx->pos += len;
        ctx->col += len;
    }

    JSON_DEBUG("pos=%d, len=%d, char=%c (%#04x), line %u, col %u", ctx->pos, ctx->len, (uv>0x80 ? '?' : (char)uv), uv, ctx->line, ctx->col);

    return uv;
}
*/

static void
json_eat_whitespace(json_context *ctx, UV flags) {
    UV this_char;
    int break_out = 0;
    UV tmp_uv;
    STRLEN tmp_len;

    JSON_DEBUG("json_eat_whitespace: starting pos %d", ctx->pos);

    while (ctx->pos < ctx->len) {
        this_char = JsCurChar(ctx);
        JSON_DEBUG("looking at %04x at pos %d", this_char, ctx->pos);
        
        switch (this_char) {
          case 0x20:   /* space */
          case 0x09:   /* tab */
          case 0x0b:   /* vertical tab */
          case 0x0c:   /* form feed */
          case 0x0d:   /* carriage return */
          case 0x00a0: /* NSBP - non-breaking space */
          case 0x200b: /* ZWSP - zero width space */
          case 0x2029: /* PS - paragraph separator */
          case 0x2060: /* WJ - word joiner */
              JsNextCharWithArg(ctx, tmp_uv, tmp_len);
              break;

          case 0x0a:   /* newline */
          case 0x0085: /* NEL - next line */
          case 0x2028: /* LS - line separator */
              JsNextCharWithArg(ctx, tmp_uv, tmp_len);
              ctx->line++;
              ctx->col = 0;
              ctx->char_col = 0;
              break;

          case ',':
              if (flags & kCommasAreWhitespace) {
                  JsNextCharWithArg(ctx, tmp_uv, tmp_len);
              }
              else {
                  break_out = 1;
              }
              break;
            
          case '/':
              JsNextCharWithArg(ctx, tmp_uv, tmp_len);
              this_char = JsCurChar(ctx);
              JSON_DEBUG("looking at %04x at pos %d", this_char, ctx->pos);
              if (this_char == '/') {
                  JSON_DEBUG("in C++ style comment at pos %d", ctx->pos);
                  while (ctx->pos < ctx->len) {
                      JsNextCharWithArg(ctx, tmp_uv, tmp_len);
                      this_char = JsCurChar(ctx);
                      if (this_char == 0x0a || this_char == 0x0d) {
                          /* FIXME: should peak at the next to see if windows line ending, etc. */
                          break;
                      }
                  }
              }
              else if (this_char == '*') {
                  JsNextCharWithArg(ctx, tmp_uv, tmp_len);
                  this_char = JsCurChar(ctx);
                  JSON_DEBUG("in comment at pos %d, looking at %04x", ctx->pos, this_char);

                  while (ctx->pos < ctx->len) {
                      if (this_char == '*') {
                          JsNextCharWithArg(ctx, tmp_uv, tmp_len);
                          this_char = JsCurChar(ctx);
                          if (this_char == '/') {
                              /* end of comment */
                              JsNextCharWithArg(ctx, tmp_uv, tmp_len);
                              break;
                          }
                      }
                      else {
                          JsNextCharWithArg(ctx, tmp_uv, tmp_len);
                          this_char = JsCurChar(ctx);
                      }
                  }
              }
              else {
                  /* syntax error -- can't have a '/' by itself */
                  JSON_DEBUG("syntax error at %d -- can't have '/' by itself", ctx->pos);
              }
              break;

          default:
              break_out = 1;
              break;
        }
        
        if (break_out) {
            break;
        }

    }

    JSON_DEBUG("json_eat_whitespace: ending pos %d", ctx->pos);
}

#define JsAppendBuf(str, ctx, start_pos, offset) ( str ? (sv_catpvn(str, ctx->data + start_pos, ctx->pos - start_pos - offset), str) : newSVpv(ctx->data + start_pos, ctx->pos - start_pos - offset) )

#define JsAppendCBuf(str, buf, len) ( str ? (sv_catpvn(str, buf, len), str) : newSVpv(buf, len) )

static void
json_eat_digits(json_context *ctx) {
    unsigned char looking_at;

    looking_at = JsCurChar(ctx);
    while (ctx->pos < ctx->len && looking_at >= '0' && looking_at <= '9') {
        JsNextChar(ctx);
        looking_at = JsCurChar(ctx);
    }
}

#define kParseNumberHaveSign      1
#define kParseNumberHaveDecimal  (1 << 1)
#define kParseNumberHaveExponent (1 << 2)
#define kParseNumberDone         (1 << 3)
#define kParseNumberTryBigNum    (1 << 4)
static SV *
json_parse_number(json_context *ctx, SV * tmp_str) {
    SV * rv = NULL;
    unsigned char looking_at;
    STRLEN start_pos = ctx->pos;
    NV nv_value = 0; /* double */
    UV uv_value = 0;
    IV iv_value = 0;
    SV * tmp_sv = NULL;
    UV flags = 0;
    char *uv_str = NULL;
    /* char uv_str[(IV_DIG > UV_DIG ? IV_DIG : UV_DIG) + 1]; */
    STRLEN size = 0;
    
    looking_at = JsNextChar(ctx);
    if (looking_at == '-') {
        JsNextChar(ctx);
        looking_at = JsNextChar(ctx);
        flags |= kParseNumberHaveSign;
    }

    if (looking_at < '0' || looking_at > '9') {
        JSON_DEBUG("syntax error at byte %d", ctx->pos);
        ctx->error = JSON_PARSE_ERROR(ctx, "syntax error (not a digit)");
        return (SV *)&PL_sv_undef;
    }

    ctx->number_count++;

    json_eat_digits(ctx);

    if (tmp_str) {
        sv_setpvn(tmp_str, "", 0);
        rv = tmp_str;
    }
    
    if (ctx->pos < ctx->len) {
        looking_at = JsCurChar(ctx);

        if (looking_at == '.') {
            JsNextChar(ctx);
            json_eat_digits(ctx);
            looking_at = JsCurChar(ctx);
            flags |= kParseNumberHaveDecimal;
        }

        if (ctx->pos < ctx->len) {
            if (looking_at == 'E' || looking_at == 'e') {
                /* exponential notation */
                flags |= kParseNumberHaveExponent;
                JsNextChar(ctx);
                if (ctx->pos < ctx->len) {
                    looking_at = JsCurChar(ctx);
                    if (looking_at == '+' || looking_at == '-') {
                        JsNextChar(ctx);
                        looking_at = JsCurChar(ctx);
                    }
                    
                    json_eat_digits(ctx);
                    looking_at = JsCurChar(ctx);
                }
            }
        }
    }

    rv = JsAppendBuf(rv, ctx, start_pos, 0);

    size = ctx->pos - start_pos;
    if (flags & (kParseNumberHaveDecimal | kParseNumberHaveExponent)) {
        if (flags & kParseNumberHaveSign) {
            if (size - 1 >= DBL_DIG) {
                flags |= kParseNumberTryBigNum;
            }
        }
        else {
            if (size >= DBL_DIG) {
                flags |= kParseNumberTryBigNum;
            }
        }
    }
    else {
        if (flags & kParseNumberHaveSign) {
            if (size - 1 >= IV_DIG) {
                if (size - 1 == IV_DIG) {
                    uv_str = form("%"IVdf"", IV_MIN);
                    if (strncmp(ctx->data + start_pos, uv_str, size) > 0) {
                        flags |= kParseNumberTryBigNum;
                    }

                }
                else {
                    flags |= kParseNumberTryBigNum;
                }
            }
        }
        else {
            if (size >= UV_DIG) {
                if (size == UV_DIG) {
                    uv_str = form("%"UVuf"", UV_MAX);
                    if (strncmp(ctx->data + start_pos, uv_str, size) > 0) {
                        flags |= kParseNumberTryBigNum;
                    }
                }
                else {
                    flags |= kParseNumberTryBigNum;
                }
            }
        }
        
    }

    if (flags & kParseNumberTryBigNum) {
        tmp_sv = rv;
        rv = NULL;

        if (flags & (kParseNumberHaveDecimal | kParseNumberHaveExponent)) {
            if (have_bigfloat()) {
                rv = get_new_big_float(tmp_sv);
            }
        }
        else {
            if (have_bigint()) {
                rv = get_new_big_int(tmp_sv);
            }
        }

        if (rv) {
            if (SvOK(rv)) {
                if (tmp_str) {
                    sv_setsv(tmp_str, rv);
                    SvREFCNT_dec(rv);
                    rv = tmp_str;
                }
                else {
                    SvREFCNT_dec(tmp_sv);
                }
                flags |= kParseNumberDone;
            }
            else {
                JSON_DEBUG("got undef when creating big num");
                rv = tmp_sv;
            }
        }
        else {
            rv = tmp_sv;
        }
    }
    
    if (! (flags & kParseNumberDone) && ! (flags & kParseNumberTryBigNum)) {
        if (flags & (kParseNumberHaveDecimal | kParseNumberHaveExponent)) {
            nv_value = SvNV(rv);
            sv_setnv(rv, nv_value);
        }
        else if (flags & kParseNumberHaveSign) {
            iv_value = SvIV(rv);
            sv_setiv(rv, iv_value);
        }
        else { 
            uv_value = SvUV(rv);
            sv_setuv(rv, uv_value);
        }
    }

    return rv;
}

static SV *
json_parse_word(json_context *ctx, SV * tmp_str, int is_identifier) {
    SV * rv = NULL;
    UV looking_at;
    UV this_char;
    STRLEN start_pos = 0;
    UV tmp_uv;
    STRLEN tmp_len;
    
    looking_at = JsCurChar(ctx);
    if (looking_at >= '0' && looking_at <= '9') {
        JSON_DEBUG("json_parse_word(): starts with digit, so calling json_parse_number()");
        return json_parse_number(ctx, tmp_str);
    }

    if (tmp_str) {
        sv_setpvn(tmp_str, "", 0);
        rv = tmp_str;
    }

    start_pos = ctx->pos;
    while (ctx->pos < ctx->len) {
        looking_at = JsCurChar(ctx);

        JSON_DEBUG("looking at %04x", looking_at);
        
        if ( (looking_at >= '0' && looking_at <= '9')
            || (looking_at >= 'A' && looking_at <= 'Z')
            || (looking_at >= 'a' && looking_at <= 'z')
            || looking_at == '_'
             ) {
            JSON_DEBUG("json_parse_word(): got %04x at %d", looking_at, ctx->pos);

            this_char = JsNextCharWithArg(ctx, tmp_uv, tmp_len);
        }
        else {
            if (ctx->pos == start_pos) {
                /* syntax error */
                JSON_DEBUG("syntax error at byte %d, looking_at = %04x", ctx->pos, looking_at);
                ctx->error = JSON_PARSE_ERROR(ctx, "syntax error (invalid char)");
                return (SV *)&PL_sv_undef;
            }
            else {
                UNLESS (is_identifier) {
                    if (strnEQ("true", ctx->data + start_pos, ctx->pos - start_pos)) {
                        JSON_DEBUG("returning true from json_parse_word() at byte %d", ctx->pos);

                        ctx->bool_count++;
                        if (ctx->flags & kConvertBool) {
                            return get_new_bool_obj(1);
                        }
                        else {
                            return JsAppendCBuf(rv, "1", 1);
                        }
                    }
                    else if (strnEQ("false", ctx->data + start_pos, ctx->pos - start_pos)) {
                        JSON_DEBUG("returning false from json_parse_word() at byte %d", ctx->pos);

                        ctx->bool_count++;
                       if (ctx->flags & kConvertBool) {
                            return get_new_bool_obj(0);
                        }
                        else {
                            return JsAppendCBuf(rv, "0", 1);
                        }
                    }
                    else if (strnEQ("null", ctx->data + start_pos, ctx->pos - start_pos)) {
                        JSON_DEBUG("returning undef from json_parse_word() at byte %d", ctx->pos);

                        ctx->null_count++;
                        return (SV *)newSV(0);
                    }
                }
                JSON_DEBUG("returning from json_parse_word() at byte %d", ctx->pos);

                ctx->string_count++;
                return JsAppendBuf(rv, ctx, start_pos, 0);
            }
            break;
        }
    }

    JSON_DEBUG("syntax error at byte %d", ctx->pos);
    ctx->error = JSON_PARSE_ERROR(ctx, "syntax error");
    return (SV *)&PL_sv_undef;
}

/* Finds the end of the current string by looking for the appropriate
   closing quote char that is not escaped.  Since the parsed string
   will always be less than or equal to the size of the encoded
   string, this function returns an upper boundary on the size needed
   for the resulting string.  If the Perl string is preallocated at
   this length, parsing runs faster.
*/
static STRLEN
find_length_of_string(json_context *ctx, UV boundary) {
    STRLEN pos = ctx->pos;
    STRLEN len = 0;
    UV this_char = 0x00;
    int escaped = 0;

    while (pos < ctx->len) {
        if (UTF8_IS_INVARIANT(ctx->data[pos])) {
            this_char = ctx->data[pos];
            pos++;
        }
        else {
            this_char = convert_utf8_to_uv((unsigned char *)&(ctx->data[pos]), &len);
            pos += len;
        }

        if (escaped) {
            escaped = 0;
        }
        else {
            if (this_char == boundary) {
                return pos - ctx->pos;
            }
            else if (this_char == '\\') {
                escaped = 1;
            }
        }
    }
    
    return 0;
}

static SV *
json_parse_string(json_context *ctx, SV * tmp_str) {
    UV looking_at;
    UV boundary;
    UV this_uv = 0;
    UV next_uv = 0;
    U8 unicode_digits[5];
    /* STRLEN grok_len = 0; */
    /* I32 grok_flags = 0; */
    STRLEN orig_start_pos;
    SV * rv = NULL;
    char * char_buf;
    int i;
    U8 * tmp_buf = NULL;
    STRLEN max_str_size = 0;
    UV tmp_uv;
    STRLEN tmp_len;
    unsigned int start_char_pos = 0;

    unicode_digits[4] = '\x00';

    looking_at = JsCurChar(ctx);
    if (looking_at != '"' && looking_at != '\'') {
        return (SV *)&PL_sv_undef;
    }

    ctx->string_count++;

    boundary = looking_at;
    this_uv = JsNextCharWithArg(ctx, tmp_uv, tmp_len);
    next_uv = JsCurChar(ctx);
    orig_start_pos = ctx->pos;

    start_char_pos = ctx->char_pos;

    /* FIXME: compute an estimate for the buffer size instead of passing zero */
    max_str_size = find_length_of_string(ctx, boundary);
    JSON_DEBUG("computed max size %d at pos %d", max_str_size, ctx->pos);

    /* tmp_str = NULL; */
    if (tmp_str) {
        rv = tmp_str;
        SvGROW(rv, max_str_size);
    }
    else {
        rv = newSV(max_str_size);
    }

    sv_setpvn(rv, "", 0);
    /* rv = newSVpv("", 0); */
    
    JSON_DEBUG("HERE, json_parse_string(), looking for boundary %04x", boundary);
    while (ctx->pos < ctx->len) {
        JSON_DEBUG("pos %d, looking at %04x", ctx->pos, next_uv);
        this_uv = JsNextCharWithArg(ctx, tmp_uv, tmp_len);

        if (next_uv == boundary) {
            JSON_DEBUG("found boundary %04x", boundary);

            tmp_len = SvCUR(rv);
            if (tmp_len > ctx->longest_string_bytes) {
                ctx->longest_string_bytes = tmp_len;
            }
            tmp_len = ctx->char_pos - start_char_pos - 1;
            if (tmp_len > ctx->longest_string_chars) {
                ctx->longest_string_chars = tmp_len;
            }

            return rv;
        }
        else if (this_uv == '\\') {
            this_uv = JsNextCharWithArg(ctx, tmp_uv, tmp_len);
            next_uv = JsCurChar(ctx);
            char_buf = NULL;

            switch (this_uv) {
            case 'b':
                char_buf = "\b";
                break;

            case 'f':
                char_buf = "\f";
                break;

            case 'n':
                char_buf = "\x0a";
                break;

            case 'r':
                char_buf = "\x0d";
                break;

            case 't':
                char_buf = "\t";
                break;

                /* these go through as themselves */
            case '\\':
            case '/':
            case '"':
            case '\'':
                char_buf = ctx->data + ctx->pos - 1;
                break;

            case 'u':
                break;
                
            default:
                /* unrecognized escape sequence, so send the escaped char through as itself */
                char_buf = ctx->data + ctx->pos - 1;
                break;
            }

            if (char_buf) {
                sv_catpvn(rv, char_buf, 1);
            }
            else {      
                switch (this_uv) {
                case 'u':
                    for (i = 0; i < 4 && ctx->pos < ctx->len; i++) {
                        this_uv = JsNextCharWithArg(ctx, tmp_uv, tmp_len);
                        if ( (this_uv >= '0' && this_uv <= '9')
                            || (this_uv >= 'A' && this_uv <= 'F')
                            || (this_uv >= 'a' && this_uv <= 'f')
                             ) {
                            unicode_digits[i] = (U8)this_uv;
                        }
                        else {
                            unicode_digits[i] = '\x00';
                            ctx->error =
                                JSON_PARSE_ERROR(ctx,
                                    "bad unicode character specification \"\\u%s\"",
                                    unicode_digits);
                            if (rv && !tmp_str) {
                                SvREFCNT_dec(rv);
                                rv = NULL;
                            }
                            return (SV *)&PL_sv_undef;
                        }
                    }

                    if (i != 4) {
                        unicode_digits[i] = '\x00';
                            ctx->error =
                                JSON_PARSE_ERROR(ctx,
                                    "bad unicode character specification \"\\u%s\"",
                                    unicode_digits);
                        if (rv && !tmp_str) {
                            SvREFCNT_dec(rv);
                            rv = NULL;
                        }
                        return (SV *)&PL_sv_undef;
                    }

                    JSON_DEBUG("found wide char %s\n", unicode_digits);

                    next_uv = JsCurChar(ctx);

                    /* grok_hex() not available in perl 5.6 */
                    /* grok_len = 4;*/
                    /* this_uv = grok_hex((char *)unicode_digits, &grok_len, &grok_flags, NULL); */
                    
                    sscanf((char *)unicode_digits, "%04"UVxf, &this_uv);

                    tmp_buf = convert_uv_to_utf8(unicode_digits, this_uv);
                    UNLESS (SvUTF8(rv)) {
                        SvUTF8_on(rv);
                        /* sv_utf8_upgrade(rv); */
                    }
                    sv_catpvn(rv, (char *)unicode_digits, PTR2UV(tmp_buf) - PTR2UV(unicode_digits));

                    break;
                    
                default:
                    break;
                }
            }
        }
        else {
            tmp_buf = convert_uv_to_utf8(unicode_digits, this_uv);
            sv_catpvn(rv, (char *)unicode_digits, PTR2UV(tmp_buf) - PTR2UV(unicode_digits));
            JSON_DEBUG("before JsCurChar()");
            next_uv = JsCurChar(ctx);
            JSON_DEBUG("after next_char(), got %04x", next_uv);
            
        }
    }
    
    ctx->error = JSON_PARSE_ERROR(ctx, "unterminated string starting at byte %d", orig_start_pos);
    return (SV *)&PL_sv_undef;
}

static SV *
json_parse_object(json_context *ctx, unsigned int cur_level) {
    UV looking_at;
    HV * hash;
    SV * key = Nullsv;
    SV * val = Nullsv;
    SV * tmp_str;
    int found_comma = 0;
    UV tmp_uv;
    STRLEN tmp_len;

    looking_at = JsCurChar(ctx);
    if (looking_at != '{') {
        JSON_DEBUG("json_parse_object: looking at %04x", looking_at);
        return (SV *)&PL_sv_undef;
    }

    ctx->hash_count++;
    cur_level++;
    UPDATE_CUR_LEVEL(ctx, cur_level);

    hash = newHV();

    JsNextCharWithArg(ctx, tmp_uv, tmp_len);

    json_eat_whitespace(ctx, kCommasAreWhitespace);
    
    looking_at = JsCurChar(ctx);

    JSON_DEBUG("json_parse_object: looking at %04x", looking_at);
    if (looking_at == '}') {
        JsNextCharWithArg(ctx, tmp_uv, tmp_len);
        return (SV *)newRV_noinc((SV *)hash);
    }

    /* key = tmp_str = sv_newmortal(); */
    key = tmp_str = newSVpv("DEADBEEF", 8);

    /* assign something so we can call SvGROW() later without causing a bus error */
    /* sv_setpvn(key, "DEADBEEF", 8); */

    while (ctx->pos < ctx->len) {
        looking_at = JsCurChar(ctx);
        found_comma = 0;

        if (looking_at == '"' || looking_at == '\'') {
            key = json_parse_string(ctx, key);
        }
        else {
            JSON_DEBUG("looking at %04x at %d", looking_at, ctx->pos);
            key = json_parse_word(ctx, key, 1);
        }

        if (ctx->error) {
            SvREFCNT_dec(tmp_str);
            SvREFCNT_dec((SV *)hash);
            return val;
        }

        JSON_DEBUG("looking at %04x at %d", looking_at, ctx->pos);

        json_eat_whitespace(ctx, 0);

        looking_at = JsCurChar(ctx);
        
        JSON_DEBUG("looking at %04x at %d", looking_at, ctx->pos);
        if (looking_at != ':') {
            JSON_DEBUG("bad object at %d", ctx->pos);
            ctx->error = JSON_PARSE_ERROR(ctx, "bad object (expected ':')");
            SvREFCNT_dec(tmp_str);
            SvREFCNT_dec((SV *)hash);
            return (SV *)&PL_sv_undef;
        }
        JsNextCharWithArg(ctx, tmp_uv, tmp_len);
        
        json_eat_whitespace(ctx, 0);
        
        val = json_parse_value(ctx, 0, cur_level);
        if (ctx->error) {
            SvREFCNT_dec(tmp_str);
            SvREFCNT_dec((SV *)hash);
            return val;
        }
        
        hv_store_ent(hash, key, val, 0);

        key = tmp_str;

        json_eat_whitespace(ctx, 0);

        looking_at = JsCurChar(ctx);
        if (looking_at == ',') {
            found_comma = 1;
            json_eat_whitespace(ctx, kCommasAreWhitespace);
            looking_at = JsCurChar(ctx);
        }
        
        switch (looking_at) {
        case '}':
            JsNextCharWithArg(ctx, tmp_uv, tmp_len);
            SvREFCNT_dec(tmp_str);
            return (SV *)newRV_noinc((SV *)hash);
            break;
            
        case ',':
            JsNextCharWithArg(ctx, tmp_uv, tmp_len);
            json_eat_whitespace(ctx, 0);
            break;

        default:
            UNLESS (found_comma) {
                JSON_DEBUG("bad object at %d (%c)", ctx->pos, looking_at);
                ctx->error = JSON_PARSE_ERROR(ctx, "bad object (expected ',' or '}'");
                SvREFCNT_dec(tmp_str);
                return (SV *)&PL_sv_undef;
            }
            break;
        }
    }

    SvREFCNT_dec(tmp_str);
    JSON_DEBUG("bad object at %d", ctx->pos);
    ctx->error = JSON_PARSE_ERROR(ctx, "bad object");
    return (SV *)&PL_sv_undef;
}

static SV *
json_parse_array(json_context *ctx, unsigned int cur_level) {
    unsigned char looking_at;
    AV * array;
    SV * val;
    int found_comma = 0;

    looking_at = JsCurChar(ctx);
    if (looking_at != '[') {
        return (SV *)&PL_sv_undef;
    }

    ctx->array_count++;
    cur_level++;
    UPDATE_CUR_LEVEL(ctx, cur_level);

    JsNextChar(ctx);

    json_eat_whitespace(ctx, 0);

    array = newAV();
    
    looking_at = JsCurChar(ctx);
    if (looking_at == ']') {
        JsNextChar(ctx);
        return (SV *)newRV_noinc((SV *)array);
    }

    while (ctx->pos < ctx->len) {
        found_comma = 0;

        json_eat_whitespace(ctx, kCommasAreWhitespace);

        val = json_parse_value(ctx, 0, cur_level);
        av_push(array, val);

        json_eat_whitespace(ctx, 0);

        looking_at = JsCurChar(ctx);
        if (looking_at == ',') {
            found_comma = 1;
            json_eat_whitespace(ctx, kCommasAreWhitespace);
            looking_at = JsCurChar(ctx);
        }
        
        switch (looking_at) {
          case ']':
              JsNextChar(ctx);
              return (SV *)newRV_noinc((SV *)array);
              break;
              
          case ',':
              JsNextChar(ctx);
              json_eat_whitespace(ctx, kCommasAreWhitespace);
              /* json_eat_whitespace(ctx, 0); */
              break;
              
          default:
              UNLESS (found_comma) {
                  JSON_DEBUG("bad array at %d", ctx->pos);
                  ctx->error = JSON_PARSE_ERROR(ctx, "syntax error in array (expected ',' or ']')");
                  return (SV *)&PL_sv_undef;
              }
              break;
        }
    }

    JSON_DEBUG("bad array at %d", ctx->pos);
    ctx->error = JSON_PARSE_ERROR(ctx, "bad array");
    return (SV *)&PL_sv_undef;
}

static SV *
json_parse_value(json_context *ctx, int is_identifier, unsigned int cur_level) {
    UV looking_at;
    SV * rv;

    JSON_DEBUG("before eat_whitespace");

    json_eat_whitespace(ctx, 0);

    JSON_DEBUG("after eat_whitespace");
    
    if (ctx->pos >= ctx->len || !ctx->data) {
        ctx->error = JSON_PARSE_ERROR(ctx, "bad object");
        return (SV *)&PL_sv_undef;
    }

    looking_at = JsCurChar(ctx);

    JSON_DEBUG("json_parse_value: looking at %04x", looking_at);

    switch (looking_at) {
    case '{':
        JSON_DEBUG("before json_parse_object()");
        rv = json_parse_object(ctx, cur_level);
        JSON_DEBUG("after json_parse_object");
        return rv;
        break;

    case '[':
        JSON_DEBUG("before json_parse_array()");
        rv = json_parse_array(ctx, cur_level);
        JSON_DEBUG("after json_parse_array()");
        return rv;
        break;

    case '"':
    case '\'':
        JSON_DEBUG("before json_parse_string(), found %04x", looking_at);
        rv = json_parse_string(ctx, 0);
        JSON_DEBUG("after json_parse_string()");
        return rv;
        break;

    case '-':
        rv = json_parse_number(ctx, 0);
        return rv;
        break;

    default:
        rv = json_parse_word(ctx, 0, is_identifier);
        return rv;
        break;
    }
}

static SV *
parse_json(json_context * ctx) {
    SV * rv = json_parse_value(ctx, 0, 0);

    json_eat_whitespace(ctx, 0);
    
    if (! ctx->error && ctx->pos < ctx->len) {
        ctx->error = JSON_PARSE_ERROR(ctx, "syntax error");
        SvREFCNT_dec(rv);
        rv = &PL_sv_undef;
    }
    

    return rv;
}


static SV *
from_json (SV * self, char * data_str, STRLEN data_str_len, SV ** error_msg, int *throw_exception,
    SV * error_data_ref, SV * stats_data_ref) {
    json_context ctx;
    SV * val;
    SV ** ptr;
    SV * self_hash = SvRV(self);
    SV * data = Nullsv;
    SV * passed_error_data_sv = Nullsv;
    
    /*
    int is_utf8 = 0;
    int is_utf_16be = 0;
    int is_utf_32be = 0;
    */

    /*    data_str = SvPV(data_sv, data_str_len); */
    UNLESS (data_str) {
        /* return undef */
        return (SV *)&PL_sv_undef;
    }

    if (data_str_len == 0) {
        /* return empty string */
        val = newSVpv("", 0);
        return val;
    }

    /*
    if (data_str_len >= 2) {
        if (data_str[0] != '\x00' && data_str[1] != '\x00') {
            is_utf8 = 1;
        }
        else if (data_str_len >= 4) {
            if (data_str[0] == '\x00') {
                if (data_str[1] != '\x00'
                    && data_str[2] == '\x00' && data_str[3] != '\x00') {
                    is_utf_16be = 1;
                }
                else if (data_str[1] == '\x00' && data_str[2] == '\x00' && data_str[3] != '\x00') {
                    is_utf_32be = 1;
                }
            }
            else {
                
            }
        }
    }
    */

    bzero(&ctx, sizeof(json_context));
    ctx.len = data_str_len;
    ctx.data = data_str;
    ctx.pos = 0;
    ctx.error = (SV *)0;
    ctx.self = self;
    ctx.bad_char_policy = get_bad_char_policy((HV *)self_hash);
    ctx.line = 1;
    ctx.col = 0;

    ptr = hv_fetch((HV *)self_hash, "convert_bool", 12, 0);
    if (ptr && SvTRUE(*ptr)) {
        ctx.flags |= kConvertBool;
    }

    val = parse_json(&ctx);
    if (ctx.error) {
        *error_msg = ctx.error;

        if (SvOK(error_data_ref) && SvROK(error_data_ref) && ctx.error_data) {
            passed_error_data_sv = SvRV(error_data_ref);
            sv_setsv(passed_error_data_sv, ctx.error_data);
        }
    }
    else {
        *error_msg = (SV *)&PL_sv_undef;
    }

    /* if do stats */
    if (SvOK(stats_data_ref) && SvROK(stats_data_ref)) {
        data = SvRV(stats_data_ref);

        /* FIXME: should destroy these if the store fails */
        hv_store((HV *)data, "strings", 7, newSVuv(ctx.string_count), 0);
        hv_store((HV *)data, "max_string_bytes", 16, newSVuv(ctx.longest_string_bytes), 0);
        hv_store((HV *)data, "max_string_chars", 16, newSVuv(ctx.longest_string_chars), 0);
        hv_store((HV *)data, "numbers", 7, newSVuv(ctx.number_count), 0);
        hv_store((HV *)data, "bools", 5, newSVuv(ctx.bool_count), 0);
        hv_store((HV *)data, "nulls", 5, newSVuv(ctx.null_count), 0);
        hv_store((HV *)data, "hashes", 6, newSVuv(ctx.hash_count), 0);
        hv_store((HV *)data, "arrays", 6, newSVuv(ctx.array_count), 0);
        hv_store((HV *)data, "max_depth", 9, newSVuv(ctx.deepest_level), 0);

        hv_store((HV *)data, "lines", 5, newSVuv(ctx.line), 0);
        hv_store((HV *)data, "bytes", 5, newSVuv(ctx.pos), 0);
        hv_store((HV *)data, "chars", 5, newSVuv(ctx.char_pos), 0);
    }

    return (SV *)val;   
}

static SV *
from_json_sv (SV * self, SV * data_sv, SV ** error_msg, int *throw_exception,
    SV * error_data_ref, SV * stats_data_ref) {
    STRLEN data_str_len;
    char * data_str;

    data_str = SvPV(data_sv, data_str_len);

    return from_json(self, data_str, data_str_len, error_msg, throw_exception, error_data_ref,
        stats_data_ref);
}

/*
static int
get_unicode_char_count(SV * self, U8 *c_str, STRLEN len) {
    STRLEN i;
    U32 count = 0;

    for (i = 0; i < len; i++) {
        if (! UTF8_IS_INVARIANT(c_str[i])) {
            len = UTF8SKIP(&c_str[i]);
            i += len - 1;
            count++;
        }
    }

    return count;
}
*/

#if 0
static SV *
parse_json_file(SV * self, SV * file, SV * error_msg_ref) {
    SV * rv;
    SV * error_msg;
    SV * passed_error_msg_sv;
    int throw_exception = 0;
    char * data;
    STRLEN data_len;
    char * filename;
    char * filename_len;
    FILE * fp;

    filename = SvPV(file, filename_len);
    if (! filename || ! (fp = fopen(filename, "r")) ) {
        /* FIXME: put a good error msg here */
        return &PL_sv_undef;
    }

    

    /* FIXME: read from file here */

    error_msg = (SV *)&PL_sv_undef;
    rv = from_json(self, data, data_len, &error_msg, &throw_exception);
    if (SvOK(error_msg) && SvROK(error_msg_ref)) {
        passed_error_msg_sv = SvRV(error_msg_ref);
        sv_setsv(passed_error_msg_sv, error_msg);
    }

    return rv;
}
#endif

static SV *
escape_json_str(self_context * self, SV * sv_str) {
    U8 * data_str;
    STRLEN data_str_len;
    STRLEN needed_len = 0;
    STRLEN sv_pos = 0;
    STRLEN len = 0;
    U8 * tmp_str = NULL;
    U8 tmp_char = 0x00;
    SV * rv;
    int check_unicode = 1; /* FIXME: get rid of this */
    UV this_uv = 0;
    U8 unicode_bytes[5];
    int escape_unicode = 0;
    int pass_bad_char = 0;

    memzero(unicode_bytes, 5); /* memzero macro provided by Perl */

    UNLESS (SvOK(sv_str)) {
        return newSVpv("null", 4);
    }

    data_str = (U8 *)SvPV(sv_str, data_str_len);
    UNLESS (data_str) {
        return newSVpv("null", 4);
    }

    self->string_count++;

    if (data_str_len == 0) {
        /* empty string */
        return newSVpv("\"\"", 2);
    }

    if (self->flags & kEscapeMultiByte) {
        escape_unicode = 1;
    }

    /* get a better estimate of needed buffer size */
    needed_len = data_str_len * 2 + 2;

    /* check_unicode = SvUTF8(sv_str); */

    rv = newSV(needed_len);
    if (check_unicode) {
        SvUTF8_on(rv);
    }
    sv_setpvn(rv, "\"", 1);

    /* printf("\tencoding string %s\n", data_str); */
    
#if DEBUG_UTF8
    fprintf(stderr, "\tencoding string ");
    print_hex_line(stderr, data_str, data_str_len);
    /* if (data_str[0] == 0xe4) { */
    sv_dump(sv_str);
        /* } */
    fprintf(stderr, "==========\n");
#endif
    

    for (sv_pos = 0; sv_pos < data_str_len; sv_pos++) {
        pass_bad_char = 0;

        if (check_unicode) {
            len = UTF8SKIP(&data_str[sv_pos]);
            if (len > 1) {
                this_uv = convert_utf8_to_uv(&data_str[sv_pos], &len);

                if (this_uv == 0 && data_str[sv_pos] != 0) {
                    UNLESS (self->bad_char_policy) {
                        /* default */
                        
                        if (data_str_len < 40) {
                            self->error = JSON_ENCODE_ERROR(self,
                                "bad utf8 sequence starting with %#02x - %s",
                                (UV)data_str[sv_pos], data_str);
                        }
                        else {
                            self->error = JSON_ENCODE_ERROR(self, "bad utf8 sequence starting with %#02x",
                                (UV)data_str[sv_pos]);
                        }
                        
                        sv_catpvn(rv, "\"", 1);
                        return rv;
                    }
                    else if (self->bad_char_policy & kBadCharConvert) {
                        this_uv = (UV)data_str[sv_pos];
                    }
                    else if (self->bad_char_policy & kBadCharPassThrough) {
                        this_uv = (UV)data_str[sv_pos];
                        pass_bad_char = 1;
                    }
                }

                sv_pos += len - 1;
            }
            else {
                this_uv = data_str[sv_pos];
            }
        }
        else {
            this_uv = data_str[sv_pos];
        }

        switch (this_uv) {
          case '\\':
              sv_catpvn(rv, "\\\\", 2);
              break;
          case '"':
              sv_catpvn(rv, "\\\"", 2);
              break;
              /* 
          case '\'':
              sv_catpvn(rv, "\\'", 2);
              break;
              */

          case '/':
              sv_catpvn(rv, "\\/", 2);
              break;
              
          case 0x08:
              sv_catpvn(rv, "\\b", 2);
              break;
              
          case 0x0c:
              sv_catpvn(rv, "\\f", 2);
              break;
              
          case 0x0a:
              sv_catpvn(rv, "\\n", 2);
              break;
              
          case 0x0d:
              sv_catpvn(rv, "\\r", 2);
              break;
              
          case 0x09:
              sv_catpvn(rv, "\\t", 2);
              break;
              
          default:
              if (this_uv < 0x1f) {
                  sv_catpvf(rv, "\\u%04x", this_uv);
              }
              else if (escape_unicode && ! UTF8_IS_INVARIANT(this_uv)) {
                  sv_catpvf(rv, "\\u%04x", this_uv);
              }
              else if (check_unicode && !pass_bad_char) {
                  tmp_str = convert_uv_to_utf8(unicode_bytes, this_uv);
                  if (PTR2UV(tmp_str) - PTR2UV(unicode_bytes) > 1) {
                      UNLESS (SvUTF8(rv)) {
                          SvUTF8_on(rv);
                      }
                  }
                  sv_catpvn(rv, (char *)unicode_bytes, PTR2UV(tmp_str) - PTR2UV(unicode_bytes));
              }
              else {
                  tmp_char = (U8)this_uv;
                  sv_catpvn(rv, (char *)&tmp_char, 1);
              }
              break;
              
        }
    }
    
    sv_catpvn(rv, "\"", 1);
    
    return rv;
}

static SV *
encode_array(self_context * self, AV * array, int indent_level, unsigned int cur_level) {
    SV * rsv = NULL;
    SV * tmp_sv = NULL;
    I32 max_i = av_len(array); /* max index, not length */
    I32 i;
    I32 j;
    SV ** element = NULL;
    I32 num_spaces = 0;
    MAGIC * magic_ptr = NULL;

    JsDumpSv((SV *)array, self->flags);

    cur_level++;
    UPDATE_CUR_LEVEL(self, cur_level);

    self->array_count++;

    if (self->flags & kPrettyPrint) {
        if (indent_level == 0) {
            rsv = newSVpv("[", 1);
        }
        else {
            num_spaces = indent_level * 4;
            rsv = newSV(num_spaces + 3);
            sv_setpvn(rsv, "\n", 1);
            for (i = 0; i < num_spaces; i++) {
                sv_catpvn(rsv, " ", 1);
            }
            sv_catpvn(rsv, "[", 1);
        }
    }
    else {
        rsv = newSVpv("[", 1);
    }

    num_spaces = (indent_level + 1) * 4;

    magic_ptr = mg_find((SV *)array, PERL_MAGIC_tied);

    for (i = 0; i <= max_i; i++) {
        element = av_fetch(array, i, 0);
        if (element && *element) {
            if (self->flags & kDumpVars) {
                fprintf(stderr, "array element:\n");
            }

            /* need to call mg_get(val) to get the actual value if this is a tied array */
            /* see sv_magic */
            if (magic_ptr || SvTYPE(*element) == SVt_PVMG) {
                /* mg_get(*element); */ /* causes assertion failure in perl 5.8.5 if tied scalar */
                SvGETMAGIC(*element);
            }

            tmp_sv = to_json(self, *element, indent_level + 1, cur_level);

            if (self->flags & kPrettyPrint) {
                sv_catpvn(rsv, "\n", 1);
                for (j = 0; j < num_spaces; j++) {
                    sv_catpvn(rsv, " ", 1);
                }
            }

            sv_catsv(rsv, tmp_sv);
            SvREFCNT_dec(tmp_sv);
            if (self->error) {
                SvREFCNT_dec(rsv);
                return (SV *)&PL_sv_undef;
            }
            tmp_sv = NULL;
        }
        else {
            /* error? */
            sv_catpvn(rsv, "null", 4);
        }

        if (i != max_i) {
            sv_catpvn(rsv, ",", 1);
        }
    }

    if (self->flags & kPrettyPrint) {
        sv_catpvn(rsv, "\n", 1);
        num_spaces = indent_level * 4;
        for (j = 0; j < num_spaces; j++) {
            sv_catpvn(rsv, " ", 1);
        }
    }
    sv_catpvn(rsv, "]", 1);

    return rsv;
}

static void
setup_self_context(SV *self_sv, self_context *self) {
    SV ** ptr = NULL;
    SV * self_hash = NULL;

    memzero((void *)self, sizeof(self_context));

    UNLESS (SvROK(self_sv)) {
        /* hmmm, this should always be a reference */
        return;
    }
    
    self_hash = SvRV(self_sv);
    ptr = hv_fetch((HV *)self_hash, "bare_keys", 9, 0);
    if (ptr && SvTRUE(*ptr)) {
        self->bare_keys = 1;
    }

    ptr = hv_fetch((HV *)self_hash, "use_exceptions", 14, 0);
    if (ptr && SvTRUE(*ptr)) {
        self->flags |= kUseExceptions;
    }

    self->bad_char_policy = get_bad_char_policy((HV *)self_hash);

    ptr = hv_fetch((HV *)self_hash, "dump_vars", 9, 0);
    if (ptr && SvTRUE(*ptr)) {
        self->flags |= kDumpVars;
    }

    ptr = hv_fetch((HV *)self_hash, "pretty", 6, 0);
    if (ptr && SvTRUE(*ptr)) {
        self->flags |= kPrettyPrint;
    }

    ptr = hv_fetch((HV *)self_hash, "escape_multi_byte", 17, 0);
    if (ptr && SvTRUE(*ptr)) {
        self->flags |= kEscapeMultiByte;
    }


#if JSON_DUMP_OPTIONS
    {
        char * char_policy = NULL;
        switch (self->bad_char_policy) {
          case kBadCharError:
              char_policy = "error";
              break;

          case kBadCharConvert:
              char_policy = "convert";
              break;

          case kBadCharPassThrough:
              char_policy = "pass_through";
              break;

          default:
              char_policy = "unrecognized bad_char policy";
              break;
        }

        fprintf(stderr, "\nBad char policy: %s\n", char_policy);

        if (self->flags & kUseExceptions) {
            fprintf(stderr, "Use Exceptions\n");
        }
        
        if (self->flags & kDumpVars) {
            fprintf(stderr, "Dump Vars\n");
        }

        if (self->flags & kPrettyPrint) {
            fprintf(stderr, "Pretty Print\n");
        }

        if (self->flags & kEscapeMultiByte) {
            fprintf(stderr, "Escape Multi-Byte Characters\n");
        }
        
        fprintf(stderr, "\n");
        fflush(stderr);
    }
#endif

}

static int
hash_key_can_be_bare(self_context * self, U8 *key, STRLEN key_len) {
    U8 this_byte;
    STRLEN i;

    UNLESS (self->bare_keys) {
        return 0;
    }

    /* Only allow if 7-bit ascii, so use byte semantics, and only
       allow if alphanumeric and '_'.
    */
    for (i = 0; i < key_len; i++) {
        this_byte = *key;
        key++;
        UNLESS (this_byte == '_'
            || (this_byte >= 'A' && this_byte <= 'Z')
            || (this_byte >= 'a' && this_byte <= 'z')
            || (this_byte >= '0' && this_byte <= '9')
                ) {
            return 0;
        }
    }

    return 1;
}

static SV *
encode_hash(self_context * self, HV * hash, int indent_level, unsigned int cur_level) {
    SV * rsv = NULL;
    SV * tmp_sv = NULL;
    SV * tmp_sv2 = NULL;
    U8 * key;
    I32 key_len;
    SV * val;
    int first = 1;
    int i;
    int num_spaces = 0;
    MAGIC * magic_ptr = NULL;
    HE * entry;
    SV * key_sv = NULL;

    cur_level++;
    UPDATE_CUR_LEVEL(self, cur_level);

    self->hash_count++;

    if (self->flags & kPrettyPrint) {
        if (indent_level == 0) {
            rsv = newSVpv("{", 1);
        }
        else {
            num_spaces = indent_level * 4;
            rsv = newSV(num_spaces + 3);
            sv_setpvn(rsv, "\n", 1);
            for (i = 0; i < num_spaces; i++) {
                sv_catpvn(rsv, " ", 1);
            }
            sv_catpvn(rsv, "{", 1);

        }

    }
    else {
        rsv = newSVpv("{", 1);
    }

    JsDumpSv((SV *)hash, self->flags);

    magic_ptr = mg_find((SV *)hash, PERL_MAGIC_tied);
    
    num_spaces = (indent_level + 1) * 4;

    /* non-sorted keys */
    hv_iterinit(hash);
    /* while ( (val = hv_iternextsv(hash, (char **)&key, &key_len)) ) { */
    while (1) {
        entry = hv_iternext(hash);
        UNLESS (entry) {
            break;
        }

        key_sv = HeSVKEY(entry);
        key = (unsigned char *)hv_iterkey(entry, &key_len);
        /* key = (U8 *)HePV(entry, key_len); */
        val = hv_iterval(hash, entry);

        UNLESS (first) {
            sv_catpvn(rsv, ",", 1);
        }

        first = 0;

        /* need to call mg_get(val) to get the actual value if this is a tied hash */
        /* see sv_magic */
        if (magic_ptr || SvTYPE(val) == SVt_PVMG) {
            /* mg_get(val); */ /* crashes in Perl 5.8.5 if doesn't have "get magic" */
            SvGETMAGIC(val);
        }

        if (self->flags & kDumpVars) {
            fprintf(stderr, "hash key = %s\nval:\n", key);
        }
    
        if (self->flags & kPrettyPrint) {
            sv_catpvn(rsv, "\n", 1);
            for (i = 0; i < num_spaces; i++) {
                sv_catpvn(rsv, " ", 1);
            }
        }

        if (hash_key_can_be_bare(self, key, key_len)) {
            /* if the key can be bare, then it cannot have any hi-bits
               set, so no need to upgrade to utf-8
            */
            sv_catpvn(rsv, (char *)key, key_len);
        }
        else {
            tmp_sv = newSVpv((char *)key, key_len);

#ifdef IS_PERL_5_8
            if (HeKWASUTF8(entry)) {
                /* The hash key was utf-8 encoding, but the char * was
                   given to us with as the decoded bytes (e.g., utf-8 =>
                   latin1), so convert back to utf-8
                */
                sv_utf8_upgrade(tmp_sv);
            }
#endif

            tmp_sv2 = escape_json_str(self, tmp_sv);
            if (self->error) {
                SvREFCNT_dec(tmp_sv);
                SvREFCNT_dec(tmp_sv2);
                SvREFCNT_dec(rsv);
                return (SV *)&PL_sv_undef;
            }

            sv_catsv(rsv, tmp_sv2);
            SvREFCNT_dec(tmp_sv);
            SvREFCNT_dec(tmp_sv2);
        }

        sv_catpvn(rsv, ":", 1);

        tmp_sv = to_json(self, val, indent_level + 2, cur_level);
        if (self->error) {
            SvREFCNT_dec(tmp_sv);
            SvREFCNT_dec(rsv);
            return (SV *)&PL_sv_undef;
        }

        sv_catsv(rsv, tmp_sv);
        SvREFCNT_dec(tmp_sv);
    }

    if (self->flags & kPrettyPrint) {
        sv_catpvn(rsv, "\n", 1);
        num_spaces = indent_level * 4;
        for (i = 0; i < num_spaces; i++) {
            sv_catpvn(rsv, " ", 1);
        }
    }
    sv_catpvn(rsv, "}", 1);

    return rsv;
}

static SV *
to_json(self_context * self, SV * data_ref, int indent_level, unsigned int cur_level) {
    SV * data;
    int type;
    SV * rsv = newSVpv("", 0);
    SV * tmp = NULL;
    STRLEN before_len = 0;
    U8 * data_str = NULL;
    STRLEN start = 0;
    STRLEN len = 0;

    JSON_DEBUG("to_json() called");

    JsDumpSv(data_ref, self->flags);

    UNLESS (SvROK(data_ref)) {
        JSON_DEBUG("not a reference");
        data = data_ref;
        if (SvOK(data)) {

            /* scalar */
            type = SvTYPE(data);
            JSON_TRACE("found type %u", type);
            switch (type) {
              case SVt_NULL:
                /* undef? */
                sv_setpvn(rsv, "null", 4);
                return rsv;
                break;

              case SVt_IV:
              case SVt_NV:
                  before_len = JsSvLen(rsv);
                  sv_catsv(rsv, data);

                  self->number_count++;

                  if (JsSvLen(rsv) == before_len) {
                      sv_catpvn(rsv, "\"\"", 2);
                  }
                  return rsv;
                  break;

              case SVt_PV:
                  JSON_TRACE("found SVt_PV");
                  sv_catsv(rsv, data);
                  tmp = rsv;
                  rsv = escape_json_str(self, tmp);
                  SvREFCNT_dec(tmp);
                  return rsv; /* this works for the error case as well */
                  break;
                  
              case SVt_PVIV:
              case SVt_PVNV:
                  sv_catsv(rsv, data);
                  tmp = rsv;
                  rsv = escape_json_str(self, tmp);
                  SvREFCNT_dec(tmp);
                  return rsv;
                  break;

              case SVt_PVLV:
                  sv_catsv(rsv, data);
                  tmp = rsv;
                  rsv = escape_json_str(self, tmp);
                  SvREFCNT_dec(tmp);
                  return rsv;
                  break;

              default:
                  /* now what? */
                  JSON_DEBUG("unkown data type");
                  sv_catsv(rsv, data);
                  tmp = rsv;
                  rsv = escape_json_str(self, tmp);
                  SvREFCNT_dec(tmp);
                  return rsv;
                  break;
            }
        }
        else {
            /* undef */
            sv_setpvn(rsv, "null", 4);
            return rsv;
        }
    }

    JSON_DEBUG("is a reference");

    if (sv_isobject(data_ref)) {
        if (sv_isa(data_ref, "JSON::DWIW::Boolean")) {
            if (SvTRUE(data_ref)) {
                sv_setpvn(rsv, "true", 4);
                self->bool_count++;
                return rsv;
            }
            else {
                sv_setpvn(rsv, "false", 5);
                self->bool_count++;
                return rsv;
            }
        }
        else if (sv_derived_from(data_ref, "Math::BigInt")
            || sv_derived_from(data_ref, "Math::BigFloat")) {
            JSON_DEBUG("found big number");
            tmp = newSVpv("", 0);
            sv_catsv(tmp, data_ref);
            data_str = (U8 *)SvPV(tmp, before_len);

            if (before_len > 0) {
                start = 0;
                len = before_len;
                if (data_str[0] == '+') {
                    start++;
                    len--;
                }

                if (data_str[before_len - 1] == '.') {
                    len--;
                }

                sv_catpvn(rsv, (char *)data_str + start, len);

            }
            else {
                sv_setpvn(rsv, "\"\"", 2);
            }

            SvREFCNT_dec(tmp);

            return rsv;
        }
    }
    
    data = SvRV(data_ref);
    type = SvTYPE(data);

    switch (type) {
      case SVt_NULL:
        /* undef ? */
        sv_setpvn(rsv, "null", 4);
        return rsv;
        break;

      case SVt_IV:
      case SVt_NV:
          before_len = JsSvLen(rsv);
          sv_catsv(rsv, data);
          if (JsSvLen(rsv) == before_len) {
              sv_catpvn(rsv, "\"\"", 2);
          }

        return rsv;
        break;

      case SVt_PV:
        sv_catsv(rsv, data);
        tmp = rsv;
        rsv = escape_json_str(self, tmp);
        SvREFCNT_dec(tmp);
        return rsv;
        break;

      case SVt_PVIV:
      case SVt_PVNV:
          sv_catsv(rsv, data);
          tmp = rsv;
          rsv = escape_json_str(self, tmp);
          SvREFCNT_dec(tmp);
          return rsv;
          break;
          /*
          before_len = JsSvLen(rsv);
          sv_catsv(rsv, data);
          if (JsSvLen(rsv) == before_len) {
              sv_catpvn(rsv, "\"\"", 2);
          }
          return rsv;
          break;
          */

      case SVt_RV:
        /* reference to a reference */
        /* FIXME: implement */
          sv_catsv(rsv, data_ref);
          tmp = rsv;
          rsv = escape_json_str(self, tmp);
          SvREFCNT_dec(tmp);

          /* sv_catpvn(rsv, "\"\"", 2); */
          return rsv;
        break;

      case SVt_PVAV: /* array */
          JSON_DEBUG("==========> found array ref");
          SvREFCNT_dec(rsv);
          return encode_array(self, (AV *)data, indent_level, cur_level);
        break;

      case SVt_PVHV: /* hash */
          JSON_DEBUG("==========> found hash ref");

          SvREFCNT_dec(rsv);
          return encode_hash(self, (HV *)data, indent_level, cur_level);
          break;

      case SVt_PVCV: /* code */
          sv_catsv(rsv, data_ref);
          tmp = rsv;
          rsv = escape_json_str(self, tmp);
          SvREFCNT_dec(tmp);

          return rsv;
          /*
            sv_setpvn(rsv, "\"code\"", 6);
            return rsv;
          */

        break;

      case SVt_PVGV: /* glob */
          sv_catsv(rsv, data_ref);
          tmp = rsv;
          rsv = escape_json_str(self, tmp);
          SvREFCNT_dec(tmp);

          return rsv;
          break;

      case SVt_PVIO:
          sv_catsv(rsv, data);
          tmp = rsv;
          rsv = escape_json_str(self, tmp);
          SvREFCNT_dec(tmp);
          return rsv;
          break;

      case SVt_PVMG: /* blessed or magical scalar */
          if (sv_isobject(data_ref)) {
              sv_catsv(rsv, data);
              tmp = rsv;
              rsv = escape_json_str(self, tmp);
              SvREFCNT_dec(tmp);
              
              return rsv;
          }
          else {
              sv_catsv(rsv, data);
              tmp = rsv;
              rsv = escape_json_str(self, tmp);
              SvREFCNT_dec(tmp);
              
              return rsv;
          }
          break;
          
      default:
          sv_catsv(rsv, data);
          tmp = rsv;
          rsv = escape_json_str(self, tmp);
          SvREFCNT_dec(tmp);
          
          return rsv;
          
/*        sv_setpvn(rsv, "unknown type", 12); */
/*        return rsv; */
              
          break;
    }

    sv_setpvn(rsv, "unknown type 2", 14);
    return rsv;

}

static int
set_encode_stats(self_context * ctx, SV * stats_data_ref) {
    SV * data = Nullsv;

    if (SvOK(stats_data_ref) && SvROK(stats_data_ref)) {
        data = SvRV(stats_data_ref);
        
        /* FIXME: should destroy these if the store fails */

        /*
        hv_store((HV *)data, "max_string_bytes", 16, newSVuv(ctx->longest_string_bytes), 0);
        hv_store((HV *)data, "max_string_chars", 16, newSVuv(ctx->longest_string_chars), 0);
        hv_store((HV *)data, "nulls", 5, newSVuv(ctx->null_count), 0);
        */

        /*
        hv_store((HV *)data, "strings", 7, newSVuv(ctx->string_count), 0);
        hv_store((HV *)data, "bools", 5, newSVuv(ctx->bool_count), 0);        
        hv_store((HV *)data, "numbers", 7, newSVuv(ctx->number_count), 0);
        */

        hv_store((HV *)data, "hashes", 6, newSVuv(ctx->hash_count), 0);
        hv_store((HV *)data, "arrays", 6, newSVuv(ctx->array_count), 0);
        hv_store((HV *)data, "max_depth", 9, newSVuv(ctx->deepest_level), 0);

    }

    return 1;
}

static SV *
has_mmap() {
#ifdef HAS_MMAP
    return &PL_sv_yes;
#else
    return &PL_sv_no;
#endif
}

static SV *
parse_mmap_file(SV * self, SV * file, SV * error_msg_ref) {
#if USE_MMAP
    char * filename;
    STRLEN filename_len;
    void * base;
    int fd = -1;
    struct stat file_info;
    size_t len = 0;
    SV * rv;
    int throw_exception = 0;
    SV * error_msg = &PL_sv_undef;
    SV * passed_error_msg_sv;

    UNLESS (SvOK(file)) {
        return &PL_sv_undef;
    }

    filename = (char *)SvPV(file, filename_len);
    fd = open(filename, O_RDONLY, 0644);
    if (fd < 0) {
        return &PL_sv_undef;
    }

    if (fstat(fd, &file_info)) {
        return &PL_sv_undef;
    }

    printf("HERE - filename='%s'\n", filename);

    /* FIXME: check here to see if file size too big, e.g., > 2GB */

    len = file_info.st_size;

    base = mmap(NULL, len, PROT_READ, MAP_FILE, fd, 0);

    if (base == MAP_FAILED) {
        printf("mmap failed\n");
        return &PL_sv_undef;
    }

    printf("HERE 2 - len=%u, base=%p\n", len, base);
    printf("data: ");
    fread(base, 1, len, stdout);
    printf("\n");

    rv = from_json(self, base, len, &error_msg, &throw_exception);
    if (SvOK(error_msg) && SvROK(error_msg_ref)) {
        passed_error_msg_sv = SvRV(error_msg_ref);
        sv_setsv(passed_error_msg_sv, error_msg);
    }

    munmap(base, len);
#else
    return &PL_sv_undef;
#endif
}


MODULE = JSON::DWIW  PACKAGE = JSON::DWIW

PROTOTYPES: DISABLE

SV *
_xs_from_json(SV * self, SV * data, SV * error_msg_ref, SV * error_data_ref, SV * stats_data_ref)
    PREINIT:
    SV * rv;
    SV * error_msg;
    SV * passed_error_msg_sv;
    int throw_exception = 0;

    CODE:
    error_msg = (SV *)&PL_sv_undef;
    rv = from_json_sv(self, data, &error_msg, &throw_exception, error_data_ref, stats_data_ref);
    if (SvOK(error_msg) && SvROK(error_msg_ref)) {
        passed_error_msg_sv = SvRV(error_msg_ref);
        sv_setsv(passed_error_msg_sv, error_msg);
    }

    RETVAL = rv;

    OUTPUT:
    RETVAL


SV *
_xs_to_json(SV * self, SV * data, SV * error_msg_ref, SV * error_data_ref, SV * stats_ref)
     PREINIT:
     self_context self_context;
     SV * rv;
     int indent_level = 0;
     SV * passed_error_data_sv = Nullsv;

     CODE:
     setup_self_context(self, &self_context);
     rv = to_json(&self_context, data, indent_level, 0);

    if (SvOK(stats_ref)) {
        set_encode_stats(&self_context, stats_ref);
     }

     if (self_context.error) {
         sv_setsv(SvRV(error_msg_ref), self_context.error);

         if (SvOK(error_data_ref) && SvROK(error_data_ref) && self_context.error_data) {
             passed_error_data_sv = SvRV(error_data_ref);
             sv_setsv(passed_error_data_sv, self_context.error_data);
         }

     }

     RETVAL = rv;

     OUTPUT:
     RETVAL

SV *
have_big_int(SV * self)
    PREINIT:
    SV * rsv = newSV(0);
    int rv;

    CODE:
    self = self;
    rv = have_bigint();
    if (rv) {
        sv_setsv(rsv, &PL_sv_yes);
    } 
    else {
        sv_setsv(rsv, &PL_sv_no);
    }

    RETVAL = rsv;

    OUTPUT:
    RETVAL

SV *
have_big_float(SV * self)
    PREINIT:
    SV * rsv = newSV(0);
    int rv;

    CODE:
    self = self; /* get rid of compiler warnings */
    rv = have_bigfloat();
    if (rv) {
        sv_setsv(rsv, &PL_sv_yes);
    } 
    else {
        sv_setsv(rsv, &PL_sv_no);
    }

    RETVAL = rsv;

    OUTPUT:
    RETVAL

SV *
size_of_uv(SV * self)
    PREINIT:
    SV * rsv = newSV(0);

    CODE:
    self = self; /* get rid of compiler warnings */
    sv_setuv(rsv, UVSIZE);

    RETVAL = rsv;

    OUTPUT:
    RETVAL

SV *
peek_scalar(SV * self, SV * val)
    CODE:
    self = self; /* get rid of compiler warnings */
    sv_dump(val);
    if (SvROK(val)) {
        sv_dump(SvRV(val));
    }

    RETVAL = &PL_sv_yes;

    OUTPUT:
    RETVAL

SV *
is_valid_utf8(SV * self, SV * str)
    PREINIT:
    SV * rv = &PL_sv_no;
    U8 * s;
    STRLEN len;

    CODE:
    self = self;
    s = (U8 *)SvPV(str, len);
    if (is_utf8_string(s, len)) {
        rv = &PL_sv_yes;
    }

    RETVAL = rv;

    OUTPUT:
    RETVAL

SV *
flagged_as_utf8(SV * self, SV * str)
    PREINIT:
    SV * rv = &PL_sv_no;

    CODE:
    self = self;
    if (SvUTF8(str)) {
        rv = &PL_sv_yes;
    }

    RETVAL = rv;

    OUTPUT:
    RETVAL

SV *
flag_as_utf8(SV * self, SV * str)
    PREINIT:
    SV * rv = &PL_sv_yes;

    CODE:
    self = self;
    SvUTF8_on(str);

    RETVAL = rv;

    OUTPUT:
    RETVAL

SV *
unflag_as_utf8(SV * self, SV * str)
    PREINIT:
    SV * rv = &PL_sv_yes;

    CODE:
    self = self;
    SvUTF8_off(str);

    RETVAL = rv;

    OUTPUT:
    RETVAL

SV *
code_point_to_hex_bytes(SV *, SV * code_point_sv)
    PREINIT:
    UV code_point;
    U8 utf8_bytes[5];
    U8 * tmp;
    STRLEN len = 0;
    SV * rv;

    CODE:
    utf8_bytes[4] = '\x00';
    code_point = SvUV(code_point_sv);
    tmp = convert_uv_to_utf8(utf8_bytes, code_point);
    rv = newSVpv("", 0);
    if (PTR2UV(tmp) > PTR2UV(utf8_bytes)) {
        STRLEN i;
        len = PTR2UV(tmp) - PTR2UV(utf8_bytes);
        for (i = 0; i < len; i++) {
            sv_catpvf(rv, "\\x%02x", (unsigned int)utf8_bytes[i]);
        }
    }
    else {

    }

    RETVAL = rv;

    OUTPUT:
    RETVAL

SV *
bytes_to_code_points(SV *, SV * bytes)
    PREINIT:
    U8 * data_str;
    STRLEN data_str_len;
    AV * array = newAV();
    STRLEN len = 0;
    UV this_char;
    STRLEN pos = 0;
    I32 max_i;
    SV * sv = NULL;
    STRLEN i;
    SV ** element;

    CODE:
    if (SvROK(bytes) && SvTYPE(SvRV(bytes)) == SVt_PVAV) {
        AV * av = (AV *)SvRV(bytes);
        max_i = av_len(av);
        sv = newSV(max_i);
        sv_setpvn(sv, "", 0);

        for (i = 0; i <= max_i; i++) {
            element = av_fetch(av, i , 0);
            if (element && *element) {
                this_char = SvUV(*element);
                fprintf(stderr, "%02"UVxf"\n", this_char);
            }
            else {
                this_char = 0;
            }
            sv_catpvf(sv, "%c", (unsigned char)this_char);
        }
        bytes = sv;
     }

    data_str = (U8 *)SvPV(bytes, data_str_len);

    while (pos < data_str_len) {
        this_char = convert_utf8_to_uv(&data_str[pos], &len);
        pos += len;
        av_push(array, newSVuv(this_char));
    }

    if (sv) {
        SvREFCNT_dec(sv);
    }

     RETVAL = newRV_noinc((SV *)array);

    OUTPUT:
    RETVAL

SV *
_has_mmap()
 CODE:
 RETVAL = has_mmap();

 OUTPUT:
 RETVAL

SV *
_parse_mmap_file(SV * self, SV * file, SV * error_msg_ref)

 CODE:
 RETVAL = parse_mmap_file(self, file, error_msg_ref);

 OUTPUT:
 RETVAL

SV *
_check_scalar(SV *, SV * the_scalar)
 CODE:
 fprintf(stderr, "SV * at addr %p\n", the_scalar);
 sv_dump(the_scalar);
 if (SvROK(the_scalar)) {
    printf("\ndereferenced:\n");
    fprintf(stderr, "SV * at addr %p\n", SvRV(the_scalar));
    sv_dump(SvRV(the_scalar));
 }
 RETVAL = &PL_sv_yes;

 OUTPUT:
 RETVAL



