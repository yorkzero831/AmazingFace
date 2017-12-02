//
//  HeadPoseDetector.m
//  AmazingFace
//
//  Created by york on 2017/12/2.
//  Copyright © 2017年 zero. All rights reserved.
//

#import "HeadPoseDetector.h"

#include <dlib/image_processing/frontal_face_detector.h>
#include <dlib/image_processing.h>
#include <dlib/image_io.h>

#include <dlib/opencv.h>

#include <opencv2/highgui/highgui.hpp>
#include <opencv2/calib3d/calib3d.hpp>
#include <opencv2/imgproc/imgproc.hpp>

using namespace cv;

@implementation HeadPoseDetector {
    dlib::shape_predictor sp;
    
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
    
    dlib::frontal_face_detector detector;
    
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _prepared = NO;
    }
    return self;
}

- (void)prepare {
    NSString *modelFileName = [[NSBundle mainBundle] pathForResource:@"shape_predictor_68_face_landmarks" ofType:@"dat"];
    std::string modelFileNameCString = [modelFileName UTF8String];
    
    detector = dlib::get_frontal_face_detector();
    dlib::deserialize(modelFileNameCString) >> sp;
    
    
    // FIXME: test this stuff for memory leaks (cpp object destruction)
    self.prepared = YES;
    
    [self prepareOpenCv];
}

