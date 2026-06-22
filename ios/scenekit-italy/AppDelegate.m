#import "AppDelegate.h"
#import "Map3DViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[Map3DViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
