//
//  CIImage+MAT.m
//  AmazingFace
//
//  Created by york on 2017/12/2.
//  Copyright © 2017年 zero. All rights reserved.
//

#import "CIImage+MAT.h"

@implementation CIImage_MAT

+ (cv::Mat)matFromPixelBuffer:(CVPixelBufferRef)buffer
{
    CVPixelBufferLockBaseAddress(buffer, 0);
    
    unsigned char *base = (unsigned char *)CVPixelBufferGetBaseAddress( buffer );
    size_t width = CVPixelBufferGetWidth( buffer );
    size_t height = CVPixelBufferGetHeight( buffer );
    size_t stride = CVPixelBufferGetBytesPerRow( buffer );
    OSType type =  CVPixelBufferGetPixelFormatType(buffer);
    size_t extendedWidth = stride / 4;  // each pixel is 4 bytes/32 bits
    cv::Mat bgraImage = cv::Mat( (int)height, (int)extendedWidth, CV_8UC4, base );
    
    CVPixelBufferUnlockBaseAddress(buffer,0);
    
    return bgraImage;
}

@end
