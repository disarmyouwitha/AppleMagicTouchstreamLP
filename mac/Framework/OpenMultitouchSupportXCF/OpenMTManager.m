//
//  OpenMTManager.m
//  OpenMultitouchSupport
//
//  Created by Takuto Nakamura on 2019/07/11.
//  Copyright © 2019 Takuto Nakamura. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <IOKit/IOKitLib.h>
#import <os/lock.h>
#import <stdlib.h>

#import "OpenMTManagerInternal.h"
#import "OpenMTListenerInternal.h"
#import "OpenMTTouchInternal.h"
#import "OpenMTEventInternal.h"
#import "OpenMTInternal.h"

static void contactEventHandler(MTDeviceRef eventDevice, MTTouch eventTouches[], int numTouches, double timestamp, int frame);
static void contactEventHandlerWithRefcon(MTDeviceRef eventDevice, MTTouch eventTouches[], size_t numTouches, double timestamp, size_t frame, void* refCon);

typedef struct {
    __unsafe_unretained OpenMTManager *manager;
    uint64_t deviceID;
    BOOL usesRefcon;
} MTDeviceCallbackContext;

@implementation OpenMTDeviceInfo

- (instancetype)initWithDeviceRef:(MTDeviceRef)deviceRef {
    if (self = [super init]) {
        // Get device ID
        uint64_t deviceID;
        OSStatus err = MTDeviceGetDeviceID(deviceRef, &deviceID);
        if (!err) {
            _deviceID = [NSString stringWithFormat:@"%llu", deviceID];
            _deviceNumericID = deviceID;
        } else {
            _deviceID = @"Unknown";
            _deviceNumericID = 0;
        }
        // Determine if built-in
        _isBuiltIn = MTDeviceIsBuiltIn ? MTDeviceIsBuiltIn(deviceRef) : YES;
        // Get family ID for precise device identification
        int familyID = 0;
        MTDeviceGetFamilyID(deviceRef, &familyID);
        // Determine device name based on family ID mapping
        // Reference: https://github.com/JitouchApp/Jitouch-project/blob/3b5018e4bc839426a6ce0917cea6df753d19da10/Application/Gesture.m#L2930
        // Normally chaining this many if statements is trolling, but I'm keeping it for documentation purposes
        if (familyID == 98 || familyID == 99 || familyID == 100) {
            // Built-in trackpad (older models)
            _deviceName = @"MacBook Trackpad";
        } else if (familyID == 101) {
            // Retina MacBook Pro trackpad
            _deviceName = @"MacBook Trackpad";
        } else if (familyID == 102) {
            // Retina MacBook with Force Touch trackpad (2015)
            _deviceName = @"MacBook Trackpad";
        } else if (familyID == 103) {
            // Retina MacBook Pro 13" with Force Touch trackpad (2015)
            _deviceName = @"MacBook Trackpad";
        } else if (familyID == 104) {
            // MacBook trackpad variant
            _deviceName = @"MacBook Trackpad";
        } else if (familyID == 105) {
            // MacBook with Touch Bar
            _deviceName = @"Touch Bar";
        } else if (familyID == 109) {
            // M4 Macbook Pro Trackpad
            _deviceName = @"MacBook Trackpad";
        } else if (familyID == 112 || familyID == 113) {
            // Magic Mouse & Magic Mouse 2/3
            _deviceName = @"Magic Mouse";
        } else if (familyID == 128 || familyID == 129 || familyID == 130) {
            // Magic Trackpad, Magic Trackpad 2, Magic Trackpad 3
            _deviceName = @"Magic Trackpad";
        } else {
            // Unknown device - use dimensions to make an educated guess
            int width = 0, height = 0;
            MTDeviceGetSensorSurfaceDimensions(deviceRef, &width, &height);
            // Heuristic: trackpads are typically wider than tall and have reasonable dimensions
            // Touch Bar is very wide and narrow (>1000 width, <100 height)
            // Regular trackpads are usually wider than tall but not extremely so
            if (width > 1000 && height < 100) {
                _deviceName = [NSString stringWithFormat:@"Unknown Touch Bar (FamilyID: %d)", familyID];
            } else if (width > height && width > 50 && height > 20) {
                // Likely a trackpad: wider than tall, reasonable dimensions
                _deviceName = [NSString stringWithFormat:@"Unknown Trackpad (FamilyID: %d)", familyID];
            } else {
                // Probably not a trackpad
                _deviceName = [NSString stringWithFormat:@"Unknown Device (FamilyID: %d)", familyID];
            }
        }
    }
    return self;
}

