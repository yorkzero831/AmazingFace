//
//  HeadPoseDetector.m
//  AmazingFace
//
//  Created by york on 2017/12/2.
//  Copyright © 2017年 zero. All rights reserved.
//
#import <Vision/Vision.h>
#import <SceneKit/SceneKit.h>
#import "HeadPoseDetector.h"


#include <iostream>
#include <iomanip>
#include <stdio.h>


#include <opencv2/core.hpp>

#include <opencv2/highgui/highgui.hpp>
#include <opencv2/calib3d/calib3d.hpp>
#include <opencv2/imgproc/imgproc.hpp>

using namespace cv;

@implementation HeadPoseDetector {
    
    //text on screen
    std::ostringstream outtext;
    
    std::vector<cv::Point3d> reprojectsrc;
    cv::Mat cam_matrix;
    cv::Mat dist_coeffs;
    std::vector<cv::Point3d> object_pts;
    std::vector<cv::Point2d> reprojectdst;
    
    //temp buf for decomposeProjectionMatrix()
    cv::Mat out_intrinsics;
    cv::Mat out_rotation;
    cv::Mat out_translation;
    
    SCNMatrix4 transformMatrix;
    SCNVector3 translationVector;
    SCNVector3 eulerVector;
    
    
}

static  HeadPoseDetector* _instance = nil;

+(instancetype) shareInstance
{
    static dispatch_once_t onceToken ;
    dispatch_once(&onceToken, ^{
        _instance = [[self alloc] init] ;
        [_instance initInstace];
    }) ;
    
    return _instance ;
}

-(void) initInstace {
    _prepared = NO;
}

- (void)prepare {
    // FIXME: test this stuff for memory leaks (cpp object destruction)
    self.prepared = YES;
    [self prepareOpenCv];
}

- (SCNVector3) getTransformVector {
    return translationVector;
}

- (SCNVector3) getEulerVector {
    return eulerVector;
}

- (SCNMatrix4) getTransformMatrix {
    return transformMatrix;
}

- (void)prepareOpenCv {
    
    translationVector = SCNVector3();
    eulerVector = SCNVector3();
    transformMatrix = SCNMatrix4Identity;
    
    float height = 720;
    float width = 1280;
    
    //fill in 3D ref points(world coordinates), model referenced from http://aifi.isr.uc.pt/Downloads/OpenGL/glAnthropometric3DModel.cpp
    object_pts.push_back(cv::Point3d(6.825897, 6.760612, 4.402142));     //#33 left brow left corner
    object_pts.push_back(cv::Point3d(1.330353, 7.122144, 6.903745));     //#29 left brow right corner
    object_pts.push_back(cv::Point3d(-1.330353, 7.122144, 6.903745));    //#34 right brow left corner
    object_pts.push_back(cv::Point3d(-6.825897, 6.760612, 4.402142));    //#38 right brow right corner
    object_pts.push_back(cv::Point3d(5.311432, 5.485328, 3.987654));     //#13 left eye left corner
    object_pts.push_back(cv::Point3d(1.789930, 5.393625, 4.413414));     //#17 left eye right corner
    object_pts.push_back(cv::Point3d(-1.789930, 5.393625, 4.413414));    //#25 right eye left corner
    object_pts.push_back(cv::Point3d(-5.311432, 5.485328, 3.987654));    //#21 right eye right corner
    object_pts.push_back(cv::Point3d(2.005628, 1.409845, 6.165652));     //#55 nose left corner
    object_pts.push_back(cv::Point3d(-2.005628, 1.409845, 6.165652));    //#49 nose right corner
    object_pts.push_back(cv::Point3d(2.774015, -2.080775, 5.048531));    //#43 mouth left corner
    object_pts.push_back(cv::Point3d(-2.774015, -2.080775, 5.048531));   //#39 mouth right corner
    object_pts.push_back(cv::Point3d(0.000000, -3.116408, 6.097667));    //#45 mouth central bottom corner
    object_pts.push_back(cv::Point3d(0.000000, -7.415691, 4.070434));    //#6 chin corner
    
    //fill in cam intrinsics and distortion coefficients
    //    cam_matrix = cv::Mat(3, 3, CV_64FC1, K);
    //    dist_coeffs = cv::Mat(5, 1, CV_64FC1, D);
    cv::Point2d center = cv::Point2d(height/2,width/2);
    cam_matrix = (cv::Mat_<double>(3,3) << height, 0, center.x, 0 , height, center.y, 0, 0, 1);
    dist_coeffs = cv::Mat::zeros(4,1,cv::DataType<double>::type);
    
    std::cout << "cam_matrix = "<< std::endl << " "  << cam_matrix << std::endl << std::endl;
    std::cout << "dist_coeffs = "<< std::endl << " "  << dist_coeffs << std::endl << std::endl;
    
    float time = 0.5;
    reprojectsrc.push_back(cv::Point3d(10.0, 10.0, 10.0) * time);
    reprojectsrc.push_back(cv::Point3d(10.0, 10.0, -10.0) * time);
    reprojectsrc.push_back(cv::Point3d(10.0, -10.0, -10.0) * time);
    reprojectsrc.push_back(cv::Point3d(10.0, -10.0, 10.0) * time);
    reprojectsrc.push_back(cv::Point3d(-10.0, 10.0, 10.0) * time);
    reprojectsrc.push_back(cv::Point3d(-10.0, 10.0, -10.0) * time);
    reprojectsrc.push_back(cv::Point3d(-10.0, -10.0, -10.0) * time);
    reprojectsrc.push_back(cv::Point3d(-10.0, -10.0, 10.0) * time);
    
    //reprojected 2D points
    reprojectdst.resize(8);
    
    //temp buf for decomposeProjectionMatrix()
    out_intrinsics = cv::Mat(3, 3, CV_64FC1);
    out_rotation = cv::Mat(3, 3, CV_64FC1);
    out_translation = cv::Mat(3, 1, CV_64FC1);
}

