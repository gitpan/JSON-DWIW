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

#define JSON_DO_DEBUG 0
#define JSON_DO_EXTENDED_ERRORS 1

#if JSON_DO_DEBUG
#define JSON_DEBUG(...) printf("%s (%d) - ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); fflush(stdout)
#else
#define JSON_DEBUG(...)
#endif

#ifndef UTF8_IS_INVARIANT
#define UTF8_IS_INVARIANT(c) (((UV)c) < 0x80)
#endif

#define kCommasAreWhitespace 1

static SV *
_build_error_str(const char *file, STRLEN line_num, SV *error_str) {
	SV * where_str = newSVpvf(" (%s line %d)", file, line_num);
	sv_catsv(error_str, where_str);
	SvREFCNT_dec(where_str);
	
	return error_str;
}

#if JSON_DO_EXTENDED_ERRORS
#define JSON_ERROR(...) _build_error_str(__FILE__, __LINE__, newSVpvf(__VA_ARGS__))
#else
#define JSON_ERROR(...) newSVpvf(__VA_ARGS__)
#endif


typedef struct {
	STRLEN len;
	char * data;
	STRLEN pos;
	SV * error;
    SV * self;
} json_context;

static SV * json_parse_value(json_context *ctx, int is_identifier);
static SV * fast_to_json(SV * self, SV * data_ref);

static char
json_next_byte(json_context *ctx) {
	char rv;

	if (ctx->pos >= ctx->len) {
		return (char)0;
	}

	rv = ctx->data[ctx->pos];
	ctx->pos++;
	return rv;
}

static char
json_peek_byte(json_context *ctx) {
	if (ctx->pos >= ctx->len) {
		return (char)0;
	}

	return ctx->data[ctx->pos];
}

static UV
convert_utf8_to_uv(U8 * utf8, STRLEN * len_ptr) {
#ifdef IS_PERL_5_6
	return utf8_to_uv_simple(utf8, len_ptr);
#else
	return utf8_to_uvuni(utf8, len_ptr);
#endif
}

static U8 *
convert_uv_to_utf8(U8 *buf, UV uv) {
#ifdef IS_PERL_5_6
	return uv_to_utf8(buf, uv);
#else
	return uvuni_to_utf8(buf, uv);
#endif
}

static UV
json_next_char(json_context *ctx) {
	UV uv = 0;
	STRLEN len = 0;

	if (ctx->pos >= ctx->len) {
		JSON_DEBUG("pos=%d, len=%d", ctx->pos, ctx->len);
		return 0;
	}

	if (UTF8_IS_INVARIANT(ctx->data[ctx->pos])) {
		uv = ctx->data[ctx->pos];
		ctx->pos++;
	}
	else {
		uv = convert_utf8_to_uv((unsigned char *)&(ctx->data[ctx->pos]), &len);
		ctx->pos += len;
	}

	JSON_DEBUG("pos=%d, len=%d, char=%c (%#04x)", ctx->pos, ctx->len, uv>0x80 ? '?' : (char)uv, uv);

	return uv;
}

static UV
json_peek_char(json_context *ctx) {
	UV uv = 0;
	STRLEN len = 0;

	if (ctx->pos >= ctx->len) {
		return 0;
	}

	if (UTF8_IS_INVARIANT(ctx->data[ctx->pos])) {
		return ctx->data[ctx->pos];
	}
	else {
		uv = convert_utf8_to_uv((unsigned char *)&(ctx->data[ctx->pos]), &len);
	}

	return uv;
}

