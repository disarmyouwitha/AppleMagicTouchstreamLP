//
//  OpenMTListener.h
//  OpenMultitouchSupport
//
//  Created by Takuto Nakamura on 2019/07/11.
//  Copyright © 2019 Takuto Nakamura. All rights reserved.
//

#ifndef OpenMTListener_h
#define OpenMTListener_h

#import <Foundation/Foundation.h>
#import "OpenMTInternal.h"
#import "OpenMTEvent.h"

typedef void (^OpenMTRawFrameCallback)(const MTTouch *touches,
                                      int numTouches,
                                      double timestamp,
                                      int frame,
                                      uint64_t deviceID);

@interface OpenMTListener: NSObject

@property (assign, readwrite) BOOL listening;

- (instancetype)initWithTarget:(id)target selector:(SEL)selector;
- (instancetype)initWithRawCallback:(OpenMTRawFrameCallback)callback;

- (void)listenToEvent:(OpenMTEvent *)event;
- (void)listenToRawFrameWithTouches:(const MTTouch *)touches
                              count:(int)numTouches
                          timestamp:(double)timestamp
                              frame:(int)frame
                           deviceID:(uint64_t)deviceID;

- (BOOL)dead;

@end

#endif /* OpenMTListener_h */
