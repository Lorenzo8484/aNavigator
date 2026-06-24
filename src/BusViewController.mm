#import "BusViewController.h"
#import "MapViewController.h"
#import "SettingsStore.h"
#import <SceneKit/SceneKit.h>

// ─── PassThroughView: lascia passare i tocchi fuori dalla glassWindow ──
@interface PassThroughView : UIView
@property (nonatomic) CGRect activeRect;
@end
@implementation PassThroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!CGRectContainsPoint(self.activeRect, point)) {
        return nil; // passa il tocco alla mappa sottostante
    }
    return [super hitTest:point withEvent:event];
}
@end

// ─── Costanti ─────────────────────────────────────────────────
static const CGFloat kGlassHeightRatio = 0.35;   // finestra bus = 35% altezza schermo
static const CGFloat kCameraAngleDeg    = 15.0;   // gradi sopra l'orizzonte
static const CGFloat kCameraFOV         = 50.0;   // field of view verticale

@interface BusViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) SCNView *scnView;
@property (nonatomic, strong) SCNNode *busNode;
@property (nonatomic, strong) SCNNode *pivotNode;
@property (nonatomic, strong) SCNNode *cameraTarget;
@property (nonatomic, strong) SCNNode *camNode;
@property (nonatomic, strong) SCNNode *modelRoot;      // nodo radice del modello USDZ
@property (nonatomic, strong) UIView *glassWindow;
@property (nonatomic, strong) UIView *glassBg;
@property (nonatomic, strong) CAGradientLayer *reflection;
@property (nonatomic) CGFloat busRotationY;
@property (nonatomic) BOOL isFullScreen;
@property (nonatomic) BOOL manuallyHidden;
@property (nonatomic) CGFloat rawHeight, rawWidth, rawLength; // dimensioni originali
@end

@implementation BusViewController

- (void)loadView {
    PassThroughView *ptv = [[PassThroughView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    ptv.backgroundColor = [UIColor clearColor];
    ptv.activeRect = CGRectMake(0, 0, 0, 0);
    self.view = ptv;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat safeTop = self.view.safeAreaInsets.top;
    CGFloat glassH = h * kGlassHeightRatio;

    // ── Glass window ───────────────────────────────────────────
    self.glassWindow = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, glassH)];
    self.glassWindow.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.glassWindow.clipsToBounds = YES;

    self.glassBg = [[UIView alloc] initWithFrame:self.glassWindow.bounds];
    self.glassBg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.glassBg.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
    self.glassBg.layer.cornerRadius = 20;
    self.glassBg.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    self.glassBg.layer.masksToBounds = YES;
    self.glassBg.layer.borderWidth = 1.5;
    self.glassBg.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.25].CGColor;
    [self.glassWindow addSubview:self.glassBg];

    self.reflection = [CAGradientLayer layer];
    self.reflection.frame = self.glassBg.bounds;
    self.reflection.colors = @[
        (id)[[UIColor whiteColor] colorWithAlphaComponent:0.12].CGColor,
        (id)[[UIColor whiteColor] colorWithAlphaComponent:0.0].CGColor,
        (id)[[UIColor whiteColor] colorWithAlphaComponent:0.0].CGColor,
        (id)[[UIColor whiteColor] colorWithAlphaComponent:0.06].CGColor
    ];
    self.reflection.startPoint = CGPointMake(0, 0);
    self.reflection.endPoint = CGPointMake(1, 1);
    [self.glassBg.layer addSublayer:self.reflection];
    [self.view addSubview:self.glassWindow];

    // ── SceneKit (riempie la glass window) ────
    CGFloat scnY = safeTop + 8;
    CGFloat margin = 4;
    self.scnView = [[SCNView alloc] initWithFrame:CGRectMake(margin, scnY, w - 2*margin, glassH - scnY - margin)];
    self.scnView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scnView.backgroundColor = [UIColor clearColor];
    self.scnView.allowsCameraControl = NO;
    self.scnView.antialiasingMode = SCNAntialiasingModeMultisampling4X;
    [self.glassWindow addSubview:self.scnView];
    
    PassThroughView *ptv = (PassThroughView *)self.view;
    ptv.activeRect = self.glassWindow.frame;

    [self setupScene];
    [self setupBus];
    [self setupGestures];
    [self applyBusRotation];
    
    // ── Pulsante X (in BusVC.view, SOPRA glassWindow + SCNView) ──
    // DEVE stare FUORI da glassWindow perché SCNView Metal lo copre
    _closeXButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _closeXButton.frame = CGRectMake(w - 44, glassH - 44, 32, 32);
    _closeXButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.35];
    _closeXButton.layer.cornerRadius = 16;
    _closeXButton.layer.borderWidth = 2;
    _closeXButton.layer.borderColor = [UIColor whiteColor].CGColor;
    [_closeXButton setTitle:@"✕" forState:UIControlStateNormal];
    _closeXButton.titleLabel.font = [UIFont boldSystemFontOfSize:22];
    [_closeXButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_closeXButton addTarget:self action:@selector(hideBus) forControlEvents:UIControlEventTouchUpInside];
    _closeXButton.hidden = YES;
    [self.view addSubview:_closeXButton];  // in self.view, NON in glassWindow
}

