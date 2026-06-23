#import <Foundation/Foundation.h>
#import "LocalizationManager.h"
#import "MapViewController.h"

@interface SettingsStore : NSObject
+ (instancetype)shared;

// Navigazione
@property (nonatomic) TransportMode transportMode;
@property (nonatomic,copy) NSString *preferredRoute; // "Più veloce", "Più breve", "Eco"
@property (nonatomic) BOOL avoidTolls, avoidHighways, avoidFerries;
@property (nonatomic) BOOL autoReroute, showAlternatives, voiceGuidance;
@property (nonatomic) float voiceVolume; // 0.0-1.0
@property (nonatomic) BOOL liveTraffic, showPOIAlongRoute, speedCameraAlert, showCurrentSpeed, offlineNavigation;
@property (nonatomic,copy) NSString *voiceLanguage; // "Italiano - Chiara" etc (placeholder)

// Mappa
@property (nonatomic) NSInteger mapType; // 0=Standard, 1=Satellite, 2=Hybrid
@property (nonatomic) BOOL view3DDefault, show3DBuildings, showTraffic, nightMode, autoZoom;
@property (nonatomic) BOOL showBusStops; // Fermate autobus sulla mappa
@property (nonatomic,copy) NSString *mapOrientation; // "Nord in alto", "Rotta in alto"
@property (nonatomic) BOOL showCompass, showScale;
@property (nonatomic,copy) NSString *poiLabels; // "Tutte", "Nessuna", "Solo principali"

// Avvisi
@property (nonatomic) AlertLevel alertLevel; // No avvisi / Importanti / Completi
@property (nonatomic) BOOL alertSpeedLimit, alertFixedCamera, alertMobileCamera;
@property (nonatomic) BOOL alertAccidents, alertRoadworks, alertClosedRoads;
@property (nonatomic) BOOL alertWeather, alertIce, alertSchoolZone;

// Sistema
@property (nonatomic,copy) NSString *unitSystem; // "Metrico", "Imperiale"
@property (nonatomic) AppLanguage language;       // IT/EN/FR/DE/ES
@property (nonatomic) BOOL hapticFeedback, batterySaver;
@property (nonatomic) float cacheSize; // GB
@property (nonatomic,copy) NSString *privacyData, *openSourceLicenses, *appVersion;
@property (nonatomic,copy) NSString *attributions; // Crediti OSM + Overpass + modelli 3D

// Schermo
@property (nonatomic) BOOL autoBrightness, darkTheme;
@property (nonatomic,copy) NSString *textSize; // "Normale", "Grande", "Molto grande"
@property (nonatomic) BOOL showSpeedometer, showETA, transparentStatusBar, reducedAnimations, alwaysOnDisplay;

// Autobus
@property (nonatomic) float busOffsetY;   // -1.5 (alto) a +1.5 (basso)
@property (nonatomic) float busOffsetX;   // -1.0 (sinistra) a +1.0 (destra)
@property (nonatomic) float busScale;     // 0.5 a 2.0 (default 1.0)
@property (nonatomic) float busRotation;  // -180° a +180° (default 0)

// Freccia
@property (nonatomic) float arrowRotation; // -180° a +180° (default 0)

- (void)save;
- (void)load;
@end
