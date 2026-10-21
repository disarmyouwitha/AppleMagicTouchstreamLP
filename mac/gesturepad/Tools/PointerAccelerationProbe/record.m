// Ordinary-mode, listen-only native baseline recorder. Never takes FLTR ownership
// and never posts, suppresses, warps, or changes input/settings.
#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import <IOKit/IOKitLib.h>
#include <mach/mach_time.h>
#include <signal.h>
#include <stdatomic.h>
#include <pthread.h>
#include "../../Framework/OpenMultitouchSupportXCF/OpenMTInternal.h"

#define CONTACT_CAPACITY 16000
#define POINTER_CAPACITY 64000
#define MAX_CONTACTS 16

typedef struct { int id, state; float x, y; } Contact;
typedef struct { double t, nativeTime; size_t count; Contact contacts[MAX_CONTACTS]; } ContactSample;
typedef struct { double t, eventTime, x, y, observedX, observedY; int type; bool edge; int64_t sourcePID; } PointerSample;
static ContactSample *contacts;
static PointerSample *pointers;
static size_t contactCount, pointerCount, droppedContacts, droppedPointers;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static atomic_bool tapDisabled;
static volatile sig_atomic_t interrupted;
static mach_timebase_info_data_t timebase;
static CGRect displays[32];
static uint32_t displayCount;
static double now(void) { return (double)mach_absolute_time() * timebase.numer / timebase.denom / 1e9; }
static void interruptHandler(int sig) { (void)sig; interrupted = 1; }

static void receiveContacts(MTDeviceRef device, MTTouch *touches, int count,
                            double timestamp, int frame) {
    (void)device; (void)frame;
    if (count < 0) return;
    ContactSample sample = {.t = now(), .nativeTime = timestamp, .count = MIN(count, MAX_CONTACTS)};
    for (size_t i = 0; i < sample.count; i++) {
        sample.contacts[i] = (Contact){touches[i].identifier, touches[i].state,
            touches[i].normalizedPosition.position.x, touches[i].normalizedPosition.position.y};
    }
    pthread_mutex_lock(&lock);
    if (count > MAX_CONTACTS || contactCount == CONTACT_CAPACITY) droppedContacts++;
    else contacts[contactCount++] = sample;
    pthread_mutex_unlock(&lock);
}

static CGEventRef receivePointer(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    (void)proxy; (void)refcon;
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        atomic_store(&tapDisabled, true);
        return event;
    }
    CGPoint point = CGEventGetLocation(event);
    CGEventRef current = CGEventCreate(NULL);
    CGPoint observed = current ? CGEventGetLocation(current) : point;
    if (current) CFRelease(current);
    bool edge = false;
    for (uint32_t i = 0; i < displayCount; i++) {
        if (CGRectContainsPoint(displays[i], point)) {
            edge = point.x < CGRectGetMinX(displays[i])+2 || point.x > CGRectGetMaxX(displays[i])-2 ||
                   point.y < CGRectGetMinY(displays[i])+2 || point.y > CGRectGetMaxY(displays[i])-2;
        }
    }
    PointerSample sample = {now(), CGEventGetTimestamp(event)/1e9, point.x, point.y,
        observed.x, observed.y, (int)type, edge, CGEventGetIntegerValueField(event, kCGEventSourceUnixProcessID)};
    pthread_mutex_lock(&lock);
    if (pointerCount == POINTER_CAPACITY) droppedPointers++;
    else pointers[pointerCount++] = sample;
    pthread_mutex_unlock(&lock);
    return event;
}

static int filterCount(MTDeviceRef device) {
    if (!MTDeviceGetService) return -1;
    io_iterator_t iterator = 0;
    if (IORegistryEntryGetChildIterator(MTDeviceGetService(device), kIOServicePlane, &iterator)) return -1;
    int count = 0;
    io_service_t child;
    while ((child = IOIteratorNext(iterator))) {
        CFTypeRef enabled = IORegistryEntryCreateCFProperty(child, CFSTR("FilterEnabled"), kCFAllocatorDefault, 0);
        if (enabled && CFEqual(enabled, kCFBooleanTrue)) count++;
        if (enabled) CFRelease(enabled);
        IOObjectRelease(child);
    }
    IOObjectRelease(iterator);
    return count;
}

