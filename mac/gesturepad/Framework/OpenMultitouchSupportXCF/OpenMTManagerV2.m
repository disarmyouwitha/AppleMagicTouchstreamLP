#import <Cocoa/Cocoa.h>
#import <IOKit/hid/IOHIDKeys.h>
#include <stdatomic.h>
#include <unistd.h>

#import "OpenMTManagerV2.h"
#import "OpenMTInternal.h"
#import "OpenMTListenerInternal.h"

typedef struct {
    __unsafe_unretained OpenMTManagerV2 *manager;
    uint64_t deviceID;
    atomic_uint_fast64_t frames;
    atomic_uint_fast64_t contactFrames;
} MTDeviceV2CallbackContext;

static void openMTManagerV2ContactFrameCallback(
    MTDeviceRef eventDevice,
    MTTouch eventTouches[],
    size_t numTouches,
    double timestamp,
    size_t frame,
    void *refCon
);
static void dispatchSync(dispatch_queue_t queue, dispatch_block_t block);

@interface OpenMTDeviceInfo (OpenMTManagerV2Internal)
- (instancetype)initWithDeviceRef:(MTDeviceRef)deviceRef;
@end

@interface OpenMTManagerV2 ()

@property (strong, nonatomic) dispatch_queue_t stateQueue;
@property (strong, nonatomic) NSMutableArray<OpenMTListener *> *rawListeners;
@property (atomic, copy) NSArray<OpenMTListener *> *rawListenersSnapshot;
@property (strong, nonatomic) NSArray<OpenMTDeviceInfo *> *availableDeviceInfos;
@property (strong, nonatomic) NSArray<OpenMTDeviceInfo *> *activeDeviceInfos;
@property (strong, nonatomic) NSMutableDictionary<NSNumber *, NSValue *> *deviceRefsByNumericID;
@property (strong, nonatomic) NSMutableDictionary<NSValue *, NSValue *> *callbackContextsByRef;
@property (assign, nonatomic) BOOL callbacksRunning;
@property (strong, nonatomic) NSMutableSet<NSNumber *> *filterDeviceIDs;
@property (copy, nonatomic) NSString *filterResult;
@property (assign, nonatomic) uint64_t filterFrames;
@property (assign, nonatomic) uint64_t filterContactFrames;

- (void)withStateSync:(dispatch_block_t)block;
- (void)withStateAsync:(dispatch_block_t)block;
- (NSArray<OpenMTDeviceInfo *> *)collectAvailableDevices;
- (MTDeviceRef)createDeviceRefForNumericID:(uint64_t)numericID;
- (BOOL)refreshActiveDeviceRefs;
- (void)clearActiveDeviceRefs;
- (void)rebuildRawSnapshotPruningDead;
- (BOOL)startHandlingRawCallbacks;
- (void)stopHandlingRawCallbacks;
- (NSArray<OpenMTDeviceInfo *> *)resolveActiveDevicesFromAvailable:(NSArray<OpenMTDeviceInfo *> *)available
                                                    previousActive:(NSArray<OpenMTDeviceInfo *> *)previous;
- (void)handleRawFrameWithTouches:(const MTTouch *)touches
                            count:(int)numTouches
                        timestamp:(double)timestamp
                            frame:(int)frame
                         deviceID:(uint64_t)deviceID;

@end

@implementation OpenMTManagerV2

+ (BOOL)systemSupportsMultitouch {
    return MTDeviceIsAvailable();
}

+ (instancetype)sharedManager {
    static OpenMTManagerV2 *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = self.new;
    });
    return sharedManager;
}

- (instancetype)init {
    if (self = [super init]) {
        _stateQueue = dispatch_queue_create("ink.ranna.openmt.v2.state", DISPATCH_QUEUE_SERIAL);
        _rawListeners = NSMutableArray.new;
        _rawListenersSnapshot = @[];
        _deviceRefsByNumericID = NSMutableDictionary.new;
        _callbackContextsByRef = NSMutableDictionary.new;
        _callbacksRunning = NO;

        _availableDeviceInfos = [self collectAvailableDevices];
        _activeDeviceInfos = _availableDeviceInfos.count > 0
            ? @[_availableDeviceInfos.firstObject]
            : @[];

        [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self
                                                           selector:@selector(willSleep:)
                                                               name:NSWorkspaceWillSleepNotification
                                                             object:nil];
        [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self
                                                           selector:@selector(didWakeUp:)
                                                               name:NSWorkspaceDidWakeNotification
                                                             object:nil];
    }
    return self;
}

