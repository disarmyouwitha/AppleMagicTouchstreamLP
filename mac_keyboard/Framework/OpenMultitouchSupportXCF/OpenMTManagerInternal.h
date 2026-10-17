//
//  OpenMTManagerInternal.h
//  OpenMultitouchSupport
//
//  Created by Takuto Nakamura on 2019/07/11.
//  Copyright © 2019 Takuto Nakamura. All rights reserved.
//

#ifndef OpenMTManagerInternal_h
#define OpenMTManagerInternal_h

#import "OpenMTInternal.h"
#import "OpenMTManager.h"

@interface OpenMTManager()

- (NSString *)deviceIDForDeviceRef:(MTDeviceRef)deviceRef;
- (uint64_t)deviceNumericIDForDeviceRef:(MTDeviceRef)deviceRef;

@end

#endif /* OpenMTManagerInternal_h */
