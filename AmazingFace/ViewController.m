//
//  ViewController.m
//  AmazingFace
//
//  Created by york on 2017/12/1.
//  Copyright © 2017年 zero. All rights reserved.
//

#import "ViewController.h"
#import "HeadPoseDetector.h"
#import <Vision/Vision.h>
#import <UIKit/UIKit.h>


#define clamp(a) (a>255?255:(a<0?0:a))


@interface ViewController () <ARSCNViewDelegate, ARSessionDelegate>

@property (nonatomic, strong) IBOutlet ARSCNView *sceneView;

@end

    
@implementation ViewController {
    HeadPoseDetector *headPosdetector;
    VNDetectFaceRectanglesRequest *faceDetection;
    VNDetectFaceLandmarksRequest *faceLandmarks;
    VNSequenceRequestHandler *faceDatectionRequest;
    VNSequenceRequestHandler *faceLandmarksRequest;
    NSArray * detectionArray;
    dispatch_queue_t faceDetecionQueue;
    dispatch_queue_t landmarkCalQueue;
    
    SCNScene *scene;
    
    CGRect rect;
    
    int frameIndex;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    faceDatectionRequest = [[VNSequenceRequestHandler alloc] init];
    faceLandmarksRequest = [[VNSequenceRequestHandler alloc] init];
    faceDetection = [[VNDetectFaceRectanglesRequest alloc] init];
    faceLandmarks = [[VNDetectFaceLandmarksRequest alloc] init];
    detectionArray = @[faceDetection];
    faceDetecionQueue = dispatch_queue_create("com.AmazingFace.detectionQueue", nil);
    landmarkCalQueue = dispatch_queue_create("com.AmazingFace.landmarkCalQueue", nil);
    
    headPosdetector = [[HeadPoseDetector alloc] init];
    
    frameIndex = 0;
    
    rect = [self.sceneView bounds];

    // Set the view's delegate
    self.sceneView.delegate = self;
    
    self.sceneView.session.delegate = self;
    
    // Show statistics such as fps and timing information
    self.sceneView.showsStatistics = YES;
    
    self.sceneView.debugOptions = ARSCNDebugOptionShowFeaturePoints;
    
    // Create a new scene
    scene = [SCNScene sceneNamed:@"art.scnassets/ship.scn"];
    
    // Get Geometry from object
    SCNNode *node = [scene.rootNode childNodeWithName:@"ship" recursively:YES];
    SCNGeometry *geo =[[[node childNodes] objectAtIndex:0] geometry];
    NSArray* sources = [geo geometrySources];
    SCNGeometrySource *vertex   = sources[0];
    SCNGeometrySource *normals  = sources[1];
    SCNGeometrySource *texcoord = sources[2];
    NSArray *materials = geo.materials;
    NSArray *elements = geo.geometryElements;
    
    NSInteger vectexCount = vertex.vectorCount;
    NSInteger dataPerVectex = vertex.bytesPerComponent * vertex.componentsPerVector;
    NSInteger dataLength = vectexCount* dataPerVectex;
    
    float vectorData[dataLength];
    
    [vertex.data getBytes:&vectorData length: dataLength];
    for (NSInteger i = 0; i < vectexCount; i ++) {
        if(i % 10 == 0)
        vectorData[i*3] += 10;
        
        // x
        vectorData[i*3];
        // y
        vectorData[i*3 + 1];
        // z
        vectorData[i*3 + 2];
    }
    // create new data
    NSData *newData = [NSData dataWithBytes:&vectorData length:dataLength];
    
    // create new geometrySource
    SCNGeometrySource *newVertex = [SCNGeometrySource geometrySourceWithData:newData semantic:SCNGeometrySourceSemanticVertex vectorCount:vectexCount floatComponents:YES componentsPerVector:vertex.componentsPerVector bytesPerComponent:vertex.bytesPerComponent dataOffset:vertex.dataOffset dataStride:vertex.dataStride];
    
    // create new geometry
    SCNGeometry *newGeo = [SCNGeometry geometryWithSources:@[newVertex, normals, texcoord] elements:elements];
    [newGeo setMaterials:materials];
    
    // update geometrt
    [[[node childNodes] objectAtIndex:0] setGeometry:newGeo];
    
    
    
    
    
    // Set the scene to the view
    self.sceneView.scene = scene;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Create a session configuration
    ARWorldTrackingConfiguration *configuration = [ARWorldTrackingConfiguration new];
    
    //[configuration set]

    // Run the view's session
    [self.sceneView.session runWithConfiguration:configuration];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // Pause the view's session
    [self.sceneView.session pause];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - ARSCNViewDelegate

/*
// Override to create and configure nodes for anchors added to the view's session.
- (SCNNode *)renderer:(id<SCNSceneRenderer>)renderer nodeForAnchor:(ARAnchor *)anchor {
    SCNNode *node = [SCNNode new];
 
    // Add geometry to the node...
 
    return node;
}
*/

- (void)session:(ARSession *)session didFailWithError:(NSError *)error {
    // Present an error message to the user
    
}

- (void)sessionWasInterrupted:(ARSession *)session {
    // Inform the user that the session has been interrupted, for example, by presenting an overlay
    
}

- (void)sessionInterruptionEnded:(ARSession *)session {
    // Reset tracking and/or remove existing anchors if consistent tracking is required
    
}

- (void)session:(ARSession *)session didUpdateFrame:(ARFrame *)frame {
    
    //you dont need to caputre every frame
    frameIndex = (frameIndex + 1)%3;
    
    CVPixelBufferRef buffer = [frame capturedImage];
    CIImage *ciimage = [CIImage imageWithCVPixelBuffer:buffer];
    CIImage *newImage = [ciimage imageByApplyingCGOrientation:kCGImagePropertyOrientationRight];
    
    matrix_float4x4 mat = [[frame camera] projectionMatrix];

    
    //if(frameIndex == 0)
    dispatch_async(faceDetecionQueue, ^{
        @autoreleasepool{
           [self detectFace:newImage];
        }
    });
    
}


- (void) detectFace:(CIImage *)image {
    if ([faceDatectionRequest performRequests:detectionArray onCIImage:image error:nil]) {
        NSArray *faceArray = [faceDetection results];
        if(faceArray.count != 0){
            //NSLog(@"GOT FACE");
            [faceLandmarks setInputFaceObservations:faceArray];
            [self detectLandmarks:image];
            
        }
       
    }
}

- (void) detectLandmarks:(CIImage *)image {
    if ([faceLandmarksRequest performRequests:@[faceLandmarks] onCIImage:image error:nil]) {
        NSArray *landmarksArray = [faceLandmarks results];
        
        VNFaceObservation *faceObservation = [landmarksArray objectAtIndex:0];
        VNFaceLandmarkRegion2D *allPoints = faceObservation.landmarks.allPoints;
        NSInteger pointCount = allPoints.pointCount;
        const CGPoint *point =  [allPoints pointsInImageOfSize:CGSizeMake(rect.size.width, rect.size.height)];
        NSString *outS = @"";
        
        
        NSArray* reslut = [self.sceneView hitTest:CGPointMake(point[8].x, rect.size.height - point[8].y) types:ARHitTestResultTypeFeaturePoint];
        NSArray* reslut1 = [self.sceneView hitTest:CGPointMake(point[20].x, rect.size.height - point[20].y) types:ARHitTestResultTypeFeaturePoint];
        NSArray* reslut2 = [self.sceneView hitTest:CGPointMake(point[29].x, rect.size.height - point[29].y) types:ARHitTestResultTypeFeaturePoint];
        NSArray* reslut3 = [self.sceneView hitTest:CGPointMake(point[30].x, rect.size.height - point[30].y) types:ARHitTestResultTypeFeaturePoint];
        if(reslut.count != 0){
            NSLog(@"get");
            ARHitTestResult *hitRes = [reslut objectAtIndex:0];
            SCNNode *node = [scene.rootNode childNodeWithName:@"face" recursively:YES];
            matrix_float4x4 transl = [hitRes worldTransform];
            
            [node setPosition:SCNVector3Make(transl.columns[3][0], transl.columns[3][1], transl.columns[3][2])];
            //[node setSimdWorldPosition:[hitRes localTransform]];
            NSLog(@"Get %f, %f;   %f, %f", point[8].x, point[8].y, point[29].x, point[29].y);
            NSLog(@"pos %f, %f, %f", [node position].x, [node position].y, [node position].z);
        }
        
        //[headPosdetector doWorkOnLandmarkArrary:landmarksArray];
    }
}


@end