- (void)dealloc {
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [self withStateSync:^{
        [self stopHandlingRawCallbacks];
        [self.rawListeners removeAllObjects];
        self.rawListenersSnapshot = @[];
    }];
}

- (void)withStateSync:(dispatch_block_t)block {
    dispatchSync(self.stateQueue, block);
}

- (void)withStateAsync:(dispatch_block_t)block {
    dispatch_async(self.stateQueue, block);
}

- (NSArray<OpenMTDeviceInfo *> *)collectAvailableDevices {
    NSMutableArray<OpenMTDeviceInfo *> *devices = [NSMutableArray array];
    if (MTDeviceCreateList) {
        CFArrayRef deviceList = MTDeviceCreateList();
        if (deviceList) {
            CFIndex count = CFArrayGetCount(deviceList);
            for (CFIndex i = 0; i < count; i++) {
                MTDeviceRef deviceRef = (MTDeviceRef)CFArrayGetValueAtIndex(deviceList, i);
                if (!deviceRef) {
                    continue;
                }
                OpenMTDeviceInfo *deviceInfo = [[OpenMTDeviceInfo alloc] initWithDeviceRef:deviceRef];
                if (deviceInfo) {
                    [devices addObject:deviceInfo];
                }
            }
            CFRelease(deviceList);
        }
    }

    if (devices.count == 0 && MTDeviceIsAvailable()) {
        MTDeviceRef defaultDevice = MTDeviceCreateDefault();
        if (defaultDevice) {
            OpenMTDeviceInfo *deviceInfo = [[OpenMTDeviceInfo alloc] initWithDeviceRef:defaultDevice];
            if (deviceInfo) {
                [devices addObject:deviceInfo];
            }
            MTDeviceRelease(defaultDevice);
        }
    }

    return [devices copy];
}

- (MTDeviceRef)createDeviceRefForNumericID:(uint64_t)numericID {
    if (numericID == 0) {
        return NULL;
    }

    if (MTDeviceCreateList) {
        CFArrayRef deviceList = MTDeviceCreateList();
        if (deviceList) {
            CFIndex count = CFArrayGetCount(deviceList);
            for (CFIndex i = 0; i < count; i++) {
                MTDeviceRef deviceRef = (MTDeviceRef)CFArrayGetValueAtIndex(deviceList, i);
                if (!deviceRef) {
                    continue;
                }
                uint64_t rawID = 0;
                if (!MTDeviceGetDeviceID(deviceRef, &rawID) && rawID == numericID) {
                    CFRetain(deviceRef);
                    CFRelease(deviceList);
                    return deviceRef;
                }
            }
            CFRelease(deviceList);
        }
    }

    MTDeviceRef defaultDevice = MTDeviceCreateDefault();
    if (defaultDevice) {
        uint64_t rawID = 0;
        if (!MTDeviceGetDeviceID(defaultDevice, &rawID) && rawID == numericID) {
            return defaultDevice;
        }
        MTDeviceRelease(defaultDevice);
    }

    return NULL;
}

- (void)clearActiveDeviceRefs {
    for (NSValue *contextValue in self.callbackContextsByRef.allValues) {
        MTDeviceV2CallbackContext *context = (MTDeviceV2CallbackContext *)contextValue.pointerValue;
        if (context) {
            free(context);
        }
    }
    [self.callbackContextsByRef removeAllObjects];

    for (NSValue *refValue in self.deviceRefsByNumericID.allValues) {
        MTDeviceRef deviceRef = (MTDeviceRef)refValue.pointerValue;
        if (deviceRef) {
            MTDeviceRelease(deviceRef);
        }
    }
    [self.deviceRefsByNumericID removeAllObjects];
}

- (BOOL)refreshActiveDeviceRefs {
    [self clearActiveDeviceRefs];

    // Pre-size registries so topology updates do not repeatedly grow hash tables.
    NSUInteger capacity = self.activeDeviceInfos.count;
    self.deviceRefsByNumericID = [NSMutableDictionary dictionaryWithCapacity:capacity];
    self.callbackContextsByRef = [NSMutableDictionary dictionaryWithCapacity:capacity];

    BOOL didAddAny = NO;
    for (OpenMTDeviceInfo *deviceInfo in self.activeDeviceInfos) {
        uint64_t numericID = deviceInfo.deviceNumericID;
        if (numericID == 0) {
            continue;
        }
        MTDeviceRef deviceRef = [self createDeviceRefForNumericID:numericID];
        if (!deviceRef) {
            continue;
        }
        self.deviceRefsByNumericID[@(numericID)] = [NSValue valueWithPointer:deviceRef];
        didAddAny = YES;
    }

    return didAddAny;
}