- (void)prepareOpenCv {
    
    double height = 0.0;
    double width = 0.0;
#ifdef YORKDEBUG
    height = 480;
    width = 360;
#else
    height = 1280;
    width = 720;
#endif
    
    
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

- (cv::Mat)matFromPixelBuffer:(CVPixelBufferRef)buffer
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

- (void)doWorkOnPixelBuffer:(uint8_t *)buffer Heigth:(size_t)bufferHeight Width:(size_t)bufferWidth BytePerRow:(size_t)bytesPerRow {
    
    if (!self.prepared) {
        [self prepare];
    }
//    CVPixelBufferLockBaseAddress(buffer, 0);
//
//    unsigned char *base = (unsigned char *)CVPixelBufferGetBaseAddress( buffer );
//    size_t bufferWidth = CVPixelBufferGetWidth( buffer );
//    size_t bufferHeight = CVPixelBufferGetHeight( buffer );
//    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(buffer);
    
    cv::Mat image = cv::Mat(bufferHeight, bufferWidth, CV_8UC4, buffer, bytesPerRow);
    //Rotate image
    
    cv::Mat imageResized;
    float ratio = 10;
    cv::resize(image, imageResized, cv::Size(), 1.0 / ratio, 1.0 / ratio);
    
    cv::Mat imageDst;
    cvtColor(imageResized, imageDst, CV_BGRA2BGR);
    
    
    dlib::cv_image<dlib::rgb_pixel> cimg(imageDst);
    
    std::vector<dlib::rectangle> convertedRectangles = detector(cimg, 0);
    
    //return when no face detected
    if (convertedRectangles.size() == 0) return;
    
    for (unsigned long j = 0; j < convertedRectangles.size(); ++j) {
        dlib::rectangle oneFaceRect = convertedRectangles[j];
        // detect all landmarks
        dlib::full_object_detection shape = sp(cimg, oneFaceRect);
        
        //draw Point
        for (unsigned int i = 0; i < 68; ++i)
        {
            circle(image, cv::Point(shape.part(i).x(), shape.part(i).y()), 2, cv::Scalar(0, 0, 255), -1);
        }
        
        for (unsigned int i = 0; i < object_pts.size(); ++i) {
            circle(image, cv::Point(object_pts[i].x, object_pts[i].y), 2, cv::Scalar(0, 0, 255), -1);
        }
        
        std::vector<cv::Point2d> image_pts;
        //fill in 2D ref points, annotations follow https://ibug.doc.ic.ac.uk/resources/300-W/
        image_pts.push_back(cv::Point2d(shape.part(17).x(), shape.part(17).y())); //#17 left brow left corner
        image_pts.push_back(cv::Point2d(shape.part(21).x(), shape.part(21).y())); //#21 left brow right corner
        image_pts.push_back(cv::Point2d(shape.part(22).x(), shape.part(22).y())); //#22 right brow left corner
        image_pts.push_back(cv::Point2d(shape.part(26).x(), shape.part(26).y())); //#26 right brow right corner
        image_pts.push_back(cv::Point2d(shape.part(36).x(), shape.part(36).y())); //#36 left eye left corner
        image_pts.push_back(cv::Point2d(shape.part(39).x(), shape.part(39).y())); //#39 left eye right corner
        image_pts.push_back(cv::Point2d(shape.part(42).x(), shape.part(42).y())); //#42 right eye left corner
        image_pts.push_back(cv::Point2d(shape.part(45).x(), shape.part(45).y())); //#45 right eye right corner
        image_pts.push_back(cv::Point2d(shape.part(31).x(), shape.part(31).y())); //#31 nose left corner
        image_pts.push_back(cv::Point2d(shape.part(35).x(), shape.part(35).y())); //#35 nose right corner
        image_pts.push_back(cv::Point2d(shape.part(48).x(), shape.part(48).y())); //#48 mouth left corner
        image_pts.push_back(cv::Point2d(shape.part(54).x(), shape.part(54).y())); //#54 mouth right corner
        image_pts.push_back(cv::Point2d(shape.part(57).x(), shape.part(57).y())); //#57 mouth central bottom corner
        image_pts.push_back(cv::Point2d(shape.part(8).x(), shape.part(8).y()));   //#8 chin corner
        
        
        //result
        cv::Mat rotation_vec;                           //3 x 1
        cv::Mat rotation_mat;                           //3 x 3 R
        cv::Mat translation_vec;                        //3 x 1 T
        cv::Mat pose_mat = cv::Mat(3, 4, CV_64FC1);     //3 x 4 R | T
        cv::Mat euler_angle = cv::Mat(3, 1, CV_64FC1);
        
        //calc pos
        cv::solvePnP(object_pts, image_pts, cam_matrix, dist_coeffs, rotation_vec, translation_vec);
        //        std::cout << "rotation_vec = "<< std::endl << " "  << rotation_vec << std::endl << std::endl;
        //        std::cout << "translation_vec = "<< std::endl << " "  << translation_vec << std::endl << std::endl;
        
        //reproject
        cv::projectPoints(reprojectsrc, rotation_vec, translation_vec, cam_matrix, dist_coeffs, reprojectdst);
        
        
        //draw axis
        line(image, reprojectdst[0], reprojectdst[1], cv::Scalar(0, 0, 255));
        line(image, reprojectdst[1], reprojectdst[2], cv::Scalar(0, 0, 255));
        line(image, reprojectdst[2], reprojectdst[3], cv::Scalar(0, 0, 255));
        line(image, reprojectdst[3], reprojectdst[0], cv::Scalar(0, 0, 255));
        line(image, reprojectdst[4], reprojectdst[5], cv::Scalar(0, 0, 255));
        line(image, reprojectdst[5], reprojectdst[6], cv::Scalar(0, 0, 255));
        line(image, reprojectdst[6], reprojectdst[7], cv::Scalar(0, 0, 255));
        line(image, reprojectdst[7], reprojectdst[4], cv::Scalar(0, 0, 255));
        line(image, reprojectdst[0], reprojectdst[4], cv::Scalar(0, 0, 255));
        line(image, reprojectdst[1], reprojectdst[5], cv::Scalar(0, 0, 255));
        line(image, reprojectdst[2], reprojectdst[6], cv::Scalar(0, 0, 255));
        line(image, reprojectdst[3], reprojectdst[7], cv::Scalar(0, 0, 255));
        
        
        
        //calc euler angle
        cv::Rodrigues(rotation_vec, rotation_mat);
        cv::hconcat(rotation_mat, translation_vec, pose_mat);
        cv::decomposeProjectionMatrix(pose_mat, out_intrinsics, out_rotation, out_translation, cv::noArray(), cv::noArray(), cv::noArray(), euler_angle);
        
        //show angle result
        outtext << "X: " << std::setprecision(3) << euler_angle.at<double>(0);
        cv::putText(image, outtext.str(), cv::Point(50, 40), cv::FONT_HERSHEY_SIMPLEX, 0.75, cv::Scalar(0, 0, 0));
        outtext.str("");
        outtext << "Y: " << std::setprecision(3) << euler_angle.at<double>(1);
        cv::putText(image, outtext.str(), cv::Point(50, 60), cv::FONT_HERSHEY_SIMPLEX, 0.75, cv::Scalar(0, 0, 0));
        outtext.str("");
        outtext << "Z: " << std::setprecision(3) << euler_angle.at<double>(2);
        cv::putText(image, outtext.str(), cv::Point(50, 80), cv::FONT_HERSHEY_SIMPLEX, 0.75, cv::Scalar(0, 0, 0));
        outtext.str("");
        
        
        
    }    
    //CVPixelBufferUnlockBaseAddress( buffer, 0 );
}


@end
