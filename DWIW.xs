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

/* #define PERL_NO_GET_CONTEXT */

#include "DWIW.h"
#include "old_parse.h"


#ifndef JSONEVT_HAVE_FULL_VARIADIC_MACROS

void
JSON_DEBUG(char *fmt, ...) {
#if JSON_DO_DEBUG
    va_list ap;

    va_start(ap, fmt);
    vprintf(fmt, ap);
    printf("\n");
    va_end(ap);
#endif

}

void
JSON_TRACE(char *fmt, ...) {
#if JSON_DO_TRACE
    va_list ap;

    va_start(ap, fmt);
    vprintf(fmt, ap);
    printf("\n");
    va_end(ap);
#endif
}

#endif /* ifndef JSONEVT_HAVE_FULL_VARIADIC_MACROS */



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


#define JSON_ENCODE_ERROR(ctx, ...) json_encode_error(ctx, __FILE__, __LINE__, __VA_ARGS__)

#endif

#define JSON_ENCODE_ERROR(ctx, ...) json_encode_error(ctx, NULL, 0, __VA_ARGS__)

#else

static SV *
JSON_ENCODE_ERROR(self_context * ctx, const char * fmt, ...) {
    va_list ap;
    SV * error;

    va_start(ap, fmt);
    error = vjson_encode_error(ctx, NULL, 0, fmt, ap);
    va_end(ap);

    return error;
}

#endif

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


static SV * to_json(self_context * self, SV * data_ref, int indent_level, unsigned int cur_level);



#define JsSvLen(val) sv_len(val)

#define JsDumpSv(sv, flags) if (flags & kDumpVars) { sv_dump(sv); }




static SV *
from_json_sv (SV * self, SV * data_sv, SV ** error_msg, int *throw_exception,
    SV * error_data_ref, SV * stats_data_ref) {
    STRLEN data_str_len;
    char * data_str;

    data_str = SvPV(data_sv, data_str_len);

    return from_json(self, data_str, data_str_len, error_msg, throw_exception, error_data_ref,
        stats_data_ref);
}

static SV *
has_jsonevt() {
#ifdef HAVE_JSONEVT
    return newSVuv(1);
#else
    return newSV(0);
#endif
}

static SV *
deserialize_json(SV * self, char * data_str, STRLEN data_str_len) {
#ifdef HAVE_JSONEVT
    SV * val;

    UNLESS (data_str) {
        /* return undef */
        return (SV *)&PL_sv_undef;
    }

    if (data_str_len == 0) {
        /* return empty string */
        val = newSVpv("", 0);
        return val;
    }

    
    val = do_json_parse_buf(self, data_str, data_str_len);

    return (SV *)val;
#else
    croak("the deserialize function is not yet available on this platform");

    return &PL_sv_undef;
#endif
}

static SV *
deserialize_json_sv (SV * self, SV * data_sv) {
    STRLEN data_str_len;
    char * data_str;

    data_str = SvPV(data_sv, data_str_len);

    return deserialize_json(self, data_str, data_str_len);
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
    /* SV * key_sv = NULL; */

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

        /* key_sv = HeSVKEY(entry); */
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
    if (SvROK(data)) {
        /* reference to a referrence */
        sv_catsv(rsv, data_ref);
        tmp = rsv;
        rsv = escape_json_str(self, tmp);
        SvREFCNT_dec(tmp);
        
        return rsv;
    }

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

    JSON_DEBUG("HERE - filename='%s'\n", filename);

    /* FIXME: check here to see if file size too big, e.g., > 2GB */

    len = file_info.st_size;

    base = mmap(NULL, len, PROT_READ, 0, fd, 0);

    if (base == MAP_FAILED) {
        printf("mmap failed\n");
        return &PL_sv_undef;
    }

    JSON_DEBUG("HERE 2 - len=%u, base=%p\n", len, base);
    JSON_DEBUG("data: ");
    fread(base, 1, len, stdout);
    JSON_DEBUG("\n");

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

SV *
get_ref_addr(SV * ref) {
    SV * addr_str = Nullsv;
    SV * sv_addr = Nullsv;
    char * str = Nullch;

    if (SvROK(ref)) {
        sv_addr = SvRV(ref);
        str = form("%"UVuf"", PTR2UV((void *)sv_addr));
        addr_str = newSVpvn(str, strlen(str));
    }
    else {
        return newSV(0);
    }

    return addr_str;
}

SV *
get_ref_type(SV * ref) {
    UNLESS (SvROK(ref)) {
        return newSV(0);
    }

    /* FIXME: complete the type checks here */

    return newSV(0);
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
has_deserialize(...)
 CODE:
    items = items;
    RETVAL = has_jsonevt();
 OUTPUT:
    RETVAL

SV *
deserialize(SV * data, ...)
    ALIAS:
        JSON::DWIW::load = 1

    PREINIT:
    SV * self = Nullsv;
    SV * rv;

    CODE:
    if (items > 1) {
        self = (SV *)ST(1);
    }
    
    /* avoid compiler warnings about unused variable */
    ix = ix;

    rv = deserialize_json_sv(self, data);

    RETVAL = rv;

    OUTPUT:
    RETVAL

SV *
deserialize_file(SV * file, ...)
    ALIAS:
        JSON::DWIW::load_file = 1

    PREINIT:
    SV * self = Nullsv;
    SV * rv;

    CODE:
    if (items > 1) {
        self = (SV *)ST(1);
    }
    
    /* avoid compiler warnings about unused variable */
    ix = ix;

    rv = do_json_parse_file(self, file);

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
    I32 i;
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

SV *
skip_deserialize_file()
 CODE:
 RETVAL = &PL_sv_yes;
 OUTPUT:
 RETVAL

SV *
get_ref_addr(SV * ref)
 CODE:
 RETVAL = get_ref_addr(ref);
 OUTPUT:
 RETVAL

SV *
get_ref_type(SV * ref)
 CODE:
 RETVAL = get_ref_type(ref);
 OUTPUT:
 RETVAL


