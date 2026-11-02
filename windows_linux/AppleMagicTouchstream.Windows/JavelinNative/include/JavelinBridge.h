#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef _WIN32
#define AMT_API __declspec(dllexport)
#else
#define AMT_API
#endif
#ifdef __cplusplus
extern "C" {
#endif
// Instances are serially owned by the host. These functions never post input.
AMT_API void *AMTJavelinCreate(void);
AMT_API void AMTJavelinDestroy(void *engine);
AMT_API int AMTJavelinAdd(void *engine, const char *outline, const char *translation);
AMT_API int AMTJavelinFormatStroke(uint32_t stroke, char *output, size_t capacity);
AMT_API int AMTJavelinCanonicalOutline(const char *input, char *output, size_t capacity);
AMT_API void AMTJavelinReset(void *engine);
AMT_API int AMTJavelinProcess(void *engine, uint32_t stroke);
AMT_API size_t AMTJavelinDeleteCount(void *engine);
AMT_API size_t AMTJavelinTextCount(void *engine);
AMT_API uint32_t AMTJavelinTextAt(void *engine, size_t index);
#ifdef __cplusplus
}
#endif
