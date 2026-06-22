#import "Map3DViewController.h"
#import "TileManager.h"
#import "CameraController.h"

@interface Map3DViewController ()

@end

@implementation Map3DViewController

// ---------------------------------------------------------------------------
#pragma mark - View lifecycle
// ---------------------------------------------------------------------------

- (void)viewDidLoad {
    [super viewDidLoad];

    // Create SceneKit view
    self.sceneView = [[SCNView alloc] initWithFrame:self.view.bounds];
    self.sceneView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.sceneView.backgroundColor = [UIColor colorWithRed:0.58 green:0.80 blue:0.98 alpha:1.0]; // light blue
    self.sceneView.allowsCameraControl = NO; // we manage camera ourselves
    self.sceneView.showsStatistics = YES;
    [self.view addSubview:self.sceneView];

    // Create scene
    [self setupScene];

    // Create camera controller
    self.cameraController = [[CameraController alloc] init];
    self.cameraController.target = SCNVector3Make(0, 0, 0); // Bologna origin
    self.cameraController.altitude = 500.0;
    self.cameraController.pitch = 60.0;
    self.cameraController.heading = 0.0;
    [self.cameraController applyCameraToScene:self.scene sceneView:self.sceneView];

    // Create tile manager
    self.tileManager = [[TileManager alloc] initWithScene:self.scene];

    // Setup location services
    [self setupLocation];

    // Setup gestures
    [self setupGestures];

    // Load initial tiles (Bologna)
    [self loadInitialTiles];
}

// ---------------------------------------------------------------------------
#pragma mark - Scene setup
// ---------------------------------------------------------------------------

- (void)setupScene {
    SCNScene *scene = [[SCNScene alloc] init];

    // Fog
    scene.fogStartDistance = 800.0;
    scene.fogEndDistance = 2000.0;
    scene.fogDensityExponent = 1.0;
    scene.fogColor = [UIColor colorWithRed:0.58 green:0.80 blue:0.98 alpha:1.0]; // match sky

    // Sky color
    scene.background.contents = [UIColor colorWithRed:0.58 green:0.80 blue:0.98 alpha:1.0];

    // Ambient light (soft fill)
    SCNLight *ambientLight = [SCNLight light];
    ambientLight.type = SCNLightTypeAmbient;
    ambientLight.color = [UIColor colorWithWhite:0.5 alpha:1.0];
    ambientLight.intensity = 400; // lumens
    SCNNode *ambientNode = [SCNNode node];
    ambientNode.light = ambientLight;
    ambientNode.name = @"ambientLight";
    [scene.rootNode addChildNode:ambientNode];

    // Directional light (sun with shadows)
    SCNLight *sunLight = [SCNLight light];
    sunLight.type = SCNLightTypeDirectional;
    sunLight.color = [UIColor colorWithWhite:0.9 alpha:1.0];
    sunLight.intensity = 1000;
    sunLight.castsShadow = YES;
    sunLight.shadowSampleCount = 16;
    sunLight.shadowBias = 1.0;
    sunLight.shadowMapSize = CGSizeMake(1024, 1024);
    sunLight.shadowRadius = 4.0;
    sunLight.shadowMode = SCNShadowModeDeferred;
    SCNNode *sunNode = [SCNNode node];
    sunNode.light = sunLight;
    sunNode.name = @"sunLight";
    sunNode.eulerAngles = SCNVector3Make(-M_PI_4, M_PI_4, 0); // from above-right
    [scene.rootNode addChildNode:sunNode];

    self.scene = scene;
    self.sceneView.scene = scene;
}

// ---------------------------------------------------------------------------
#pragma mark - Location
// ---------------------------------------------------------------------------

