#import "SettingsStore.h"

static NSString* alertLevelName(AlertLevel a) {
    switch(a){ case AlertLevelNone: return @"No avvisi"; case AlertLevelImportant: return @"Avvisi importanti"; case AlertLevelFull: return @"Avvisi completi"; }
}

@implementation SettingsStore

+ (instancetype)shared {
    static SettingsStore *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SettingsStore alloc] init];
        [instance load];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        // Defaults
        _transportMode = TransportModeAuto;
        _preferredRoute = @"Più veloce";
        _avoidTolls = NO; _avoidHighways = NO; _avoidFerries = NO;
        _autoReroute = YES; _showAlternatives = NO; _voiceGuidance = YES;
        _voiceVolume = 0.7;
        _liveTraffic = YES; _showPOIAlongRoute = NO; _speedCameraAlert = YES;
        _showCurrentSpeed = YES; _offlineNavigation = NO;
        _voiceLanguage = @"Italiano - Chiara";
        
        _mapType = 0;
        _view3DDefault = YES; _show3DBuildings = YES; _showTraffic = YES;
        _showBusStops = NO;
        _nightMode = NO; _autoZoom = YES;
        _mapOrientation = @"Nord in alto";
        _showCompass = NO; _showScale = YES;
        _poiLabels = @"Tutte";
        
        _alertLevel = AlertLevelFull;
        _alertSpeedLimit = YES; _alertFixedCamera = YES; _alertMobileCamera = NO;
        _alertAccidents = YES; _alertRoadworks = YES; _alertClosedRoads = YES;
        _alertWeather = NO; _alertIce = NO; _alertSchoolZone = YES;
        
        _unitSystem = @"Metrico"; _language = AppLanguageItalian;
        _hapticFeedback = YES; _batterySaver = NO;
        _cacheSize = 2.3;
        _privacyData = @""; _openSourceLicenses = @""; _appVersion = @"v5.4";
        _attributions = @""; // caricato sotto
        
        _autoBrightness = YES; _darkTheme = YES; _textSize = @"Normale";
        _showSpeedometer = YES; _showETA = YES; _transparentStatusBar = YES;
        _reducedAnimations = NO; _alwaysOnDisplay = NO;
        
        _busOffsetY = 0.0; _busOffsetX = 0.0; _busScale = 1.0; _busRotation = 0.0;
        _arrowRotation = 0.0;
    }
    return self;
}

- (void)save {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setInteger:_transportMode forKey:@"set_transport"];
    [ud setObject:_preferredRoute forKey:@"set_route"];
    [ud setBool:_avoidTolls forKey:@"set_avoidTolls"]; [ud setBool:_avoidHighways forKey:@"set_avoidHW"]; [ud setBool:_avoidFerries forKey:@"set_avoidFer"];
    [ud setBool:_autoReroute forKey:@"set_reroute"]; [ud setBool:_showAlternatives forKey:@"set_alt"]; [ud setBool:_voiceGuidance forKey:@"set_voice"];
    [ud setFloat:_voiceVolume forKey:@"set_vol"];
    [ud setBool:_liveTraffic forKey:@"set_traffic"]; [ud setBool:_showPOIAlongRoute forKey:@"set_poi"]; [ud setBool:_speedCameraAlert forKey:@"set_camera"];
    [ud setBool:_showCurrentSpeed forKey:@"set_speed"]; [ud setBool:_offlineNavigation forKey:@"set_offline"];
    [ud setObject:_voiceLanguage forKey:@"set_voicelang"];
    
    [ud setInteger:_mapType forKey:@"set_maptype"];
    [ud setBool:_view3DDefault forKey:@"set_3d"]; [ud setBool:_show3DBuildings forKey:@"set_3dbuild"]; [ud setBool:_showTraffic forKey:@"set_showtraffic"];
    [ud setBool:_showBusStops forKey:@"set_busstops"];
    [ud setBool:_nightMode forKey:@"set_night"]; [ud setBool:_autoZoom forKey:@"set_autozoom"];
    [ud setObject:_mapOrientation forKey:@"set_orient"];
    [ud setBool:_showCompass forKey:@"set_compass"]; [ud setBool:_showScale forKey:@"set_scale"];
    [ud setObject:_poiLabels forKey:@"set_poilabels"];
    
    [ud setInteger:_alertLevel forKey:@"set_alertlevel"];
    [ud setBool:_alertSpeedLimit forKey:@"set_asl"]; [ud setBool:_alertFixedCamera forKey:@"set_afc"]; [ud setBool:_alertMobileCamera forKey:@"set_amc"];
    [ud setBool:_alertAccidents forKey:@"set_aac"]; [ud setBool:_alertRoadworks forKey:@"set_arw"]; [ud setBool:_alertClosedRoads forKey:@"set_acr"];
    [ud setBool:_alertWeather forKey:@"set_awt"]; [ud setBool:_alertIce forKey:@"set_aic"]; [ud setBool:_alertSchoolZone forKey:@"set_asz"];
    
    [ud setObject:_unitSystem forKey:@"set_unit"];
    [ud setInteger:_language forKey:@"set_lang"];
    [ud setBool:_hapticFeedback forKey:@"set_hap"]; [ud setBool:_batterySaver forKey:@"set_batt"];
    [ud setFloat:_cacheSize forKey:@"set_cache"];
    
    [ud setBool:_autoBrightness forKey:@"set_ab"]; [ud setBool:_darkTheme forKey:@"set_dark"]; [ud setObject:_textSize forKey:@"set_tsize"];
    [ud setBool:_showSpeedometer forKey:@"set_spd"]; [ud setBool:_showETA forKey:@"set_eta"]; [ud setBool:_transparentStatusBar forKey:@"set_tsb"];
    [ud setBool:_reducedAnimations forKey:@"set_ra"]; [ud setBool:_alwaysOnDisplay forKey:@"set_aod"];
    [ud setFloat:_busOffsetY forKey:@"set_busY"]; [ud setFloat:_busOffsetX forKey:@"set_busX"]; [ud setFloat:_busScale forKey:@"set_busS"];
    [ud setFloat:_busRotation forKey:@"set_busR"];
    [ud setFloat:_arrowRotation forKey:@"set_arrR"];
    [ud synchronize];
}