- (void)rebuildRawSnapshotPruningDead {
    for (NSInteger i = self.rawListeners.count - 1; i >= 0; i--) {
        OpenMTListener *listener = self.rawListeners[i];
        if (listener.dead) {
            [self.rawListeners removeObjectAtIndex:i];
        }
    }
    self.rawListenersSnapshot = [self.rawListeners copy];
}

- (BOOL)startHandlingRawCallbacks {
    if (self.callbacksRunning) {
        return YES;
    }
    if (![self refreshActiveDeviceRefs]) {
        return NO;
    }

    BOOL startedAny = NO;
    for (NSNumber *numericID in self.deviceRefsByNumericID.allKeys) {
        NSValue *refValue = self.deviceRefsByNumericID[numericID];
        MTDeviceRef deviceRef = refValue ? (MTDeviceRef)refValue.pointerValue : NULL;
        if (!deviceRef) {
            continue;
        }

        MTDeviceV2CallbackContext *context = malloc(sizeof(MTDeviceV2CallbackContext));
        if (!context) {
            continue;
        }
        context->manager = self;
        context->deviceID = numericID.unsignedLongLongValue;
        atomic_init(&context->frames, 0);
        atomic_init(&context->contactFrames, 0);

        BOOL registered = MTRegisterContactFrameCallbackWithRefcon(
            deviceRef,
            openMTManagerV2ContactFrameCallback,
            context
        );
        if (!registered) {
            free(context);
            continue;
        }

        self.callbackContextsByRef[[NSValue valueWithPointer:deviceRef]] = [NSValue valueWithPointer:context];
        MTDeviceStart(deviceRef, 0);
        startedAny = YES;
    }

    self.callbacksRunning = startedAny;
    if (!startedAny) {
        [self clearActiveDeviceRefs];
    }
    return startedAny;
}

- (void)stopHandlingRawCallbacks {
    [self endNativeTakeover];
    if (self.filterDeviceIDs.count) return;
    if (!self.callbacksRunning && self.deviceRefsByNumericID.count == 0) {
        return;
    }

    for (NSValue *refValue in self.deviceRefsByNumericID.allValues) {
        MTDeviceRef deviceRef = (MTDeviceRef)refValue.pointerValue;
        if (!deviceRef) {
            continue;
        }
        MTUnregisterContactFrameCallback(deviceRef, (MTFrameCallbackFunction)openMTManagerV2ContactFrameCallback);
        if (MTDeviceIsRunning(deviceRef)) {
            MTDeviceStop(deviceRef);
        }
    }

    self.callbacksRunning = NO;
    [self clearActiveDeviceRefs];
}

- (NSArray<OpenMTDeviceInfo *> *)resolveActiveDevicesFromAvailable:(NSArray<OpenMTDeviceInfo *> *)available
                                                    previousActive:(NSArray<OpenMTDeviceInfo *> *)previous {
    NSMutableDictionary<NSNumber *, OpenMTDeviceInfo *> *availableByNumericID =
        [NSMutableDictionary dictionaryWithCapacity:available.count];
    for (OpenMTDeviceInfo *device in available) {
        uint64_t numericID = device.deviceNumericID;
        if (numericID > 0) {
            availableByNumericID[@(numericID)] = device;
        }
    }

    NSMutableArray<OpenMTDeviceInfo *> *resolved = [NSMutableArray array];
    for (OpenMTDeviceInfo *active in previous) {
        OpenMTDeviceInfo *match = availableByNumericID[@(active.deviceNumericID)];
        if (match) {
            [resolved addObject:match];
        }
    }

    if (resolved.count == 0 && available.count > 0) {
        [resolved addObject:available.firstObject];
    }

    return [resolved copy];
}

- (void)handleRawFrameWithTouches:(const MTTouch *)touches
                            count:(int)numTouches
                        timestamp:(double)timestamp
                            frame:(int)frame
                         deviceID:(uint64_t)deviceID {
    NSArray<OpenMTListener *> *snapshot = self.rawListenersSnapshot;
    if (snapshot.count == 0) {
        return;
    }

    for (OpenMTListener *listener in snapshot) {
        if (listener.dead || !listener.listening) {
            continue;
        }
        [listener listenToRawFrameWithTouches:touches
                                        count:numTouches
                                    timestamp:timestamp
                                        frame:frame
                                     deviceID:deviceID];
    }
}