@end

@interface OpenMTManager() {
    os_unfair_lock _actuatorLock;
}

@property (strong, readwrite) NSMutableArray *listeners;
@property (strong, readwrite) NSMutableArray *rawListeners;
@property (atomic, copy) NSArray<OpenMTListener *> *listenersSnapshot;
@property (atomic, copy) NSArray<OpenMTListener *> *rawListenersSnapshot;
@property (strong, readwrite) NSArray<OpenMTDeviceInfo *> *availableDeviceInfos;
@property (strong, readwrite) NSArray<OpenMTDeviceInfo *> *activeDeviceInfos;
@property (strong, readwrite) NSMutableDictionary<NSString *, NSValue *> *deviceRefs;
@property (assign, readwrite) CFMutableDictionaryRef deviceIDsByRef;
@property (assign, readwrite) CFMutableDictionaryRef deviceNumericIDsByRef;
@property (strong, readwrite) NSMutableDictionary<NSString *, NSValue *> *availableDeviceRefs;
@property (copy, readwrite) NSString *primaryDeviceID;
@property (strong, readwrite) NSMutableDictionary<NSValue *, NSValue *> *deviceCallbackContexts;
@property (strong, readwrite) NSMutableDictionary<NSNumber *, NSValue *> *actuatorCache;

- (NSArray<OpenMTDeviceInfo *> *)collectAvailableDevices;
- (void)clearAvailableDeviceRefs;
- (void)rebuildListenerSnapshotsPruningDead;
@end

@implementation OpenMTManager

+ (BOOL)systemSupportsMultitouch {
    return MTDeviceIsAvailable();
}

+ (OpenMTManager *)sharedManager {
    static OpenMTManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = self.new;
    });
    return sharedManager;
}

- (instancetype)init {
    if (self = [super init]) {
        self.listeners = NSMutableArray.new;
        self.rawListeners = NSMutableArray.new;
        self.listenersSnapshot = @[];
        self.rawListenersSnapshot = @[];
        self.deviceRefs = NSMutableDictionary.new;
        self.deviceIDsByRef = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, NULL, &kCFTypeDictionaryValueCallBacks);
        self.deviceNumericIDsByRef = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, NULL, &kCFTypeDictionaryValueCallBacks);
        self.availableDeviceRefs = NSMutableDictionary.new;
        self.deviceCallbackContexts = NSMutableDictionary.new;
        self.actuatorCache = NSMutableDictionary.new;
        _actuatorLock = OS_UNFAIR_LOCK_INIT;
        [self enumerateDevices];
        
        [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(willSleep:) name:NSWorkspaceWillSleepNotification object:nil];
        [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(didWakeUp:) name:NSWorkspaceDidWakeNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [self clearActuatorCache];
    [self clearDeviceRefs];
    [self clearAvailableDeviceRefs];
    if (self.deviceIDsByRef) {
        CFRelease(self.deviceIDsByRef);
        self.deviceIDsByRef = NULL;
    }
    if (self.deviceNumericIDsByRef) {
        CFRelease(self.deviceNumericIDsByRef);
        self.deviceNumericIDsByRef = NULL;
    }
}

- (void)rebuildListenerSnapshotsPruningDead {
    for (NSInteger i = self.listeners.count - 1; i >= 0; i--) {
        OpenMTListener *listener = self.listeners[i];
        if (listener.dead) {
            [self.listeners removeObjectAtIndex:i];
        }
    }
    for (NSInteger i = self.rawListeners.count - 1; i >= 0; i--) {
        OpenMTListener *listener = self.rawListeners[i];
        if (listener.dead) {
            [self.rawListeners removeObjectAtIndex:i];
        }
    }
    self.listenersSnapshot = [self.listeners copy];
    self.rawListenersSnapshot = [self.rawListeners copy];
}