static void writeJSON(FILE *file, NSDictionary *record) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:nil];
    fwrite(data.bytes, 1, data.length, file); fputc('\n', file);
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    mach_timebase_info(&timebase);
    atomic_init(&tapDisabled, false);
    NSString *deviceArgument = nil, *output = nil;
    double seconds = 20;
    BOOL list = NO;
    for (int i = 1; i < argc; i++) {
        NSString *arg = @(argv[i]);
        if ([arg isEqualToString:@"--help"]) {
            puts("Recorder --list | --device-id N --output file.jsonl [--seconds 20]\nOrdinary monitoring and a listen-only session event tap. No output or takeover."); return 0;
        } else if ([arg isEqualToString:@"--list"]) list = YES;
        else if ([arg isEqualToString:@"--device-id"] && i+1 < argc) deviceArgument = @(argv[++i]);
        else if ([arg isEqualToString:@"--output"] && i+1 < argc) output = @(argv[++i]);
        else if ([arg isEqualToString:@"--seconds"] && i+1 < argc) seconds = atof(argv[++i]);
        else { fprintf(stderr, "Unknown/incomplete argument: %s\n", argv[i]); return 2; }
    }
    if (!list && (!deviceArgument || !output || !isfinite(seconds) || seconds <= 0 || seconds > 60)) {
        fprintf(stderr, "Use --help. A device ID, new output file, and duration in (0,60] are required.\n"); return 2;
    }
    // Help exits before enumeration. Recording never prompts for permission itself.
    if (!list && !CGPreflightListenEventAccess()) {
        fprintf(stderr, "Input Monitoring is not granted. Enable it for your terminal/Recorder in System Settings, then retry.\n"); return 1;
    }
    CFArrayRef devices = MTDeviceCreateList();
    MTDeviceRef selected = NULL;
    if (devices) for (CFIndex i = 0; i < CFArrayGetCount(devices); i++) {
        MTDeviceRef device = (void *)CFArrayGetValueAtIndex(devices, i);
        uint64_t id = 0;
        if (MTDeviceGetDeviceID(device, &id)) continue;
        NSString *value = [NSString stringWithFormat:@"%llu", (unsigned long long)id];
        if (list) puts(value.UTF8String);
        if ([deviceArgument isEqualToString:value]) { selected = device; CFRetain(selected); }
    }
    if (devices) CFRelease(devices);
    if (list) { if (selected) MTDeviceRelease(selected); return 0; }
    if (!selected) { fprintf(stderr, "Selected device is not available.\n"); return 1; }
    if (filterCount(selected) != 0) {
        fprintf(stderr, "Release Trackpad Takeover on the selected pad before recording. No native session opened.\n");
        MTDeviceRelease(selected); return 1;
    }
    FILE *file = fopen(output.fileSystemRepresentation, "wx");
    if (!file) { perror("Cannot create new output"); MTDeviceRelease(selected); return 1; }
    contacts = calloc(CONTACT_CAPACITY, sizeof(ContactSample));
    pointers = calloc(POINTER_CAPACITY, sizeof(PointerSample));
    if (!contacts || !pointers) { fprintf(stderr,"Allocation failed.\n"); fclose(file); MTDeviceRelease(selected); return 1; }
    CGDirectDisplayID ids[32];
    if (CGGetActiveDisplayList(32, ids, &displayCount) != kCGErrorSuccess) displayCount = 0;
    for (uint32_t i = 0; i < displayCount; i++) displays[i] = CGDisplayBounds(ids[i]);
    CGEventMask mask = CGEventMaskBit(kCGEventMouseMoved);
    CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGTailAppendEventTap, kCGEventTapOptionListenOnly, mask, receivePointer, NULL);
    if (!tap) { fprintf(stderr,"Cannot create listen-only pointer tap.\n"); fclose(file); MTDeviceRelease(selected); free(contacts); free(pointers); return 1; }
    CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0);
    if (!source) {
        fprintf(stderr,"Cannot register callbacks.\n"); if (source) CFRelease(source); CFRelease(tap); fclose(file); MTDeviceRelease(selected); free(contacts); free(pointers); return 1;
    }
    MTRegisterContactFrameCallback(selected, receiveContacts);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
    CGEventTapEnable(tap, true);
    OSStatus started = MTDeviceStart(selected, 0);
    if (started) fprintf(stderr,"Ordinary start failed: %d\n", (int)started);
    signal(SIGINT, interruptHandler); signal(SIGTERM, interruptHandler);
    double start = now();
    if (!started) fprintf(stderr,"BASELINE %.0fs: move ONE finger on device %s at slow/medium/fast speeds. Lift between strokes. Avoid display edges; no other mouse/keyboard/clicks. Ctrl-C ends early.\n",seconds, deviceArgument.UTF8String);
    while (!started && !interrupted && !atomic_load(&tapDisabled) && now()-start < seconds) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, .05, false);
    }
    OSStatus stopped = started ? 0 : MTDeviceStop(selected);
    MTUnregisterContactFrameCallback(selected, receiveContacts);
    CGEventTapEnable(tap, false);
    CFMachPortInvalidate(tap);
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
    CFRelease(source); CFRelease(tap); MTDeviceRelease(selected);
    pthread_mutex_lock(&lock);
    writeJSON(file, @{ @"schema": @"gesturepad.pointer-recording.v1", @"kind": @"metadata", @"device_id": deviceArgument,
        @"contact_samples": @(contactCount), @"pointer_samples": @(pointerCount), @"dropped_contacts": @(droppedContacts),
        @"dropped_pointer": @(droppedPointers), @"tap_disabled": @(atomic_load(&tapDisabled)),
        @"start_result": @(started), @"stop_result": @(stopped), @"duration_seconds": @(now()-start),
        @"cursor_units": @"Quartz global logical points", @"pointer_source": @"all session mouseMoved events; isolate selected pad manually",
        @"note": @"t is callback receipt mach uptime seconds; native_t/event_t retained for latency analysis. No per-device pointer attribution is claimed." });
    for (size_t i = 0; i < contactCount; i++) {
        ContactSample r = contacts[i]; NSMutableArray *values = NSMutableArray.new;
        for (size_t j = 0; j < r.count; j++) {
            Contact c = r.contacts[j]; [values addObject:@{@"id":@(c.id), @"state":@(c.state), @"x":@(c.x), @"y":@(c.y)}];
        }
        writeJSON(file, @{@"kind":@"contacts", @"t":@(r.t), @"native_t":@(r.nativeTime), @"contacts":values});
    }
    for (size_t i = 0; i < pointerCount; i++) {
        PointerSample r = pointers[i]; writeJSON(file, @{@"kind":@"pointer", @"t":@(r.t), @"event_t":@(r.eventTime),
            @"x":@(r.x), @"y":@(r.y), @"observed_cursor_x":@(r.observedX), @"observed_cursor_y":@(r.observedY),
            @"edge":@(r.edge), @"source_pid":@(r.sourcePID)});
    }
    pthread_mutex_unlock(&lock);
    fclose(file); free(contacts); free(pointers);
    fprintf(stderr,"Saved %zu contact / %zu pointer samples; dropped=%zu/%zu, stop=%d, tapDisabled=%d: %s\n",contactCount,pointerCount,droppedContacts,droppedPointers,(int)stopped,atomic_load(&tapDisabled),output.UTF8String);
    return started || stopped || droppedContacts || droppedPointers || atomic_load(&tapDisabled) ? 1 : 0;
} }