- (void)refreshAvailableDevices {
    [self withStateSync:^{
        if (self.filterDeviceIDs.count) return;
        NSArray<OpenMTDeviceInfo *> *devices = [self collectAvailableDevices];
        self.availableDeviceInfos = devices;

        NSArray<OpenMTDeviceInfo *> *resolved = [self resolveActiveDevicesFromAvailable:devices
                                                                          previousActive:self.activeDeviceInfos];

        BOOL hadListeners = self.rawListenersSnapshot.count > 0;
        BOOL wasRunning = self.callbacksRunning;
        if (wasRunning) {
            [self stopHandlingRawCallbacks];
        }

        self.activeDeviceInfos = resolved;

        if (hadListeners) {
            [self startHandlingRawCallbacks];
        }
    }];
}

- (NSArray<OpenMTDeviceInfo *> *)availableDevices {
    __block NSArray<OpenMTDeviceInfo *> *devices = nil;
    [self withStateSync:^{
        devices = self.availableDeviceInfos;
    }];
    return devices ?: @[];
}

- (NSArray<OpenMTDeviceInfo *> *)activeDevices {
    __block NSArray<OpenMTDeviceInfo *> *devices = nil;
    [self withStateSync:^{
        devices = self.activeDeviceInfos;
    }];
    return devices ?: @[];
}

- (BOOL)setActiveDevices:(NSArray<OpenMTDeviceInfo *> *)deviceInfos {
    __block BOOL success = NO;
    [self withStateSync:^{
        if (self.filterDeviceIDs.count) {
            NSSet *requested = [NSSet setWithArray:[deviceInfos valueForKey:@"deviceNumericID"]];
            // The selection transition has already prepared the exact native set.
            if ([requested isEqualToSet:self.filterDeviceIDs]) {
                self.activeDeviceInfos = [deviceInfos copy];
                success = YES;
            }
            return;
        }
        if (deviceInfos.count == 0) {
            success = NO;
            return;
        }

        NSMutableSet<NSNumber *> *availableNumericIDs = [NSMutableSet setWithCapacity:self.availableDeviceInfos.count];
        for (OpenMTDeviceInfo *device in self.availableDeviceInfos) {
            if (device.deviceNumericID > 0) {
                [availableNumericIDs addObject:@(device.deviceNumericID)];
            }
        }

        for (OpenMTDeviceInfo *deviceInfo in deviceInfos) {
            if (deviceInfo.deviceNumericID == 0 || ![availableNumericIDs containsObject:@(deviceInfo.deviceNumericID)]) {
                success = NO;
                return;
            }
        }

        NSArray<NSNumber *> *currentIDs = [self.activeDeviceInfos valueForKey:@"deviceNumericID"];
        NSArray<NSNumber *> *nextIDs = [deviceInfos valueForKey:@"deviceNumericID"];
        if ([currentIDs isEqualToArray:nextIDs]) {
            success = YES;
            return;
        }

        BOOL hadListeners = self.rawListenersSnapshot.count > 0;
        if (self.callbacksRunning) {
            [self stopHandlingRawCallbacks];
        }

        self.activeDeviceInfos = [deviceInfos copy];

        if (hadListeners) {
            [self startHandlingRawCallbacks];
        }
        success = YES;
    }];
    return success;
}

- (OpenMTListener *)addRawListenerWithCallback:(OpenMTRawFrameCallback)callback {
    __block OpenMTListener *listener = nil;
    [self withStateSync:^{
        if (!self.class.systemSupportsMultitouch) {
            return;
        }
        listener = [[OpenMTListener alloc] initWithRawCallback:callback];
        [self.rawListeners addObject:listener];
        [self rebuildRawSnapshotPruningDead];
        if (!self.callbacksRunning) {
            [self startHandlingRawCallbacks];
        }
    }];
    return listener;
}

- (void)removeRawListener:(OpenMTListener *)listener {
    [self withStateSync:^{
        [self.rawListeners removeObject:listener];
        [self rebuildRawSnapshotPruningDead];
        if (self.rawListenersSnapshot.count == 0) {
            [self stopHandlingRawCallbacks];
        }
    }];
}

- (BOOL)isListening {
    __block BOOL listening = NO;
    [self withStateSync:^{
        listening = self.callbacksRunning;
    }];
    return listening;
}

