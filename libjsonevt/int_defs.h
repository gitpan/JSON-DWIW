/* Creation date: 2008-04-05T03:57:11Z
 * Authors: Don
 */

/* $Header: /repository/projects/libjsonevt/int_defs.h,v 1.1 2008/04/06 09:32:27 don Exp $ */

#ifndef INT_DEFS_H
#define INT_DEFS_H

#ifdef _MSC_VER
typedef unsigned __int8   uint8_t;
typedef unsigned __int32  uint32_t;
#else
#ifdef __FreeBSD__
#include <inttypes.h>
#else
#include <stdint.h>
#endif
#endif

#endif /* INT_DEFS_H */

