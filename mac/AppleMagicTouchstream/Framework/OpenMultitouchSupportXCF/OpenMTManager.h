//
//  OpenMTManager.h
//  OpenMultitouchSupport
//
//  Created by Takuto Nakamura on 2019/07/11.
//  Copyright © 2019 Takuto Nakamura. All rights reserved.
//

#ifndef OpenMTManager_h
#define OpenMTManager_h

#import <Foundation/Foundation.h>
#if !__has_include(<OpenMultitouchSupportXCF/OpenMTListener.h>)
#import "OpenMTListener.h"
#import "OpenMTEvent.h"
#else
#import <OpenMultitouchSupportXCF/OpenMTListener.h>
#import <OpenMultitouchSupportXCF/OpenMTEvent.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@interface OpenMTDeviceInfo: NSObject
@property (nonatomic, readonly) NSString * _Nonnull deviceName;
@property (nonatomic, readonly) NSString *deviceID;
@property (nonatomic, readonly) UInt64 deviceNumericID;
@property (nonatomic, readonly) BOOL isBuiltIn;
@property (nonatomic, readonly) UInt64 registryEntryID;
@property (nonatomic, readonly) NSString *serialNumber;
@property (nonatomic, readonly) NSString *transport;
@end

@interface OpenMTManager: NSObject

+ (BOOL)systemSupportsMultitouch;
+ (OpenMTManager *)sharedManager;

- (NSArray<OpenMTDeviceInfo *> *)availableDevices;
- (BOOL)setActiveDevices:(NSArray<OpenMTDeviceInfo *> *)deviceInfos;
- (NSArray<OpenMTDeviceInfo *> *)activeDevices;
- (void)refreshAvailableDevices;

- (OpenMTListener *)addListenerWithTarget:(id)target selector:(SEL)selector;
- (void)removeListener:(OpenMTListener *)listener;

- (OpenMTListener *)addRawListenerWithCallback:(OpenMTRawFrameCallback)callback;
- (void)removeRawListener:(OpenMTListener *)listener;

- (BOOL)isHapticEnabled;
- (BOOL)setHapticEnabled:(BOOL)enabled;

// Retire only this connection's cached actuator; never changes contact capture.
- (void)invalidateHapticDeviceID:(NSString *)deviceID;

// Advanced haptic feedback methods
- (BOOL)triggerRawHaptic:(SInt32)actuationID unknown1:(UInt32)unknown1 unknown2:(Float32)unknown2 unknown3:(Float32)unknown3;
- (BOOL)triggerRawHaptic:(SInt32)actuationID unknown1:(UInt32)unknown1 unknown2:(Float32)unknown2 unknown3:(Float32)unknown3 deviceID:(NSString * _Nullable)deviceID;

@end

NS_ASSUME_NONNULL_END

#endif /* OpenMTManager_h */