- (void)setupScene {
    SCNScene *scene = [SCNScene scene];
    scene.background.contents = [UIColor clearColor];

    self.cameraTarget = [SCNNode node];
    self.cameraTarget.position = SCNVector3Make(0, 0, 0);
    [scene.rootNode addChildNode:self.cameraTarget];

    SCNNode *amb = [SCNNode node];
    amb.light = [SCNLight light];
    amb.light.type = SCNLightTypeAmbient;
    amb.light.color = [UIColor colorWithWhite:0.5 alpha:1.0];
    [scene.rootNode addChildNode:amb];

    SCNNode *key = [SCNNode node];
    key.light = [SCNLight light];
    key.light.type = SCNLightTypeDirectional;
    key.light.color = [UIColor colorWithWhite:0.95 alpha:1.0];
    key.light.intensity = 1000;
    key.light.castsShadow = YES;
    key.light.shadowMapSize = CGSizeMake(1024, 1024);
    key.position = SCNVector3Make(5, 10, 8);
    key.eulerAngles = SCNVector3Make(-0.6, -0.4, 0);
    [scene.rootNode addChildNode:key];

    SCNNode *fill = [SCNNode node];
    fill.light = [SCNLight light];
    fill.light.type = SCNLightTypeDirectional;
    fill.light.color = [UIColor colorWithWhite:0.35 alpha:1.0];
    fill.light.intensity = 400;
    fill.position = SCNVector3Make(-3, 2, -4);
    [scene.rootNode addChildNode:fill];

    SCNCamera *cam = [SCNCamera camera];
    cam.fieldOfView = kCameraFOV;
    cam.zNear = 0.05;
    cam.zFar = 500;

    self.camNode = [SCNNode node];
    self.camNode.camera = cam;
    self.camNode.position = SCNVector3Make(0, 5, 8);

    SCNLookAtConstraint *lookAt = [SCNLookAtConstraint lookAtConstraintWithTarget:self.cameraTarget];
    lookAt.gimbalLockEnabled = YES;
    self.camNode.constraints = @[lookAt];
    [scene.rootNode addChildNode:self.camNode];

    self.scnView.scene = scene;
}

- (void)setupBus {
    SCNScene *busScene = [SCNScene sceneNamed:@"brisbane_city_bus.usdz"];
    if (!busScene) {
        NSLog(@"⚠️ [BusVC] Failed to load brisbane_city_bus.usdz");
        return;
    }
    self.modelRoot = [busScene.rootNode clone];

    // Salva dimensioni originali (senza scala)
    SCNVector3 bMin, bMax;
    [self.modelRoot getBoundingBoxMin:&bMin max:&bMax];
    self.rawHeight = bMax.y - bMin.y;
    self.rawWidth  = bMax.x - bMin.x;
    self.rawLength = bMax.z - bMin.z;
    if (self.rawHeight <= 0) self.rawHeight = 1.0;

    // Crea pivot e bus node
    self.pivotNode = [SCNNode node];
    self.pivotNode.position = SCNVector3Make(0, 0, 0);
    [self.scnView.scene.rootNode addChildNode:self.pivotNode];

    self.busNode = [SCNNode node];
    [self.pivotNode addChildNode:self.busNode];
    [self.busNode addChildNode:self.modelRoot];

    // Applica scala iniziale
    [self updateBusScale];
}

