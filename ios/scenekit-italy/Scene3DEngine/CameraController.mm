#import "CameraController.h"

@interface CameraController ()

@property (nonatomic, strong) SCNNode *cameraNode;
@property (nonatomic, strong) SCNNode *targetNode;

@end

@implementation CameraController

// ---------------------------------------------------------------------------
#pragma mark - Init
// ---------------------------------------------------------------------------

- (instancetype)init {
    self = [super init];
    if (self) {
        _altitude = 500.0;
        _pitch = 60.0;
        _heading = 0.0;
        _target = SCNVector3Make(0, 0, 0);
    }
    return self;
}

// ---------------------------------------------------------------------------
#pragma mark - Apply camera
// ---------------------------------------------------------------------------

- (void)applyCameraToScene:(SCNScene *)scene sceneView:(SCNView *)sceneView {
    if (!scene) return;

    // Create or reuse camera node
    if (!self.cameraNode) {
        // Target node for look-at constraint
        self.targetNode = [SCNNode node];
        self.targetNode.position = self.target;
        [scene.rootNode addChildNode:self.targetNode];

        // Camera node
        SCNCamera *camera = [SCNCamera camera];
        camera.zNear = 0.1;
        camera.zFar = 5000.0;
        camera.automaticallyAdjustsZRange = YES;
        camera.fieldOfView = 60.0;

        self.cameraNode = [SCNNode node];
        self.cameraNode.camera = camera;
        self.cameraNode.name = @"mainCamera";
        [scene.rootNode addChildNode:self.cameraNode];

        // Look-at constraint
        SCNLookAtConstraint *constraint = [SCNLookAtConstraint lookAtConstraintWithTarget:self.targetNode];
        constraint.gimbalLockEnabled = YES;
        self.cameraNode.constraints = @[constraint];
    }

    // Update target position
    self.targetNode.position = self.target;

    // Calculate camera position in spherical coordinates around target
    double pitchRad = self.pitch * M_PI / 180.0;
    double headingRad = self.heading * M_PI / 180.0;

    // Spherical to cartesian: y is up, heading is rotation around Y axis
    // pitch 0 = looking straight down, pitch 80 = almost horizontal
    double phi = pitchRad; // angle from vertical
    double theta = headingRad; // rotation around Y axis

    double r = self.altitude;

    // In SceneKit: y is up, x is right, z is forward
    // Heading 0 = looking north (+Z in our coord system where lat→Z)
    // Camera must be at SOUTH of target to look north
    // Negate z so: heading=0 → camera at -Z → looking toward +Z (north/building
    double x = r * sin(phi) * sin(theta);
    double y = r * cos(phi);
    double z = -r * sin(phi) * cos(theta); // negate: heading 0 → look north (+Z)

    SCNVector3 cameraPos = SCNVector3Make(
        self.target.x + (float)x,
        self.target.y + (float)y,
        self.target.z + (float)z
    );

    self.cameraNode.position = cameraPos;
}

// ---------------------------------------------------------------------------
#pragma mark - Animated transition
// ---------------------------------------------------------------------------

- (void)animateToAltitude:(CGFloat)altitude pitch:(CGFloat)pitch heading:(CGFloat)heading target:(SCNVector3)target duration:(NSTimeInterval)duration {
    // Store original values
    CGFloat origAltitude = self.altitude;
    CGFloat origPitch = self.pitch;
    CGFloat origHeading = self.heading;
    SCNVector3 origTarget = self.target;

    // Animate using SCNAction on camera node (or we can just set values with spring)
    // For simplicity, set immediately and let caller use SCNAction if desired
    self.altitude = altitude;
    self.pitch = pitch;
    self.heading = heading;
    self.target = target;

    // In a production app we'd use a spring animation here
    // For now, directly apply
    // The caller should ensure sceneView is available
}

@end
