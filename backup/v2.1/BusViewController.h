#import <UIKit/UIKit.h>
#import <SceneKit/SceneKit.h>

@class MapViewController;

@interface BusViewController : UIViewController
@property (nonatomic, weak) MapViewController *mapVC;
@property (nonatomic, readonly) SCNView *scnView;
- (void)applyGlassOpacity:(CGFloat)alpha;
- (void)setFullScreen:(BOOL)full animated:(BOOL)animated;
- (void)updateBusScale;
- (void)applyBusRotation;
- (void)showBus;
- (void)hideBus;
- (UIImage *)busSnapshot;
@property (nonatomic, readonly) UIButton *closeXButton;
@property (nonatomic, readonly) BOOL manuallyHidden;
@end