// Ricalcola scala, pivot e camera. Camera a distanza FISSA (5.5 unita).
// Il bus e PIU LUNGO CHE ALTO → scala basata sulla LARGHEZZA, non sull'altezza.
// Riempie il 92% della larghezza visibile, IDENTICO in portrait e landscape.
- (void)updateBusScale {
    if (!self.modelRoot || self.rawHeight <= 0) return;

    CGFloat camAngle = M_PI * kCameraAngleDeg / 180.0;
    CGFloat fovRad   = M_PI * kCameraFOV / 360.0;

    // Distanza camera FISSA
    CGFloat camDist = 5.5;

    // Larghezza 3D visibile a questa distanza
    CGFloat visibleW = 2.0 * camDist * tan(fovRad);

    // Bus riempie il 180% della LARGHEZZA visibile (quasi 2x rispetto a prima)
    CGFloat targetW = visibleW * 1.80;
    CGFloat scale = targetW / self.rawWidth;
    
    // Applica scala utente da Impostazioni
    SettingsStore *st = [SettingsStore shared];
    scale *= st.busScale;

    self.modelRoot.scale = SCNVector3Make(scale, scale, scale);

    // Dimensioni effettive
    CGFloat effH = self.rawHeight * scale;

    // Pivot: 20% dal basso
    self.pivotNode.pivot = SCNMatrix4MakeTranslation(0, effH * 0.20, 0);
    // Posizione da slider (offsetX/Y). Default (0,0) = centrato.
    self.pivotNode.position = SCNVector3Make(st.busOffsetX * effH * 0.5, st.busOffsetY * effH * 0.3, 0);

    // Camera target: centro geometrico
    CGFloat centerY = effH * 0.5;
    self.cameraTarget.position = SCNVector3Make(0, centerY, 0);

    // Camera a 15° sopra, distanza fissa
    CGFloat camY = centerY + camDist * sin(camAngle);
    CGFloat camZ = camDist * cos(camAngle);
    self.camNode.position = SCNVector3Make(0, camY, camZ);
}

- (void)applyBusRotation {
    SettingsStore *st = [SettingsStore shared];
    CGFloat rotRad = st.busRotation * M_PI / 180.0;
    self.pivotNode.eulerAngles = SCNVector3Make(0, rotRad, 0);
}

- (void)setupGestures {
    // Nessuna gesture — il bus si muove solo dagli slider nelle Impostazioni
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint velocity = [pan velocityInView:self.scnView];
    self.busRotationY += velocity.x / 4000.0;
    self.pivotNode.eulerAngles = SCNVector3Make(0, self.busRotationY, 0);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return NO;
}

- (UIImage *)busSnapshot {
    if (!self.scnView) return nil;
    UIImage *raw = [self.scnView snapshot];
    if (!raw) return nil;
    
    // Crop & scale to 44pt (132px @3x)
    CGSize target = CGSizeMake(132, 132);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:target];
    UIImage *scaled = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [raw drawInRect:CGRectMake(0, 0, target.width, target.height)];
    }];
    return scaled;
}

- (void)applyGlassOpacity:(CGFloat)alpha {
    self.glassBg.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:alpha];
}

