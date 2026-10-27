#ifndef OpenMTManagerV2_h
#define OpenMTManagerV2_h

#import <Foundation/Foundation.h>
#if !__has_include(<OpenMultitouchSupportXCF/OpenMTManager.h>)
#import "OpenMTManager.h"
#import "OpenMTListener.h"
#else
#import <OpenMultitouchSupportXCF/OpenMTManager.h>
#import <OpenMultitouchSupportXCF/OpenMTListener.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@interface OpenMTManagerV2 : NSObject

+ (BOOL)systemSupportsMultitouch;
+ (instancetype)sharedManager;

- (NSArray<OpenMTDeviceInfo *> *)availableDevices;
- (NSArray<OpenMTDeviceInfo *> *)activeDevices;
- (void)refreshAvailableDevices;
// Discovery never stops callbacks or changes ownership.
- (NSArray<OpenMTDeviceInfo *> *)discoverAvailableDevices;
- (BOOL)reconcileOrdinaryDevices:(NSArray<OpenMTDeviceInfo *> *)devices;
- (BOOL)setActiveDevices:(NSArray<OpenMTDeviceInfo *> *)deviceInfos;

- (OpenMTListener *)addRawListenerWithCallback:(OpenMTRawFrameCallback)callback;
- (void)removeRawListener:(OpenMTListener *)listener;
- (BOOL)isListening;

// Selected-device private-API takeover; application owns opt-in persistence.
- (BOOL)beginNativeTakeoverForDeviceIDs:(NSArray<NSNumber *> *)deviceIDs;
- (BOOL)updateNativeTakeoverForDeviceIDs:(NSArray<NSNumber *> *)deviceIDs;
- (void)endNativeTakeover;
- (NSDictionary<NSString *, id> *)nativeTakeoverStatus;

@end

NS_ASSUME_NONNULL_END

#endif /* OpenMTManagerV2_h */