- (NSArray<OpenMTDeviceInfo *> *)collectAvailableDevices {
    NSMutableArray<OpenMTDeviceInfo *> *devices = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSValue *> *refs = [NSMutableDictionary dictionary];
    [self clearAvailableDeviceRefs];
    
    if (MTDeviceCreateList) {
        CFArrayRef deviceList = MTDeviceCreateList();
        if (deviceList) {
            CFIndex count = CFArrayGetCount(deviceList);
            for (CFIndex i = 0; i < count; i++) {
                MTDeviceRef deviceRef = (MTDeviceRef)CFArrayGetValueAtIndex(deviceList, i);
                OpenMTDeviceInfo *deviceInfo = [[OpenMTDeviceInfo alloc] initWithDeviceRef:deviceRef];
                [devices addObject:deviceInfo];
                if (deviceInfo.deviceID.length && deviceRef) {
                    CFRetain(deviceRef);
                    refs[deviceInfo.deviceID] = [NSValue valueWithPointer:deviceRef];
                }
            }
            CFRelease(deviceList);
        }
    }
    
    if (devices.count == 0 && MTDeviceIsAvailable()) {
        MTDeviceRef defaultDevice = MTDeviceCreateDefault();
        if (defaultDevice) {
            OpenMTDeviceInfo *deviceInfo = [[OpenMTDeviceInfo alloc] initWithDeviceRef:defaultDevice];
            [devices addObject:deviceInfo];
            if (deviceInfo.deviceID.length) {
                refs[deviceInfo.deviceID] = [NSValue valueWithPointer:defaultDevice];
            } else {
                MTDeviceRelease(defaultDevice);
            }
        }
    }
    self.availableDeviceRefs = refs;
    
    return [devices copy];
}

- (void)enumerateDevices {
    NSArray<OpenMTDeviceInfo *> *devices = [self collectAvailableDevices];
    self.availableDeviceInfos = devices;
    if (devices.count > 0) {
        OpenMTDeviceInfo *defaultDevice = devices[0];
        self.activeDeviceInfos = @[defaultDevice];
        self.primaryDeviceID = defaultDevice.deviceID;
    } else {
        self.activeDeviceInfos = @[];
        self.primaryDeviceID = nil;
    }
}

- (MTDeviceRef)createDeviceRefForDeviceID:(NSString *)deviceID {
    if (!deviceID.length) {
        return NULL;
    }
    NSValue *cachedRefValue = self.availableDeviceRefs[deviceID];
    if (cachedRefValue) {
        MTDeviceRef cachedRef = (MTDeviceRef)cachedRefValue.pointerValue;
        if (cachedRef) {
            CFRetain(cachedRef);
            return cachedRef;
        }
    }
    MTDeviceRef foundDevice = NULL;
    if (MTDeviceCreateList) {
        CFArrayRef deviceList = MTDeviceCreateList();
        if (deviceList) {
            CFIndex count = CFArrayGetCount(deviceList);
            for (CFIndex i = 0; i < count; i++) {
                MTDeviceRef deviceRef = (MTDeviceRef)CFArrayGetValueAtIndex(deviceList, i);
                uint64_t rawID = 0;
                OSStatus err = MTDeviceGetDeviceID(deviceRef, &rawID);
                if (!err) {
                    NSString *devID = [NSString stringWithFormat:@"%llu", rawID];
                    if ([devID isEqualToString:deviceID]) {
                        foundDevice = deviceRef;
                        CFRetain(foundDevice);
                        break;
                    }
                }
            }
            CFRelease(deviceList);
        }
    }
    if (!foundDevice && MTDeviceIsAvailable()) {
        MTDeviceRef defaultDevice = MTDeviceCreateDefault();
        if (defaultDevice) {
            uint64_t rawID = 0;
            OSStatus err = MTDeviceGetDeviceID(defaultDevice, &rawID);
            if (!err) {
                NSString *devID = [NSString stringWithFormat:@"%llu", rawID];
                if ([devID isEqualToString:deviceID]) {
                    foundDevice = defaultDevice;
                } else {
                    MTDeviceRelease(defaultDevice);
                }
            } else {
                MTDeviceRelease(defaultDevice);
            }
        }
    }
    return foundDevice;
}

- (void)storeDeviceRef:(MTDeviceRef)deviceRef deviceID:(NSString *)deviceID {
    if (!deviceRef || !deviceID.length) {
        return;
    }
    NSValue *refValue = [NSValue valueWithPointer:deviceRef];
    self.deviceRefs[deviceID] = refValue;
    if (self.deviceIDsByRef) {
        CFDictionarySetValue(self.deviceIDsByRef, deviceRef, (__bridge const void *)(deviceID));
    }
    unsigned long long parsedID = strtoull(deviceID.UTF8String, NULL, 0);
    if (parsedID > 0) {
        if (self.deviceNumericIDsByRef) {
            NSNumber *numericID = @(parsedID);
            CFDictionarySetValue(self.deviceNumericIDsByRef, deviceRef, (__bridge const void *)(numericID));
        }
    }
}

