#ifndef WATCH_CJSON_XC_MEMORY_H_
#define WATCH_CJSON_XC_MEMORY_H_

#include <stdlib.h>

/*
 * The repository cJSON implementation uses the common xc_memory abstraction.
 * The watch application only needs cJSON's allocation hooks, so the delivery
 * package provides a portable libc-backed implementation instead of pulling
 * the complete repository base layer into every vendor package.
 */
#define xc_malloc malloc
#define xc_free free
#define xc_realloc realloc

#endif
