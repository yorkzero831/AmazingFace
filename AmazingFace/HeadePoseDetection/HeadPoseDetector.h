//
//  HeadPoseDetector.h
//  AmazingFace
//
//  Created by york on 2017/12/2.
//  Copyright © 2017年 zero. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

@interface HeadPoseDetector : NSObject

@property (assign) BOOL prepared;

- (void)doWorkOnLandmarkArrary:(NSArray *)landmarksArray;
@end