- (void)clearDeviceRefs {
    for (NSValue *contextValue in self.deviceCallbackContexts.allValues) {
        MTDeviceCallbackContext *context = (MTDeviceCallbackContext *)contextValue.pointerValue;
        if (context) {
            free(context);
        }
    }
    [self.deviceCallbackContexts removeAllObjects];
    for (NSValue *refValue in self.deviceRefs.allValues) {
        MTDeviceRef deviceRef = (MTDeviceRef)refValue.pointerValue;
        if (deviceRef) {
            MTDeviceRelease(deviceRef);
        }
    }
    [self.deviceRefs removeAllObjects];
    if (self.deviceIDsByRef) {
        CFDictionaryRemoveAllValues(self.deviceIDsByRef);
    }
    if (self.deviceNumericIDsByRef) {
        CFDictionaryRemoveAllValues(self.deviceNumericIDsByRef);
    }
}

- (void)clearAvailableDeviceRefs {
    for (NSValue *refValue in self.availableDeviceRefs.allValues) {
        MTDeviceRef deviceRef = (MTDeviceRef)refValue.pointerValue;
        if (deviceRef) {
            MTDeviceRelease(deviceRef);
        }
    }
    [self.availableDeviceRefs removeAllObjects];
}

- (BOOL)refreshActiveDeviceRefs {
    [self clearDeviceRefs];
    BOOL didAddAny = NO;
    for (OpenMTDeviceInfo *deviceInfo in self.activeDeviceInfos) {
        MTDeviceRef deviceRef = [self createDeviceRefForDeviceID:deviceInfo.deviceID];
        if (deviceRef) {
            [self storeDeviceRef:deviceRef deviceID:deviceInfo.deviceID];
            didAddAny = YES;
        }
    }
    return didAddAny;
}

- (MTDeviceRef)primaryDeviceRef {
    if (!self.primaryDeviceID.length) {
        return NULL;
    }
    NSValue *refValue = self.deviceRefs[self.primaryDeviceID];
    if (!refValue) {
        MTDeviceRef deviceRef = [self createDeviceRefForDeviceID:self.primaryDeviceID];
        if (deviceRef) {
            [self storeDeviceRef:deviceRef deviceID:self.primaryDeviceID];
            return deviceRef;
        }
        return NULL;
    }
    return (MTDeviceRef)refValue.pointerValue;
}

- (NSString *)deviceIDForDeviceRef:(MTDeviceRef)deviceRef {
    if (!deviceRef) {
        return nil;
    }
    NSString *deviceID = nil;
    if (self.deviceIDsByRef) {
        deviceID = (__bridge NSString *)CFDictionaryGetValue(self.deviceIDsByRef, deviceRef);
    }
    if (deviceID.length) {
        return deviceID;
    }
    uint64_t rawID = 0;
    OSStatus err = MTDeviceGetDeviceID(deviceRef, &rawID);
    if (!err) {
        deviceID = [NSString stringWithFormat:@"%llu", rawID];
        if (self.deviceIDsByRef) {
            CFDictionarySetValue(self.deviceIDsByRef, deviceRef, (__bridge const void *)(deviceID));
        }
        if (self.deviceNumericIDsByRef && rawID > 0) {
            NSNumber *numericID = @(rawID);
            CFDictionarySetValue(self.deviceNumericIDsByRef, deviceRef, (__bridge const void *)(numericID));
        }
        return deviceID;
    }
    return nil;
}

- (uint64_t)deviceNumericIDForDeviceRef:(MTDeviceRef)deviceRef {
    if (!deviceRef) {
        return 0;
    }
    NSNumber *cached = nil;
    if (self.deviceNumericIDsByRef) {
        cached = (__bridge NSNumber *)CFDictionaryGetValue(self.deviceNumericIDsByRef, deviceRef);
    }
    if (cached) {
        return cached.unsignedLongLongValue;
    }
    uint64_t rawID = 0;
    OSStatus err = MTDeviceGetDeviceID(deviceRef, &rawID);
    if (!err && rawID > 0) {
        if (self.deviceNumericIDsByRef) {
            NSNumber *numericID = @(rawID);
            CFDictionarySetValue(self.deviceNumericIDsByRef, deviceRef, (__bridge const void *)(numericID));
        }
        return rawID;
    }
    return 0;
}

