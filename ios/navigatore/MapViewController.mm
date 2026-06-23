#import "MapViewController.h"

@interface MapViewController ()
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) CLLocationManager *locManager;
@property (nonatomic, strong) AVSpeechSynthesizer *speechSynth;
@property (nonatomic) BOOL isNavigating;
@property (nonatomic) CLLocationCoordinate2D destination;
@end

@implementation MapViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Location
    self.locManager = [[CLLocationManager alloc] init];
    self.locManager.delegate = self;
    self.locManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
    [self.locManager requestWhenInUseAuthorization];
    
    // Speech
    self.speechSynth = [[AVSpeechSynthesizer alloc] init];
    
    // WKWebView
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    [config.preferences setValue:@YES forKey:@"allowFileAccessFromFileURLs"];
    [config setValue:@YES forKey:@"allowUniversalAccessFromFileURLs"];
    config.allowsInlineMediaPlayback = YES;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    
    WKUserContentController *userCtrl = [[WKUserContentController alloc] init];
    [userCtrl addScriptMessageHandler:self name:@"speak"];
    [userCtrl addScriptMessageHandler:self name:@"navUpdate"];
    [userCtrl addScriptMessageHandler:self name:@"navigationEnd"];
    [userCtrl addScriptMessageHandler:self name:@"searchResult"];
    [userCtrl addScriptMessageHandler:self name:@"log"];
    config.userContentController = userCtrl;
    
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.webView.navigationDelegate = self;
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.scrollView.scrollEnabled = NO;
    self.webView.backgroundColor = [UIColor blackColor];
    [self.view insertSubview:self.webView atIndex:0];
    
    // Load map.html
    NSString *path = [[NSBundle mainBundle] pathForResource:@"map" ofType:@"html"];
    if (path) {
        NSURL *url = [NSURL fileURLWithPath:path];
        [self.webView loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
    }
}

// ===== WKNavigationDelegate =====
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)nav {
    NSLog(@"Map loaded, starting GPS...");
    [self.locManager startUpdatingLocation];
    [self.locManager startUpdatingHeading];
}

// ===== CLLocationManagerDelegate =====
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *loc = [locations lastObject];
    if (!loc) return;
    
    NSString *js = [NSString stringWithFormat:@"updatePosition(%.6f, %.6f, %.1f)",
                    loc.coordinate.latitude, loc.coordinate.longitude, loc.course];
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)heading {
    NSString *js = [NSString stringWithFormat:@"updateHeading(%.1f)", heading.trueHeading];
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    if (manager.authorizationStatus == kCLAuthorizationStatusAuthorizedWhenInUse ||
        manager.authorizationStatus == kCLAuthorizationStatusAuthorizedAlways) {
        [manager startUpdatingLocation];
        [manager startUpdatingHeading];
    }
}

// ===== WKScriptMessageHandler (JS → ObjC) =====
- (void)userContentController:(WKUserContentController *)uc didReceiveScriptMessage:(WKScriptMessage *)msg {
    if ([msg.name isEqualToString:@"speak"]) {
        NSString *text = msg.body;
        if ([text isKindOfClass:[NSString class]] && text.length > 0) {
            AVSpeechUtterance *utt = [AVSpeechUtterance speechUtteranceWithString:text];
            utt.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"it-IT"];
            utt.rate = 0.5;
            [self.speechSynth speakUtterance:utt];
        }
    } else if ([msg.name isEqualToString:@"navUpdate"]) {
        // Update nav UI in future versions
        NSLog(@"Nav update: %@", msg.body);
    } else if ([msg.name isEqualToString:@"navigationEnd"]) {
        self.isNavigating = NO;
        NSLog(@"Navigation ended");
    } else if ([msg.name isEqualToString:@"searchResult"]) {
        NSLog(@"Search result: %@", msg.body);
    } else if ([msg.name isEqualToString:@"log"]) {
        NSLog(@"JS: %@", msg.body);
    }
}

@end
