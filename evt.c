/*
Copyright (c) 2007 Don Owens <don@regexguy.com>.  All rights reserved.

This is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.  See perlartistic.

This program is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
PURPOSE.
*/

/* TODO before release:
   
   - (done) fix static stack (switch to heap if data structure is deep)
   - (done) write test for deep structure
   - (done) test scripts
   - compatability with old implementation
       + bad_char_policy (done)
       + booleans (done)
       + numbers - handle ints and overflow (done)
   - compilation on windows (done)
   - turn off forced -Wall (done)
   - take care of mmap case (includes on windows, etc.)
   - (done) remove unused callbacks
   - (done) add module name and version to errors, as in the old implementation
   - (done) handle booleans, nulls, and numbers by themselves
   - (done) check if need to free src when calling sv_setsv()
   - (done) make sure module name and version are in error messages
       + done and have test for it
   - add deserialize_file() subroutine
   - check stats fields (missing max_string_chars/bytes)
   - document stats fields (is max_string_bytes the size of the JSON string or the Perl string)
   - "strict" option to follow Crockford's tests
   - document deserialize() and deserialize_file()
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

#include <stdlib.h>

#include "jsonevt.h"
#include "evt.h"

#define DO_DEBUG 0

#if DO_DEBUG
#define LOG_DEBUG(...) (printf("%s (%d) - ", __FILE__, __LINE__), printf(__VA_ARGS__), printf("\n"), fflush(stdout))
#define DUMP_STACK(ctx) dump_stack(ctx)
#else
#define LOG_DEBUG(...) ;
#define DUMP_STACK(ctx) ;
#endif

#if 1
#define PDB(...) fprintf(stderr, "in %s, line %d of %s: ", __func__, __LINE__, __FILE__); \
    fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); fflush(stderr)
#else
#define PDB(...)
#endif

#if 0
#define SETUP_TRACE fprintf(stderr, "in %s() at line %d of %s\n", __func__, __LINE__, __FILE__); \
    fflush(stderr);
#else
#define SETUP_TRACE
#endif

#define MOD_NAME "JSON::DWIW"

#define UNLESS(stuff) if (! (stuff))

typedef struct {
    SV * data;
} parse_cb_stack_entry;

#define EVT_OPTION_CONVERT_BOOL    1
#define EVT_OPTION_USE_EXCEPTIONS (1 << 1)

typedef struct {
    parse_cb_stack_entry * stack;
    int stack_level;
    int stack_size;
    uint options;
} parse_callback_ctx;

typedef struct {
    parse_callback_ctx cbd;
} perl_wrapper_ctx;

#define GROW_STACK(ctx) ( ((ctx)->stack_size <<= 1), Renew((ctx)->stack, (ctx)->stack_size, parse_cb_stack_entry))

#define ENSURE_STACK(ctx) ( (ctx)->stack_level >= (ctx)->stack_size - 1 ? GROW_STACK(ctx) : 0 )
#define CUR_STACK_LEVEL(ctx) ((ctx)->stack_level)
#define CUR_STACK_ENTRY(ctx) ( (parse_cb_stack_entry *)((ctx)->stack + (ctx)->stack_level) )
#define POP_STACK(ctx) (memzero((void *)((ctx)->stack + (ctx)->stack_level), sizeof((ctx)->stack)), (ctx)->stack_level--);
#define PUSH_STACK_ENTRY(ctx) ( ENSURE_STACK(ctx), (ctx)->stack_level++, ( (parse_cb_stack_entry *)((ctx)->stack + (ctx)->stack_level) ) )

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
json_call_method_no_arg_one_return(SV * obj_or_class, char * method) {
    SV * rv = NULL;
    _json_call_method_no_arg_one_return(obj_or_class, method, &rv);

    return rv;
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

static SV *
json_call_method_one_arg_one_return(SV * obj_or_class, char * method, SV * arg) {
    SV * rv = NULL;
    _json_call_method_one_arg_one_return(obj_or_class, method, arg, &rv);

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

#if 0
static int bool_module_loaded = 0;
static SV *
get_new_bool_obj(int bool_val) {
    SV * obj;
    /* SV * bool_sv = bool_val ? newSViv(bool_val) : newSVpv("", 0); */
    SV * bool_sv = newSViv(bool_val);
    HV * class_stash;
    SV * class_name = newSVpvn("JSON::DWIW::Boolean", 19);
    SV * version = newSVpvn("0", 1);

    UNLESS (bool_module_loaded) {
        load_module(0, class_name, version);
        bool_module_loaded = 1;
    }

    SvREFCNT_dec(class_name);
    SvREFCNT_dec(version);
    class_stash = gv_stashpv("JSON::DWIW::Boolean", 1);

    obj = sv_bless(newRV_noinc(bool_sv), class_stash);

    return obj;
}
#endif

