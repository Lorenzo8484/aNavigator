#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>

@class SCNView;
@class SCNScene;
@class TileManager;
@class CameraController;

@interface Map3DViewController : UIViewController <CLLocationManagerDelegate>

// Scene
@property (nonatomic, strong) SCNView *sceneView;
@property (nonatomic, strong) SCNScene *scene;

// Location
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic) CLLocationCoordinate2D currentUserLocation;
@property (nonatomic) BOOL hasUserLocation;

// Tile management
@property (nonatomic, strong) TileManager *tileManager;

// Camera
@property (nonatomic, strong) CameraController *cameraController;

// Gesture state
@property (nonatomic) CGPoint lastPanLocation;

// Methods
- (void)setupScene;
- (void)setupLocation;
- (void)setupGestures;
- (void)loadInitialTiles;

@end
