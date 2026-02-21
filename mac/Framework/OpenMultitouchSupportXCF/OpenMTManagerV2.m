#import <Cocoa/Cocoa.h>

#import "OpenMTManagerV2.h"
#import "OpenMTInternal.h"
#import "OpenMTListenerInternal.h"

typedef struct {
    __unsafe_unretained OpenMTManagerV2 *manager;
    uint64_t deviceID;
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
        _stateQueue = dispatch_queue_create("com.kyome.openmt.v2.state", DISPATCH_QUEUE_SERIAL);
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
        [manager handleRawFrameWithTouches:eventTouches
                                     count:(int)numTouches
                                 timestamp:timestamp
                                     frame:(int)frame
                                  deviceID:(context ? context->deviceID : 0)];
    }
}
