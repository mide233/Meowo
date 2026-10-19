#ifndef MEOWO_CORE_H
#define MEOWO_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Returns a static, null-terminated version string. Do not free. */
const char* meowo_core_version(void);

/*
 * Opens or creates a Meowo library directory.
 * Returns a non-zero handle on success, 0 on failure. On failure, *error is
 * set to a malloc-allocated UTF-8 message (free with meowo_free).
 */
uint64_t meowo_workspace_open(const char* root, char** error);

/* Closes a workspace handle. Safe to call with 0. */
void meowo_workspace_close(uint64_t handle);

/*
 * Executes a JSON request. The returned string is malloc-allocated JSON and
 * must be freed with meowo_free. On failure, returns NULL and sets *error to a
 * malloc-allocated UTF-8 message.
 */
char* meowo_invoke(uint64_t handle, const char* request, char** error);

void meowo_free(char* ptr);

#ifdef __cplusplus
}
#endif

#endif