- (void)load {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud objectForKey:@"set_transport"]) {
        _transportMode = (TransportMode)[ud integerForKey:@"set_transport"];
        _preferredRoute = [ud objectForKey:@"set_route"];
        _avoidTolls = [ud boolForKey:@"set_avoidTolls"]; _avoidHighways = [ud boolForKey:@"set_avoidHW"]; _avoidFerries = [ud boolForKey:@"set_avoidFer"];
        _autoReroute = [ud boolForKey:@"set_reroute"]; _showAlternatives = [ud boolForKey:@"set_alt"]; _voiceGuidance = [ud boolForKey:@"set_voice"];
        _voiceVolume = [ud floatForKey:@"set_vol"];
        _liveTraffic = [ud boolForKey:@"set_traffic"]; _showPOIAlongRoute = [ud boolForKey:@"set_poi"]; _speedCameraAlert = [ud boolForKey:@"set_camera"];
        _showCurrentSpeed = [ud boolForKey:@"set_speed"]; _offlineNavigation = [ud boolForKey:@"set_offline"];
        _voiceLanguage = [ud objectForKey:@"set_voicelang"] ?: @"Italiano - Chiara";
        
        _mapType = [ud integerForKey:@"set_maptype"];
        _view3DDefault = [ud boolForKey:@"set_3d"]; _show3DBuildings = [ud boolForKey:@"set_3dbuild"]; _showTraffic = [ud boolForKey:@"set_showtraffic"];
        _showBusStops = [ud objectForKey:@"set_busstops"] ? [ud boolForKey:@"set_busstops"] : NO;
        _nightMode = [ud boolForKey:@"set_night"]; _autoZoom = [ud boolForKey:@"set_autozoom"];
        _mapOrientation = [ud objectForKey:@"set_orient"];
        _showCompass = [ud boolForKey:@"set_compass"]; _showScale = [ud boolForKey:@"set_scale"];
        _poiLabels = [ud objectForKey:@"set_poilabels"];
        
        _alertLevel = (AlertLevel)[ud integerForKey:@"set_alertlevel"];
        _alertSpeedLimit = [ud boolForKey:@"set_asl"]; _alertFixedCamera = [ud boolForKey:@"set_afc"]; _alertMobileCamera = [ud boolForKey:@"set_amc"];
        _alertAccidents = [ud boolForKey:@"set_aac"]; _alertRoadworks = [ud boolForKey:@"set_arw"]; _alertClosedRoads = [ud boolForKey:@"set_acr"];
        _alertWeather = [ud boolForKey:@"set_awt"]; _alertIce = [ud boolForKey:@"set_aic"]; _alertSchoolZone = [ud boolForKey:@"set_asz"];
        
        _unitSystem = [ud objectForKey:@"set_unit"]; _language = (AppLanguage)[ud integerForKey:@"set_lang"];
        _hapticFeedback = [ud boolForKey:@"set_hap"]; _batterySaver = [ud boolForKey:@"set_batt"];
        _cacheSize = [ud floatForKey:@"set_cache"];
        
        _autoBrightness = [ud boolForKey:@"set_ab"]; _darkTheme = [ud boolForKey:@"set_dark"]; _textSize = [ud objectForKey:@"set_tsize"];
        _showSpeedometer = [ud boolForKey:@"set_spd"]; _showETA = [ud boolForKey:@"set_eta"]; _transparentStatusBar = [ud boolForKey:@"set_tsb"];
        _reducedAnimations = [ud boolForKey:@"set_ra"]; _alwaysOnDisplay = [ud boolForKey:@"set_aod"];
        _busOffsetY = [ud floatForKey:@"set_busY"]; _busOffsetX = [ud floatForKey:@"set_busX"]; _busScale = [ud objectForKey:@"set_busS"] ? [ud floatForKey:@"set_busS"] : 1.0;
        _busRotation = [ud objectForKey:@"set_busR"] ? [ud floatForKey:@"set_busR"] : 0.0;
        _arrowRotation = [ud objectForKey:@"set_arrR"] ? [ud floatForKey:@"set_arrR"] : 0.0;
    }
}
@end