//- (void)handlePathEvent:(OpenMTTouch *)touch {
//    NSLog(@"%@", touch.description);
//}

- (void)handleMultitouchEvent:(OpenMTEvent *)event {
    NSArray<OpenMTListener *> *snapshot = self.listenersSnapshot;
    for (OpenMTListener *listener in snapshot) {
        if (listener.dead) {
            continue;
        }
        if (!listener.listening) {
            continue;
        }
        dispatchResponseAsync(^{
            [listener listenToEvent:event];
        });
    }
}

- (void)handleRawFrameWithDevice:(MTDeviceRef)deviceRef
                         touches:(const MTTouch *)touches
                           count:(int)numTouches
                       timestamp:(double)timestamp
                           frame:(int)frame
                        deviceID:(uint64_t)deviceID {
    NSArray<OpenMTListener *> *snapshot = self.rawListenersSnapshot;
    if (snapshot.count == 0) {
        return;
    }
    for (OpenMTListener *listener in snapshot) {
        if (listener.dead) {
            continue;
        }
        if (!listener.listening) {
            continue;
        }
        [listener listenToRawFrameWithTouches:touches
                                        count:numTouches
                                    timestamp:timestamp
                                        frame:frame
                                     deviceID:deviceID];
    }
}

- (void)startHandlingMultitouchEvents {
    if (![self refreshActiveDeviceRefs]) {
        return;
    }
    @try {
        for (NSValue *refValue in self.deviceRefs.allValues) {
            MTDeviceRef deviceRef = (MTDeviceRef)refValue.pointerValue;
            if (!deviceRef) {
                continue;
            }
            MTDeviceCallbackContext *context = malloc(sizeof(MTDeviceCallbackContext));
            if (!context) {
                MTRegisterContactFrameCallback(deviceRef, contactEventHandler);
                MTDeviceStart(deviceRef, 0);
                continue;
            }
            context->manager = self;
            context->deviceID = [self deviceNumericIDForDeviceRef:deviceRef];
            context->usesRefcon = MTRegisterContactFrameCallbackWithRefcon(deviceRef, contactEventHandlerWithRefcon, context);
            if (!context->usesRefcon) {
                MTRegisterContactFrameCallback(deviceRef, contactEventHandler); // work
            }
            self.deviceCallbackContexts[[NSValue valueWithPointer:deviceRef]] = [NSValue valueWithPointer:context];
            // MTEasyInstallPrintCallbacks(deviceRef, YES, NO, NO, NO, NO, NO); // work
            // MTRegisterPathCallback(deviceRef, pathEventHandler); // work
            // MTRegisterMultitouchImageCallback(deviceRef, MTImagePrintCallback); // not work
            MTDeviceStart(deviceRef, 0);
        }
    } @catch (NSException *exception) {
    }
}

- (void)stopHandlingMultitouchEvents {
    @try {
        for (NSValue *refValue in self.deviceRefs.allValues) {
            MTDeviceRef deviceRef = (MTDeviceRef)refValue.pointerValue;
            if (!deviceRef || !MTDeviceIsRunning(deviceRef)) {
                continue;
            }
            NSValue *contextValue = self.deviceCallbackContexts[[NSValue valueWithPointer:deviceRef]];
            MTDeviceCallbackContext *context = contextValue ? (MTDeviceCallbackContext *)contextValue.pointerValue : NULL;
            if (context && context->usesRefcon) {
                MTUnregisterContactFrameCallback(deviceRef, (MTFrameCallbackFunction)contactEventHandlerWithRefcon);
            } else {
                MTUnregisterContactFrameCallback(deviceRef, contactEventHandler); // work
            }
            // MTUnregisterPathCallback(deviceRef, pathEventHandler); // work
            // MTUnregisterImageCallback(deviceRef, MTImagePrintCallback); // not work
            MTDeviceStop(deviceRef);
        }
        [self clearActuatorCache];
        [self clearDeviceRefs];
    } @catch (NSException *exception) {
    }
}

- (void)willSleep:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self stopHandlingMultitouchEvents];
    });
}

