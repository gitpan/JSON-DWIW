/* Creation date: 2008-04-06T19:51:15Z
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

#include "old_parse.h"

#define JsHaveMoreChars(ctx) ( (ctx)->pos < (ctx)->len )

#define UC2UV(c) ( (UV)(c) )

#define JsCurChar(ctx) ( JsHaveMoreChars(ctx) ? ( UTF8_IS_INVARIANT(ctx->data[ctx->pos]) ? UC2UV(ctx->data[ctx->pos]) : ( convert_utf8_to_uv((unsigned char *)&(ctx->data[ctx->pos]), NULL))) : 0 )

#define JsNextChar(ctx) ( JsHaveMoreChars(ctx) ? (UTF8_IS_INVARIANT(ctx->data[ctx->pos]) ? (ctx->col++, ctx->char_pos++, ctx->char_col++, UC2UV(ctx->data[ctx->pos++])) : json_next_multibyte_char(ctx)) : 0 )

#define JsNextCharWithArg(ctx, uv, len) ( JsHaveMoreChars(ctx) ? (UTF8_IS_INVARIANT(ctx->data[ctx->pos]) ? (ctx->col++, ctx->char_pos++, ctx->char_col++, UC2UV(ctx->data[ctx->pos++])) : (uv = convert_utf8_to_uv((unsigned char *)&(ctx->data[ctx->pos]), &len), ctx->pos += len, ctx->col += len, ctx->char_pos++, ctx->char_col++, uv) ) : 0 )

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


static int
check_bom(json_context * ctx) {
    UV len = ctx->len;
    char * buf = ctx->data;
    char * error_fmt = "found BOM for unsupported %s encoding -- this parser requires UTF-8";

    /* check for UTF BOM signature */
    /* The signature, if present, is the U+FEFF character encoded the
       same as the rest of the buffer.
       See <http://www.unicode.org/unicode/faq/utf_bom.html#25>.
    */
    if (len >= 1) {
        switch (*buf) {

          case '\xEF': /* maybe utf-8 */
              if (len >= 3 && MEM_EQ(buf, "\xEF\xBB\xBF", 3)) {
                  /* UTF-8 signature */

                  /* Move our position past the signature and parse as
                     if there were no signature, but this explicitly
                     indicates the buffer is encoded in utf-8
                  */
                  JsNextChar(ctx);
                  /* NEXT_CHAR(ctx); */

                  /*
                  ctx->pos += 3;
                  ctx->cur_byte_pos += 3;
                  ctx->cur_char_pos++;
                  ctx->char_pos++;
                  */
              }
              return 1;
              break;


              /* The rest, if present are not supported by this
                 parser, so reject with an error.
              */

          case '\xFE': /* maybe utf-16 big-endian */
              if (len >= 2 && MEM_EQ(buf, "\xFE\xFF", 2)) {
                  /* UTF-16BE */
                  ctx->error = JSON_PARSE_ERROR(ctx, error_fmt, "UTF-16BE");
                  return 0;
              }
              break;

          case '\xFF': /* maybe utf-16 little-endian or utf-32 little-endian */
              if (len >= 2) {
                  if (MEM_EQ(buf, "\xFF\xFE", 2)) {
                      /* UTF-16LE */
                      ctx->error = JSON_PARSE_ERROR(ctx, error_fmt, "UTF-16LE");
                      return 0;
                  }
                  else if (len >= 4) {
                      if (MEM_EQ(buf, "\xFF\xFE\x00\x00", 4)) {
                          /* UTF-32LE */
                          ctx->error = JSON_PARSE_ERROR(ctx, error_fmt, "UTF-32LE");
                          return 0;
                      }
                  }
              }
              break;

          case '\x00': /* maybe utf-32 big-endian */
              if (len >= 4) {
                  if (MEM_EQ(buf, "\x00\x00\xFE\xFF", 4)) {
                      /* UTF-32BE */
                      ctx->error = JSON_PARSE_ERROR(ctx, error_fmt, "UTF-32B");
                      return 0;
                  }
              }
              break;

          default:
              /* allow through */
              return 1;
              break;
        }

    }

    return 1;
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

SV *
json_parse_error(json_context * ctx, const char * file, unsigned int line_num,
    const char * fmt, ...) {
    SV * error;
    va_list ap;

    va_start(ap, fmt);
    error = vjson_parse_error(ctx, file, line_num, fmt, ap);
    va_end(ap);

    return error;
}

#ifndef __GNUC__

SV *
JSON_PARSE_ERROR(json_context * ctx, const char * fmt, ...) {
    SV * error;
    va_list ap;

    va_start(ap, fmt);
    error = vjson_parse_error(ctx, NULL, 0, fmt, ap);
    va_end(ap);

    return error;
}
#endif /* ifndef __GNUC__ */



/* HERE */
static SV * json_parse_value(json_context *ctx, int is_identifier, unsigned int cur_level);


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