#if 0
static void
dump_stack(parse_callback_ctx * ctx) {
    parse_cb_stack_entry * entry;
    int i;
    char * type_str;

    for (i = 0; i <= ctx->stack_level; i++) {
        entry = (parse_cb_stack_entry *)(ctx->stack + i);

        LOG_DEBUG("stack level %d\n", i);
        
        switch (entry->type) {
          case TYPE_NONE:
              type_str = "None";
              break;
          case TYPE_HASH:
              type_str = "Hash";
              break;
          case TYPE_ARRAY:
              type_str = "Array";
              break;
          case TYPE_HASH_ENTRY_KEY:
              type_str = "HashEntryKey";
              break;
          case TYPE_HASH_ENTRY_VAL:
              type_str = "HashEntryVal";
              break;
          case TYPE_ARRAY_ELEMENT:
              type_str = "ArrayElement";
              break;
          case TYPE_HASH_ENTRY:
              type_str = "HashEntry";
              break;

          default:
              type_str = "Unknown";
              break;
        }

        LOG_DEBUG("\ttype %s\n", type_str);
        if (entry->ref) {
            LOG_DEBUG("\tRV\n");
        }
        else {
            LOG_DEBUG("\tSV\n");
        }
    }
}
#endif

#define kHaveModuleNotChecked 0
#define kHaveModule 1
#define kHaveModuleDontHave 2

static int
have_bigint() {
    static unsigned char have_big_int = kHaveModuleNotChecked;
    SV *rv;
    
    if (have_big_int != kHaveModuleNotChecked) {
        if (have_big_int == kHaveModule) {
            return 1;
        }
        else {
            return 0;
        }
    }

    rv = eval_pv("require Math::BigInt", 0);
    if (rv && SvTRUE(rv)) {
        /* module loaded successfully */
        have_big_int = kHaveModule;
        return 1;
    }
    else {
        /* we don't have it */
        have_big_int = kHaveModuleDontHave;
        return 0;
    }

    return 0;
    
}