- (void)didWakeUp:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self startHandlingMultitouchEvents];
    });
}

// Public Functions
- (void)refreshAvailableDevices {
    self.availableDeviceInfos = [self collectAvailableDevices];
}

- (NSArray<OpenMTDeviceInfo *> *)availableDevices {
    return self.availableDeviceInfos;
}

- (BOOL)setActiveDevices:(NSArray<OpenMTDeviceInfo *> *)deviceInfos {
    if (deviceInfos.count == 0) {
        return NO;
    }
    for (OpenMTDeviceInfo *deviceInfo in deviceInfos) {
        if (![self.availableDeviceInfos containsObject:deviceInfo]) {
            return NO;
        }
    }
    NSArray<NSString *> *currentIDs = [self.activeDeviceInfos valueForKey:@"deviceID"];
    NSArray<NSString *> *nextIDs = [deviceInfos valueForKey:@"deviceID"];
    if ([currentIDs isEqualToArray:nextIDs]) {
        return YES;
    }
    BOOL wasRunning = NO;
    for (NSValue *refValue in self.deviceRefs.allValues) {
        MTDeviceRef deviceRef = (MTDeviceRef)refValue.pointerValue;
        if (deviceRef && MTDeviceIsRunning(deviceRef)) {
            wasRunning = YES;
            break;
        }
    }
    if (wasRunning) {
        [self stopHandlingMultitouchEvents];
    }
    self.activeDeviceInfos = [deviceInfos copy];
    self.primaryDeviceID = deviceInfos.firstObject.deviceID;
    if (wasRunning) {
        [self startHandlingMultitouchEvents];
    }
    return YES;
}

- (NSArray<OpenMTDeviceInfo *> *)activeDevices {
    return self.activeDeviceInfos;
}

- (OpenMTListener *)addListenerWithTarget:(id)target selector:(SEL)selector {
    __block OpenMTListener *listener = nil;
    dispatchSync(dispatch_get_main_queue(), ^{
        if (!self.class.systemSupportsMultitouch) { return; }
        listener = [[OpenMTListener alloc] initWithTarget:target selector:selector];
        if (self.listeners.count == 0 && self.rawListeners.count == 0) {
            [self startHandlingMultitouchEvents];
        }
        [self.listeners addObject:listener];
        [self rebuildListenerSnapshotsPruningDead];
    });
    return listener;
}

- (void)removeListener:(OpenMTListener *)listener {
    dispatchSync(dispatch_get_main_queue(), ^{
        [self.listeners removeObject:listener];
        [self rebuildListenerSnapshotsPruningDead];
        if (self.listeners.count == 0 && self.rawListeners.count == 0) {
            [self stopHandlingMultitouchEvents];
        }
    });
}

- (OpenMTListener *)addRawListenerWithCallback:(OpenMTRawFrameCallback)callback {
    __block OpenMTListener *listener = nil;
    dispatchSync(dispatch_get_main_queue(), ^{
        if (!self.class.systemSupportsMultitouch) { return; }
        listener = [[OpenMTListener alloc] initWithRawCallback:callback];
        if (self.listeners.count == 0 && self.rawListeners.count == 0) {
            [self startHandlingMultitouchEvents];
        }
        [self.rawListeners addObject:listener];
        [self rebuildListenerSnapshotsPruningDead];
    });
    return listener;
}

- (void)removeRawListener:(OpenMTListener *)listener {
    dispatchSync(dispatch_get_main_queue(), ^{
        [self.rawListeners removeObject:listener];
        [self rebuildListenerSnapshotsPruningDead];
        if (self.listeners.count == 0 && self.rawListeners.count == 0) {
            [self stopHandlingMultitouchEvents];
        }
    });
}

- (BOOL)isHapticEnabled {
    MTDeviceRef deviceRef = [self primaryDeviceRef];
    if (!deviceRef) {
        return NO;
    }
    
    MTActuatorRef actuator = MTDeviceGetMTActuator(deviceRef);
    if (!actuator) {
        return NO;
    }
    
    return MTActuatorGetSystemActuationsEnabled(actuator);
}

- (BOOL)setHapticEnabled:(BOOL)enabled {
    MTDeviceRef deviceRef = [self primaryDeviceRef];
    if (!deviceRef) {
        return NO;
    }
    
    MTActuatorRef actuator = MTDeviceGetMTActuator(deviceRef);
    if (!actuator) {
        return NO;
    }
    
    OSStatus result = MTActuatorSetSystemActuationsEnabled(actuator, enabled);
    return result == noErr;
}