- (void)setupLocation {
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    self.locationManager.distanceFilter = 10.0; // meters

    CLAuthorizationStatus status = self.locationManager.authorizationStatus;
    if (status == kCLAuthorizationStatusNotDetermined) {
        [self.locationManager requestWhenInUseAuthorization];
    } else if (status == kCLAuthorizationStatusAuthorizedWhenInUse ||
               status == kCLAuthorizationStatusAuthorizedAlways) {
        [self.locationManager startUpdatingLocation];
    }
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    if (status == kCLAuthorizationStatusAuthorizedWhenInUse ||
        status == kCLAuthorizationStatusAuthorizedAlways) {
        [self.locationManager startUpdatingLocation];
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *loc = [locations lastObject];
    if (!loc) return;

    self.currentUserLocation = loc.coordinate;
    self.hasUserLocation = YES;

    // Update camera target to follow user
    double latRad = self.currentUserLocation.latitude * M_PI / 180.0;
    double sceneX = (self.currentUserLocation.longitude - 11.34) * 111320.0 * cos(latRad);
    double sceneZ = (self.currentUserLocation.latitude - 44.49) * 111320.0;
    self.cameraController.target = SCNVector3Make((float)sceneX, 0, (float)sceneZ);

    // Load tiles around user location
    [self.tileManager updateForLocation:self.currentUserLocation.latitude
                                   lon:self.currentUserLocation.longitude];
}

// ---------------------------------------------------------------------------
#pragma mark - Gestures
// ---------------------------------------------------------------------------

- (void)setupGestures {
    // Pan gesture -> orbit camera around target
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(handlePan:)];
    pan.minimumNumberOfTouches = 1;
    pan.maximumNumberOfTouches = 1;
    [self.sceneView addGestureRecognizer:pan];

    // Pinch gesture -> zoom (change altitude)
    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self
                                                                                action:@selector(handlePinch:)];
    [self.sceneView addGestureRecognizer:pinch];

    // Two-finger pan -> change pitch (tilt)
    UIPanGestureRecognizer *tiltPan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                              action:@selector(handleTiltPan:)];
    tiltPan.minimumNumberOfTouches = 2;
    tiltPan.maximumNumberOfTouches = 2;
    [self.sceneView addGestureRecognizer:tiltPan];
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.sceneView];

    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.lastPanLocation = translation;
    }

    CGFloat dx = translation.x - self.lastPanLocation.x;
    self.lastPanLocation = translation;

    // Horizontal pan -> change heading (left/right orbit)
    self.cameraController.heading += dx * 0.2;
    // Keep heading in 0-360 range
    while (self.cameraController.heading < 0) self.cameraController.heading += 360;
    while (self.cameraController.heading >= 360) self.cameraController.heading -= 360;

    // Vertical pan -> change pitch (up/down tilt)
    CGFloat dy = translation.y - (self.lastPanLocation.y - (translation.y - dy));
    // Actually let's use the y translation from gesture velocity more carefully
    // We'll detect y movement differently - use velocity instead
    CGFloat velocityY = [gesture velocityInView:self.sceneView].y;
    if (gesture.state == UIGestureRecognizerStateChanged) {
        // The pan y-translation tracks cumulative; we already tracked dx.
        // For pitch, let's use the delta since last call.
        // We stored translation, so compute the y delta from the stored value
        static CGFloat lastY = 0;
        if (gesture.state == UIGestureRecognizerStateBegan) {
            lastY = translation.y;
        }
        CGFloat yDelta = translation.y - lastY;
        lastY = translation.y;
        self.cameraController.pitch -= yDelta * 0.2;
        self.cameraController.pitch = fmax(0, fmin(80, self.cameraController.pitch));
    }

    if (gesture.state == UIGestureRecognizerStateEnded ||
        gesture.state == UIGestureRecognizerStateCancelled) {
        self.lastPanLocation = CGPointZero;
    }

    [self.cameraController applyCameraToScene:self.scene sceneView:self.sceneView];
}

- (void)handlePinch:(UIPinchGestureRecognizer *)gesture {
    static CGFloat initialAltitude = 0;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        initialAltitude = self.cameraController.altitude;
    }

    CGFloat scale = gesture.scale;
    // Invert: pinch out (scale > 1) = zoom out = increase altitude
    self.cameraController.altitude = initialAltitude / scale;
    self.cameraController.altitude = fmax(100, fmin(2000, self.cameraController.altitude));

    if (gesture.state == UIGestureRecognizerStateChanged) {
        [self.cameraController applyCameraToScene:self.scene sceneView:self.sceneView];
    }
}

- (void)handleTiltPan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.sceneView];

    // Vertical two-finger swipe changes pitch
    CGFloat pitchDelta = -translation.y * 0.2;
    self.cameraController.pitch += pitchDelta;
    self.cameraController.pitch = fmax(0, fmin(80, self.cameraController.pitch));

    [gesture setTranslation:CGPointZero inView:self.sceneView];

    if (gesture.state == UIGestureRecognizerStateChanged) {
        [self.cameraController applyCameraToScene:self.scene sceneView:self.sceneView];
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Initial tiles
// ---------------------------------------------------------------------------

- (void)loadInitialTiles {
    // Load tiles around Bologna center (44.49, 11.34)
    [self.tileManager updateForLocation:44.49 lon:11.34];
}

// ---------------------------------------------------------------------------
#pragma mark - Orientation
// ---------------------------------------------------------------------------

- (BOOL)shouldAutorotate {
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

@end
