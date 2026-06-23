#import <UIKit/UIKit.h>

@class MapViewController;

typedef NS_ENUM(NSInteger, SettingsSection) {
    SettingsSectionNavigation = 0,
    SettingsSectionMap,
    SettingsSectionAlerts,
    SettingsSectionSystem,
    SettingsSectionDisplay
};

@interface SettingsViewController : UIViewController
@property (nonatomic, weak) MapViewController *mapVC;
@end
