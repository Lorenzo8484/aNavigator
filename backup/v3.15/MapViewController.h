#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <CoreLocation/CoreLocation.h>
#import <AVFoundation/AVFoundation.h>

typedef NS_ENUM(NSInteger, TransportMode) {
    TransportModeAuto, TransportModeBus, TransportModeTruck
};
typedef NS_ENUM(NSInteger, AlertLevel) {
    AlertLevelNone, AlertLevelImportant, AlertLevelFull
};

@class BusViewController;
@class SettingsViewController;

@interface MapViewController : UIViewController <CLLocationManagerDelegate>

// Web map (replaces MKMapView)
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) WKWebViewConfiguration *webConfig;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, weak) BusViewController *busVC;

// Navigation state
@property (nonatomic) BOOL isNavigating;
@property (nonatomic) NSInteger currentStepIndex;
@property (nonatomic) CLLocationDistance distanceRemaining;
@property (nonatomic) NSTimeInterval etaSeconds;

// Camera settings
@property (nonatomic) CGFloat cameraAltitude;
@property (nonatomic) CGFloat cameraPitch;
@property (nonatomic) CGFloat cameraOffset;
@property (nonatomic) CGFloat cameraHeadingOffset;

// UI opacity
@property (nonatomic) CGFloat menuOpacity;

// Bus stops
@property (nonatomic, strong) NSMutableSet<NSString *> *busStopsFetched;
@property (nonatomic) BOOL pendingBusFetch;

// Buttons
@property (nonatomic, strong) UIButton *searchButton;
@property (nonatomic, strong) UIButton *mapButton;
@property (nonatomic, strong) UIButton *trackingButton;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, strong) UIButton *modalitaButton;
@property (nonatomic, strong) UIButton *compassButton;
@property (nonatomic, strong) UIButton *logButton;
@property (nonatomic, strong) UIButton *goButton;
@property (nonatomic, strong) UIButton *endNavButton;
@property (nonatomic, readonly) BOOL searchActive;
@property (nonatomic) BOOL busForceHidden;
@property (nonatomic) BOOL mapOrientationLocked;
@property (nonatomic) BOOL userTracking;
@property (nonatomic) BOOL userTrackingWithHeading;

// Search
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *searchResultsTable;
@property (nonatomic, strong) UIView *searchOverlay;
@property (nonatomic, strong) UIView *searchBlur;
@property (nonatomic, strong) NSMutableArray *searchResults;
@property (nonatomic) BOOL searchActive_Ivar;

// Nav UI
@property (nonatomic, strong) UIView *navBar;
@property (nonatomic, strong) UILabel *instructionLabel;
@property (nonatomic, strong) UILabel *distanceLabel;
@property (nonatomic, strong) UILabel *etaLabel;
@property (nonatomic, strong) UILabel *speedLabel;

// Speech
@property (nonatomic, strong) AVSpeechSynthesizer *speechSynthesizer;

// Arrow
@property (nonatomic, strong) UIImage *arrow3D;

// Log
@property (nonatomic, strong) UIView *logPanel;
@property (nonatomic, strong) UITextView *logTextView;
@property (nonatomic, strong) NSMutableString *logBuffer;

// Methods
- (void)openSettings;
- (void)settingsDidClose;
- (void)applyCameraSettings;
- (void)applyArrowTransform;
- (void)applyMenuOpacity;
- (void)showBusView:(BOOL)show fullScreen:(BOOL)full;
- (void)applyBusStopsVisibility;
- (void)appLog:(NSString *)fmt,...;
- (void)updateNavUI;
- (void)showGoButton;
- (void)hideGoButton;
- (void)closeSearch;
- (void)showAlert:(NSString *)title message:(NSString *)msg;
- (void)endNavigation;
- (void)updateTrackingButton;
- (void)setUserTrackingWithHeading:(BOOL)val;
- (void)setUserTracking:(BOOL)val;

@end
