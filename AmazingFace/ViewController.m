//
//  ViewController.m
//  AmazingFace
//
//  Created by york on 2017/12/1.
//  Copyright © 2017年 zero. All rights reserved.
//

#import "ViewController.h"
#import "HeadPoseDetector.h"

#define clamp(a) (a>255?255:(a<0?0:a))


@interface ViewController () <ARSCNViewDelegate, ARSessionDelegate>

@property (nonatomic, strong) IBOutlet ARSCNView *sceneView;

@end

    
@implementation ViewController {
    HeadPoseDetector *headPosdetector;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    headPosdetector = [[HeadPoseDetector alloc] init];

    // Set the view's delegate
    self.sceneView.delegate = self;
    
    self.sceneView.session.delegate = self;
    
    // Show statistics such as fps and timing information
    self.sceneView.showsStatistics = YES;
    
    // Create a new scene
    SCNScene *scene = [SCNScene sceneNamed:@"art.scnassets/ship.scn"];
    
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
    CVPixelBufferRef buffer = [frame capturedImage];
    
    CVPixelBufferLockBaseAddress(buffer, 0);
    // it has two plane of yuv and cbcr
    if (CVPixelBufferGetPlaneCount(buffer) < 2) {
        return;
    }
    
    size_t width = CVPixelBufferGetWidth(buffer);
    size_t height = CVPixelBufferGetHeight(buffer);
    
    uint8_t *yBuffer = CVPixelBufferGetBaseAddressOfPlane(buffer, 0);
    size_t yPitch = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0);
    
    uint8_t *cbCrBuffer = CVPixelBufferGetBaseAddressOfPlane(buffer, 1);
    size_t cbCrPitch = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1);
    
    
    int bytesPerPixel = 4;
    uint8_t *rgbBuffer = malloc(height * width * bytesPerPixel);
    
    for(int yy = 0; yy < height; yy++) {
        
        uint8_t *yBufferLine = &yBuffer[yy * yPitch];
        uint8_t *cbCrBufferLine = &cbCrBuffer[(yy >> 1) * cbCrPitch];
        
        for(int x = 0; x < width -1; x++) {
            int16_t y = yBufferLine[x];
            int16_t cb = cbCrBufferLine[x & ~1] - 128;
            int16_t cr = cbCrBufferLine[x | 1] - 128;
            
            uint8_t *rgbOutput = &rgbBuffer[ ( (x + 1) * height - yy ) * bytesPerPixel];
            
            int16_t r = (int16_t)roundf( y + cr *  1.4 );
            int16_t g = (int16_t)roundf( y + cb * -0.343 + cr * -0.711 );
            int16_t b = (int16_t)roundf( y + cb *  1.765);
            
            rgbOutput[0] = 0xff;
            rgbOutput[1] = clamp(b);
            rgbOutput[2] = clamp(g);
            rgbOutput[3] = clamp(r);

        }
    }
    
    //[headPosdetector doWorkOnPixelBuffer:rgbBuffer Heigth:height Width:width BytePerRow:cbCrPitch];
    free(rgbBuffer);

    
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    
}


@end
