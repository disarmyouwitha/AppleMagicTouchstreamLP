//
//  OpenMultitouchSupportXCF.h
//  OpenMultitouchSupportXCF
//
//  Created by Takuto Nakamura on 2024/03/02.
//

#import <Cocoa/Cocoa.h>

FOUNDATION_EXPORT double OpenMultitouchSupportXCFVersionNumber;
FOUNDATION_EXPORT const unsigned char OpenMultitouchSupportXCFVersionString[];

#if !__has_include(<OpenMultitouchSupportXCF/OpenMTManager.h>)
#import "OpenMTManager.h"
#import "OpenMTManagerV2.h"
#import "OpenMTListener.h"
#import "OpenMTEvent.h"
#import "OpenMTTouch.h"
#else
#import <OpenMultitouchSupportXCF/OpenMTManager.h>
#import <OpenMultitouchSupportXCF/OpenMTManagerV2.h>
#import <OpenMultitouchSupportXCF/OpenMTListener.h>
#import <OpenMultitouchSupportXCF/OpenMTEvent.h>
#import <OpenMultitouchSupportXCF/OpenMTTouch.h>
#endif
