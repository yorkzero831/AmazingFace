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

+(instancetype) shareInstance ; 

@property (assign) BOOL prepared;

- (void)doWorkOnLandmarkArrary:(NSArray *)landmarksArray CameraMatrix:(matrix_float3x3) camera_mat Buffer:(CVPixelBufferRef) buffer;

- (SCNVector3) getTransformVector;

- (SCNVector3) getEulerVector;

- (SCNMatrix4) getTransformMatrix;

@end