static void
json_eat_whitespace(json_context *ctx, UV flags) {
	UV this_char;
	int break_out = 0;

	JSON_DEBUG("json_eat_whitespace: starting pos %d", ctx->pos);

	while (ctx->pos < ctx->len) {
		this_char = json_peek_char(ctx);
		JSON_DEBUG("looking at %04x at pos %d", this_char, ctx->pos);
		
		switch (this_char) {
		  case 0x20:
		  case 0x09:
		  case 0x0a:
		  case 0x0d:
			  json_next_char(ctx);
			  break;

		  case ',':
			  if (flags & kCommasAreWhitespace) {
				  json_next_char(ctx);
			  }
			  else {
				  break_out = 1;
			  }
			  break;
			
		  case '/':
			  json_next_char(ctx);
			  this_char = json_peek_char(ctx);
			  JSON_DEBUG("looking at %04x at pos %d", this_char, ctx->pos);
			  if (this_char == '/') {
				  JSON_DEBUG("in C++ style comment at pos %d", ctx->pos);
				  while (ctx->pos < ctx->len) {
					  json_next_char(ctx);
					  this_char = json_peek_char(ctx);
					  if (this_char == 0x0a || this_char == 0x0d) {
						  /* FIXME: should peak at the next to see if windows line ending, etc. */
						  break;
					  }
				  }
			  }
			  else if (this_char == '*') {
				  json_next_char(ctx);
				  this_char = json_peek_char(ctx);
				  JSON_DEBUG("in comment at pos %d, looking at %04x", ctx->pos, this_char);

				  while (ctx->pos < ctx->len) {
					  if (this_char == '*') {
						  json_next_char(ctx);
						  this_char = json_peek_char(ctx);
						  if (this_char == '/') {
							  /* end of comment */
							  json_next_char(ctx);
							  break;
						  }
					  }
					  else {
						  json_next_char(ctx);
						  this_char = json_peek_char(ctx);
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

static SV *
_append_buffer(SV * str, json_context *ctx, STRLEN start_pos, STRLEN offset) {
	if (str) {
		sv_catpvn(str, ctx->data + start_pos, ctx->pos - start_pos - offset);
	}
	else {
		str = newSVpv(ctx->data + start_pos, ctx->pos - start_pos - offset);
	}
	
	return str;
}

static SV *
_append_c_buffer(SV * str, const char *buf, STRLEN len) {
	if (str) {
		sv_catpvn(str, buf, len);
	}
	else {
		str = newSVpv(buf, len);
	}
	
	return str;
}

static void
json_eat_digits(json_context *ctx) {
	unsigned char looking_at;

	looking_at = json_peek_byte(ctx);
	while (ctx->pos < ctx->len && looking_at >= '0' && looking_at <= '9') {
		json_next_byte(ctx);
		looking_at = json_peek_byte(ctx);
	}
}

static SV *
json_parse_number(json_context *ctx, SV * tmp_str) {
	SV * rv = NULL;
	unsigned char looking_at;
	unsigned char this_char;
	STRLEN start_pos = ctx->pos;
	NV num_value = 0; /* double */
	
	looking_at = json_peek_byte(ctx);
	if (looking_at == '-') {
		json_next_byte(ctx);
		looking_at = json_peek_byte(ctx);
	}

	if (looking_at < '0' || looking_at > '9') {
		JSON_DEBUG("syntax error at byte %d", ctx->pos);
		ctx->error = JSON_ERROR("syntax error at byte %d", ctx->pos);
		return (SV *)&PL_sv_undef;
	}

	json_eat_digits(ctx);

	if (ctx->pos < ctx->len) {
		looking_at = json_peek_byte(ctx);

		if (looking_at == '.') {
			json_next_byte(ctx);
			json_eat_digits(ctx);
			looking_at = json_peek_byte(ctx);
		}

		if (ctx->pos < ctx->len) {
			if (looking_at == 'E' || looking_at == 'e') {
				/* exponential notation */
				json_next_byte(ctx);
				if (ctx->pos < ctx->len) {
					looking_at = json_peek_byte(ctx);
					if (looking_at == '+' || looking_at == '-') {
						json_next_byte(ctx);
						looking_at = json_peek_byte(ctx);
					}
					
					json_eat_digits(ctx);
					looking_at = json_peek_byte(ctx);
				}
			}
		}
	}

	/* FIXME: return a number here instead of a string -- use Bigint if the number is big */
	rv = _append_buffer(rv, ctx, start_pos, 0);
	
	num_value = SvNV(rv);
	sv_setnv(rv, num_value);

	return rv;
}

static SV *
json_parse_word(json_context *ctx, SV * tmp_str, int is_identifier) {
	SV * rv = NULL;
	UV looking_at;
	UV this_char;
	STRLEN start_pos = 0;
	
	looking_at = json_peek_char(ctx);
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
		looking_at = json_peek_char(ctx);

		JSON_DEBUG("looking at %04x", looking_at);
		
		if ( (looking_at >= '0' && looking_at <= '9')
			|| (looking_at >= 'A' && looking_at <= 'Z')
			|| (looking_at >= 'a' && looking_at <= 'z')
			|| looking_at == '_'
			 ) {
			JSON_DEBUG("json_parse_word(): got %04x at %d", looking_at, ctx->pos);

			this_char = json_next_char(ctx);
		}
		else {
			if (ctx->pos == start_pos) {
				/* syntax error */
				JSON_DEBUG("syntax error at byte %d, looking_at = %04x", ctx->pos, looking_at);
				ctx->error = JSON_ERROR("syntax error at byte %d", ctx->pos);
				return (SV *)&PL_sv_undef;
			}
			else {
				if (! is_identifier) {
					if (! strncasecmp("true", ctx->data + start_pos, ctx->pos - start_pos)) {
						JSON_DEBUG("returning true from json_parse_word() at byte %d", ctx->pos);
						return _append_c_buffer(rv, "1", 1);
					}
					else if (! strncasecmp("false", ctx->data + start_pos, ctx->pos - start_pos)) {
						JSON_DEBUG("returning false from json_parse_word() at byte %d", ctx->pos);
						return _append_c_buffer(rv, "0", 1);
					}
					else if (! strncasecmp("null", ctx->data + start_pos, ctx->pos - start_pos)) {
						JSON_DEBUG("returning undef from json_parse_word() at byte %d", ctx->pos);
						return (SV *)&PL_sv_undef;
					}
				}
				JSON_DEBUG("returning from json_parse_word() at byte %d", ctx->pos);
				return _append_buffer(rv, ctx, start_pos, 0);
			}
			break;
		}
	}

	JSON_DEBUG("syntax error at byte %d", ctx->pos);
	ctx->error = JSON_ERROR("syntax error at byte %d", ctx->pos);
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
	STRLEN start_pos;
	STRLEN orig_start_pos;
	SV * rv = NULL;
	char * char_buf;
	int i;
	U8 * tmp_buf = NULL;
	STRLEN max_str_size = 0;

	unicode_digits[4] = '\x00';

	looking_at = json_peek_char(ctx);
	if (looking_at != '"' && looking_at != '\'') {
		return (SV *)&PL_sv_undef;
	}

	boundary = looking_at;
	this_uv = json_next_char(ctx);
	next_uv = json_peek_char(ctx);
	orig_start_pos = ctx->pos;

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
		this_uv = json_next_char(ctx);

		if (next_uv == boundary) {
			JSON_DEBUG("found boundary %04x", boundary);
			return rv;
		}
		else if (this_uv == '\\') {
			this_uv = json_next_char(ctx);
			next_uv = json_peek_char(ctx);
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
						this_uv = json_next_char(ctx);
						if ( (this_uv >= '0' && this_uv <= '9')
							|| (this_uv >= 'A' && this_uv <= 'F')
							|| (this_uv >= 'a' && this_uv <= 'f')
							 ) {
							unicode_digits[i] = this_uv;
						}
						else {
							ctx->error = JSON_ERROR("bad unicode character specification at byte %d",
								ctx->pos - 1);
							if (rv && !tmp_str) {
								SvREFCNT_dec(rv);
								rv = NULL;
							}
							return (SV *)&PL_sv_undef;
						}
					}

					if (i != 4) {
						ctx->error = JSON_ERROR("bad unicode character specification at byte %d",
							ctx->pos - 1);
						if (rv && !tmp_str) {
							SvREFCNT_dec(rv);
							rv = NULL;
						}
						return (SV *)&PL_sv_undef;
					}

					JSON_DEBUG("found wide char %s\n", unicode_digits);

					next_uv = json_peek_char(ctx);

					sscanf((char *)unicode_digits, "%04x", &this_uv);
					tmp_buf = convert_uv_to_utf8(unicode_digits, this_uv);
					if (!SvUTF8(rv)) {
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
			JSON_DEBUG("before json_peek_char()");
			next_uv = json_peek_char(ctx);
			JSON_DEBUG("after next_char(), got %04x", next_uv);
			
		}
	}
	
	ctx->error = JSON_ERROR("unterminated string starting at byte %d", orig_start_pos);
	return (SV *)&PL_sv_undef;
}

static SV *
json_parse_object(json_context *ctx) {
	UV looking_at;
	HV * hash;
	SV * key;
	SV * val;
	SV * tmp_str;
	int found_comma = 0;

	looking_at = json_peek_char(ctx);
	if (looking_at != '{') {
		JSON_DEBUG("json_parse_object: looking at %04x", looking_at);
		return (SV *)&PL_sv_undef;
	}

	hash = newHV();

	json_next_char(ctx);

	json_eat_whitespace(ctx, kCommasAreWhitespace);
	
	looking_at = json_peek_char(ctx);

	JSON_DEBUG("json_parse_object: looking at %04x", looking_at);
	if (looking_at == '}') {
		json_next_char(ctx);
		return (SV *)newRV_noinc((SV *)hash);
	}

	key = tmp_str = sv_newmortal();

	/* assign something so we can call SvGROW() later without causing a bus error */
	sv_setpvn(key, "DEADBEEF", 8);

	while (ctx->pos < ctx->len) {
		looking_at = json_peek_char(ctx);
		found_comma = 0;

		if (looking_at == '"' || looking_at == '\'') {
			key = json_parse_string(ctx, key);
		}
		else {
			JSON_DEBUG("looking at %04x at %d", looking_at, ctx->pos);
			key = json_parse_word(ctx, key, 1);
		}

		JSON_DEBUG("looking at %04x at %d", looking_at, ctx->pos);

		json_eat_whitespace(ctx, 0);

		looking_at = json_peek_char(ctx);
		
		JSON_DEBUG("looking at %04x at %d", looking_at, ctx->pos);
		if (looking_at != ':') {
			JSON_DEBUG("bad object at %d", ctx->pos);
			ctx->error = JSON_ERROR("bad object at byte %d", ctx->pos);
			return (SV *)&PL_sv_undef;
		}
		json_next_char(ctx);
		
		json_eat_whitespace(ctx, 0);
		
		val = json_parse_value(ctx, 0);
		
		hv_store_ent(hash, key, val, 0);

		if (!SvOK(key)) {
			key = tmp_str;
		}

		json_eat_whitespace(ctx, 0);

		looking_at = json_peek_char(ctx);
		if (looking_at == ',') {
			found_comma = 1;
			json_eat_whitespace(ctx, kCommasAreWhitespace);
			looking_at = json_peek_char(ctx);
		}
		
		switch (looking_at) {
		case '}':
			json_next_char(ctx);
			return (SV *)newRV_noinc((SV *)hash);
			break;
			
		case ',':
			json_next_char(ctx);
			json_eat_whitespace(ctx, 0);
			break;

		default:
			if (!found_comma) {
				JSON_DEBUG("bad object at %d (%c)", ctx->pos, looking_at);
				ctx->error = JSON_ERROR("bad object at byte %d (%04x)", ctx->pos, looking_at);
				return (SV *)&PL_sv_undef;
			}
			break;
		}
	}

	JSON_DEBUG("bad object at %d", ctx->pos);
	ctx->error = JSON_ERROR("bad object at byte %d", ctx->pos);
	return (SV *)&PL_sv_undef;
}

static SV *
json_parse_array(json_context *ctx) {
	unsigned char looking_at;
	AV * array;
	SV * val;
	int found_comma = 0;

	looking_at = json_peek_byte(ctx);
	if (looking_at != '[') {
		return (SV *)&PL_sv_undef;
	}

	json_next_byte(ctx);

	json_eat_whitespace(ctx, 0);

	array = newAV();
	
	looking_at = json_peek_byte(ctx);
	if (looking_at == ']') {
		json_next_byte(ctx);
		return (SV *)newRV_noinc((SV *)array);
	}

	while (ctx->pos < ctx->len) {
		found_comma = 0;

		json_eat_whitespace(ctx, kCommasAreWhitespace);

	    val = json_parse_value(ctx, 0);
		av_push(array, val);

		json_eat_whitespace(ctx, 0);

		looking_at = json_peek_byte(ctx);
		if (looking_at == ',') {
			found_comma = 1;
			json_eat_whitespace(ctx, kCommasAreWhitespace);
			looking_at = json_peek_byte(ctx);
		}
		
		switch (looking_at) {
		  case ']':
			  json_next_byte(ctx);
			  return (SV *)newRV_noinc((SV *)array);
			  break;
			  
		  case ',':
			  json_next_byte(ctx);
			  json_eat_whitespace(ctx, kCommasAreWhitespace);
			  /* json_eat_whitespace(ctx, 0); */
			  break;
			  
		  default:
			  if (!found_comma) {
				  JSON_DEBUG("bad array at %d", ctx->pos);
				  ctx->error = JSON_ERROR("bad array at byte %d", ctx->pos);
				  return (SV *)&PL_sv_undef;
			  }
			  break;
		}
	}

	JSON_DEBUG("bad array at %d", ctx->pos);
	ctx->error = JSON_ERROR("bad array at byte %d", ctx->pos);
	return (SV *)&PL_sv_undef;
}

static SV *
json_parse_value(json_context *ctx, int is_identifier) {
	UV looking_at;
	SV * rv;

	JSON_DEBUG("before eat_whitespace");

	json_eat_whitespace(ctx, 0);

	JSON_DEBUG("after eat_whitespace");
	
	if (ctx->pos >= ctx->len || !ctx->data) {
		ctx->error = JSON_ERROR("bad object at byte %d", ctx->pos);
		return (SV *)&PL_sv_undef;
	}

	looking_at = json_peek_char(ctx);

	JSON_DEBUG("json_parse_value: looking at %04x", looking_at);

	switch (looking_at) {
	case '{':
		JSON_DEBUG("before json_parse_object()");
		rv = json_parse_object(ctx);
		JSON_DEBUG("after json_parse_object");
		return rv;
		break;

	case '[':
		JSON_DEBUG("before json_parse_array()");
		rv = json_parse_array(ctx);
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
parse_json(json_context *ctx) {
	return json_parse_value(ctx, 0);
}

static SV *
_private_from_json (SV * self, SV * data_sv, SV ** error_msg) {
	STRLEN data_str_len;
	char * data_str;
	json_context ctx;
	SV * val;

	data_str = SvPV(data_sv, data_str_len);
	if (!data_str) {
		/* return undef */
		return (SV *)&PL_sv_undef;
	}

	if (data_str_len == 0) {
		/* return empty string */
		val = newSVpv("", 0);
		return val;
	}

	ctx.len = data_str_len;
	ctx.data = data_str;
	ctx.pos = 0;
	ctx.error = (SV *)0;
	ctx.self = self;

	val = parse_json(&ctx);
	if (ctx.error) {
		*error_msg = ctx.error;
	}
	else {
		*error_msg = (SV *)&PL_sv_undef;
	}

	return (SV *)val;	
}

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

static SV *
fast_escape_json_str(SV * self, SV * sv_str) {
	U8 * data_str;
	STRLEN data_str_len;
	STRLEN needed_len = 0;
	STRLEN sv_pos = 0;
	STRLEN len = 0;
	U8 * tmp_str = NULL;
	U8 tmp_char = 0x00;
	SV * rv;
	int unicode_char_count = 0;
	int check_unicode = 1;
	UV this_uv = 0;
	U8 unicode_bytes[5];
	int escape_unicode = 0;

	memzero(unicode_bytes, 5); /* memzero macro provided by Perl */

	if (!SvOK(sv_str)) {
		return newSVpv("null", 4);
	}

	data_str = (U8 *)SvPV(sv_str, data_str_len);
	if (!data_str) {
		return newSVpv("null", 4);
	}

	if (data_str_len == 0) {
		return newSVpv("", 0);
	}

	needed_len = data_str_len * 2 + 2;

	check_unicode = SvUTF8(sv_str);

	rv = newSV(needed_len);
	if (check_unicode) {
		SvUTF8_on(rv);
	}
	sv_setpvn(rv, "\"", 1);

	for (sv_pos = 0; sv_pos < data_str_len; sv_pos++) {
		if (check_unicode) {
			len = UTF8SKIP(&data_str[sv_pos]);
			if (len > 1) {
				this_uv = convert_utf8_to_uv(&data_str[sv_pos], &len);
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
		  case '"':
			  /* case '\'': */
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
			  else if (check_unicode) {
				  tmp_str = convert_uv_to_utf8(unicode_bytes, this_uv);
				  if (PTR2UV(tmp_str) - PTR2UV(unicode_bytes) > 1) {
					  if (!SvUTF8(rv)) {
						  SvUTF8_on(rv);
					  }
				  }
				  sv_catpvn(rv, (char *)unicode_bytes, PTR2UV(tmp_str) - PTR2UV(unicode_bytes));
			  }
			  else {
				  tmp_char = this_uv;
				  sv_catpvn(rv, (char *)&tmp_char, 1);
			  }
			  break;
			  
		}
	}
	
	sv_catpvn(rv, "\"", 1);
	
	return rv;
}

static SV *
encode_array(SV * self, AV * array) {
	SV * rsv = newSVpv("[", 1);
	SV * tmp_sv = NULL;
	I32 max_i = av_len(array); /* max index, not length */
	I32 i;
	SV ** element = NULL;

	for (i = 0; i <= max_i; i++) {
		element = av_fetch(array, i, 0);
		if (element && *element) {
			tmp_sv = fast_to_json(self, *element);
			sv_catsv(rsv, tmp_sv);
			SvREFCNT_dec(tmp_sv);
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

	sv_catpvn(rsv, "]", 1);

	return rsv;
}

static SV *
encode_hash(SV * self, HV * hash) {
	SV * rsv = newSVpv("{", 1);
	SV * tmp_sv = NULL;
	SV * tmp_sv2 = NULL;
	char * key;
	I32 key_len;
	SV * val;
	int first = 1;
	
	/* non-sorted keys */
	hv_iterinit(hash);
	while (val = hv_iternextsv(hash, &key, &key_len)) {
		if (!first) {
			sv_catpvn(rsv, ",", 1);
		}

		first = 0;

		tmp_sv = newSVpv(key, key_len);
		tmp_sv2 = fast_escape_json_str(self, tmp_sv);
		
		sv_catsv(rsv, tmp_sv2);
		SvREFCNT_dec(tmp_sv);
		SvREFCNT_dec(tmp_sv2);

		sv_catpvn(rsv, ":", 1);

		tmp_sv = fast_to_json(self, val);
		sv_catsv(rsv, tmp_sv);
		SvREFCNT_dec(tmp_sv);
	}

	sv_catpvn(rsv, "}", 1);

	return rsv;
}

static SV *
fast_to_json(SV * self, SV * data_ref) {
	SV * data;
	int type;
	SV * rsv = newSVpv("", 0);
	SV * tmp = NULL;

	if (! SvROK(data_ref)) {
		data = data_ref;
		if (SvOK(data)) {
			/* scalar */
			type = SvTYPE(data);
			switch (type) {
			  case SVt_NULL:
				/* undef? */
				sv_setpvn(rsv, "null", 4);
				return rsv;
				break;
			  case SVt_IV:
			  case SVt_NV:
				  sv_catsv(rsv, data);
				  return rsv;
				  break;
			  case SVt_PV:
				sv_catsv(rsv, data);
				tmp = rsv;
				rsv = fast_escape_json_str(self, tmp);
				SvREFCNT_dec(tmp);
				return rsv;
				break;
			  case SVt_PVIV:
			  case SVt_PVNV:
			  case SVt_PVLV:
				  sv_catsv(rsv, data);
				  return rsv;
				  break;
			  default:
				  /* now what? */
				  sv_catsv(rsv, data);
				  tmp = rsv;
				  rsv = fast_escape_json_str(self, tmp);
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
		sv_catsv(rsv, data);
		return rsv;
		break;
	  case SVt_PV:
		sv_catsv(rsv, data);
		tmp = rsv;
		rsv = fast_escape_json_str(self, tmp);
		SvREFCNT_dec(tmp);
		return rsv;
		break;
	  case SVt_PVIV:
	  case SVt_PVNV:
	  case SVt_PVLV:
		  sv_catsv(rsv, data);
		  return rsv;
		  break;
	  case SVt_RV:
		/* reference to a reference */
		/* FIXME: implement */
		break;

	  case SVt_PVAV: /* array */
		  SvREFCNT_dec(rsv);
		  return encode_array(self, (AV *)data);
		break;
	  case SVt_PVHV: /* hash */
		  SvREFCNT_dec(rsv);
		  return encode_hash(self, (HV *)data);
		  break;
	  case SVt_PVCV: /* code */
		sv_setpvn(rsv, "code", 4);
		return rsv;
		break;
	  case SVt_PVGV: /* glob */
		  sv_catsv(rsv, data);
		  tmp = rsv;
		  rsv = fast_escape_json_str(self, tmp);
		  SvREFCNT_dec(tmp);

		  return rsv;
		  break;
	  case SVt_PVIO:
		  sv_catsv(rsv, data);
		  tmp = rsv;
		  rsv = fast_escape_json_str(self, tmp);
		  SvREFCNT_dec(tmp);
		  return rsv;
		  break;
	  case SVt_PVMG: /* blessed or magical scalar */
		  if (sv_isobject(data_ref)) {
			  if (sv_derived_from(data_ref, "HASH")) {
				  SvREFCNT_dec(rsv);
				  return encode_hash(self, (HV *)data);
			  }
			  else if (sv_derived_from(data_ref, "ARRAY")) {
				  SvREFCNT_dec(rsv);
				  return encode_array(self, (AV *)data);
			  }
			  else if (sv_derived_from(data_ref, "SCALAR")) {
				  sv_catsv(rsv, data);
				  return rsv;
			  }
		  }
		  else {
			  sv_catsv(rsv, data);
			  tmp = rsv;
			  rsv = fast_escape_json_str(self, tmp);
			  SvREFCNT_dec(tmp);
			  
			  return rsv;

/* 			  sv_setpvn(rsv, "magic scalar", 12); */
/* 			  return rsv; */
		  }
		  break;
		  
	  default:
		  sv_catsv(rsv, data);
		  tmp = rsv;
		  rsv = fast_escape_json_str(self, tmp);
		  SvREFCNT_dec(tmp);
		  
		  return rsv;
		  
/* 		  sv_setpvn(rsv, "unknown type", 12); */
/* 		  return rsv; */
			  
		  break;
	}

	sv_setpvn(rsv, "unknown type 2", 14);
	return rsv;

}


MODULE = JSON::DWIW  PACKAGE = JSON::DWIW

PROTOTYPES: DISABLE

SV *
_escape_json_str(self, sv_str)
 SV * self
 SV * sv_str
 
    PREINIT:
    SV * rv;

    CODE:
    rv = fast_escape_json_str(self, sv_str);
    RETVAL = rv;

    OUTPUT:
    RETVAL


SV *
_xs_from_json(self, data, error_msg_ref)
 SV * self
 SV * data
 SV * error_msg_ref

    PREINIT:
    SV * rv;
    SV * error_msg;
    SV * passed_error_msg_sv;

    CODE:
    error_msg = (SV *)&PL_sv_undef;
    rv = _private_from_json(self, data, &error_msg);
    if (SvOK(error_msg) && SvROK(error_msg_ref)) {
        passed_error_msg_sv = SvRV(error_msg_ref);
	    sv_setsv(passed_error_msg_sv, error_msg);
    }

    RETVAL = rv;

    OUTPUT:
    RETVAL


SV *
_xs_to_json(self, data)
 SV * self
 SV * data

	 CODE:
     RETVAL = fast_to_json(self, data);

     OUTPUT:
     RETVAL

