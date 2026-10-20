#pragma once
#include <stdint.h>

typedef struct {
    uint64_t frames;
    uint64_t withContacts;
    uint64_t lastCount;
    uint64_t maxCount;
} ProbeNativeCounts;

// Optional diagnostic using the app's existing private MultitouchSupport path.
// 0=started, 1=missing inventory API, 2=no match, 3=ambiguous, 4=already running,
// 5=MTDeviceStart failed. Does not open or seize a HID device.
int ProbeNativeStart(const char *serial, const char *transport);
void ProbeNativeStop(void);
ProbeNativeCounts ProbeNativeRead(void);

// Separate opt-in FLTR experiment; never called by the original seize probe.
// 6=wrong native driver type, 7=pre-existing filter or inspection failure.
int ProbeNativeStartFilter(const char *serial);
int ProbeNativeFilterClients(uint64_t *ownedCount);
int32_t ProbeNativeLastStartStatus(void);
int32_t ProbeNativeLastStopStatus(void);
typedef struct { int64_t identifier, xMillionths, yMillionths; } ProbeNativePosition;
ProbeNativePosition ProbeNativeReadPosition(void);