// Registry inspection is read-only. Refuse to join an existing filter owner.
static int filterClients(MTDeviceRef device, BOOL requireOwn) {
    if (!MTDeviceGetService) return -1;
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IORegistryEntryGetChildIterator(MTDeviceGetService(device), kIOServicePlane, &iterator)) return -1;
    int count = 0;
    NSString *prefix = [NSString stringWithFormat:@"pid %d,", getpid()];
    io_service_t child;
    while ((child = IOIteratorNext(iterator))) {
        if (IOObjectConformsTo(child, "AppleMultitouchDeviceUserClient")) {
            id enabled = CFBridgingRelease(IORegistryEntryCreateCFProperty(child, CFSTR("FilterEnabled"), kCFAllocatorDefault, 0));
            id owner = CFBridgingRelease(IORegistryEntryCreateCFProperty(child, CFSTR("IOUserClientCreator"), kCFAllocatorDefault, 0));
            if ([enabled isEqual:@YES] && (!requireOwn || ([owner isKindOfClass:NSString.class] && [owner hasPrefix:prefix]))) count++;
        }
        IOObjectRelease(child);
    }
    IOObjectRelease(iterator);
    return count;
}

- (OSStatus)startNativeDevice:(MTDeviceRef)device mode:(MTRunMode)mode { return MTDeviceStart(device, mode); }
- (OSStatus)stopNativeDevice:(MTDeviceRef)device { return MTDeviceStop(device); }
- (int)nativeFilterClients:(MTDeviceRef)device own:(BOOL)own { return filterClients(device, own); }

- (NSString *)validatedNativeFilterLabelForDeviceID:(NSNumber *)deviceID {
    OpenMTDeviceInfo *info = nil;
    for (OpenMTDeviceInfo *candidate in self.activeDeviceInfos) {
        if (candidate.deviceNumericID == deviceID.unsignedLongLongValue) info = candidate;
    }
    MTDeviceRef device = self.deviceRefsByNumericID[deviceID].pointerValue;
    int type = -1;
    self.filterResult = @"Takeover refused: every selection must be an active external USB/Bluetooth model 0324 trackpad.";
    if (!info || info.isBuiltIn || !device || !MTDeviceGetService ||
        !([info.transport isEqualToString:@"USB"] || [info.transport isEqualToString:@"Bluetooth"])) return nil;
    OSStatus typeStatus = MTDeviceGetDriverType(device, &type);
    if (typeStatus || type != 4) {
        self.filterResult = [NSString stringWithFormat:@"Takeover refused: %@ %@ native driver type=%d, status=%d (requires type 4).", info.transport, info.serialNumber, type, (int)typeStatus];
        return nil;
    }
    io_service_t service = MTDeviceGetService(device);
    id product = CFBridgingRelease(IORegistryEntrySearchCFProperty(service, kIOServicePlane, CFSTR(kIOHIDProductIDKey), kCFAllocatorDefault, kIORegistryIterateRecursively | kIORegistryIterateParents));
    id vendor = CFBridgingRelease(IORegistryEntrySearchCFProperty(service, kIOServicePlane, CFSTR(kIOHIDVendorIDKey), kCFAllocatorDefault, kIORegistryIterateRecursively | kIORegistryIterateParents));
    unsigned int expectedVendor = [info.transport isEqualToString:@"USB"] ? 0x05ac : 0x004c;
    if (![product isKindOfClass:NSNumber.class] || ![vendor isKindOfClass:NSNumber.class] ||
        [product unsignedIntValue] != 0x324 || [vendor unsignedIntValue] != expectedVendor) {
        self.filterResult = [NSString stringWithFormat:@"Takeover refused: %@ requires vendor %04x/model 0324; observed vendor=%@, product=%@.", info.transport, expectedVendor, vendor, product];
        return nil;
    }
    if ([self nativeFilterClients:device own:NO] != 0 ||
        !self.callbackContextsByRef[[NSValue valueWithPointer:device]]) {
        self.filterResult = @"Takeover refused: a selection has an existing/unreadable filter owner or no contact callback.";
        return nil;
    }
    return [NSString stringWithFormat:@"%@ %@", info.transport, info.serialNumber];
}

