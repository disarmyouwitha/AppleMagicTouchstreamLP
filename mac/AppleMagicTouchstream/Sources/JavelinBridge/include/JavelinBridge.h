#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// Instances are serially owned by the host. These functions never post input.
void *AMTJavelinCreate(void);
void AMTJavelinDestroy(void *engine);
int AMTJavelinAdd(void *engine, const char *outline, const char *translation);
int AMTJavelinCanonicalOutline(const char *input, char *output, size_t capacity);
void AMTJavelinReset(void *engine);
int AMTJavelinProcess(void *engine, uint32_t stroke);
size_t AMTJavelinDeleteCount(void *engine);
size_t AMTJavelinTextCount(void *engine);
uint32_t AMTJavelinTextAt(void *engine, size_t index);
#ifdef __cplusplus
}
#endif
