#import <Foundation/Foundation.h>
#import <SceneKit/SceneKit.h>

@interface CameraController : NSObject

// Camera parameters
@property (nonatomic) CGFloat altitude;   // 100 - 2000 meters
@property (nonatomic) CGFloat pitch;      // 0 - 80 degrees
@property (nonatomic) CGFloat heading;    // 0 - 360 degrees
@property (nonatomic) SCNVector3 target;  // look-at point in scene coordinates

// Apply current camera settings to the scene
- (void)applyCameraToScene:(SCNScene *)scene sceneView:(SCNView *)sceneView;

// Animated transition to new values
- (void)animateToAltitude:(CGFloat)altitude pitch:(CGFloat)pitch heading:(CGFloat)heading target:(SCNVector3)target duration:(NSTimeInterval)duration;

@end
