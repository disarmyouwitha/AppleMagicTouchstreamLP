#ifndef OpenMTManagerV2_h
#define OpenMTManagerV2_h

#import <Foundation/Foundation.h>
#import <OpenMultitouchSupportXCF/OpenMTManager.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^OpenMTDirectRawFrameHandler)(const MTTouch *touches,
                                            int numTouches,
                                            double timestamp,
                                            int frame,
                                            uint64_t deviceID);

@interface OpenMTManagerV2 : NSObject

+ (BOOL)systemSupportsMultitouch;
+ (instancetype)sharedManager;

- (NSArray<OpenMTDeviceInfo *> *)availableDevices;
- (NSArray<OpenMTDeviceInfo *> *)activeDevices;
- (void)refreshAvailableDevices;
- (BOOL)setActiveDevices:(NSArray<OpenMTDeviceInfo *> *)deviceInfos;

- (NSUUID * _Nullable)addDirectRawFrameHandler:(OpenMTDirectRawFrameHandler)handler;
- (void)removeDirectRawFrameHandlerWithToken:(NSUUID *)token;
- (BOOL)isListening;

@end

NS_ASSUME_NONNULL_END

#endif /* OpenMTManagerV2_h */
