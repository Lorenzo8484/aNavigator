#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <CoreLocation/CoreLocation.h>
#import <AVFoundation/AVFoundation.h>

@interface MapViewController : UIViewController <WKNavigationDelegate, WKScriptMessageHandler, CLLocationManagerDelegate>
@end