- (UInt64)deviceIDForPrimaryActuator {
    MTDeviceRef primaryRef = [self primaryDeviceRef];
    if (!primaryRef) {
        return 0;
    }
    uint64_t deviceID = 0;
    OSStatus err = MTDeviceGetDeviceID(primaryRef, &deviceID);
    if (err || deviceID == 0) {
        return 0;
    }
    return deviceID;
}

- (UInt64)findActuationSupportedTrackpadDeviceID {
    // Use IOKit to find any actuation-supported trackpad
    io_iterator_t iterator = IO_OBJECT_NULL;
    const CFMutableDictionaryRef matchingRef = IOServiceMatching("AppleMultitouchDevice");
    const kern_return_t result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingRef, &iterator);
    
    if (result != KERN_SUCCESS) {
        return 0;
    }
    
    UInt64 selectedDeviceID = 0;
    io_service_t service = IO_OBJECT_NULL;
    
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        CFMutableDictionaryRef propertiesRef = NULL;
        const kern_return_t propResult = IORegistryEntryCreateCFProperties(service, &propertiesRef, CFAllocatorGetDefault(), 0);
        
        if (propResult != KERN_SUCCESS) {
            IOObjectRelease(service);
            continue;
        }
        
        NSDictionary *properties = (__bridge_transfer NSDictionary *)propertiesRef;
        
        NSNumber *actuationSupported = properties[@"ActuationSupported"];
        if (actuationSupported.boolValue) {
            NSNumber *multitouchID = properties[@"Multitouch ID"];
            selectedDeviceID = multitouchID.unsignedLongLongValue;
            IOObjectRelease(service);
            break;
        }
        
        IOObjectRelease(service);
    }
    
    IOObjectRelease(iterator);
    return selectedDeviceID;
}

- (CFTypeRef)cachedActuatorForDeviceID:(UInt64)deviceID {
    if (deviceID == 0) {
        return NULL;
    }
    NSNumber *key = @(deviceID);
    os_unfair_lock_lock(&_actuatorLock);
    NSValue *cachedValue = self.actuatorCache[key];
    if (cachedValue) {
        CFTypeRef actuatorRef = (CFTypeRef)cachedValue.pointerValue;
        os_unfair_lock_unlock(&_actuatorLock);
        return actuatorRef;
    }
    os_unfair_lock_unlock(&_actuatorLock);

    CFTypeRef actuatorRef = MTActuatorCreateFromDeviceID(deviceID);
    if (!actuatorRef) {
        return NULL;
    }
    IOReturn openResult = MTActuatorOpen(actuatorRef);
    if (openResult != kIOReturnSuccess) {
        CFRelease(actuatorRef);
        return NULL;
    }
    os_unfair_lock_lock(&_actuatorLock);
    self.actuatorCache[key] = [NSValue valueWithPointer:actuatorRef];
    os_unfair_lock_unlock(&_actuatorLock);
    return actuatorRef;
}

- (void)clearActuatorCache {
    NSDictionary<NSNumber *, NSValue *> *snapshot = nil;
    os_unfair_lock_lock(&_actuatorLock);
    if (self.actuatorCache.count > 0) {
        snapshot = [self.actuatorCache copy];
        [self.actuatorCache removeAllObjects];
    }
    os_unfair_lock_unlock(&_actuatorLock);
    for (NSValue *value in snapshot.allValues) {
        CFTypeRef actuatorRef = (CFTypeRef)value.pointerValue;
        if (actuatorRef) {
            MTActuatorClose(actuatorRef);
            CFRelease(actuatorRef);
        }
    }
}
// actuation IDs range from 1-6 going weakest to strongest
// unknown 2 controls the sharpness. Test: activation id 1 with unknown2=10
// unknown 3 is used as onset/offset in other cases. onset=0 offset=2. Can be negative
- (BOOL)triggerRawHaptic:(SInt32)actuationID unknown1:(UInt32)unknown1 unknown2:(Float32)unknown2 unknown3:(Float32)unknown3 {
    return [self triggerRawHaptic:actuationID unknown1:unknown1 unknown2:unknown2 unknown3:unknown3 deviceID:nil];
}