- (BOOL)beginNativeTakeoverForDeviceIDs:(NSArray<NSNumber *> *)deviceIDs {
    __block BOOL success = NO;
    [self withStateSync:^{
        if (self.filterDeviceIDs.count) return;
        NSArray<NSNumber *> *uniqueIDs = [NSOrderedSet orderedSetWithArray:deviceIDs].array;
        self.filterResult = @"Select at least one supported USB/Bluetooth trackpad.";
        if (!uniqueIDs.count) return;
        NSMutableArray<NSString *> *labels = NSMutableArray.new;
        // Validate every selected device before changing any native session.
        for (NSNumber *deviceID in uniqueIDs) {
            NSString *label = [self validatedNativeFilterLabelForDeviceID:deviceID];
            if (!label) return;
            [labels addObject:label];
        }
        self.filterFrames = self.filterContactFrames = 0;
        self.filterDeviceIDs = NSMutableSet.new;
        for (NSNumber *deviceID in uniqueIDs) {
            MTDeviceRef device = self.deviceRefsByNumericID[deviceID].pointerValue;
            MTDeviceV2CallbackContext *context = self.callbackContextsByRef[[NSValue valueWithPointer:device]].pointerValue;
            OSStatus stop = [self stopNativeDevice:device];
            if (stop) {
                [self endNativeTakeover];
                self.filterResult = [NSString stringWithFormat:@"Takeover failed: ordinary stop=%d. %@", (int)stop, self.filterResult];
                return;
            }
            atomic_store(&context->frames, 0);
            atomic_store(&context->contactFrames, 0);
            // Track it before start so failure cleanup also restores this device.
            [self.filterDeviceIDs addObject:deviceID];
            OSStatus start = [self startNativeDevice:device mode:(MTRunMode)0x40000000u];
            if (start || [self nativeFilterClients:device own:NO] != 1 || [self nativeFilterClients:device own:YES] != 1) {
                [self endNativeTakeover];
                self.filterResult = [NSString stringWithFormat:@"Takeover start/ownership verification failed (start=%d). %@", (int)start, self.filterResult];
                return;
            }
        }
        self.filterResult = [NSString stringWithFormat:@"Trackpad Takeover active: %@.", [labels componentsJoinedByString:@", "]];
        success = YES;
    }];
    return success;
}

// Add ordinary callback sessions for new selections without touching retained refs.
- (BOOL)prepareNativeTakeoverDeviceID:(NSNumber *)deviceID {
    MTDeviceRef existing = self.deviceRefsByNumericID[deviceID].pointerValue;
    if (existing && self.callbackContextsByRef[[NSValue valueWithPointer:existing]]) {
        BOOL active = NO;
        for (OpenMTDeviceInfo *candidate in self.activeDeviceInfos) {
            if (candidate.deviceNumericID == deviceID.unsignedLongLongValue) active = YES;
        }
        if (!active) {
            for (OpenMTDeviceInfo *candidate in self.availableDeviceInfos) {
                if (candidate.deviceNumericID == deviceID.unsignedLongLongValue) {
                    self.activeDeviceInfos = [self.activeDeviceInfos arrayByAddingObject:candidate];
                    break;
                }
            }
        }
        return YES;
    }
    OpenMTDeviceInfo *info = nil;
    for (OpenMTDeviceInfo *candidate in self.availableDeviceInfos) {
        if (candidate.deviceNumericID == deviceID.unsignedLongLongValue) info = candidate;
    }
    if (!info) { self.filterResult = @"Takeover refused: selected device is no longer available."; return NO; }
    MTDeviceRef device = existing ?: [self createDeviceRefForNumericID:deviceID.unsignedLongLongValue];
    if (!device) { self.filterResult = @"Takeover refused: cannot retain selected native device."; return NO; }
    self.deviceRefsByNumericID[deviceID] = [NSValue valueWithPointer:device];
    MTDeviceV2CallbackContext *context = calloc(1, sizeof(*context));
    if (!context) { self.filterResult = @"Takeover refused: cannot allocate contact callback."; return NO; }
    context->manager = self;
    context->deviceID = deviceID.unsignedLongLongValue;
    atomic_init(&context->frames, 0);
    atomic_init(&context->contactFrames, 0);
    if (!MTRegisterContactFrameCallbackWithRefcon(device, openMTManagerV2ContactFrameCallback, context)) {
        free(context);
        self.filterResult = @"Takeover refused: cannot register contact callback.";
        return NO;
    }
    self.callbackContextsByRef[[NSValue valueWithPointer:device]] = [NSValue valueWithPointer:context];
    self.activeDeviceInfos = [self.activeDeviceInfos arrayByAddingObject:info];
    OSStatus ordinary = [self startNativeDevice:device mode:0];
    self.callbacksRunning = YES;
    if (ordinary) { self.filterResult = [NSString stringWithFormat:@"Ordinary preparation failed: %d.", (int)ordinary]; return NO; }
    return YES;
}

