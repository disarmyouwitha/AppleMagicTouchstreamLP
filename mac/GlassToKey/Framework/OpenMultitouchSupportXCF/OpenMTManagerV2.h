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
- (BOOL)setActiveDevices:(NSArray<OpenMTDeviceInfo *> *)deviceInfos;

- (OpenMTListener *)addRawListenerWithCallback:(OpenMTRawFrameCallback)callback;
- (void)removeRawListener:(OpenMTListener *)listener;
- (BOOL)isListening;

// Explicit selected-device private-API takeover; never persisted across sessions.
- (BOOL)beginNativeTakeoverForDeviceIDs:(NSArray<NSNumber *> *)deviceIDs;
- (void)endNativeTakeover;
- (NSDictionary<NSString *, id> *)nativeTakeoverStatus;

@end

NS_ASSUME_NONNULL_END

#endif /* OpenMTManagerV2_h */