- (BOOL)triggerRawHaptic:(SInt32)actuationID unknown1:(UInt32)unknown1 unknown2:(Float32)unknown2 unknown3:(Float32)unknown3 deviceID:(NSString * _Nullable)deviceID {
    UInt64 multitouchDeviceID = 0;
    if (deviceID.length) {
        unsigned long long parsedID = strtoull(deviceID.UTF8String, NULL, 0);
        if (parsedID > 0) {
            multitouchDeviceID = (UInt64)parsedID;
        }
    }
    if (multitouchDeviceID == 0) {
        multitouchDeviceID = [self deviceIDForPrimaryActuator];
    }
    if (multitouchDeviceID == 0) {
        multitouchDeviceID = [self findActuationSupportedTrackpadDeviceID];
    }
    if (multitouchDeviceID == 0) {
        return NO;
    }
    CFTypeRef actuatorRef = [self cachedActuatorForDeviceID:multitouchDeviceID];
    if (!actuatorRef) {
        return NO;
    }
    IOReturn result = MTActuatorActuate(actuatorRef, actuationID, unknown1, unknown2, unknown3);
    return result == kIOReturnSuccess;
}
// Utility Tools C Language
static void dispatchSync(dispatch_queue_t queue, dispatch_block_t block) {
    if (!strcmp(dispatch_queue_get_label(queue), dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL))) {
        block();
        return;
    }
    dispatch_sync(queue, block);
}

static void dispatchResponseAsync(dispatch_block_t block) {
    static dispatch_queue_t responseQueue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        responseQueue = dispatch_queue_create("com.kyome.openmt", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_async(responseQueue, block);
}

static void contactEventHandlerWithRefcon(MTDeviceRef eventDevice, MTTouch eventTouches[], size_t numTouches, double timestamp, size_t frame, void* refCon) {
    @autoreleasepool {
        MTDeviceCallbackContext *context = (MTDeviceCallbackContext *)refCon;
        OpenMTManager *manager = context && context->manager ? context->manager : OpenMTManager.sharedManager;
        uint64_t deviceID = context ? context->deviceID : [manager deviceNumericIDForDeviceRef:eventDevice];

        [manager handleRawFrameWithDevice:eventDevice
                                  touches:eventTouches
                                    count:(int)numTouches
                                timestamp:timestamp
                                    frame:(int)frame
                                 deviceID:deviceID];
        if (manager.listenersSnapshot.count == 0) {
            return;
        }
        NSMutableArray *touches = [NSMutableArray arrayWithCapacity:(NSUInteger)numTouches];

        for (size_t i = 0; i < numTouches; i++) {
            OpenMTTouch *touch = [[OpenMTTouch alloc] initWithMTTouch:&eventTouches[i]];
            [touches addObject:touch];
        }

        OpenMTEvent *event = OpenMTEvent.new;
        event.touches = touches;
        event.deviceID = [manager deviceIDForDeviceRef:eventDevice] ?: @"Unknown";
        event.frameID = (int)frame;
        event.timestamp = timestamp;

        [manager handleMultitouchEvent:event];
    }
}

static void contactEventHandler(MTDeviceRef eventDevice, MTTouch eventTouches[], int numTouches, double timestamp, int frame) {
    @autoreleasepool {
        OpenMTManager *manager = OpenMTManager.sharedManager;
        uint64_t deviceID = [manager deviceNumericIDForDeviceRef:eventDevice];
        [manager handleRawFrameWithDevice:eventDevice
                                  touches:eventTouches
                                    count:numTouches
                                timestamp:timestamp
                                    frame:frame
                                 deviceID:deviceID];
        if (manager.listenersSnapshot.count == 0) {
            return;
        }
        NSMutableArray *touches = [NSMutableArray arrayWithCapacity:(NSUInteger)numTouches];

        for (int i = 0; i < numTouches; i++) {
            OpenMTTouch *touch = [[OpenMTTouch alloc] initWithMTTouch:&eventTouches[i]];
            [touches addObject:touch];
        }

        OpenMTEvent *event = OpenMTEvent.new;
        event.touches = touches;
        event.deviceID = [manager deviceIDForDeviceRef:eventDevice] ?: @"Unknown";
        event.frameID = frame;
        event.timestamp = timestamp;

        [manager handleMultitouchEvent:event];
    }
}

@end