- (BOOL)acquireNativeFilterID:(NSNumber *)deviceID {
    MTDeviceRef device = self.deviceRefsByNumericID[deviceID].pointerValue;
    OSStatus stopped = device ? [self stopNativeDevice:device] : -1;
    if (stopped) { self.filterResult = [NSString stringWithFormat:@"%@ ordinary stop=%d", deviceID, (int)stopped]; return NO; }
    MTDeviceV2CallbackContext *context = self.callbackContextsByRef[[NSValue valueWithPointer:device]].pointerValue;
    if (context) {
        atomic_store(&context->frames, 0);
        atomic_store(&context->contactFrames, 0);
    }
    if (!self.filterDeviceIDs) self.filterDeviceIDs = NSMutableSet.new;
    // Include failed starts in cleanup, just as in the original all-pad start.
    [self.filterDeviceIDs addObject:deviceID];
    OSStatus started = [self startNativeDevice:device mode:(MTRunMode)0x40000000u];
    if (started || [self nativeFilterClients:device own:NO] != 1 || [self nativeFilterClients:device own:YES] != 1) {
        self.filterResult = [NSString stringWithFormat:@"%@ start/ownership verification failed: %d", deviceID, (int)started];
        return NO;
    }
    return YES;
}

- (BOOL)releaseNativeFilterIDs:(NSSet<NSNumber *> *)deviceIDs {
    BOOL success = YES;
    NSMutableArray<NSString *> *results = NSMutableArray.new;
    for (NSNumber *deviceID in deviceIDs) {
        if (![self.filterDeviceIDs containsObject:deviceID]) continue;
        MTDeviceRef device = self.deviceRefsByNumericID[deviceID].pointerValue;
        MTDeviceV2CallbackContext *context = self.callbackContextsByRef[[NSValue valueWithPointer:device]].pointerValue;
        OSStatus stopped = device ? [self stopNativeDevice:device] : -1;
        if (stopped) {
            success = NO;
            [results addObject:[NSString stringWithFormat:@"%@ stop=%d; retry Release Trackpads", deviceID, (int)stopped]];
            continue;
        }
        if (context) {
            self.filterFrames += atomic_load(&context->frames);
            self.filterContactFrames += atomic_load(&context->contactFrames);
            atomic_store(&context->frames, 0);
            atomic_store(&context->contactFrames, 0);
        }
        [self.filterDeviceIDs removeObject:deviceID];
        OSStatus recovery = [self startNativeDevice:device mode:0];
        // IOServiceClose can return before the old user client disappears from
        // IORegistry. Start ordinary mode first (MTDeviceStart waits for service
        // quiet), then allow a bounded publication grace period. Never restart
        // a retained filter just to wait for a removed client's registry entry.
        int remaining = [self nativeFilterClients:device own:YES];
        for (int attempt = 0; remaining > 0 && attempt < 20; attempt++) {
            usleep(5000);
            remaining = [self nativeFilterClients:device own:YES];
        }
        if (recovery || remaining) success = NO;
        [results addObject:[NSString stringWithFormat:@"%@ recovery=%d, owned filters=%d", deviceID, (int)recovery, remaining]];
    }
    self.filterResult = [results componentsJoinedByString:@"; "];
    return success;
}

