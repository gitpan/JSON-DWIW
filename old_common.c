/* Creation date: 2008-04-15T03:00:18Z
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

#include "old_common.h"

UV
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

static int g_have_big_int = kHaveModuleNotChecked;
static int g_have_big_float = kHaveModuleNotChecked;

int
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

int
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