// ─── Espandi/riduci a schermo intero ──────────────────────────
- (void)setFullScreen:(BOOL)full animated:(BOOL)animated {
    self.isFullScreen = full;

    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat safeTop = self.view.safeAreaInsets.top;
    CGFloat margin = 4;

    if (full) {
        void(^apply)(void) = ^{
            self.glassWindow.frame = CGRectMake(0, 0, w, h);
            self.glassBg.frame = self.glassWindow.bounds;
            self.glassBg.layer.cornerRadius = 0;
            self.glassBg.layer.maskedCorners = 0;
            self.reflection.frame = self.glassBg.bounds;
            CGFloat scnY = safeTop + 8;
            self.scnView.frame = CGRectMake(margin, scnY, w - 2*margin, h - scnY - margin);
            [self.mapVC showBusView:YES fullScreen:YES];
            // X visibile anche in landscape (top-right)
            self.closeXButton.hidden = NO;
            self.closeXButton.frame = CGRectMake(w - 44, safeTop + 12, 32, 32);
            [self.view bringSubviewToFront:self.closeXButton];
            // Ricalcola scala per il nuovo viewport (più grande)
            [self updateBusScale];
            [self applyBusRotation];
        };
        if (animated) [UIView animateWithDuration:0.35 animations:apply];
        else apply();
    } else {
        CGFloat glassH = h * kGlassHeightRatio;
        void(^apply)(void) = ^{
            self.glassWindow.frame = CGRectMake(0, 0, w, glassH);
            self.glassBg.frame = self.glassWindow.bounds;
            self.glassBg.layer.cornerRadius = 20;
            self.glassBg.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
            self.reflection.frame = self.glassBg.bounds;
            CGFloat scnY = safeTop + 8;
            self.scnView.frame = CGRectMake(margin, scnY, w - 2*margin, glassH - scnY - margin);
            [self.mapVC showBusView:YES fullScreen:NO];
            // X visibile in portrait
            self.closeXButton.hidden = NO;
            self.closeXButton.frame = CGRectMake(w - 44, glassH - 44, 32, 32);
            [self.view bringSubviewToFront:self.closeXButton];
            // Ricalcola scala per viewport portrait
            [self updateBusScale];
            [self applyBusRotation];
        };
        if (animated) [UIView animateWithDuration:0.35 animations:apply];
        else apply();
    }

    PassThroughView *ptv = (PassThroughView *)self.view;
    ptv.activeRect = self.glassWindow.frame;
}

- (void)hideBus {
    [UIView animateWithDuration:0.3 animations:^{
        self.view.alpha = 0;
        self.closeXButton.alpha = 0;
    } completion:^(BOOL finished) {
        self.view.hidden = YES;
        self.view.alpha = 1;
        self.closeXButton.hidden = YES;
        self.closeXButton.alpha = 1.0;
        self.isFullScreen = NO;
        _manuallyHidden = YES;  // impedisce a applyOrientation di ri-mostrare
        CGFloat w = self.view.bounds.size.width;
        CGFloat h = self.view.bounds.size.height;
        CGFloat glassH = h * kGlassHeightRatio;
        CGFloat margin = 4;
        CGFloat safeTop = self.view.safeAreaInsets.top;
        self.glassWindow.frame = CGRectMake(0, 0, w, glassH);
        self.glassBg.frame = self.glassWindow.bounds;
        self.glassBg.layer.cornerRadius = 20;
        self.glassBg.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
        CGFloat scnY = safeTop + 8;
        self.scnView.frame = CGRectMake(margin, scnY, w - 2*margin, glassH - scnY - margin);

        PassThroughView *ptv = (PassThroughView *)self.view;
        ptv.activeRect = self.glassWindow.frame;

        [self.mapVC showBusView:NO fullScreen:NO];
        [self updateBusScale];
        [self applyBusRotation];
    }];
}

- (void)showBus {
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    _manuallyHidden = NO;  // l'utente vuole rivedere il bus
    
    // In landscape, sempre full screen
    if (h < w) {
        self.view.hidden = NO;
        self.view.alpha = 1.0;
        [self setFullScreen:YES animated:YES];
        return;
    }
    
    self.view.hidden = NO;
    self.closeXButton.hidden = NO;
    [self.view bringSubviewToFront:self.closeXButton];
    [UIView animateWithDuration:0.3 animations:^{
        self.view.alpha = 1.0;
        self.closeXButton.alpha = 1.0;
    }];
    
    CGFloat glassH = h * kGlassHeightRatio;
    CGFloat margin = 4;
    CGFloat safeTop = self.view.safeAreaInsets.top;
    
    self.glassWindow.frame = CGRectMake(0, 0, w, glassH);
    self.glassBg.frame = self.glassWindow.bounds;
    self.glassBg.layer.cornerRadius = 20;
    self.glassBg.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    self.reflection.frame = self.glassBg.bounds;
    
    CGFloat scnY = safeTop + 8;
    self.scnView.frame = CGRectMake(margin, scnY, w - 2*margin, glassH - scnY - margin);
    
    // Riposiziona X in basso a destra della glass window
    self.closeXButton.frame = CGRectMake(w - 44, glassH - 44, 32, 32);
    [self.view bringSubviewToFront:self.closeXButton];
    
    PassThroughView *ptv = (PassThroughView *)self.view;
    ptv.activeRect = self.glassWindow.frame;
    
    [self.mapVC showBusView:YES fullScreen:NO];
    [self updateBusScale];
    [self applyBusRotation];
}

@end