- (void)doWorkOnLandmarkArrary:(NSArray *)landmarksArray CameraMatrix:(matrix_float3x3) camera_mat Buffer:(CVPixelBufferRef) buffer{
    
    if (!self.prepared) {
        [self prepare];
    }
    //return when no face detected
    if (landmarksArray.count == 0) return;
    
    CVPixelBufferLockBaseAddress(buffer, 0);
    cv::Mat mat;
    void *address =  CVPixelBufferGetBaseAddressOfPlane(buffer, 0);
    int bufferWidth = (int)CVPixelBufferGetWidthOfPlane(buffer,0);
    int bufferHeight = (int)CVPixelBufferGetHeightOfPlane(buffer, 0);
    int bytePerRow = (int)CVPixelBufferGetBytesPerRowOfPlane(buffer, 0);
    mat = cv::Mat(bufferHeight, bufferWidth, CV_8UC1, address, bytePerRow);
    //Rotate the frame we receive
    cv::Mat rotated;
    cv::transpose(mat, rotated);
    cv::flip(rotated, rotated,1);
    
    circle(rotated, cv::Point(150 ,100), 20, cv::Scalar(0, 0, 0), -1);
    
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    
    
    
    
    cv::Mat arkitCam_martix = (cv::Mat_<double>(3,3) <<
                               camera_mat.columns[0][0], camera_mat.columns[0][1], camera_mat.columns[0][2],
                               camera_mat.columns[1][0] , camera_mat.columns[1][1], camera_mat.columns[1][2],
                               camera_mat.columns[2][0], camera_mat.columns[2][1], camera_mat.columns[2][2]);
    
    std::cout << "cam_matrix = "<< std::endl << " "  << arkitCam_martix << std::endl << std::endl;
    
    for (int i = 0; i < landmarksArray.count; i++) {
        VNFaceObservation *faceObservation = [landmarksArray objectAtIndex:i];
        VNFaceLandmarkRegion2D *allPoints = faceObservation.landmarks.allPoints;
        NSInteger pointCount = allPoints.pointCount;
        const CGPoint *point =  [allPoints pointsInImageOfSize:CGSizeMake(720, 1280)];
        
        std::vector<cv::Point2d> image_pts;
        image_pts.push_back(cv::Point2d(point[0].x, point[0].y)); //#17 left brow left corner
        image_pts.push_back(cv::Point2d(point[3].x, point[3].y)); //#21 left brow right corner
        image_pts.push_back(cv::Point2d(point[4].x, point[4].y)); //#22 right brow left corner
        image_pts.push_back(cv::Point2d(point[7].x, point[7].y)); //#26 right brow right corner
        image_pts.push_back(cv::Point2d(point[8].x, point[8].y)); //#36 left eye left corner
        image_pts.push_back(cv::Point2d(point[12].x, point[12].y)); //#39 left eye right corner
        image_pts.push_back(cv::Point2d(point[16].x, point[16].y)); //#42 right eye left corner
        image_pts.push_back(cv::Point2d(point[20].x, point[20].y)); //#45 right eye right corner
        image_pts.push_back(cv::Point2d(point[53].x, point[53].y)); //#31 nose left corner
        image_pts.push_back(cv::Point2d(point[57].x, point[57].y)); //#35 nose right corner
        image_pts.push_back(cv::Point2d(point[33].x, point[33].y)); //#48 mouth left corner
        image_pts.push_back(cv::Point2d(point[29].x, point[29].y)); //#54 mouth right corner
        image_pts.push_back(cv::Point2d(point[31].x, point[31].y)); //#57 mouth central bottom corner
        image_pts.push_back(cv::Point2d(point[45].x, point[45].y));   //#8 chin corner
        
        //result
        cv::Mat rotation_vec;                           //3 x 1
        cv::Mat rotation_mat;                           //3 x 3 R
        cv::Mat translation_vec;                        //3 x 1 T
        cv::Mat pose_mat = cv::Mat(3, 4, CV_64FC1);     //3 x 4 R | T
        cv::Mat euler_angle = cv::Mat(3, 1, CV_64FC1);
        
        
        
        //calc pos
        cv::solvePnP(object_pts, image_pts, cam_matrix, dist_coeffs, rotation_vec, translation_vec);
        
        //reproject
        cv::projectPoints(reprojectsrc, rotation_vec, translation_vec, cam_matrix, dist_coeffs, reprojectdst);
        
        //calc euler angle
        cv::Rodrigues(rotation_vec, rotation_mat);
        cv::hconcat(rotation_mat, translation_vec, pose_mat);
        cv::decomposeProjectionMatrix(pose_mat, out_intrinsics, out_rotation, out_translation, cv::noArray(), cv::noArray(), cv::noArray(), euler_angle);
        
//        std::cout<< "X: " << std::setprecision(3) << euler_angle.at<double>(0) <<std::endl;
//        std::cout<< "Y: " << std::setprecision(3) << euler_angle.at<double>(1) <<std::endl;
//        std::cout<< "Z: " << std::setprecision(3) << euler_angle.at<double>(2) <<std::endl;
        
        //std::cout << "pos = "  << reprojectdst[0].x <<" " << reprojectdst[0].y << std::endl;
        
        //std::cout << "translation_vec = "<< std::endl << " "  << translation_vec << std::endl << std::endl;
        //std::cout << "rotation_mat = "<< std::endl << " "  << rotation_mat << std::endl << std::endl;
        
        translationVector.x = translation_vec.at<double>(0);
        translationVector.y = translation_vec.at<double>(1);
        translationVector.z = translation_vec.at<double>(2);
//        eulerVector.x = euler_angle.at<double>(0);
//        eulerVector.y = euler_angle.at<double>(1);
//        eulerVector.z = euler_angle.at<double>(2);
        
//        transformMatrix.m11 = rotation_mat.at<double>(0, 0);
//        transformMatrix.m12 = rotation_mat.at<double>(0, 1);
//        transformMatrix.m13 = rotation_mat.at<double>(0, 2);
//        transformMatrix.m14 = translation_vec.at<double>(0);  //transform
//        transformMatrix.m21 = rotation_mat.at<double>(1, 0);
//        transformMatrix.m22 = rotation_mat.at<double>(1, 1);
//        transformMatrix.m23 = rotation_mat.at<double>(1, 2);
//        transformMatrix.m24 = translation_vec.at<double>(1);  //transform
//        transformMatrix.m31 = rotation_mat.at<double>(2, 0);
//        transformMatrix.m32 = rotation_mat.at<double>(2, 1);
//        transformMatrix.m33 = rotation_mat.at<double>(2, 2);
//        transformMatrix.m34 = translation_vec.at<double>(2);  //transform
//        transformMatrix.m41 = 0.0;
//        transformMatrix.m42 = 0.0;
//        transformMatrix.m43 = 0.0;
//        transformMatrix.m44 = 1;
        
    }
}


@end
