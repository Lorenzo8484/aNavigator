#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, AppLanguage) {
    AppLanguageItalian = 0,
    AppLanguageEnglish,
    AppLanguageFrench,
    AppLanguageGerman,
    AppLanguageSpanish
};

extern NSString * const kLanguageChangedNotification;

/// Macro per lookup immediato
NSString* LOC(NSString *key);

@interface LocalizationManager : NSObject
+ (instancetype)shared;
@property (nonatomic) AppLanguage currentLanguage;
- (NSString*)stringForKey:(NSString*)key;
- (void)setLanguage:(AppLanguage)lang;
- (NSArray<NSString*>*)availableLanguageNames;
- (NSString*)languageNameForCode:(AppLanguage)lang;
- (AppLanguage)languageCodeForName:(NSString*)name;
@end
