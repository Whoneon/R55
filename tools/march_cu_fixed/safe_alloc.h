/*
   Safe memory allocation wrappers for march_cu.

   The original code never checks malloc/realloc return values,
   causing segfaults on large instances (e.g., 2M clauses for R(5,5)).

   These wrappers abort with a clear error message instead of
   silently dereferencing NULL.

   Added 2026-03 for the R(5,5) project.
*/

#ifndef __SAFE_ALLOC_H__
#define __SAFE_ALLOC_H__

#include <stdio.h>
#include <stdlib.h>

static inline void *safe_malloc(size_t size, const char *file, int line) {
    void *ptr = malloc(size);
    if (ptr == NULL && size > 0) {
        fprintf(stderr, "FATAL: malloc(%zu) failed at %s:%d\n", size, file, line);
        fprintf(stderr, "  The instance is too large for available memory.\n");
        fprintf(stderr, "  Try reducing the number of clauses or increasing RAM.\n");
        exit(EXIT_CODE_ERROR);
    }
    return ptr;
}

static inline void *safe_realloc(void *old, size_t size, const char *file, int line) {
    void *ptr = realloc(old, size);
    if (ptr == NULL && size > 0) {
        fprintf(stderr, "FATAL: realloc(%zu) failed at %s:%d\n", size, file, line);
        fprintf(stderr, "  The instance is too large for available memory.\n");
        exit(EXIT_CODE_ERROR);
    }
    return ptr;
}

#define SAFE_MALLOC(size)       safe_malloc((size), __FILE__, __LINE__)
#define SAFE_REALLOC(ptr, size) safe_realloc((ptr), (size), __FILE__, __LINE__)

#endif