- (BOOL)updateNativeTakeoverForDeviceIDs:(NSArray<NSNumber *> *)deviceIDs {
    __block BOOL success = NO;
    [self withStateSync:^{
        NSSet<NSNumber *> *desired = [NSSet setWithArray:deviceIDs];
        NSSet<NSNumber *> *previous = [self.filterDeviceIDs copy] ?: NSSet.new;
        NSMutableSet *retained = [previous mutableCopy]; [retained intersectSet:desired];
        NSMutableSet *removed = [previous mutableCopy]; [removed minusSet:desired];
        NSMutableSet *added = [desired mutableCopy]; [added minusSet:previous];
        // Retained sessions must still be ours; never stop/restart them to validate.
        for (NSNumber *deviceID in retained) {
            MTDeviceRef device = self.deviceRefsByNumericID[deviceID].pointerValue;
            if (!device || [self nativeFilterClients:device own:NO] != 1 || [self nativeFilterClients:device own:YES] != 1) {
                self.filterResult = @"Selection unchanged: retained filter ownership verification failed. Release and retry.";
                return;
            }
        }
        NSMutableArray *labels = NSMutableArray.new;
        // All additions are prepared/validated before any existing filter changes.
        for (NSNumber *deviceID in added) {
            if (![self prepareNativeTakeoverDeviceID:deviceID]) return;
            NSString *label = [self validatedNativeFilterLabelForDeviceID:deviceID];
            if (!label) return;
            [labels addObject:label];
        }
        NSString *failure = nil;
        for (NSNumber *deviceID in added) {
            if (![self acquireNativeFilterID:deviceID]) { failure = self.filterResult; break; }
        }
        if (!failure && ![self releaseNativeFilterIDs:removed]) failure = self.filterResult;
        if (failure) {
            NSMutableArray *recovery = NSMutableArray.new;
            // Old filters were kept until additions succeeded. Undo only additions.
            if (![self releaseNativeFilterIDs:added]) [recovery addObject:self.filterResult];
            for (NSNumber *deviceID in previous) {
                if ([self.filterDeviceIDs containsObject:deviceID]) continue;
                MTDeviceRef device = self.deviceRefsByNumericID[deviceID].pointerValue;
                if (!device || [self nativeFilterClients:device own:NO] != 0 || ![self acquireNativeFilterID:deviceID]) {
                    [recovery addObject:[NSString stringWithFormat:@"%@ previous ownership could not be restored (%@)", deviceID, self.filterResult]];
                }
            }
            self.filterResult = [NSString stringWithFormat:@"Selection change failed: %@. %@", failure,
                recovery.count ? [@"Recovery incomplete: " stringByAppendingString:[recovery componentsJoinedByString:@"; "]] : @"Previous ownership restored; selection unchanged."];
            return;
        }
        self.filterResult = desired.count ? [NSString stringWithFormat:@"Trackpad Takeover active on %lu selected trackpad(s).", (unsigned long)desired.count] : @"Released trackpads.";
        success = YES;
    }];
    return success;
}

- (void)endNativeTakeover {
    [self withStateSync:^{
        if (!self.filterDeviceIDs.count) return;
        BOOL released = [self releaseNativeFilterIDs:[self.filterDeviceIDs copy]];
        self.filterResult = [NSString stringWithFormat:@"%@ %@", released ? @"Released trackpads." : @"Release incomplete.", self.filterResult];
    }];
}

- (NSDictionary<NSString *, id> *)nativeTakeoverStatus {
    __block NSDictionary *status;
    [self withStateSync:^{
        uint64_t frames = self.filterFrames, contacts = self.filterContactFrames;
        for (NSNumber *deviceID in self.filterDeviceIDs) {
            MTDeviceRef device = self.deviceRefsByNumericID[deviceID].pointerValue;
            MTDeviceV2CallbackContext *context = device ? self.callbackContextsByRef[[NSValue valueWithPointer:device]].pointerValue : NULL;
            if (context) {
                frames += atomic_load(&context->frames);
                contacts += atomic_load(&context->contactFrames);
            }
        }
        status = @{ @"active": @(self.filterDeviceIDs.count != 0),
                    @"deviceIDs": self.filterDeviceIDs.allObjects ?: @[],
                    @"frames": @(frames), @"contacts": @(contacts),
                    @"message": self.filterResult ?: @"Off. Take over the currently selected trackpads." };
    }];
    return status;
}

- (void)willSleep:(NSNotification *)note {
    (void)note;
    [self withStateAsync:^{
        [self stopHandlingRawCallbacks];
    }];
}

- (void)didWakeUp:(NSNotification *)note {
    (void)note;
    [self withStateAsync:^{
        if (self.rawListenersSnapshot.count > 0) {
            [self startHandlingRawCallbacks];
        }
    }];
}

static void dispatchSync(dispatch_queue_t queue, dispatch_block_t block) {
    if (!strcmp(dispatch_queue_get_label(queue), dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL))) {
        block();
        return;
    }
    dispatch_sync(queue, block);
}

@end

static void openMTManagerV2ContactFrameCallback(
    MTDeviceRef eventDevice,
    MTTouch eventTouches[],
    size_t numTouches,
    double timestamp,
    size_t frame,
    void *refCon
) {
    (void)eventDevice;
    @autoreleasepool {
        MTDeviceV2CallbackContext *context = (MTDeviceV2CallbackContext *)refCon;
        OpenMTManagerV2 *manager = context ? context->manager : nil;
        if (!manager) {
            return;
        }
        atomic_fetch_add(&context->frames, 1);
        if (numTouches) atomic_fetch_add(&context->contactFrames, 1);
        [manager handleRawFrameWithTouches:eventTouches
                                     count:(int)numTouches
                                 timestamp:timestamp
                                     frame:(int)frame
                                  deviceID:(context ? context->deviceID : 0)];
    }
}