static int
have_bigfloat() {
    static unsigned char have_big_float = kHaveModuleNotChecked;
    SV *rv;
    
    if (have_big_float != kHaveModuleNotChecked) {
        if (have_big_float == kHaveModule) {
            return 1;
        }
        else {
            return 0;
        }
    }

    rv = eval_pv("require Math::BigFloat", 0);
    if (rv && SvTRUE(rv)) {
        /* module loaded successfully */
        have_big_float = kHaveModule;
        return 1;
    }
    else {
        /* we don't have it */
        have_big_float = kHaveModuleDontHave;
        return 0;
    }

    return 0;
    
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

static int
insert_entry(parse_callback_ctx * ctx, SV * val) {
    parse_cb_stack_entry * cur_entry = CUR_STACK_ENTRY(ctx);
    parse_cb_stack_entry * new_entry;
    int type = 0;
    int level = CUR_STACK_LEVEL(ctx);
    SV * s;

    
    if (SvROK(cur_entry->data)) {
        s = SvRV(cur_entry->data);
        type = SvTYPE(s);

        if (type == SVt_PVAV) {
            av_push((AV *)SvRV(cur_entry->data), val);
        }
        else {
            /* must be a hash (SVt_PVHV) */
            /* val must be a hash key, so push it onto the stack */
            new_entry = PUSH_STACK_ENTRY(ctx);
            new_entry->data = val;
        }
    }
    else {
        /* scalar -- must be a hash key, so insert the val */
        s = cur_entry->data;
        cur_entry = (parse_cb_stack_entry *)(ctx->stack + level - 1);
        
        hv_store_ent((HV *)SvRV(cur_entry->data), s, val, 0);
        POP_STACK(ctx);
    }
    
    return 1;
}

static int
push_stack_val(parse_callback_ctx * ctx, SV * val) {
    int cur_level = CUR_STACK_LEVEL(ctx);
    /* parse_cb_stack_entry * cur_entry = CUR_STACK_ENTRY(ctx); */
    parse_cb_stack_entry * new_entry;
    int is_hash_or_array = 0;
    int type = 0;

    /*
    int type = cur_entry->type;
    int sv_type = SvTYPE(val);
    */

    if (SvROK(val)) {
        type = SvTYPE(SvRV(val));
        if (type == SVt_PVHV || type == SVt_PVAV) {
            is_hash_or_array = 1;
        }
    }

    if (is_hash_or_array) {
        if (cur_level >= 0) {
            /* av_push((AV *)SvRV(cur_entry->data), val); */
            SETUP_TRACE;
            insert_entry(ctx, val);
        }

        new_entry = PUSH_STACK_ENTRY(ctx);
        new_entry->data = val;
    }
    else {        
        SETUP_TRACE;
        if (cur_level >= 0) {
            SETUP_TRACE;
            insert_entry(ctx, val);
        }
        else {
            SETUP_TRACE;
            new_entry = PUSH_STACK_ENTRY(ctx);
            new_entry->data = val;
        }
        /* av_push((AV *)SvRV(cur_entry->data), val); */
    }

    return 1;

#if 0
    switch (type) {
      case TYPE_HASH_ENTRY:
          new_entry = PUSH_STACK_ENTRY(ctx);
          new_entry->type = TYPE_HASH_ENTRY_KEY;
          new_entry->ref = NULL;
          new_entry->data = val;
          LOG_DEBUG("adding hash key");
          break;

      case TYPE_HASH_ENTRY_KEY:
          new_entry = PUSH_STACK_ENTRY(ctx);
          new_entry->type = TYPE_HASH_ENTRY_VAL;
          new_entry->ref = NULL;
          new_entry->data = val;
          LOG_DEBUG("adding hash val");
          break;

      case TYPE_ARRAY_ELEMENT:
          POP_STACK(ctx);
          cur_entry = PUSH_STACK_ENTRY(ctx);
          cur_entry->type = TYPE_ARRAY_ELEMENT;
          
          if (SvOK(val)) {
              cur_entry->ref = val;
              cur_entry->data = SvRV(val);
          } else {
              cur_entry->ref = NULL;
              cur_entry->data = val;
          }
          LOG_DEBUG("adding array element");
          break;

      default:
          LOG_DEBUG("reached default case in push_stack_val()");
          return 0;
          break;
    }

    return 1;

#endif
}

static int
string_callback(void * cb_data, char * data, uint data_len, uint flags, uint level) {
    parse_callback_ctx * ctx = (parse_callback_ctx *)cb_data;
    SV * val;

    val = newSVpvn(data, data_len);

    /* flag as utf-8 */
    SvUTF8_on(val);

    SETUP_TRACE;
    push_stack_val(ctx, val);
    SETUP_TRACE;

    return 0;
}

static int
number_callback(void * cb_data, char * data, uint data_len, uint flags, uint level) {
    parse_callback_ctx * ctx = (parse_callback_ctx *)cb_data;
    NV nv_val;
    IV iv_val;
    UV uv_val;
    
    SV * sv_val = Nullsv;
    SV * tmp_sv = Nullsv;
    int try_big_num = 0;
    char * uv_str = Nullch;
    unsigned char number_done = 0;

    SETUP_TRACE;

    /* figure out if we need to create a BigNum object or not */
    if (flags & (JSON_EVT_PARSE_NUMBER_HAVE_DECIMAL | JSON_EVT_PARSE_NUMBER_HAVE_EXPONENT)) {
        if (flags & JSON_EVT_PARSE_NUMBER_HAVE_SIGN) {
            if (data_len - 1 >= DBL_DIG) {
                try_big_num = 1;
            }
        }
        else if (data_len >= DBL_DIG) {
            try_big_num = 1;
        }
    }
    else {
        if (flags & JSON_EVT_PARSE_NUMBER_HAVE_SIGN) {
            if (data_len - 1 >= IV_DIG) {
                if (data_len - 1 == IV_DIG) {
                    uv_str = form("%"IVdf"", IV_MIN);
                    if (strncmp(data, uv_str, data_len) > 0) {
                        try_big_num = 1;
                    }
                }
                else {
                    try_big_num = 1;
                }
            }
        }
        else {
            if (data_len >= UV_DIG) {
                if (data_len == UV_DIG) {
                    uv_str = form("%"UVuf"", UV_MAX);
                    if (strncmp(data, uv_str, data_len) > 0) {
                        try_big_num = 1;
                    }
                }
                else {
                    try_big_num = 1;
                }
            }
        }
    }

    if (try_big_num) {
        if (flags & (JSON_EVT_PARSE_NUMBER_HAVE_EXPONENT | JSON_EVT_PARSE_NUMBER_HAVE_DECIMAL)) {
            if (have_bigfloat()) {
                tmp_sv = newSVpvn(data, data_len);
                sv_val = get_new_big_float(tmp_sv);
                SvREFCNT_dec(tmp_sv);
            }
        }
        else {
            if (have_bigint()) {
                tmp_sv = newSVpvn(data, data_len);
                sv_val = get_new_big_int(tmp_sv);
                SvREFCNT_dec(tmp_sv);
            }
        }

        if (sv_val) {
            if (SvOK(sv_val)) {
                number_done = 1;
            }
            else {
                SvREFCNT_dec(sv_val);
                sv_val = Nullsv;
            }
        }
    }

    UNLESS (number_done) {
        sv_val = newSVpvn(data, data_len);

        if (try_big_num) {
            /* we're in danger of overflow, so leave it as a string */
            SvUTF8_on(sv_val);
        }
        else {
            if (flags & (JSON_EVT_PARSE_NUMBER_HAVE_DECIMAL | JSON_EVT_PARSE_NUMBER_HAVE_EXPONENT)) {

                /* float */
                nv_val = SvNV(sv_val);
                sv_setnv(sv_val, nv_val);
            }
            else if (flags & JSON_EVT_PARSE_NUMBER_HAVE_SIGN) {
                /* signed int */
                iv_val = SvIV(sv_val);
                sv_setiv(sv_val, iv_val);
            }
            else {
                /* unsigned int */
                uv_val = SvUV(sv_val);
                sv_setuv(sv_val, uv_val);
            }
        }

    }

    push_stack_val(ctx, sv_val);

    return 0;
}

static int
array_begin_callback(void * cb_data, uint flags, uint level) {
    parse_callback_ctx * ctx = (parse_callback_ctx *)cb_data;

    push_stack_val(ctx, newRV_noinc((SV *)newAV()));

    LOG_DEBUG("\nin array_begin callback at level %u\n", level);

    return 0;
}

static int
array_end_callback(void * cb_data, uint flags, uint level) {
    parse_callback_ctx * ctx = (parse_callback_ctx *)cb_data;

    if (CUR_STACK_LEVEL(ctx) > 0) {
        POP_STACK(ctx);
    }
    LOG_DEBUG("\nin array_end callback at level %u\n", level);

    return 0;
}

#if 0
static int
array_element_begin_callback(void * cb_data, uint flags, uint level) {
    LOG_DEBUG("\nin array element begin callback at level %u\n", level);

    return 0;
}

static int
array_element_end_callback(void * cb_data, uint flags, uint level) {
    LOG_DEBUG("\nin array element end callback at level %u\n", level);

    return 0;
}
#endif

static int
hash_begin_callback(void * cb_data, uint flags, uint level) {
    parse_callback_ctx * ctx = (parse_callback_ctx *)cb_data;

    push_stack_val(ctx, newRV_noinc((SV *)newHV()));

    LOG_DEBUG("in hash_begin callback at level %u, cb_data is %p", level, ctx);

    return 0;
}

static int
hash_end_callback(void * cb_data, uint flags, uint level) {
    parse_callback_ctx * ctx = (parse_callback_ctx *)cb_data;


    if (CUR_STACK_LEVEL(ctx) > 0) {
        POP_STACK(ctx);
    }

    LOG_DEBUG("in hash_end callback at level %u, cb_data is %p", level, ctx);

    return 0;
}

#if 0
static int
hash_entry_begin_callback(void * cb_data, uint flags, uint level) {
    /* parse_callback_ctx * ctx = (parse_callback_ctx *)cb_data; */

    LOG_DEBUG("in hash_entry_begin callback at level %u", level);

    return 0;
}

static int
hash_entry_end_callback(void * cb_data, uint flags, uint level) {
    /*
    */

    LOG_DEBUG("\nin hash_entry_end callback at level %u, stack_level %d\n", level, ctx->stack_level);
    return 0;
}
#endif

static int
bool_callback(void * cb_data, uint bool_val, uint flags, uint level) {
    parse_callback_ctx * ctx = (parse_callback_ctx *)cb_data;
    SV * s;

    if (ctx->options & EVT_OPTION_CONVERT_BOOL) {
        s = get_new_bool_obj(bool_val);
    }
    else {
        s = bool_val ? newSVuv(1) : newSVpvn("", 0);
    }

    push_stack_val(ctx, s);

    LOG_DEBUG("\nin bool_callback with val %u at level %u\n", bool_val, level);

    return 0;
}

static int
null_callback(void * cb_data, uint flags, uint level) {
    parse_callback_ctx * ctx = (parse_callback_ctx *)cb_data;
    SV * s = newSV(0);

    push_stack_val(ctx, s);

    return 0;
}

static int
sv_str_eq(SV * sv_val, const char * c_buf, STRLEN c_buf_len) {
    STRLEN sv_len = 0;
    char * sv_buf;

    sv_buf = SvPV(sv_val, sv_len);

    UNLESS (sv_len == c_buf_len) {
        return 0;
    }

    UNLESS (memcmp((void *)sv_buf, (void *)c_buf, (size_t)c_buf_len)) {
        return 1;
    }

    return 0;
}

static int
setup_options(jsonevt_ctx * json_ctx, parse_callback_ctx * ctx, SV * self_sv) {
    SV ** ptr;
    HV * self_hash;
    IV num_keys = 0;

    UNLESS (self_sv) {
        return 0;
    }

    if (SvROK(self_sv)) {
        self_hash = (HV *)SvRV(self_sv);
    }
    else {
        self_hash = (HV *)self_sv;
    }

    if (SvTYPE(self_hash) != SVt_PVHV) {
        return 0;
    }

    num_keys = HvKEYS(self_hash);

    if (num_keys == 0) {
        return 0;
    }

    ptr = hv_fetch((HV *)self_hash, "convert_bool", 12, 0);
    if (ptr && SvTRUE(*ptr)) {
        ctx->options |= EVT_OPTION_CONVERT_BOOL;
    }

    ptr = hv_fetch((HV *)self_hash, "use_exceptions", 14, 0);
    if (ptr && SvTRUE(*ptr)) {
        ctx->options |= EVT_OPTION_USE_EXCEPTIONS;
    }

    ptr = hv_fetch((HV *)self_hash, "bad_char_policy", 15, 0);
    if (ptr && SvTRUE(*ptr)) {
        if (sv_str_eq(*ptr, "convert", 7)) {
            jsonevt_set_bad_char_policy(json_ctx, JSON_EVT_OPTION_BAD_CHAR_POLICY_CONVERT);
        }
        else if (sv_str_eq(*ptr, "pass_through", 12)) {
            jsonevt_set_bad_char_policy(json_ctx, JSON_EVT_OPTION_BAD_CHAR_POLICY_PASS);
        }
    }

    return 1;
}

static jsonevt_ctx *
init_cbs(perl_wrapper_ctx * pwctx, SV * self_sv) {
    jsonevt_ctx * ctx = jsonevt_new_ctx();
    parse_callback_ctx * cb_data;
    /*
    char * error = Nullch;
    SV * rv = Nullsv;
    HV * error_hash = Nullhv;
    HV * stats = Nullhv;
    int throw_exception = 0;
    SV * tmp_sv = Nullsv;
    SV * error_msg = Nullsv;
    SV * error_data_ref = Nullsv;
    SV * stats_ref = Nullsv;
    */

    SETUP_TRACE;

    memzero(pwctx, sizeof(*pwctx));
    cb_data = &pwctx->cbd;

    /* memzero(&cb_data, sizeof(parse_callback_ctx)); */

    cb_data->stack_size = 64;

    New(0, cb_data->stack, cb_data->stack_size, parse_cb_stack_entry);

    cb_data->stack_level = -1;
    memzero(cb_data->stack, cb_data->stack_size * sizeof(parse_cb_stack_entry));

    jsonevt_set_cb_data(ctx, cb_data);

    jsonevt_set_string_cb(ctx, string_callback);
    jsonevt_set_number_cb(ctx, number_callback);
    jsonevt_set_begin_array_cb(ctx, array_begin_callback);
    jsonevt_set_end_array_cb(ctx, array_end_callback);
    /*
    jsonevt_set_begin_array_element_cb(ctx, array_element_begin_callback);
    jsonevt_set_end_array_element_cb(ctx, array_element_end_callback);
    */
    jsonevt_set_begin_hash_cb(ctx, hash_begin_callback);
    jsonevt_set_end_hash_cb(ctx, hash_end_callback);
    /*
    jsonevt_set_begin_hash_entry_cb(ctx, hash_entry_begin_callback);
    jsonevt_set_end_hash_entry_cb(ctx, hash_entry_end_callback);
    */

    jsonevt_set_bool_cb(ctx, bool_callback);
    jsonevt_set_null_cb(ctx, null_callback);

    setup_options(ctx, cb_data, self_sv);



    return ctx;
}

static SV *
handle_parse_result(int result, jsonevt_ctx * ctx, perl_wrapper_ctx * wctx) {
    char * error = Nullch;
    SV * rv = Nullsv;
    HV * error_hash = Nullhv;
    int throw_exception = 0;
    SV * tmp_sv = Nullsv;
    SV * error_msg = Nullsv;
    SV * error_data_ref = Nullsv;
    SV * stats_ref = Nullsv;
    HV * stats = Nullhv;
    
    UNLESS (result) {
        SETUP_TRACE;
    
        error = jsonevt_get_error(ctx);

        if (wctx->cbd.options & EVT_OPTION_USE_EXCEPTIONS) {
            throw_exception = 1;
        }

        SETUP_TRACE;

        LOG_DEBUG("\nError: %s\n\n", error);
        if (error) {
            error_msg = newSVpvf("%s v%s %s", MOD_NAME, XS_VERSION, error);
        }
        else {
            error_msg = newSVpvf("%s v%s - error", MOD_NAME, XS_VERSION);
        }

        error_hash = newHV();

        error_data_ref = newRV_noinc((SV *)error_hash);
        
        hv_store(error_hash, "version", 7, newSVpvf("%s", XS_VERSION), 0);
        hv_store(error_hash, "char", 4, newSVuv(jsonevt_get_error_char_pos(ctx)), 0);
        hv_store(error_hash, "byte", 4, newSVuv(jsonevt_get_error_byte_pos(ctx)), 0);
        hv_store(error_hash, "line", 4, newSVuv(jsonevt_get_error_line(ctx)), 0);
        hv_store(error_hash, "col", 3, newSVuv(jsonevt_get_error_char_col(ctx)), 0);
        hv_store(error_hash, "byte_col", 8, newSVuv(jsonevt_get_error_byte_col(ctx)), 0);

        tmp_sv = get_sv("JSON::DWIW::LastErrorData", 1);
        sv_setsv(tmp_sv, error_data_ref);
        SvREFCNT_dec(error_data_ref);

        tmp_sv = get_sv("JSON::DWIW::LastError", 1);
        sv_setsv(tmp_sv, error_msg); /* ref count decremented below after exceptions check */

        tmp_sv = get_sv("JSON::DWIW::Last_Stats", 1);
        sv_setsv(tmp_sv, &PL_sv_undef);

        if (wctx->cbd.stack[0].data) {
            SvREFCNT_dec(wctx->cbd.stack[0].data);
        }

        SETUP_TRACE;
    }
    else {
        SETUP_TRACE;
        rv = wctx->cbd.stack[0].data;
        stats = newHV();

        hv_store(stats, "strings", 7, newSVuv(jsonevt_get_stats_string_count(ctx)), 0);
        hv_store(stats, "max_string_bytes", 16, newSVuv(jsonevt_get_stats_longest_string_bytes(ctx)), 0);
        hv_store(stats, "max_string_chars", 16, newSVuv(jsonevt_get_stats_longest_string_chars(ctx)), 0);
        hv_store(stats, "numbers", 7, newSVuv(jsonevt_get_stats_number_count(ctx)), 0);
        hv_store(stats, "bools", 5, newSVuv(jsonevt_get_stats_bool_count(ctx)), 0);
        hv_store(stats, "nulls", 5, newSVuv(jsonevt_get_stats_null_count(ctx)), 0);
        hv_store(stats, "hashes", 6, newSVuv(jsonevt_get_stats_hash_count(ctx)), 0);
        hv_store(stats, "arrays", 6, newSVuv(jsonevt_get_stats_array_count(ctx)), 0);
        hv_store(stats, "max_depth", 9, newSVuv(jsonevt_get_stats_deepest_level(ctx)), 0);
        
        hv_store(stats, "lines", 5, newSVuv(jsonevt_get_stats_line_count(ctx)), 0);
        hv_store(stats, "bytes", 5, newSVuv(jsonevt_get_stats_byte_count(ctx)), 0);
        hv_store(stats, "chars", 5, newSVuv(jsonevt_get_stats_char_count(ctx)), 0);
        
        tmp_sv = get_sv("JSON::DWIW::Last_Stats", 1);
        stats_ref = newRV_noinc((SV *)stats);
        sv_setsv(tmp_sv, stats_ref);
        SvREFCNT_dec(stats_ref);
        
        tmp_sv = get_sv("JSON::DWIW::LastErrorData", 1);
        sv_setsv(tmp_sv, &PL_sv_undef);

        tmp_sv = get_sv("JSON::DWIW::LastError", 1);
        sv_setsv(tmp_sv, &PL_sv_undef);

    }

    jsonevt_free_ctx(ctx);

    if (throw_exception) {
        tmp_sv = get_sv("@", TRUE);
        sv_setsv(tmp_sv, error_msg);
        SvREFCNT_dec(error_msg);

        croak(Nullch);
    }

    SvREFCNT_dec(error_msg);

    /* LOG_DEBUG("\n\noriginal buf: %s\n\n", buf); */

    if (rv) {
        LOG_DEBUG("returning rv");
        /* return &PL_sv_yes; */
        return rv;
    }
    else {
        LOG_DEBUG("returning undef");
        return &PL_sv_undef;
    }

    return &PL_sv_undef;
}

SV *
do_json_parse_buf(SV * self_sv, char * buf, STRLEN buf_len) {
    jsonevt_ctx * ctx;
    perl_wrapper_ctx wctx;

    SETUP_TRACE;

    memzero(&wctx, sizeof(perl_wrapper_ctx));
    ctx = init_cbs(&wctx, self_sv);

    return handle_parse_result(jsonevt_parse(ctx, buf, buf_len), ctx, &wctx);

}


SV *
do_json_parse(SV * self_sv, SV * json_str_sv) {
    char * buf;
    STRLEN buf_len;

    SETUP_TRACE;

    buf = SvPV(json_str_sv, buf_len);
    
    return do_json_parse_buf(self_sv, buf, buf_len);
}

SV *
do_json_parse_file(SV * self_sv, SV * file_sv) {
    char * filename;
    STRLEN filename_len;
    jsonevt_ctx * ctx;
    perl_wrapper_ctx wctx;

    SETUP_TRACE;

    filename = SvPV(file_sv, filename_len);

    memzero(&wctx, sizeof(perl_wrapper_ctx));
    ctx = init_cbs(&wctx, self_sv);

    return handle_parse_result(jsonevt_parse_file(ctx, filename), ctx, &wctx);
}