#define JsAppendBuf(str, ctx, start_pos, offset) ( str ? (sv_catpvn(str, ctx->data + start_pos, ctx->pos - start_pos - offset), str) : newSVpvn(ctx->data + start_pos, ctx->pos - start_pos - offset) )

#define JsAppendCBuf(str, buf, len) ( str ? (sv_catpvn(str, buf, len), str) : newSVpvn(buf, len) )

static void
json_eat_digits(json_context *ctx) {
    UV looking_at;

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
    UV looking_at;
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
        /* JsNextChar(ctx); */
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
            || looking_at == '_' || looking_at == '$'
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


#define HEX_NIBBLE_TO_INT(nc) \
    ( nc >= '0' && nc <= '9' ? (int)(nc - '0') :                        \
        ( nc >= 'a' && nc <= 'f' ? (int)(nc - 'a' + 10) :               \
            ( nc >= 'A' && nc <= 'F' ? (int)(nc - 'A' + 10) : -1  )     \
          )                                                             \
      )

#define GET_HEX_NIBBLE(ctx, nv, u_bytes, i, this_char, error_msg)       \
                this_char = JsNextCharWithArg(ctx, tmp_uv, tmp_len);    \
                nv = HEX_NIBBLE_TO_INT(this_char);                      \
                  if (nv == -1) {                                       \
                      u_bytes[i] = '\x00';                              \
                      ctx->error = JSON_PARSE_ERROR(ctx, error_msg, u_bytes); \
                      if (rv && !tmp_str) {                             \
                          SvREFCNT_dec(rv);                             \
                          rv = NULL;                                    \
                      }                                                 \
                      return (SV *)&PL_sv_undef;                        \
                  }                                                     \
                  u_bytes[i] = nv;                                      \
                  i++;


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
    int nibble_val = 0;

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

              case 'v':
                  char_buf = "\x0b";
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

              case 'x':
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

#define BHE_MSG "bad hex escape specification \"\\x%s\""

                  case 'x':
                      i = 0;
                      GET_HEX_NIBBLE(ctx, nibble_val, unicode_digits, i, this_uv, BHE_MSG);
                      GET_HEX_NIBBLE(ctx, nibble_val, unicode_digits, i, this_uv, BHE_MSG);
                      next_uv = JsCurChar(ctx);
                      this_uv = 16 * unicode_digits[0] + unicode_digits[1];

                      tmp_buf = convert_uv_to_utf8(unicode_digits, this_uv);
                      UNLESS (SvUTF8(rv)) {
                          SvUTF8_on(rv);
                      }
                      sv_catpvn(rv, (char *)unicode_digits,
                          PTR2UV(tmp_buf) - PTR2UV(unicode_digits));
                      break;

#define BUE_MSG "bad unicode character specification \"\\u%s\""

                case 'u':
                      i = 0;
                      GET_HEX_NIBBLE(ctx, nibble_val, unicode_digits, i, this_uv, BUE_MSG);
                      GET_HEX_NIBBLE(ctx, nibble_val, unicode_digits, i, this_uv, BUE_MSG);
                      GET_HEX_NIBBLE(ctx, nibble_val, unicode_digits, i, this_uv, BUE_MSG);
                      GET_HEX_NIBBLE(ctx, nibble_val, unicode_digits, i, this_uv, BUE_MSG);

                      next_uv = JsCurChar(ctx);
                      this_uv = 4096 * unicode_digits[0] + 256 * unicode_digits[1]
                          + 16 * unicode_digits[2] + unicode_digits[3];

                      tmp_buf = convert_uv_to_utf8(unicode_digits, this_uv);
                      UNLESS (SvUTF8(rv)) {
                          SvUTF8_on(rv);
                      }
                      sv_catpvn(rv, (char *)unicode_digits,
                          PTR2UV(tmp_buf) - PTR2UV(unicode_digits));

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
    UV looking_at;
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

SV *
from_json(SV * self, char * data_str, STRLEN data_str_len, SV ** error_msg, int *throw_exception,
    SV * error_data_ref, SV * stats_data_ref) {
    json_context ctx;
    SV * val = Nullsv;
    SV ** ptr;
    HV * self_hash = Nullhv;
    SV * data = Nullsv;
    SV * passed_error_data_sv = Nullsv;
    
    if (self && SvOK(self) && SvROK(self)) {
        self_hash = (HV *)SvRV(self);
    }

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


    memzero(&ctx, sizeof(json_context));
    ctx.len = data_str_len;
    ctx.data = data_str;
    ctx.pos = 0;
    ctx.error = (SV *)0;
    ctx.self = self;
    ctx.line = 1;
    ctx.col = 0;

    if (self_hash) {
        ctx.bad_char_policy = get_bad_char_policy((HV *)self_hash);
        ptr = hv_fetch((HV *)self_hash, "convert_bool", 12, 0);
        if (ptr && SvTRUE(*ptr)) {
            ctx.flags |= kConvertBool;
        }
    }

    if (check_bom(&ctx)) {
        val = parse_json(&ctx);
    }
    else {
        val = newSV(0);
    }

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




