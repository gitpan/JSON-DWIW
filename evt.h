#ifndef EVT_H
#define EVT_H

SV *
do_json_parse_buf(SV * self_sv, char * buf, STRLEN buf_len);

SV * do_json_parse(SV * self_sv, SV * json_str_sv);
SV * do_json_parse_file(SV * self_sv, SV * file_sv);


#endif

