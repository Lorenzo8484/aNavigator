#import "MapViewController.h"
#import "SettingsViewController.h"
#import "SettingsStore.h"
#import "BusViewController.h"
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

@interface MapViewController () <CLLocationManagerDelegate, WKNavigationDelegate, WKScriptMessageHandler, UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate>
@end

@implementation MapViewController {
    CLLocation *_lastLocation;
    BOOL _busWasVisible;
    BOOL _modalitaWasVisible, _searchWasVisible, _trackingWasVisible, _settingsWasVisible, _compassWasVisible, _logWasVisible;
    UIButton *_goButton;
    NSDictionary *_pendingDestDict; // {lat, lon, name}
    CLLocationSpeed _currentSpeed;
    NSTimer *_navTimer;
    CGFloat _currentHeading;
    CGFloat _currentCourse; // direzione di marcia dal GPS
    CGFloat _cameraHeading; // ultimo heading applicato alla camera
    CGFloat _arrowBaseScale;
    CLLocation *_prevLocation;
    CLLocationCoordinate2D _prevSnapped;
    CLLocationCoordinate2D _lastSnapped;
    BOOL _hasSnapped;
    NSTimeInterval _interpStart;
    BOOL _isRecalculating;
    NSTimer *_arrowTimer;
    NSMutableArray *_busStopAnnotations; // array of NSDictionary {lat, lon, name}
    NSString *_lastSpokenInstruction;
    UIButton *_simButton;
    NSDictionary *_pendingSimDestDict;
    // Simulazione
    BOOL _isSimulating;
    NSTimer *_simTimer;
    NSArray *_simCoords; // array di {lat, lon}
    NSInteger _simIndex;
    double _simStepPerTick; // metri per tick simulazione
    double _simLat, _simLon, _simCourse; // posizione interpolata (scritta da simTick, letta da pushPosition)
    BOOL _hasSimPos;
    int _posUpdateCounter;
    // Movimento fluido (20 fps)
    BOOL _isInterpolating;
    CLLocationCoordinate2D _interpFrom;
    CLLocationCoordinate2D _interpTo;
    NSTimeInterval _interpStartTime;
    NSTimer *_smoothTimer;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self generateArrow3D]; // DEVE essere prima di setupMapView!
    self.view.backgroundColor = [UIColor blackColor];
    // Carica impostazioni camera salvate, o default
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    self.cameraAltitude = [ud objectForKey:@"autista_cam_alt"] ? [ud floatForKey:@"autista_cam_alt"] : 500;
    self.cameraPitch = [ud objectForKey:@"autista_cam_pit"] ? [ud floatForKey:@"autista_cam_pit"] : 60;
    self.cameraOffset = [ud objectForKey:@"autista_cam_off"] ? [ud floatForKey:@"autista_cam_off"] : 0;
    self.cameraVerticalOffset = [ud objectForKey:@"autista_cam_voff"] ? [ud floatForKey:@"autista_cam_voff"] : 0;
    self.menuOpacity = [ud objectForKey:@"autista_menu_op"] ? [ud floatForKey:@"autista_menu_op"] : 1.0;
    self.speechSynthesizer = [[AVSpeechSynthesizer alloc] init];
    [self setupMapView];
    [self applyArrowTransform];
    [self setupLocationManager];
    [self setupSearchOverlay];
    [self setupButtons];
    [self applyMenuOpacity];
    [self loadSavedLayout];
    // Tap sulla mappa chiude ricerca/tastiera
    UITapGestureRecognizer *mapTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissSearch)];
    mapTap.cancelsTouchesInView = NO;
    [self.webView addGestureRecognizer:mapTap];
    [self setupSearchTapToDismiss];
    [self setupNavBar];
    
    // Inizializza bus stops
    _busStopAnnotations = [NSMutableArray array];
    self.busStopsFetched = [NSMutableSet set];
    self.pendingBusFetch = NO;
    
    // Crea BusViewController — child VC per finestra autobus 3D
    BusViewController *busVC = [[BusViewController alloc] init];
    busVC.mapVC = self;
    [self addChildViewController:busVC];
    busVC.view.frame = self.view.bounds;
    busVC.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:busVC.view];
    [busVC didMoveToParentViewController:self];
    busVC.view.hidden = YES;
    busVC.view.alpha = 0;
    self.busVC = busVC;
    
    // Pannello log debugging
    [self setupLogPanel];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mapSettingsChanged) name:@"MapSettingsChanged" object:nil];
    
    // Timer per istruzioni vocali (ogni 2 secondi durante navigazione)
    [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(speakCurrentInstruction) userInfo:nil repeats:YES];
    
    [self applyCameraSettings];
    [self applyAllSettings];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Bussola: center + bounds (NON frame, che resetta la transform)
    CGFloat h = self.view.bounds.size.height;
    self.compassButton.center = CGPointMake(12 + 26, h - 110 + 26);
    self.compassButton.bounds = CGRectMake(0, 0, 52, 52);
    self.compassButton.layer.cornerRadius = 26;
}

#pragma mark - Setup

- (void)setupMapView {
    WKUserContentController *userCtrl = [[WKUserContentController alloc] init];
    [userCtrl addScriptMessageHandler:self name:@"speak"];
    [userCtrl addScriptMessageHandler:self name:@"navigationEnd"];
    [userCtrl addScriptMessageHandler:self name:@"navUpdate"];
    [userCtrl addScriptMessageHandler:self name:@"error"];
    [userCtrl addScriptMessageHandler:self name:@"searchResults"];
    [userCtrl addScriptMessageHandler:self name:@"routeReady"];
    [userCtrl addScriptMessageHandler:self name:@"simCoords"];
    [userCtrl addScriptMessageHandler:self name:@"appLog"];
    
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    config.userContentController = userCtrl;
    
    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:config];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.navigationDelegate = self;
    self.webView.scrollView.bounces = NO;
    self.webView.scrollView.bouncesZoom = NO;
    self.webView.opaque = NO;
    self.webView.backgroundColor = [UIColor clearColor];
    
    // Load map.html from main bundle
    NSString *htmlPath = [[NSBundle mainBundle] pathForResource:@"map" ofType:@"html"];
    if (htmlPath) {
        NSURL *htmlURL = [NSURL fileURLWithPath:htmlPath];
        NSURL *bundleDir = [htmlURL URLByDeletingLastPathComponent];
        [self.webView loadFileURL:htmlURL allowingReadAccessToURL:bundleDir];
    }
    
    [self.view addSubview:self.webView];
}

- (void)setupLocationManager {
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
    self.locationManager.distanceFilter = 1.0;
    [self.locationManager requestWhenInUseAuthorization];
    [self.locationManager startUpdatingLocation];
    [self.locationManager startUpdatingHeading];
    self.locationManager.headingFilter = 5.0;
}

- (void)setupSearchOverlay {
    CGFloat w = self.view.bounds.size.width;
    CGFloat topH = 120;
    
    self.searchOverlay = [[UIView alloc] initWithFrame:CGRectMake(0, -topH, w, topH)];
    self.searchOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.searchOverlay.clipsToBounds = NO;
    self.searchOverlay.hidden = YES;
    
    // Glass background — STESSO STILE menu impostazioni
    self.searchBlur = [[UIView alloc] init];
    self.searchBlur.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.93];
    self.searchBlur.frame = self.searchOverlay.bounds;
    self.searchBlur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.searchBlur.layer.cornerRadius = 28;
    self.searchBlur.layer.masksToBounds = YES;
    self.searchBlur.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    self.searchBlur.layer.borderWidth = 1.5;
    self.searchBlur.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.25].CGColor;
    [self.searchOverlay addSubview:self.searchBlur];
    
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(12, 50, w - 70, 44)];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"";
    self.searchBar.barStyle = UIBarStyleDefault;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.searchTextField.textColor = [UIColor colorWithWhite:0.30 alpha:1.0];
    self.searchBar.searchTextField.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.92];
    self.searchBar.searchTextField.layer.cornerRadius = 12;
    self.searchBar.searchTextField.layer.masksToBounds = YES;
    self.searchBar.searchTextField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Cerca indirizzo o luogo..." attributes:@{NSForegroundColorAttributeName: [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0]}];
    self.searchBar.tintColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    // Pulsante X per cancellare testo
    self.searchBar.searchTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    [self.searchOverlay addSubview:self.searchBar];
    
    [self.view addSubview:self.searchOverlay];
    
    self.searchResultsTable = [[UITableView alloc] initWithFrame:CGRectMake(0, topH, w, 0) style:UITableViewStylePlain];
    self.searchResultsTable.dataSource = self;
    self.searchResultsTable.delegate = self;
    self.searchResultsTable.backgroundColor = [UIColor colorWithWhite:0.16 alpha:0.95];
    self.searchResultsTable.separatorColor = [[UIColor whiteColor] colorWithAlphaComponent:0.1];
    self.searchResultsTable.hidden = YES;
    self.searchResultsTable.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.searchResultsTable registerClass:[UITableViewCell class] forCellReuseIdentifier:@"SCell"];
    [self.searchOverlay addSubview:self.searchResultsTable];
}

- (void)setupButtons {
    CGFloat margin = 12;
    CGFloat pillW = 100;
    CGFloat pillH = 40;
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat radius = pillH / 2;
    
    // Glass pill helper
    void(^glassPill)(UIButton*) = ^(UIButton *btn) {
        btn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
        btn.layer.cornerRadius = radius;
        btn.layer.borderWidth = 1.5;
        btn.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.25].CGColor;
        btn.layer.shadowColor = [UIColor blackColor].CGColor;
        btn.layer.shadowOpacity = 0.3;
        btn.layer.shadowRadius = 8;
        btn.layer.shadowOffset = CGSizeZero;
    };
    
    // 🚌 Modalita (top-right) — apre/chiude finestra autobus
    self.modalitaButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.modalitaButton.frame = CGRectMake(w - pillW - margin, 54, pillW, pillH);
    self.modalitaButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    glassPill(self.modalitaButton);
    self.modalitaButton.tintColor = [UIColor whiteColor];
    self.modalitaButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [self.modalitaButton setTitle:@"  Modalità" forState:UIControlStateNormal];
    [self.modalitaButton setImage:[UIImage systemImageNamed:@"bus.fill"] forState:UIControlStateNormal];
    [self.modalitaButton addTarget:self action:@selector(modalitaButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.modalitaButton];
    
    // 🗺️ Mappa / X button (top-right) — Mappa in landscape, X in portrait (chiude bus)
    self.mapButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.mapButton.frame = CGRectMake(w - 48, 54, 40, pillH);
    self.mapButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    glassPill(self.mapButton);
    self.mapButton.tintColor = [UIColor whiteColor];
    self.mapButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [self.mapButton addTarget:self action:@selector(topRightButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.mapButton.hidden = YES; // inizialmente nascosto (bus non visibile)
    [self.view addSubview:self.mapButton];
    
    // 🔍 Search pill (sotto la finestra bus)
    self.searchButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.searchButton.frame = CGRectMake(w - pillW - margin, h * 0.35 + 10, pillW, pillH);
    self.searchButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    glassPill(self.searchButton);
    self.searchButton.tintColor = [UIColor whiteColor];
    self.searchButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [self.searchButton setTitle:@"  Cerca" forState:UIControlStateNormal];
    [self.searchButton setImage:[UIImage systemImageNamed:@"magnifyingglass"] forState:UIControlStateNormal];
    [self.searchButton addTarget:self action:@selector(openSearch) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.searchButton];
    
    // 📍 Tracking pill
    self.trackingButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.trackingButton.frame = CGRectMake(w - pillW - margin, h - 120, pillW, pillH);
    self.trackingButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    glassPill(self.trackingButton);
    self.trackingButton.tintColor = [UIColor whiteColor];
    self.trackingButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [self.trackingButton setTitle:@"  Posizione" forState:UIControlStateNormal];
    [self.trackingButton setImage:[UIImage systemImageNamed:@"location.fill"] forState:UIControlStateNormal];
    [self.trackingButton addTarget:self action:@selector(trackingButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.trackingButton];
    
    // ⚙️ Settings pill
    self.settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.settingsButton.frame = CGRectMake(w - pillW - margin, h - 60, pillW, pillH);
    self.settingsButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    glassPill(self.settingsButton);
    self.settingsButton.tintColor = [UIColor whiteColor];
    self.settingsButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [self.settingsButton setTitle:@"  Impostaz." forState:UIControlStateNormal];
    [self.settingsButton setImage:[UIImage systemImageNamed:@"gearshape.fill"] forState:UIControlStateNormal];
    [self.settingsButton addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.settingsButton];
    
    // 🧭 Bussola (bottom-left, sotto log)
    self.compassButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.compassButton.frame = CGRectMake(margin, h - 110, 52, 52);
    // NO autoresizingMask — la transform di rotazione lo rompe
    self.compassButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
    self.compassButton.layer.cornerRadius = 26;
    self.compassButton.layer.borderWidth = 1.5;
    self.compassButton.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.25].CGColor;
    self.compassButton.tintColor = [UIColor whiteColor];
    // Icona bussola personalizzata (PNG fornito)
    NSString *compassPath = [[NSBundle mainBundle] pathForResource:@"compass" ofType:@"png"];
    UIImage *compassImg = compassPath ? [UIImage imageWithContentsOfFile:compassPath] : nil;
    if (!compassImg) compassImg = [UIImage systemImageNamed:@"location.north.line"];
    [self.compassButton setImage:compassImg forState:UIControlStateNormal];
    self.compassButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.compassButton addTarget:self action:@selector(compassButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.compassButton.hidden = ![SettingsStore shared].showCompass; // use custom compass (no system compass in Leaflet)
    [self.view addSubview:self.compassButton];
    [self.view bringSubviewToFront:self.compassButton];
    
    // 📋 Log toggle (bottom-left, sopra la bussola)
    self.logButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.logButton.frame = CGRectMake(margin, h - 170, 44, 44);
    self.logButton.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    self.logButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
    self.logButton.layer.cornerRadius = 22;
    self.logButton.layer.borderWidth = 1;
    self.logButton.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2].CGColor;
    self.logButton.tintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.7];
    [self.logButton setImage:[UIImage systemImageNamed:@"terminal.fill"] forState:UIControlStateNormal];
    [self.logButton addTarget:self action:@selector(toggleLogPanel) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.logButton];
    
    // 🛣️ Pill via (alta 120pt: info grandi + nome strada)
    self.roadNameLabel = [[UIView alloc] init];
    self.roadNameLabel.frame = CGRectMake(12, h - 220, w - 24, 140);
    self.roadNameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    self.roadNameLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
    self.roadNameLabel.layer.cornerRadius = 22;
    self.roadNameLabel.layer.masksToBounds = YES;
    self.roadNameLabel.layer.borderWidth = 1.5;
    self.roadNameLabel.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.25].CGColor;
    self.roadNameLabel.hidden = YES;
    [self.view addSubview:self.roadNameLabel];
    
    // Riga superiore: ETA (sinistra) | Durata (centro) | Distanza (destra) — doppia dimensione
    CGFloat roadPW = w - 24;
    self.roadETALabel = [[UILabel alloc] init];
    self.roadETALabel.frame = CGRectMake(16, 8, (roadPW - 32) / 3, 36);
    self.roadETALabel.font = [UIFont boldSystemFontOfSize:20];
    self.roadETALabel.textColor = [UIColor whiteColor];
    self.roadETALabel.textAlignment = NSTextAlignmentLeft;
    self.roadETALabel.text = @"";
    [self.roadNameLabel addSubview:self.roadETALabel];
    
    self.roadTimeLabel = [[UILabel alloc] init];
    self.roadTimeLabel.frame = CGRectMake(16 + (roadPW - 32) / 3, 8, (roadPW - 32) / 3, 36);
    self.roadTimeLabel.font = [UIFont boldSystemFontOfSize:20];
    self.roadTimeLabel.textColor = [UIColor whiteColor];
    self.roadTimeLabel.textAlignment = NSTextAlignmentCenter;
    self.roadTimeLabel.text = @"";
    [self.roadNameLabel addSubview:self.roadTimeLabel];
    
    self.roadDistLabel = [[UILabel alloc] init];
    self.roadDistLabel.frame = CGRectMake(16 + 2 * (roadPW - 32) / 3, 8, (roadPW - 32) / 3, 36);
    self.roadDistLabel.font = [UIFont boldSystemFontOfSize:20];
    self.roadDistLabel.textColor = [UIColor whiteColor];
    self.roadDistLabel.textAlignment = NSTextAlignmentRight;
    self.roadDistLabel.text = @"";
    [self.roadNameLabel addSubview:self.roadDistLabel];
    
    // Riga inferiore: nome via (bianco, centrato, multi-linea)
    self.roadStreetLabel = [[UILabel alloc] init];
    self.roadStreetLabel.frame = CGRectMake(12, 52, roadPW - 24, 78);
    self.roadStreetLabel.numberOfLines = 2;
    self.roadStreetLabel.font = [UIFont boldSystemFontOfSize:22];
    self.roadStreetLabel.textColor = [UIColor whiteColor];
    self.roadStreetLabel.textAlignment = NSTextAlignmentCenter;
    self.roadStreetLabel.text = @"";
    [self.roadNameLabel addSubview:self.roadStreetLabel];
    
    // ⏹️ Stop button (cerchio rosso, visibile solo in navigazione)
    self.stopNavButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.stopNavButton.frame = CGRectMake(12, h - 260, 52, 52);
    self.stopNavButton.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    self.stopNavButton.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.7];
    self.stopNavButton.layer.cornerRadius = 26;
    self.stopNavButton.layer.borderWidth = 2;
    self.stopNavButton.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5].CGColor;
    [self.stopNavButton setImage:[UIImage systemImageNamed:@"stop.fill"] forState:UIControlStateNormal];
    self.stopNavButton.tintColor = [UIColor whiteColor];
    self.stopNavButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.stopNavButton.imageEdgeInsets = UIEdgeInsetsMake(12, 12, 12, 12);
    [self.stopNavButton addTarget:self action:@selector(endNavigation) forControlEvents:UIControlEventTouchUpInside];
    self.stopNavButton.hidden = YES;
    [self.view addSubview:self.stopNavButton];
}

- (void)setupNavBar {
    CGFloat w = self.view.bounds.size.width;
    self.navBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 180)];
    self.navBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.navBar.hidden = YES;
    
    // Glass nav background — STESSO STILE menu impostazioni
    UIView *bv = [[UIView alloc] init];
    bv.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
    bv.frame = self.navBar.bounds;
    bv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    bv.layer.borderWidth = 1.5;
    bv.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.25].CGColor;
    [self.navBar addSubview:bv];
    
    UIView *spacer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 50)];
    [self.navBar addSubview:spacer];
    
    self.instructionLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 56, w - 32, 36)];
    self.instructionLabel.font = [UIFont boldSystemFontOfSize:18];
    self.instructionLabel.textColor = [UIColor whiteColor];
    self.instructionLabel.numberOfLines = 2;
    self.instructionLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.navBar addSubview:self.instructionLabel];
    
    self.distanceLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 96, w - 32, 20)];
    self.distanceLabel.font = [UIFont systemFontOfSize:14];
    self.distanceLabel.textColor = [UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1.0];
    self.distanceLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.navBar addSubview:self.distanceLabel];
    
    self.etaLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 122, 120, 24)];
    self.etaLabel.font = [UIFont boldSystemFontOfSize:17];
    self.etaLabel.textColor = [UIColor whiteColor];
    [self.navBar addSubview:self.etaLabel];
    
    self.speedLabel = [[UILabel alloc] initWithFrame:CGRectMake(w - 80, 116, 64, 36)];
    self.speedLabel.font = [UIFont boldSystemFontOfSize:26];
    self.speedLabel.textColor = [UIColor whiteColor];
    self.speedLabel.textAlignment = NSTextAlignmentRight;
    self.speedLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.navBar addSubview:self.speedLabel];
    
    self.endNavButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.endNavButton.frame = CGRectMake(w - 68, 156, 56, 24);
    self.endNavButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.endNavButton setTitle:@"Esci" forState:UIControlStateNormal];
    self.endNavButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    self.endNavButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
    self.endNavButton.tintColor = [UIColor whiteColor];
    self.endNavButton.layer.cornerRadius = 12;
    self.endNavButton.layer.borderWidth = 1;
    self.endNavButton.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.25].CGColor;
    [self.endNavButton addTarget:self action:@selector(endNavigation) forControlEvents:UIControlEventTouchUpInside];
    [self.navBar addSubview:self.endNavButton];
    
    [self.view addSubview:self.navBar];
}

#pragma mark - Log Panel

- (void)setupLogPanel {
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat logH = 120;
    
    self.logBuffer = [NSMutableString string];
    
    // Pannello semi-trasparente in basso
    self.logPanel = [[UIView alloc] initWithFrame:CGRectMake(8, h - logH - 70, w - 16, logH)];
    self.logPanel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    self.logPanel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
    self.logPanel.layer.cornerRadius = 12;
    self.logPanel.layer.borderWidth = 1;
    self.logPanel.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15].CGColor;
    self.logPanel.hidden = YES;
    [self.view addSubview:self.logPanel];
    
    // Etichetta titolo
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(10, 4, 100, 18)];
    title.text = @"📋 LOG";
    title.font = [UIFont boldSystemFontOfSize:11];
    title.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6];
    [self.logPanel addSubview:title];
    
    // Pulsante copy
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(logH + 10, 2, 60, 22);
    copyBtn.titleLabel.font = [UIFont systemFontOfSize:10];
    [copyBtn setTitle:@"Copia" forState:UIControlStateNormal];
    copyBtn.tintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
    [copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
    [self.logPanel addSubview:copyBtn];
    
    // Pulsante clear
    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    clearBtn.frame = CGRectMake(logH + 70, 2, 60, 22);
    clearBtn.titleLabel.font = [UIFont systemFontOfSize:10];
    [clearBtn setTitle:@"Pulisci" forState:UIControlStateNormal];
    clearBtn.tintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
    [clearBtn addTarget:self action:@selector(clearLog) forControlEvents:UIControlEventTouchUpInside];
    [self.logPanel addSubview:clearBtn];
    
    // Pulsante X per chiudere
    UIButton *xBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    xBtn.frame = CGRectMake(logH + 160, 2, 30, 22);
    xBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    [xBtn setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    xBtn.tintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
    [xBtn addTarget:self action:@selector(toggleLogPanel) forControlEvents:UIControlEventTouchUpInside];
    [self.logPanel addSubview:xBtn];
    
    // Area testo scrollabile
    self.logTextView = [[UITextView alloc] initWithFrame:CGRectMake(6, 24, logH + 120, logH - 28)];
    self.logTextView.backgroundColor = [UIColor clearColor];
    self.logTextView.textColor = [UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1.0];
    self.logTextView.font = [UIFont fontWithName:@"Menlo" size:9] ?: [UIFont systemFontOfSize:9];
    self.logTextView.editable = NO;
    self.logTextView.text = @"";
    [self.logPanel addSubview:self.logTextView];
}

- (void)appLog:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSLog(@"%@", msg);
    
    // Aggiungi al buffer
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"HH:mm:ss";
    NSString *ts = [df stringFromDate:[NSDate date]];
    [self.logBuffer appendFormat:@"[%@] %@\n", ts, msg];
    
    // Mantieni solo ultime 30 righe
    NSArray *lines = [self.logBuffer componentsSeparatedByString:@"\n"];
    if (lines.count > 30) {
        NSArray *last = [lines subarrayWithRange:NSMakeRange(lines.count - 30, 30)];
        self.logBuffer = [[last componentsJoinedByString:@"\n"] mutableCopy];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.logTextView.text = self.logBuffer;
        // Scroll in fondo
        if (self.logTextView.text.length > 0) {
            NSRange bottom = NSMakeRange(self.logTextView.text.length - 1, 1);
            [self.logTextView scrollRangeToVisible:bottom];
        }
    });
}

- (void)copyLog {
    [[UIPasteboard generalPasteboard] setString:self.logBuffer];
    [self appLog:@"📋 Log copiato negli appunti"];
}

- (void)clearLog {
    self.logBuffer = [NSMutableString string];
    self.logTextView.text = @"";
}

- (void)toggleLogPanel {
    self.logPanel.hidden = !self.logPanel.hidden;
    if (!self.logPanel.hidden) {
        [self.view bringSubviewToFront:self.logPanel];
    }
}

#pragma mark - Search

- (void)openSearch {
    // Nascondi la finestra dell'autobus durante la ricerca — INCONDIZIONALE
    self.busForceHidden = YES;
    if (self.busVC) {
        _busWasVisible = !self.busVC.view.hidden;
        self.busVC.view.hidden = YES;
        self.busVC.view.alpha = 0;
        [self.busVC.closeXButton setHidden:YES];
    }
    self.searchActive_Ivar = YES;
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    
    // Salva stato pulsanti prima di nasconderli
    _modalitaWasVisible = !self.modalitaButton.hidden;
    _searchWasVisible = !self.searchButton.hidden;
    _trackingWasVisible = !self.trackingButton.hidden;
    _settingsWasVisible = !self.settingsButton.hidden;
    _compassWasVisible = !self.compassButton.hidden;
    _logWasVisible = !self.logPanel.hidden;
    
    // Full-screen gray search page
    self.searchOverlay.hidden = NO;
    self.searchOverlay.backgroundColor = [UIColor colorWithWhite:0.16 alpha:0.95];
    self.searchBlur.backgroundColor = [UIColor colorWithWhite:0.16 alpha:0.95];
    self.searchBlur.layer.cornerRadius = 0;
    self.searchBlur.layer.maskedCorners = 0;
    self.searchBlur.layer.borderWidth = 0;
    self.searchOverlay.frame = CGRectMake(0, 0, w, h);
    self.searchBlur.frame = self.searchOverlay.bounds;
    
    // Search bar in alto, margin safe area — X integrato nella barra
    CGFloat safeTop = self.view.safeAreaInsets.top;
    self.searchBar.frame = CGRectMake(12, safeTop + 8, w - 24, 44);
    self.searchBar.showsCancelButton = YES;
    
    // Nascondi TUTTI i pulsanti mappa
    self.modalitaButton.hidden = YES;
    self.mapButton.hidden = YES;
    self.searchButton.hidden = YES;
    [self hideGoButton];
    self.settingsButton.hidden = YES;
    self.trackingButton.hidden = YES;
    self.compassButton.hidden = YES;
    self.logButton.hidden = YES;
    self.logPanel.hidden = YES;
    [UIView animateWithDuration:0.25 animations:^{
        self.searchOverlay.alpha = 1;
    } completion:^(BOOL finished) {
        [self.searchBar becomeFirstResponder];
        // Mostra destinazioni recenti
        CGFloat safeTop = self.view.safeAreaInsets.top;
        CGFloat tableY = safeTop + 8 + 44 + 8;
        CGFloat tableH = h - tableY - 20;
        self.searchResultsTable.frame = CGRectMake(0, tableY, w, tableH);
        self.searchResults = [[[SettingsStore shared] recentDestinations] mutableCopy];
        [self.searchResultsTable reloadData];
        self.searchResultsTable.hidden = (self.searchResults.count == 0);
        if (self.searchResults.count > 0) {
            [self appLog:@"📋 Mostrati %lu recenti", (unsigned long)self.searchResults.count];
        }
    }];
}

- (void)closeSearch {
    self.searchActive_Ivar = NO;
    self.busForceHidden = NO;
    
    [self.searchBar resignFirstResponder];
    [UIView animateWithDuration:0.2 animations:^{
        self.searchOverlay.alpha = 0;
    } completion:^(BOOL finished) {
        self.searchOverlay.hidden = YES;
        self.searchOverlay.alpha = 1;
        
        // Ripristina TUTTI i pulsanti allo stato salvato
        self.modalitaButton.hidden = !self->_modalitaWasVisible;
        self.mapButton.hidden = YES; // X gestito da BusViewController
        self.searchButton.hidden = !self->_searchWasVisible;
        self.settingsButton.hidden = !self->_settingsWasVisible;
        self.trackingButton.hidden = !self->_trackingWasVisible;
        self.compassButton.hidden = !self->_compassWasVisible;
        self.logButton.hidden = NO;  // log toggle sempre visibile dopo ricerca
        self.logPanel.hidden = !self->_logWasVisible;  // ripristina stato log
        
        self.searchResultsTable.hidden = YES;
        self.searchResults = [NSMutableArray array];
        [self.searchResultsTable reloadData];
        self.searchBar.text = @"";
        if (self->_busWasVisible && self.busVC) {
            self.busVC.view.hidden = NO;
            self.busVC.view.alpha = 1.0;
            [self.busVC showBus];  // ripristina layout + X completi
            self->_busWasVisible = NO;
        }
    }];
}

- (void)dismissSearch {
    if (self.searchActive_Ivar) {
        [self closeSearch];
    }
}

// Tap sul search overlay (fuori dalla barra) chiude la tastiera
- (void)setupSearchTapToDismiss {
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.searchOverlay addGestureRecognizer:tap];
}

- (void)dismissKeyboard {
    if (self.searchActive_Ivar) {
        [self.searchBar resignFirstResponder];
    }
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    [self closeSearch];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length >= 1) {
        // Call nativeSearchOSM via evaluateJavaScript — it posts results back via WKScriptMessageHandler
        NSString *escaped = [searchText stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
        escaped = [escaped stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
        NSString *js = [NSString stringWithFormat:@"nativeSearchOSM('%@')", escaped];
        [self.webView evaluateJavaScript:js completionHandler:nil];
    } else {
        // Mostra destinazioni recenti
        self.searchResults = [[[SettingsStore shared] recentDestinations] mutableCopy];
        [self.searchResultsTable reloadData];
        self.searchResultsTable.hidden = (self.searchResults.count == 0);
    }
}

#pragma mark - TableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.searchResults.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SCell" forIndexPath:indexPath];
    NSDictionary *r = self.searchResults[indexPath.row];
    UIListContentConfiguration *cfg = cell.defaultContentConfiguration;
    cfg.text = r[@"displayName"] ?: (r[@"name"] ?: @"");
    cfg.secondaryText = r[@"displaySubtitle"] ?: (r[@"full"] ?: @"");
    cfg.textProperties.color = [UIColor whiteColor];
    cfg.textProperties.font = [UIFont systemFontOfSize:15];
    cfg.secondaryTextProperties.color = [[UIColor whiteColor] colorWithAlphaComponent:0.55];
    cfg.secondaryTextProperties.font = [UIFont systemFontOfSize:11];
    cell.contentConfiguration = cfg;
    cell.backgroundColor = [UIColor clearColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *result = self.searchResults[indexPath.row];
    double lat = [result[@"lat"] doubleValue];
    double lon = [result[@"lon"] doubleValue];
    NSString *name = result[@"name"] ?: result[@"displayName"];
    if (!name) name = @"Destinazione";
    
    [self appLog:@"📍 Tappato risultato: %@ (lat=%.4f, lon=%.4f)", name, lat, lon];
    if (lat == 0 && lon == 0) {
        [self appLog:@"❌ Coordinate invalide (0, 0) — salto ricalcolo"];
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self closeSearch];
        // Call calculateRoute JS to get route to this destination
        NSString *js = [NSString stringWithFormat:@"calculateRoute(%f, %f, %f, %f, '%@')",
                        _lastLocation ? _lastLocation.coordinate.latitude : 44.49,
                        _lastLocation ? _lastLocation.coordinate.longitude : 11.34,
                        lat, lon,
                        [name stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"]];
        [self appLog:@"🧑‍💻 evaluateJS: calculateRoute(%f, %f, %f, %f, '%@')",
         _lastLocation ? _lastLocation.coordinate.latitude : 44.49,
         _lastLocation ? _lastLocation.coordinate.longitude : 11.34,
         lat, lon, name];
        [self.webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
            if (error) {
                [self appLog:@"❌ calculateRoute error: %@ (procedo comunque)", error.localizedDescription];
            } else {
                [self appLog:@"✅ calculateRoute completata (JS sta disegnando percorso)"];
            }
            // Store destination — VAI mostra quando JS chiama routeReady
            self->_pendingDestDict = @{@"lat": @(lat), @"lon": @(lon), @"name": name};
            [self appLog:@"   _pendingDestDict salvato: %@", self->_pendingDestDict];
        }];
    });
}

#pragma mark - Settings

- (void)openSettings {
    // Chiudi ricerca se attiva
    if (self.searchActive_Ivar) {
        [self closeSearch];
    }
    // Nascondi search overlay e finestra autobus
    self.searchOverlay.hidden = YES;
    self.busForceHidden = YES;
    if (self.busVC && !self.busVC.view.hidden) {
        self.busVC.view.hidden = YES;
        [self.busVC.closeXButton setHidden:YES];
        _busWasVisible = YES;
    }
    SettingsViewController *svc = [[SettingsViewController alloc] init];
    svc.mapVC = self;
    [self addChildViewController:svc];
    svc.view.frame = self.view.bounds;
    svc.view.alpha = 0;
    [self.view addSubview:svc.view];
    [svc didMoveToParentViewController:self];
    [UIView animateWithDuration:0.3 animations:^{
        svc.view.alpha = 1;
    }];
}

- (void)updateTopRightButtonForOrientation:(BOOL)isLandscape {
    if (isLandscape) {
        // Paesaggio: pulsante "Mappa" allungato (toggle bus)
        [self.mapButton setImage:[UIImage systemImageNamed:@"map.fill"] forState:UIControlStateNormal];
        [self.mapButton setTitle:@"  Mappa" forState:UIControlStateNormal];
        self.mapButton.layer.cornerRadius = 20; // pill shape
    } else {
        // Portrait: X rotondo
        [self.mapButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
        [self.mapButton setTitle:@"" forState:UIControlStateNormal];
        self.mapButton.layer.cornerRadius = 20; // round
        self.mapButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
        self.mapButton.tintColor = [UIColor whiteColor];
    }
}

- (void)topRightButtonTapped {
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    BOOL isLandscape = h < w;
    
    if (isLandscape) {
        // Landscape: toggle bus view
        [self toggleBusView];
    } else {
        // Portrait: chiudi bus se visibile, altrimenti chiudi ricerca
        if (self.busVC && !self.busVC.view.hidden) {
            [self.busVC hideBus];
        } else if (self.searchActive_Ivar) {
            [self closeSearch];
        }
    }
}

- (void)modalitaButtonTapped {
    if (self.busVC.view.hidden) {
        [self.busVC showBus];
    } else {
        [self.busVC hideBus];
    }
}

- (void)compassButtonTapped {
    // Resetta orientamento a Nord
    if (self.userTrackingWithHeading) {
        self.userTrackingWithHeading = NO;
    }
    // Call JS to reset bearing to 0
    [self.webView evaluateJavaScript:@"setMapBearing(0)" completionHandler:nil];
}

#pragma mark - Bus View

- (void)showBusView:(BOOL)show fullScreen:(BOOL)full {
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    
    if (show) {
        if (full) {
            // Landscape full screen
            self.modalitaButton.hidden = YES;
            self.mapButton.hidden = YES;
            self.searchButton.hidden = YES;
            self.settingsButton.hidden = YES;
            self.trackingButton.hidden = YES;
            self.compassButton.hidden = YES;
            self.logButton.hidden = YES;
        } else {
            // Portrait: X nel BusVC, qui gestiamo solo i pulsanti mappa
            self.modalitaButton.hidden = YES;
            self.mapButton.hidden = YES;
            self.searchButton.hidden = NO;
            self.settingsButton.hidden = NO;
            self.trackingButton.hidden = NO;
            self.compassButton.hidden = YES;
            self.logButton.hidden = NO;
            self.searchButton.frame = CGRectMake(w - 112, h * 0.35 + 20, 100, 40);
            self.trackingButton.frame = CGRectMake(w - 112, h - 120, 100, 40);
            self.settingsButton.frame = CGRectMake(w - 112, h - 60, 100, 40);
        }
    } else {
        // Bus hidden
        self.modalitaButton.hidden = NO;
        self.mapButton.hidden = YES;
        self.searchButton.hidden = NO;
        self.settingsButton.hidden = NO;
        self.trackingButton.hidden = NO;
        self.compassButton.hidden = YES;
        self.logButton.hidden = NO;
        self.modalitaButton.frame = CGRectMake(w - 112, 54, 100, 40);
        self.searchButton.frame = CGRectMake(w - 112, h * 0.35 + 10, 100, 40);
        self.trackingButton.frame = CGRectMake(w - 112, h - 120, 100, 40);
        self.settingsButton.frame = CGRectMake(w - 112, h - 60, 100, 40);
    }
}

#pragma mark - Camera

#pragma mark - Camera Slider (real-time push to JS)

- (void)pushCameraSettingsToJS {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    double alt = [ud objectForKey:@"autista_cam_alt"] ? [ud floatForKey:@"autista_cam_alt"] : 500;
    double pit = [ud objectForKey:@"autista_cam_pit"] ? [ud floatForKey:@"autista_cam_pit"] : 60;
    double off = [ud objectForKey:@"autista_cam_off"] ? [ud floatForKey:@"autista_cam_off"] : 0;
    double voff = [ud objectForKey:@"autista_cam_voff"] ? [ud floatForKey:@"autista_cam_voff"] : 0;
    double zoom = MAX(10.0, MIN(19.0, 18.0 - log2(MAX(alt, 10.0) / 100.0)));
    
    NSString *js = [NSString stringWithFormat:
        @"_camZoom=%f;_camPitch=%f;_camOffset=%f;_camVertOffset=%f;",
        zoom, pit, off, voff];
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

- (void)showSliderValue:(NSString *)text {
    if (!self.floatingSliderLabel) {
        UILabel *lbl = [[UILabel alloc] init];
        lbl.font = [UIFont boldSystemFontOfSize:32];
        lbl.textColor = [UIColor whiteColor];
        lbl.textAlignment = NSTextAlignmentCenter;
        lbl.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        lbl.layer.cornerRadius = 16;
        lbl.layer.masksToBounds = YES;
        lbl.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:lbl];
        [NSLayoutConstraint activateConstraints:@[
            [lbl.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [lbl.bottomAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:60],
            [lbl.widthAnchor constraintGreaterThanOrEqualToConstant:120],
            [lbl.heightAnchor constraintEqualToConstant:60]
        ]];
        self.floatingSliderLabel = lbl;
    }
    self.floatingSliderLabel.text = text;
    self.floatingSliderLabel.alpha = 0;
    self.floatingSliderLabel.hidden = NO;
    [UIView animateWithDuration:0.15 animations:^{
        self.floatingSliderLabel.alpha = 1.0;
    }];
}

- (void)hideSliderValue {
    if (!self.floatingSliderLabel) return;
    [UIView animateWithDuration:0.2 animations:^{
        self.floatingSliderLabel.alpha = 0;
    } completion:^(BOOL finished) {
        self.floatingSliderLabel.hidden = YES;
    }];
}

- (void)applyCameraSettings {
    // Durante navigazione/simulazione: pusha valori al JS rAF engine in tempo reale
    if (self.isNavigating || _isSimulating) {
        if (!_lastLocation) return;
        [self pushCameraSettingsToJS];
        return;
    }
    if (!_lastLocation) {
        CLLocationCoordinate2D target = CLLocationCoordinate2DMake(44.49, 11.34);
        double zoom = MAX(10.0, MIN(19.0, 18.0 - log2(MAX(self.cameraAltitude, 10.0) / 100.0)));
        NSString *js = [NSString stringWithFormat:
            @"animateCamera(%f, %f, %f, %f, %f);",
            target.latitude, target.longitude, zoom,
            0.0,
            self.cameraPitch];
        [self.webView evaluateJavaScript:js completionHandler:nil];
        return;
    }
    CLLocationDirection heading;
    if (self.isNavigating) {
        // Se in navigazione e in movimento, usa la rotta GPS. Se fermo, mantieni bearing attuale.
        if (_currentSpeed >= 3.0) {
            heading = (_lastLocation.course >= 0) ? _lastLocation.course : _cameraHeading;
        } else {
            heading = _cameraHeading; // mantiene bearing attuale, non oscilla da fermo
        }
    } else if (self.mapOrientationLocked) {
        heading = 0;
    } else {
        heading = MAX(0, _lastLocation.course);
    }
    double headingRad = heading * M_PI / 180.0;
    // Offset: cameraOffset = laterale (destra/sinistra), cameraVerticalOffset = su/giù (longitudinale)
    CLLocationCoordinate2D centerCoord = _lastLocation.coordinate;
    double latPerMeter = 1.0 / 111320.0;
    double lonPerMeter = 1.0 / (111320.0 * cos(centerCoord.latitude * M_PI / 180.0));
    
    // Laterale (perpendicolare alla direzione)
    double latOffset = self.cameraOffset * cos(headingRad + M_PI_2) * latPerMeter;
    double lonOffset = self.cameraOffset * sin(headingRad + M_PI_2) * lonPerMeter;
    
    // Longitudinale (parallelo alla direzione = su/giù)
    double latVert = self.cameraVerticalOffset * cos(headingRad) * latPerMeter;
    double lonVert = self.cameraVerticalOffset * sin(headingRad) * lonPerMeter;
    
    // Combinato
    CLLocationCoordinate2D target = CLLocationCoordinate2DMake(
        centerCoord.latitude + latOffset + latVert,
        centerCoord.longitude + lonOffset + lonVert);

    // Altitudine dinamica in base alla velocità (solo in navigazione)
    CLLocationDistance effectiveAltitude = self.cameraAltitude;
    if (self.isNavigating) {
        double speedKmh = _currentSpeed * 3.6;
        double factor = 1.0 + MAX(0, (speedKmh - 40.0) / 160.0) * 2.0;
        factor = MIN(factor, 3.0);
        effectiveAltitude = self.cameraAltitude * factor;
    }

    // BUGFIX: da fermo in navigazione NON aggiornare _cameraHeading — evitava rotazione di 30° ogni 2s!
    if (self.isNavigating && _currentSpeed < 3.0) {
        _cameraHeading = heading; // mantieni esattamente, senza aggiungere offset
    } else {
        _cameraHeading = heading; // mantieni esattamente
    }
    
    // JS calls for camera - zoom based on altitude, max zoom 21.5 per ~10m reali
    double zoom = MAX(10.0, MIN(21.5, 18.0 - log2(MAX(effectiveAltitude, 10.0) / 100.0)));
    // Use single animateCamera to avoid conflicting animations
    NSString *js = [NSString stringWithFormat:
        @"animateCamera(%f, %f, %f, %f, %f);",
        target.latitude, target.longitude, zoom,
        _cameraHeading,
        self.cameraPitch];
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

- (void)applyMenuOpacity {
    CGFloat a = 0.15 + self.menuOpacity * 0.55;
    self.mapButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:a];
    self.modalitaButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:a];
    self.searchButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:a];
    self.trackingButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:a];
    self.settingsButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:a];
    self.compassButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:a];
    [self.busVC applyGlassOpacity:a];
}

#pragma mark - Preview Route

- (void)previewRouteTo:(NSDictionary *)destinationDict {
    // destinationDict = {lat, lon, name}
    double destLat = [destinationDict[@"lat"] doubleValue];
    double destLon = [destinationDict[@"lon"] doubleValue];
    NSString *destName = destinationDict[@"name"] ?: @"Destinazione";
    
    double fromLat = _lastLocation ? _lastLocation.coordinate.latitude : 44.49;
    double fromLon = _lastLocation ? _lastLocation.coordinate.longitude : 11.34;
    
    NSString *escapedName = [destName stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    NSString *js = [NSString stringWithFormat:
        @"calculateRoute(%f, %f, %f, %f, '%@')",
        fromLat, fromLon, destLat, destLon, escapedName];
    
    [self.webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        if (error) {
            [self showAlert:@"Errore navigazione" message:error.localizedDescription];
            return;
        }
        if (!result) {
            [self showAlert:@"Errore navigazione" message:@"Nessun percorso trovato"];
            return;
        }
        // result is a JSON string with route info
        NSString *routeJSON = nil;
        if ([result isKindOfClass:[NSString class]]) {
            routeJSON = (NSString *)result;
        } else if ([result isKindOfClass:[NSDictionary class]]) {
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
            if (jsonData) routeJSON = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_pendingDestDict = destinationDict;
            [self showGoButton];
        });
    }];
}

- (void)showGoButton {
    if (self.isNavigating || _isSimulating) {
        [self appLog:@"⏭️ showGoButton saltato: navigazione/simulazione attiva"];
        return;
    }
    if (self->_goButton) return;
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    UIButton *go = [UIButton buttonWithType:UIButtonTypeSystem];
    go.frame = CGRectMake(w/2 - 70, h - 150, 140, 50);
    go.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    go.backgroundColor = [UIColor colorWithRed:0.0 green:0.45 blue:0.9 alpha:0.9];
    go.layer.cornerRadius = 25;
    go.tintColor = [UIColor whiteColor];
    go.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    [go setTitle:@"VAI" forState:UIControlStateNormal];
    [go addTarget:self action:@selector(goButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:go];
    self->_goButton = go;
    
    // Pulsante Simulazione — più grande per non sbagliare
    UIButton *sim = [UIButton buttonWithType:UIButtonTypeSystem];
    sim.frame = CGRectMake(w/2 - 70, h - 90, 140, 42);
    sim.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    sim.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.2 alpha:0.95];
    sim.layer.cornerRadius = 21;
    sim.tintColor = [UIColor whiteColor];
    sim.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [sim setTitle:@"▶ Simulazione" forState:UIControlStateNormal];
    [sim addTarget:self action:@selector(simulationButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:sim];
    self->_simButton = sim;
}

- (void)hideGoButton {
    [self->_goButton removeFromSuperview];
    self->_goButton = nil;
    [self->_simButton removeFromSuperview];
    self->_simButton = nil;
    
    // Ferma simulazione se attiva
    if (_isSimulating) {
        _isSimulating = NO;
        [_simTimer invalidate]; _simTimer = nil;
        _simCoords = nil;
        _simIndex = 0;
    }
}

- (void)goButtonTapped {
    [self appLog:@"🟢 VAI premuto"];
    [self hideGoButton];
    if (self->_pendingDestDict) {
        [self appLog:@"   pendingDestDict ok: %@", self->_pendingDestDict];
        // Salva nei recenti
        [[SettingsStore shared] addRecentDestination:self->_pendingDestDict];
        [self startNavigationTo:self->_pendingDestDict];
        self->_pendingDestDict = nil;
        [self appLog:@"   pendingDestDict azzerato"];
        // Avvia simulazione lungo la route
        [self fireSimulation];
    } else {
        [self appLog:@"❌ VAI: _pendingDestDict è NIL"];
    }
}

#pragma mark - Simulazione

- (void)simulationButtonTapped {
    [self appLog:@"🟢 Simulazione premuta"];
    [self hideGoButton];
    if (!self->_pendingDestDict) {
        [self appLog:@"❌ Simulazione: _pendingDestDict è NIL"];
        return;
    }
    
    NSDictionary *dest = [self->_pendingDestDict copy];
    [[SettingsStore shared] addRecentDestination:dest];
    self->_pendingDestDict = nil;
    
    // _simCoords è già popolato da simCoords message handler (quando OSRM ha risposto)
    if (!_simCoords || _simCoords.count < 2) {
        [self appLog:@"⚠️ _simCoords vuoto — calcolo route OSRM..."];
        double fromLat = _lastLocation ? _lastLocation.coordinate.latitude : 44.49;
        double fromLon = _lastLocation ? _lastLocation.coordinate.longitude : 11.34;
        double toLat = [dest[@"lat"] doubleValue];
        double toLon = [dest[@"lon"] doubleValue];
        NSString *name = dest[@"name"] ?: @"";
        NSString *escaped = [name stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
        NSString *calcJs = [NSString stringWithFormat:
            @"calculateRoute(%f, %f, %f, %f, '%@')",
            fromLat, fromLon, toLat, toLon, escaped];
        [self.webView evaluateJavaScript:calcJs completionHandler:^(id r, NSError *e) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appLog:@"⚠️ OSRM completion — _simCoords count=%lu", (unsigned long)(_simCoords ? [_simCoords count] : 0)];
                if (_simCoords && _simCoords.count >= 2) {
                    [self startNavigationTo:dest];
                    [self fireSimulation];
                } else {
                    [self appLog:@"❌ Simulazione: impossibile ottenere coordinate"];
                }
            });
        }];
        return;
    }
    
    [self appLog:@"✅ _simCoords già pronto (%lu coordinate) — avvio subito", (unsigned long)[_simCoords count]];
    [self startNavigationTo:dest];
    [self fireSimulation];
}

- (void)fireSimulation {
    if (!_simCoords || _simCoords.count < 2) {
        [self appLog:@"❌ fireSimulation: _simCoords insufficienti (count=%lu)", (unsigned long)[_simCoords count]];
        return;
    }
    _simIndex = 0;
    _posUpdateCounter = 0;
    _isSimulating = YES;
    [self appLog:@"🔥 fireSimulation: %lu coord, stepPerTick=%.3f m", (unsigned long)[_simCoords count], _simStepPerTick];
    NSDictionary *first = _simCoords[0];
    double firstLat = [first[@"lat"] doubleValue];
    double firstLon = [first[@"lon"] doubleValue];
    [self appLog:@"   prima posizione: %.6f, %.6f", firstLat, firstLon];
    [self setSimulatedLocation:firstLat lon:firstLon course:0];
    // FORZA pushPosition + startNavEngine SUBITO (senza aspettare 12 tick)
    [self pushPositionToJS];
    [self.webView evaluateJavaScript:@"if(!_navEngineRunning)startNavEngine();" completionHandler:nil];
    _simTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/60.0 target:self selector:@selector(simTick) userInfo:nil repeats:YES];
    [self appLog:@"✅ Simulazione avviata: %lu coord, %.3f m/tick, 60fps", (unsigned long)[_simCoords count], _simStepPerTick];
}

- (void)setSimulatedLocation:(double)lat lon:(double)lon course:(double)course {
    // Aggiorna _lastLocation con posizione simulata
    CLLocation *loc = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat, lon)
                                                    altitude:0
                                          horizontalAccuracy:5
                                            verticalAccuracy:5
                                                      course:course
                                                       speed:4.17
                                                   timestamp:[NSDate date]];
    _prevLocation = _lastLocation;
    _lastLocation = loc;
    _currentSpeed = 4.17;
    _currentCourse = course;
    
    // NavPush: invia pushPosition ogni ~50ms (più frequente per startup veloce)
    // Il JS rAF engine bufferizza e interpola a 60fps
    static int _camCounter = 0;
    _camCounter++;
    if (_camCounter >= 3) {
        _camCounter = 0;
        [self pushPositionToJS];
    }
}

- (void)simTick {
    if (!_isSimulating || !_simCoords || _simIndex >= (NSInteger)[_simCoords count] - 1) {
        if (_isSimulating) {
            [self appLog:@"✅ Simulazione completata"];
            _isSimulating = NO;
            [_simTimer invalidate]; _simTimer = nil;
            _simCoords = nil;
            [self.webView evaluateJavaScript:@"stopNavEngine();" completionHandler:nil];
        }
        return;
    }
    
    double remain = _simStepPerTick; // metri per tick
    
    // PARTENZA dalla posizione CORRENTE (accumulata dai tick precedenti)
    double curLat, curLon;
    if (_lastLocation) {
        curLat = _lastLocation.coordinate.latitude;
        curLon = _lastLocation.coordinate.longitude;
    } else {
        NSDictionary *first = _simCoords.firstObject;
        curLat = [first[@"lat"] doubleValue];
        curLon = [first[@"lon"] doubleValue];
    }
    
    while (remain > 0 && _simIndex < (NSInteger)[_simCoords count] - 1) {
        NSDictionary *nextDict = _simCoords[_simIndex + 1];
        double nextLat = [nextDict[@"lat"] doubleValue];
        double nextLon = [nextDict[@"lon"] doubleValue];
        
        // Distanza da cur a next
        double dlat = (nextLat - curLat) * M_PI / 180.0;
        double dlon = (nextLon - curLon) * M_PI / 180.0;
        double a = sin(dlat/2) * sin(dlat/2) + cos(curLat * M_PI / 180.0) * cos(nextLat * M_PI / 180.0) * sin(dlon/2) * sin(dlon/2);
        double c = 2 * atan2(sqrt(a), sqrt(1-a));
        double distToNext = 6371000 * c; // metri
        
        if (distToNext <= remain + 0.001) {
            // RAGGIUNTO il prossimo punto! Avanza _simIndex
            remain -= distToNext;
            _simIndex++;
            curLat = nextLat;
            curLon = nextLon;
        } else {
            // Interpola lungo il segmento da posizione corrente
            double frac = remain / distToNext;
            curLat = curLat + (nextLat - curLat) * frac;
            curLon = curLon + (nextLon - curLon) * frac;
            remain = 0;
        }
    }
    
    // Calcola rotta (bearing) verso il prossimo punto
    double course = 0;
    if (_simIndex < (NSInteger)[_simCoords count] - 1) {
        NSDictionary *next = _simCoords[_simIndex + 1];
        double nLat = [next[@"lat"] doubleValue] * M_PI / 180.0;
        double nLon = [next[@"lon"] doubleValue] * M_PI / 180.0;
        double cLat = curLat * M_PI / 180.0;
        double cLon = curLon * M_PI / 180.0;
        double dLon = nLon - cLon;
        double y = sin(dLon) * cos(nLat);
        double x = cos(cLat) * sin(nLat) - sin(cLat) * cos(nLat) * cos(dLon);
        course = atan2(y, x) * 180.0 / M_PI;
        if (course < 0) course += 360;
    }
    
    [self appLog:@"  🧭 course=%.0f → setSimLoc(%.6f, %.6f)", course, curLat, curLon];
    [self setSimulatedLocation:curLat lon:curLon course:course];
    
    if (_simIndex >= (NSInteger)[_simCoords count] - 1) {
        [self appLog:@"✅ Simulazione completata"];
        _isSimulating = NO;
        [_simTimer invalidate]; _simTimer = nil;
        _simCoords = nil;
    }
}

#pragma mark - Navigation

- (void)startNavigationTo:(NSDictionary *)destinationDict {
    [self appLog:@"🟢 startNavigationTo:"];
    self.isNavigating = YES;
    self.currentStepIndex = 0;
    self.distanceRemaining = 0;
    self.etaSeconds = 0;
    self.userTracking = YES;
    self.userTrackingWithHeading = YES;
    [self updateTrackingButton];
    // navBar nascosta — info nella pill via in basso
    self.navBar.hidden = YES;
    self.stopNavButton.hidden = NO;
    
    // Mostra pill via con fade-in
    if (self.roadNameLabel) {
        self.roadNameLabel.hidden = NO;
        self.roadNameLabel.alpha = 0;
        [UIView animateWithDuration:0.3 animations:^{
            self.roadNameLabel.alpha = 1;
        }];
    }
    
    // Smooth position timer 20 fps per navigazione fluida
    _isInterpolating = NO;
    _interpStartTime = 0;
    [self startSmoothTimer];
    
    // Avvicina camera SUBITO con le impostazioni salvate dall'utente
    if (_lastLocation) {
        [self appLog:@"   GPS: %f,%f course=%f", _lastLocation.coordinate.latitude, _lastLocation.coordinate.longitude, _lastLocation.course];
        // Converte altitude in zoom: più bassa = zoom più alto
        double alt = MAX(self.cameraAltitude, 10.0);
        double zoom = MAX(10.0, MIN(19.0, 18.0 - log2(alt / 100.0)));
        double pitch = self.cameraPitch > 0 ? self.cameraPitch : 60.0;
        double bearing = _lastLocation.course >= 0 ? _lastLocation.course : _cameraHeading;
        NSString *flyJs = [NSString stringWithFormat:
            @"animateCamera(%f, %f, %f, %f, %f);",
            _lastLocation.coordinate.latitude,
            _lastLocation.coordinate.longitude,
            zoom, bearing, pitch];
        [self.webView evaluateJavaScript:flyJs completionHandler:nil];
    } else {
        [self appLog:@"   ⚠️ GPS NON disponibile (no animateCamera)"];
    }
    
    [self appLog:@"   applyCameraSettings..."];
    [self applyCameraSettings];
    [self appLog:@"   startNavigation() JS..."];
    [self.webView evaluateJavaScript:@"startNavigation()" completionHandler:^(id res, NSError *err) {
        if (err) [self appLog:@"   ⚠️ startNavigation JS error: %@", err.localizedDescription];
        else [self appLog:@"   ✅ startNavigation() JS ok"];
    }];
    
    [_navTimer invalidate];
    _navTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(navTick) userInfo:nil repeats:YES];
    [self appLog:@"   navTimer partito"];
    [self updateNavUI];
    [self appLog:@"✅ Navigazione avviata completa"];
}

- (void)endNavigation {
    self.isNavigating = NO;
    [_navTimer invalidate]; _navTimer = nil;
    
    // Clear JS route, destination, e ferma rAF engine
    [self.webView evaluateJavaScript:@"endNavigation(); clearRoute(); clearDestination(); stopNavEngine();" completionHandler:^(id res, NSError *err) {
        if (err) [self appLog:@"endNavigation JS error: %@", err.localizedDescription];
    }];
    
    self.navBar.hidden = YES;
    self.stopNavButton.hidden = YES;
    // Nascondi pill via
    if (self.roadNameLabel && !self.roadNameLabel.hidden) {
        [UIView animateWithDuration:0.25 animations:^{
            self.roadNameLabel.alpha = 0;
        } completion:^(BOOL fin) {
            self.roadNameLabel.hidden = YES;
            self.roadStreetLabel.text = @"";
            self.roadETALabel.text = @"";
            self.roadTimeLabel.text = @"";
            self.roadDistLabel.text = @"";
        }];
    }
    
    [self hideGoButton];
    self.userTracking = NO;
    self.userTrackingWithHeading = NO;
    [self updateTrackingButton];
    _isInterpolating = NO;
    [self stopSmoothTimer];
}

/// Timer 2-secondi — ottiene stato navigazione da JS e aggiorna UI
- (void)navTick {
    if (!self.isNavigating || !_lastLocation) return;
    
    [self.webView evaluateJavaScript:@"getNavState()" completionHandler:^(id result, NSError *error) {
        if (error || !result) return;
        
        NSDictionary *state = nil;
        if ([result isKindOfClass:[NSString class]]) {
            NSData *data = [(NSString *)result dataUsingEncoding:NSUTF8StringEncoding];
            state = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        } else if ([result isKindOfClass:[NSDictionary class]]) {
            state = (NSDictionary *)result;
        }
        
        if (![state isKindOfClass:[NSDictionary class]]) return;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *instruction = state[@"instruction"];
            if (instruction) self.instructionLabel.text = instruction;
            
            id distVal = state[@"distanceRemaining"];
            if (distVal) self.distanceRemaining = [distVal doubleValue];
            
            id etaVal = state[@"etaSeconds"];
            if (etaVal) self.etaSeconds = [etaVal doubleValue];
            
            id speedVal = state[@"speedKmh"];
            if (speedVal) {
                double kmh = [speedVal doubleValue];
                // Keep GPS speed if available
                if (_currentSpeed < 0.1) _currentSpeed = kmh / 3.6;
            }
            
            [self updateNavUI];
            
            // Check for arrival
            NSNumber *arrived = state[@"arrived"];
            if ([arrived boolValue]) {
                [self announceArrival];
            }
        });
    }];
    
    // Ricalcolo se fuori rotta — via JS snapToRoute
    [self.webView evaluateJavaScript:[NSString stringWithFormat:@"snapToRoute(%f, %f)",
        _lastLocation.coordinate.latitude, _lastLocation.coordinate.longitude]
        completionHandler:^(id result, NSError *error) {
            if (error || !result) return;
            // result is the snapped coordinate or distance from route
            // If distance > threshold, recalculate
            if ([result isKindOfClass:[NSNumber class]]) {
                double dist = [result doubleValue];
                if (dist > 5.0 && !self->_isRecalculating) {
                    [self recalculateRoute];
                }
            }
        }];
    
    [self applyCameraSettings];
    [self applyAllSettings];
}

- (void)updateNavUI {
    self.distanceLabel.text = self.distanceRemaining >= 1000
        ? [NSString stringWithFormat:@"%.1f km rimanenti", self.distanceRemaining/1000.0]
        : [NSString stringWithFormat:@"%.0f m rimanenti", self.distanceRemaining];
    NSInteger mins = (NSInteger)(self.etaSeconds/60);
    self.etaLabel.text = mins >= 60
        ? [NSString stringWithFormat:@"🕐 %ldh %ldm", (long)(mins/60), (long)(mins%60)]
        : [NSString stringWithFormat:@"🕐 %ld min", (long)MAX(1,mins)];
    double kmh = _currentSpeed * 3.6;
    self.speedLabel.text = kmh > 2 ? [NSString stringWithFormat:@"%.0f", kmh] : @"--";
}

- (void)speakCurrentInstruction {
    if (!self.isNavigating) return;
    SettingsStore *st = [SettingsStore shared];
    if (!st.voiceGuidance) return;
    NSString *txt = self.instructionLabel.text;
    if (!txt || txt.length == 0) return;
    // Non ripetere la stessa istruzione
    if ([txt isEqualToString:_lastSpokenInstruction]) return;
    _lastSpokenInstruction = txt;
    txt = [txt stringByReplacingOccurrencesOfString:@"<[^>]+>" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0,txt.length)];
    AVSpeechUtterance *u = [AVSpeechUtterance speechUtteranceWithString:txt];
    NSString *lang = st.voiceLanguage ?: @"it-IT";
    u.voice = [AVSpeechSynthesisVoice voiceWithLanguage:lang];
    u.rate = 0.5; u.volume = st.voiceVolume;
    [self.speechSynthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    [self.speechSynthesizer speakUtterance:u];
}

- (void)announceArrival {
    self.isNavigating = NO; [_navTimer invalidate]; _navTimer = nil;
    SettingsStore *st = [SettingsStore shared];
    [self.webView evaluateJavaScript:@"endNavigation()" completionHandler:nil];
    if (!st.voiceGuidance) return;
    AVSpeechUtterance *u = [AVSpeechUtterance speechUtteranceWithString:@"Sei arrivato a destinazione!"];
    u.voice = [AVSpeechSynthesisVoice voiceWithLanguage:(st.voiceLanguage ?: @"it-IT")];
    u.rate = 0.45; u.volume = st.voiceVolume;
    [self.speechSynthesizer speakUtterance:u];
    [self showAlert:@"Arrivato! 🎉" message:@"Sei arrivato a destinazione."];
    [self endNavigation];
}

- (void)generateArrow3D {
    // Freccia PNG da v6.25, ridotta 24×31pt
    NSString *path = [[NSBundle mainBundle] pathForResource:@"arrow" ofType:@"png"];
    if (path) {
        self.arrow3D = [UIImage imageWithContentsOfFile:path];
    }
    // Fallback di sicurezza
    if (!self.arrow3D) {
        CGFloat w = 24, h = 31;
        CGSize sz = CGSizeMake(w, h);
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:sz];
        self.arrow3D = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            UIBezierPath *arrow = [UIBezierPath bezierPath];
            [arrow moveToPoint:CGPointMake(w/2, 0)];
            [arrow addLineToPoint:CGPointMake(w, h*0.38)];
            [arrow addLineToPoint:CGPointMake(w*0.62, h*0.38)];
            [arrow addLineToPoint:CGPointMake(w*0.62, h)];
            [arrow addLineToPoint:CGPointMake(w*0.38, h)];
            [arrow addLineToPoint:CGPointMake(w*0.38, h*0.38)];
            [arrow addLineToPoint:CGPointMake(0, h*0.38)];
            [arrow closePath];
            [[UIColor colorWithRed:0.0 green:0.35 blue:0.9 alpha:1.0] setFill];
            [arrow fill];
        }];
    }
}

#pragma mark - Buttons

- (void)trackingButtonTapped {
    if (!self.userTracking) {
        // Attiva tracking e centra SUBITO sulla posizione
        self.userTracking = YES;
        self.userTrackingWithHeading = NO;
        if (_lastLocation) {
            [self.webView evaluateJavaScript:@"centerOnUser()" completionHandler:nil];
        }
    } else if (!self.userTrackingWithHeading) {
        // Attiva heading
        self.userTrackingWithHeading = YES;
    } else {
        // Disattiva
        self.userTracking = NO;
        self.userTrackingWithHeading = NO;
    }
    [self updateTrackingButton];
}

- (void)updateTrackingButton {
    NSString *icon;
    if (self.userTrackingWithHeading) {
        icon = @"location.north.line.fill";
    } else if (self.userTracking) {
        icon = @"location.fill";
    } else {
        icon = @"location";
    }
    [self.trackingButton setImage:[UIImage systemImageNamed:icon] forState:UIControlStateNormal];
}

#pragma mark - MapView Delegate (removed — all JS now)

#pragma mark - Location

/// Restituisce la coordinata più vicina sul percorso (JS delegated)
- (CLLocationCoordinate2D)closestPointOnRouteToCoordinate:(CLLocationCoordinate2D)coord {
    // JS snapToRoute returns snapped coordinate
    __block CLLocationCoordinate2D result = coord;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSString *js = [NSString stringWithFormat:@"snapToRoute(%f, %f)", coord.latitude, coord.longitude];
    [self.webView evaluateJavaScript:js completionHandler:^(id res, NSError *err) {
        if (!err && res && [res isKindOfClass:[NSString class]]) {
            NSData *data = [(NSString *)res dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *pt = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([pt isKindOfClass:[NSDictionary class]]) {
                result = CLLocationCoordinate2DMake([pt[@"lat"] doubleValue], [pt[@"lon"] doubleValue]);
            }
        }
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)));
    return result;
}

/// Restituisce la coordinata N metri più avanti sul percorso (JS delegated)
- (CLLocationCoordinate2D)coordinateOnRouteAheadOf:(CLLocationCoordinate2D)currentCoord meters:(CLLocationDistance)lookAhead {
    __block CLLocationCoordinate2D result = currentCoord;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSString *js = [NSString stringWithFormat:@"coordinateAheadOnRoute(%f, %f, %f)",
                    currentCoord.latitude, currentCoord.longitude, lookAhead];
    [self.webView evaluateJavaScript:js completionHandler:^(id res, NSError *err) {
        if (!err && res && [res isKindOfClass:[NSString class]]) {
            NSData *data = [(NSString *)res dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *pt = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([pt isKindOfClass:[NSDictionary class]]) {
                result = CLLocationCoordinate2DMake([pt[@"lat"] doubleValue], [pt[@"lon"] doubleValue]);
            }
        }
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)));
    return result;
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    // Durante la simulazione, NON sovrascrivere la posizione simulata con GPS reale!
    if (_isSimulating) {
        return;
    }
    _prevLocation = _lastLocation;
    _lastLocation = locations.lastObject;
    _currentSpeed = MAX(0, _lastLocation.speed);
    _currentCourse = _lastLocation.course;
    
    // Snap GPS alla strada via JS
    CLLocationCoordinate2D snapped = _lastLocation.coordinate;
    if (self.isNavigating) {
        __block CLLocationCoordinate2D jsSnapped = snapped;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        NSString *js = [NSString stringWithFormat:@"snapToRoute(%f, %f)", _lastLocation.coordinate.latitude, _lastLocation.coordinate.longitude];
        [self.webView evaluateJavaScript:js completionHandler:^(id res, NSError *err) {
            if (!err && res && [res isKindOfClass:[NSString class]]) {
                NSData *data = [(NSString *)res dataUsingEncoding:NSUTF8StringEncoding];
                NSDictionary *pt = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if ([pt isKindOfClass:[NSDictionary class]]) {
                    jsSnapped = CLLocationCoordinate2DMake([pt[@"lat"] doubleValue], [pt[@"lon"] doubleValue]);
                }
            }
            dispatch_semaphore_signal(sem);
        }];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)));
        snapped = jsSnapped;
    }
    
    if (!_hasSnapped) {
        // Primo fix: inizializza entrambi allo stesso punto
        _prevSnapped = snapped;
        _lastSnapped = snapped;
    } else {
        _prevSnapped = _lastSnapped;
        _lastSnapped = snapped;
    }
    _hasSnapped = YES;
    _interpStart = [[NSDate date] timeIntervalSince1970];
    
    // Posizione fluida: se nav reale, interpola tra punti GPS a 20 fps
    if (self.isNavigating && !_isSimulating) {
        _interpFrom = _isInterpolating ? _interpTo : snapped;
        _interpTo = snapped;
        _interpStartTime = [[NSDate date] timeIntervalSince1970];
        _isInterpolating = YES;
        // smoothTick si occupa di inviare posizione via pushPosition
    } else {
        // Non in navigazione: aggiorna subito via pushPosition
        [self pushPositionToJSWithLat:snapped.latitude lon:snapped.longitude course:_currentCourse];
    }
    
    // Camera solo se in movimento (>7 km/h)
    if (self.userTracking && _lastLocation) {
        if (self.userTrackingWithHeading && _lastLocation.course >= 0 && _currentSpeed > 2.0) {
            [self applyCameraSettings];
        } else if (!self.userTrackingWithHeading) {
            NSString *js = [NSString stringWithFormat:@"centerOnUser()"];
            [self.webView evaluateJavaScript:js completionHandler:nil];
        }
    }
    [self fetchBusStopsIfNeeded];
}

#pragma mark - Smooth Position (20 fps)

- (void)startSmoothTimer {
    [_smoothTimer invalidate];
    _smoothTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/60.0 target:self selector:@selector(smoothTick) userInfo:nil repeats:YES];
}

- (void)stopSmoothTimer {
    [_smoothTimer invalidate];
    _smoothTimer = nil;
}

- (void)smoothTick {
    // Se simulazione attiva, simTick già gestisce posizione
    if (_isSimulating) return;
    if (!self.isNavigating) return;
    
    // Interpolazione GPS reale
    if (_isInterpolating) {
        NSTimeInterval elapsed = [[NSDate date] timeIntervalSince1970] - _interpStartTime;
        double t = MIN(elapsed / 0.5, 1.0); // interpola in 0.5 secondi
        t = t * t * (3.0 - 2.0 * t); // smoothstep
        
        double lat = _interpFrom.latitude + (_interpTo.latitude - _interpFrom.latitude) * t;
        double lon = _interpFrom.longitude + (_interpTo.longitude - _interpFrom.longitude) * t;
        
        double course = _currentCourse;
        if (course < 0 && t > 0.01) {
            course = atan2(_interpTo.latitude - _interpFrom.latitude, _interpTo.longitude - _interpFrom.longitude) * 180.0 / M_PI;
            if (course < 0) course += 360;
        }
        
        // Push ogni 12 tick (5fps) — JS rAF interpola
        static int _gpsFrame = 0;
        _gpsFrame++;
        if (_gpsFrame >= 12) {
            _gpsFrame = 0;
            [self pushPositionToJSWithLat:lat lon:lon course:course];
        }
        
        if (t >= 1.0) {
            _isInterpolating = NO;
        }
    }
    
    // Camera non serve più — JS rAF fa jumpTo a 60fps
}

#pragma mark - NavEngine Push (5fps → JS rAF)

- (void)pushPositionToJS {
    // Usa _hasSimPos durante simulazione, altrimenti _lastLocation
    double lat, lon, course;
    if (_hasSimPos) {
        lat = _simLat;
        lon = _simLon;
        course = _simCourse;
    } else if (_lastLocation) {
        lat = _lastLocation.coordinate.latitude;
        lon = _lastLocation.coordinate.longitude;
        course = _lastLocation.course >= 0 ? _lastLocation.course : _currentCourse;
    } else {
        return;
    }
    [self pushPositionToJSWithLat:lat lon:lon course:course];
}

- (void)pushPositionToJSWithLat:(double)lat lon:(double)lon course:(double)course {
    double ts = [[NSDate date] timeIntervalSince1970] * 1000.0;
    NSString *js = [NSString stringWithFormat:@"pushPosition(%f,%f,%f,%f)", lat, lon, course, ts];
    [self.webView evaluateJavaScript:js completionHandler:nil];
    // Avvia rAF engine se non già attivo
    [self.webView evaluateJavaScript:@"if(!_navEngineRunning)startNavEngine();" completionHandler:nil];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading {
    if (newHeading.headingAccuracy < 0) return;
    _currentHeading = newHeading.trueHeading;
    // Rotazione freccia + camera gestita dal JS rAF engine
    // Ruota bussola custom (native)
    [UIView animateWithDuration:0.25 animations:^{
        self.compassButton.transform = CGAffineTransformMakeRotation(-newHeading.trueHeading * M_PI / 180.0);
    }];
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    if (manager.authorizationStatus == kCLAuthorizationStatusAuthorizedWhenInUse ||
        manager.authorizationStatus == kCLAuthorizationStatusAuthorizedAlways) {
        [self.locationManager startUpdatingLocation];
    }
}

- (void)settingsDidClose {
    self.busForceHidden = NO;
    if (_busWasVisible && self.busVC) {
        self.busVC.view.hidden = NO;
        _busWasVisible = NO;
    }
    [self applyAllSettings];
}

- (void)applyNavigationSettings:(NSDictionary *)req {
    SettingsStore *st = [SettingsStore shared];
    // Note: navigation settings are handled by JS OSRM routing
    // Alt routes, transport mode etc are configured in JS
}

- (void)mapSettingsChanged {
    SettingsStore *st = [SettingsStore shared];
    [self appLog:@"▶ SETTINGS: night=%d dark=%d type=%ld bright=%.2f", st.nightMode, st.darkTheme, (long)st.mapType, st.mapBrightness];
    [self applyAllSettings];
}

- (void)refreshBuildingsVisibilityIfNeeded {
    // Buildings handled in applyAllSettings with correct MapLibre layer names
    // Map type also handled in applyAllSettings — no duplicate call needed
}

- (void)applyAllSettings {
    SettingsStore *st = [SettingsStore shared];
    
    // === MAPPA ===
    // Dark mode: solo modalità notturna (non tema scuro UI)
    if (st.nightMode) {
        [self appLog:@"→ setMapType(1) darkMode"];
        [self.webView evaluateJavaScript:@"setMapType(1)" completionHandler:^(id r, NSError *err) {
            if (err) [self appLog:@"❌ setMapType(1) ERR: %@", err.localizedDescription];
            else [self appLog:@"✓ setMapType(1) fatto"];
        }];
    } else {
        long mt = (long)st.mapType;
        [self appLog:@"→ setMapType(%ld) giorno", mt];
        [self.webView evaluateJavaScript:[NSString stringWithFormat:@"setMapType(%ld)", mt] completionHandler:^(id r, NSError *err) {
            if (err) [self appLog:@"❌ setMapType(%ld) ERR: %@", mt, err.localizedDescription];
            else [self appLog:@"✓ setMapType(%ld) fatto", mt];
        }];
    }
    
    // Mappa luminosita - from SettingsStore
    [self appLog:@"→ setMapBrightness(%.2f)", st.mapBrightness];
    [self.webView evaluateJavaScript:[NSString stringWithFormat:@"setMapBrightness(%f)", st.mapBrightness] completionHandler:^(id r, NSError *err) {
        if (err) [self appLog:@"❌ setMapBrightness ERR: %@", err.localizedDescription];
        else [self appLog:@"✓ setMapBrightness fatto"];
    }];
    
    // POI Labels — toggle via MapLibre
    if ([st.poiLabels isEqualToString:@"Nessuna"]) {
        [self.webView evaluateJavaScript:@"try{map.setLayoutProperty('poi_r20','visibility','none');}catch(e){} try{map.setLayoutProperty('poi_r7','visibility','none');}catch(e){} try{map.setLayoutProperty('poi_transit','visibility','none');}catch(e){}" completionHandler:nil];
    } else {
        [self.webView evaluateJavaScript:@"try{map.setLayoutProperty('poi_r20','visibility','visible');}catch(e){} try{map.setLayoutProperty('poi_r7','visibility','visible');}catch(e){} try{map.setLayoutProperty('poi_transit','visibility','visible');}catch(e){}" completionHandler:nil];
    }
    
    [self refreshBuildingsVisibilityIfNeeded];
    
    // Orientamento mappa
    self.mapOrientationLocked = [st.mapOrientation isEqualToString:@"Nord in alto"];
    
    // === VISUALE ===
    BOOL dark = st.nightMode || st.darkTheme;
    self.view.backgroundColor = dark ? [UIColor blackColor] : [UIColor colorWithWhite:0.15 alpha:1.0];
    
    // Bussola nativa MapLibre JS (bussola custom nascosta)
    self.compassButton.hidden = YES;
    [self applyMenuOpacity];
    
    // Mostra edifici 3D (MapLibre — nascondi/mostra layer building)
    if (st.show3DBuildings) {
        [self.webView evaluateJavaScript:@"try{map.setLayoutProperty('building','visibility','visible');}catch(e){} try{map.setLayoutProperty('building-3d','visibility','visible');}catch(e){}" completionHandler:nil];
    } else {
        [self.webView evaluateJavaScript:@"try{map.setLayoutProperty('building','visibility','none');}catch(e){} try{map.setLayoutProperty('building-3d','visibility','none');}catch(e){}" completionHandler:nil];
    }
    
    // Dimensione testo
    CGFloat fontSize;
    if ([st.textSize isEqualToString:@"Grande"]) fontSize = 20;
    else if ([st.textSize isEqualToString:@"Molto grande"]) fontSize = 24;
    else fontSize = 18;
    self.instructionLabel.font = [UIFont boldSystemFontOfSize:fontSize];
    self.distanceLabel.font = [UIFont systemFontOfSize:fontSize-4];
    self.etaLabel.font = [UIFont boldSystemFontOfSize:fontSize-1];
    
    self.speedLabel.hidden = !st.showSpeedometer;
    self.etaLabel.hidden = !st.showETA;
    
    // Scala (MapLibre nativa)
    if (st.showScale) {
        [self.webView evaluateJavaScript:@"try{toggleScale(true)}catch(e){}" completionHandler:nil];
    } else {
        [self.webView evaluateJavaScript:@"try{toggleScale(false)}catch(e){}" completionHandler:nil];
    }
    
    if (st.reducedAnimations) {
        [UIView setAnimationsEnabled:NO];
    } else {
        [UIView setAnimationsEnabled:YES];
    }
    
    // Traffico - non disponibile in MapLibre gratuito
    // showTraffic toggle esiste ma non ha effetto (nessun dato traffico gratuito)
    
    // === VOCE ===
    // voiceGuidance e voiceVolume applicati in speakCurrentInstruction/announceArrival
    
    // === OPACITÀ MENU ===
    [self applyMenuOpacity];
    
    // === FRECCIA ===
    [self applyArrowTransform];
    
    // === FERMATE AUTOBUS ===
    [self applyBusStopsVisibility];
    [self fetchBusStopsIfNeeded];
    
    // === CAMERA ===
    if (_lastLocation) {
        [self applyCameraSettings];
    }
}

- (void)showAlert:(NSString *)title message:(NSString *)msg {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - Bus Stops

- (void)applyBusStopsVisibility {
    BOOL show = [SettingsStore shared].showBusStops;
    // Bus stop visibility is managed by JS markers
    // Pass visibility state to JS
    NSString *js = show ? @"busStopsSetVisible(true)" : @"busStopsSetVisible(false)";
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

- (NSString *)tileKeyForCoordinate:(CLLocationCoordinate2D)coord {
    double lat = round(coord.latitude * 20.0) / 20.0;   // ~5.5km tile
    double lon = round(coord.longitude * 20.0) / 20.0;
    return [NSString stringWithFormat:@"%.2f,%.2f", lat, lon];
}

- (void)fetchBusStopsIfNeeded {
    if (![SettingsStore shared].showBusStops) return;
    if (self.pendingBusFetch) return;
    
    // Approximate zoom-based check — skip if too zoomed out
    __block BOOL shouldFetch = NO;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [self.webView evaluateJavaScript:@"getMapZoom()" completionHandler:^(id res, NSError *err) {
        if (!err && res && [res isKindOfClass:[NSNumber class]]) {
            double zoom = [res doubleValue];
            shouldFetch = (zoom >= 10.0); // zoom 10+ is city level
        }
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)));
    if (!shouldFetch) return;
    
    // Get map bounds from JS
    __block double south = 0, north = 0, west = 0, east = 0;
    sem = dispatch_semaphore_create(0);
    [self.webView evaluateJavaScript:@"getMapBounds()" completionHandler:^(id res, NSError *err) {
        if (!err && res && [res isKindOfClass:[NSString class]]) {
            NSData *data = [(NSString *)res dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *bounds = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([bounds isKindOfClass:[NSDictionary class]]) {
                south = [bounds[@"south"] doubleValue];
                north = [bounds[@"north"] doubleValue];
                west = [bounds[@"west"] doubleValue];
                east = [bounds[@"east"] doubleValue];
            }
        }
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)));
    
    if (south == 0 && north == 0) return; // couldn't get bounds
    
    // Only fetch if in Italy (~35°N to 48°N, 6°E to 19°E)
    double centerLat = (south + north) / 2.0;
    double centerLon = (west + east) / 2.0;
    if (centerLat < 35.0 || centerLat > 48.0 ||
        centerLon < 6.0 || centerLon > 19.0) return;
    
    CLLocationCoordinate2D center = CLLocationCoordinate2DMake(centerLat, centerLon);
    NSString *tile = [self tileKeyForCoordinate:center];
    if ([self.busStopsFetched containsObject:tile]) return;
    
    [self.busStopsFetched addObject:tile];
    self.pendingBusFetch = YES;
    
    // Overpass API query
    NSString *query = [NSString stringWithFormat:
        @"[out:json][timeout:8];"
        @"(node[\"highway\"=\"bus_stop\"](%.6f,%.6f,%.6f,%.6f);"
        @"node[\"public_transport\"=\"stop_position\"][\"bus\"=\"yes\"](%.6f,%.6f,%.6f,%.6f););"
        @"out center 200;",
        south, west, north, east,
        south, west, north, east];
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:@"https://overpass-api.de/api/interpreter"]];
    req.HTTPMethod = @"POST";
    req.HTTPBody = [query dataUsingEncoding:NSUTF8StringEncoding];
    req.timeoutInterval = 10;
    
    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.pendingBusFetch = NO;
        });
        if (err || !data) return;
        [self processBusStopsJSON:data];
    }] resume];
}

- (void)processBusStopsJSON:(NSData *)data {
    NSError *err;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (err || ![json isKindOfClass:[NSDictionary class]]) return;
    
    NSArray *elements = json[@"elements"];
    if (![elements isKindOfClass:[NSArray class]]) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Convert elements to JSON string and pass to JS
        NSError *jsonErr;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:elements options:0 error:&jsonErr];
        if (!jsonData) return;
        NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        
        // Escape for JS
        jsonStr = [jsonStr stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
        jsonStr = [jsonStr stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
        jsonStr = [jsonStr stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
        
        NSString *js = [NSString stringWithFormat:@"busStopsFromJSON('%@')", jsonStr];
        [self.webView evaluateJavaScript:js completionHandler:^(id res, NSError *err) {
            if (err) {
                [self appLog:@"busStopsFromJSON error: %@", err.localizedDescription];
            } else {
                NSInteger count = [res integerValue];
                if (count > 0) {
                    [self appLog:@"🚏 Aggiunte %ld fermate autobus", (long)count];
                }
            }
        }];
    });
}

#pragma mark - Bus Toggle

- (void)toggleBusView {
    if (self.busVC.view.hidden) {
        [self.busVC showBus];
    } else {
        [self.busVC hideBus];
    }
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.name isEqualToString:@"speak"]) {
        NSString *text = message.body;
        if (![text isKindOfClass:[NSString class]]) return;
        SettingsStore *st = [SettingsStore shared];
        if (!st.voiceGuidance) return;
        AVSpeechUtterance *u = [AVSpeechUtterance speechUtteranceWithString:text];
        NSString *lang = st.voiceLanguage ?: @"it-IT";
        u.voice = [AVSpeechSynthesisVoice voiceWithLanguage:lang];
        u.rate = 0.5;
        u.volume = st.voiceVolume;
        [self.speechSynthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
        [self.speechSynthesizer speakUtterance:u];
    } else if ([message.name isEqualToString:@"navigationEnd"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self announceArrival];
        });
    } else if ([message.name isEqualToString:@"navUpdate"]) {
        NSString *jsonStr = message.body;
        if (![jsonStr isKindOfClass:[NSString class]]) return;
        NSData *data = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *state = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![state isKindOfClass:[NSDictionary class]]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *instruction = state[@"instruction"];
            if (instruction) self.instructionLabel.text = instruction;
            NSString *streetName = state[@"streetName"];
            if (streetName && streetName.length > 0) {
                // Animazione nome via: scende dall'alto quando cambia (solo sul label, non sulla pill)
                BOOL shouldAnimate = !self.roadNameLabel.hidden && ![self.roadStreetLabel.text isEqualToString:streetName];
                self.roadNameLabel.hidden = NO;
                self.roadStreetLabel.text = streetName;
                if (shouldAnimate) {
                    CATransition *slide = [CATransition animation];
                    slide.duration = 0.35;
                    slide.type = kCATransitionMoveIn;
                    slide.subtype = kCATransitionFromTop;
                    slide.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
                    [self.roadStreetLabel.layer addAnimation:slide forKey:@"streetChange"];
                }
            }
            // ETA: ora arrivo
            id etaVal = state[@"eta"];
            if (etaVal) {
                self.etaSeconds = [etaVal doubleValue];
                NSDate *arrival = [NSDate dateWithTimeIntervalSinceNow:self.etaSeconds];
                NSDateFormatter *df = [[NSDateFormatter alloc] init];
                df.dateFormat = @"HH:mm";
                self.roadETALabel.text = [df stringFromDate:arrival];
            }
            // Distanza rimanente
            id distVal = state[@"distance"];
            if (distVal) {
                self.distanceRemaining = [distVal doubleValue];
                self.roadDistLabel.text = self.distanceRemaining >= 1000
                    ? [NSString stringWithFormat:@"%.1f km", self.distanceRemaining / 1000.0]
                    : [NSString stringWithFormat:@"%.0f m", self.distanceRemaining];
            }
            // Tempo percorrenza
            NSInteger mins = (NSInteger)(self.etaSeconds / 60);
            self.roadTimeLabel.text = mins >= 60
                ? [NSString stringWithFormat:@"%ldh %ldm", (long)(mins / 60), (long)(mins % 60)]
                : [NSString stringWithFormat:@"%ld min", (long)MAX(1, mins)];
            id speedVal = state[@"speed"];
            // Only use JS speed as fallback if GPS hasn't provided one
            if (speedVal && _currentSpeed < 0.1) {
                double kmh = [speedVal doubleValue];
                _currentSpeed = kmh / 3.6;
            }
            [self updateNavUI];
            NSNumber *arrived = state[@"arrived"];
            if ([arrived boolValue]) {
                [self announceArrival];
            }
        });
    } else if ([message.name isEqualToString:@"error"]) {
        NSString *desc = message.body;
        if (![desc isKindOfClass:[NSString class]]) desc = @"Errore sconosciuto";
        [self appLog:@"⚠️ JS Error: %@", desc];
    } else if ([message.name isEqualToString:@"searchResults"]) {
        // Results from nativeSearchOSM JS function (Nominatim → WKScriptMessageHandler)
        NSArray *results = nil;
        if ([message.body isKindOfClass:[NSArray class]]) {
            results = (NSArray *)message.body;
        } else if ([message.body isKindOfClass:[NSString class]]) {
            NSData *data = [(NSString *)message.body dataUsingEncoding:NSUTF8StringEncoding];
            results = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        }
        if (![results isKindOfClass:[NSArray class]]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.searchResults = [results mutableCopy];
            [self.searchResultsTable reloadData];
            CGFloat w = self.searchOverlay.bounds.size.width;
            CGFloat maxH = self.searchOverlay.bounds.size.height - CGRectGetMaxY(self.searchBar.frame) - 20;
            CGFloat tableH = MIN((CGFloat)self.searchResults.count * 52, maxH);
            CGFloat tableY = CGRectGetMaxY(self.searchBar.frame) + 8;
            self.searchResultsTable.frame = CGRectMake(0, tableY, w, tableH);
            self.searchResultsTable.hidden = (self.searchResults.count == 0);
        });
    } else if ([message.name isEqualToString:@"appLog"]) {
        NSString *msg = message.body;
        if ([msg isKindOfClass:[NSString class]]) {
            [self appLog:@"📱 JS: %@", msg];
        }
    } else if ([message.name isEqualToString:@"simCoords"]) {
        NSString *jsonStr = message.body;
        if (![jsonStr isKindOfClass:[NSString class]]) return;
        [self appLog:@"📩 simCoords ricevute (%lu chars) — salvo _simCoords", (unsigned long)[jsonStr length]];
        NSData *data = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
        NSArray *coords = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([coords isKindOfClass:[NSArray class]] && coords.count >= 2) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appLog:@"✅ simCoords: %lu coordinate salvate, stepPerTick=%.4f", (unsigned long)[coords count], 0.1389];
                    _simCoords = coords;
                    _simIndex = 0;
                    _simStepPerTick = 0.1389;
            });
        }
    } else if ([message.name isEqualToString:@"routeReady"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self appLog:@"✅ Percorso pronto, mostro VAI"];
            [self showGoButton];
        });
    }
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self appLog:@"🌍 map.html caricato"];
    // Apply initial settings once map is loaded
    [self applyAllSettings];
}

- (BOOL)searchActive {
    return self.searchActive_Ivar;
}

#pragma mark - Layout Edit Mode

- (void)enterLayoutEditMode {
    _layoutEditMode = YES;
    
    // Crea pillola stile pulsante (come Modalità, Cerca, etc.)
    if (!self.layoutEditOverlay) {
        CGFloat pillW = 100;
        CGFloat pillH = 40;
        CGFloat radius = pillH / 2;
        CGFloat w = self.view.bounds.size.width;
        
        UIView *pill = [[UIView alloc] initWithFrame:CGRectMake(w - pillW - 12, 54, pillW, pillH)];
        pill.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
        pill.layer.cornerRadius = radius;
        pill.layer.borderWidth = 1.5;
        pill.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.25].CGColor;
        pill.layer.shadowColor = [UIColor blackColor].CGColor;
        pill.layer.shadowOpacity = 0.3;
        pill.layer.shadowRadius = 8;
        pill.layer.shadowOffset = CGSizeZero;
        pill.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        pill.userInteractionEnabled = YES;
        
        // ✕ Annulla (grigio su cerchio bianco, piccolo)
        UIButton *xBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        xBtn.frame = CGRectMake(6, 4, 32, 32);
        xBtn.backgroundColor = [UIColor whiteColor];
        xBtn.layer.cornerRadius = 16;
        [xBtn setTitle:@"✕" forState:UIControlStateNormal];
        [xBtn setTitleColor:[UIColor grayColor] forState:UIControlStateNormal];
        xBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        [xBtn addTarget:self action:@selector(layoutCancelTapped) forControlEvents:UIControlEventTouchUpInside];
        [pill addSubview:xBtn];
        
        // ✓ Salva (verde)
        UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        saveBtn.frame = CGRectMake(pillW - 38, 4, 32, 32);
        saveBtn.tintColor = [UIColor systemGreenColor];
        [saveBtn setImage:[UIImage systemImageNamed:@"checkmark.circle.fill"] forState:UIControlStateNormal];
        [saveBtn addTarget:self action:@selector(layoutSaveTapped) forControlEvents:UIControlEventTouchUpInside];
        [pill addSubview:saveBtn];
        
        [self.view addSubview:pill];
        self.layoutEditOverlay = pill;
    }
    self.layoutEditOverlay.hidden = NO;
    [self.view bringSubviewToFront:self.layoutEditOverlay];
    
    // Raccogli tutti gli elementi draggabili (escluso busVC, navBar, e la pill edit)
    NSMutableArray *items = [NSMutableArray array];
    void(^addItem)(UIView*, NSString*, CGRect) = ^(UIView *v, NSString *id, CGRect df) {
        if (!v) return;
        [items addObject:@{@"view": v, @"id": id, @"default": [NSValue valueWithCGRect:df]}];
    };
    
    addItem(self.modalitaButton, @"modalita", CGRectMake(self.view.bounds.size.width - 112, 54, 100, 40));
    addItem(self.mapButton, @"map", CGRectMake(self.view.bounds.size.width - 48, 54, 40, 40));
    addItem(self.searchButton, @"search", CGRectMake(self.view.bounds.size.width - 112, self.view.bounds.size.height * 0.35 + 10, 100, 40));
    addItem(self.trackingButton, @"tracking", CGRectMake(self.view.bounds.size.width - 112, self.view.bounds.size.height - 120, 100, 40));
    addItem(self.settingsButton, @"settings", CGRectMake(self.view.bounds.size.width - 112, self.view.bounds.size.height - 60, 100, 40));
    addItem(self.compassButton, @"compass", CGRectMake(12, self.view.bounds.size.height - 110, 52, 52));
    addItem(self.logButton, @"log", CGRectMake(12, self.view.bounds.size.height - 170, 44, 44));
    addItem((UIView *)self.roadNameLabel, @"streetname", CGRectMake(12, self.view.bounds.size.height - 220, self.view.bounds.size.width - 24, 140));
    addItem(self.stopNavButton, @"stopnav", CGRectMake(12, self.view.bounds.size.height - 260, 52, 52));
    // Mostra temporaneamente la pillola nome via per editarla (se nascosta)
    if (self.roadNameLabel.hidden && !self.isNavigating) {
        self.roadNameLabel.hidden = NO;
        self.roadNameLabel.alpha = 0.5;
        self.roadStreetLabel.text = @"Via Nome Strada";
        self.roadETALabel.text = @"14:30";
        self.roadTimeLabel.text = @"9 min";
        self.roadDistLabel.text = @"3.2 km";
        self.roadNameLabel.tag = 9999;
    }
    // Anche la pill edit è draggabile
    addItem(self.layoutEditOverlay, @"editpill", CGRectMake(self.view.bounds.size.width - 112, 54, 100, 40));
    self.layoutItems = items;
    
    // Aggiungi pan gesture a ogni elemento
    for (NSDictionary *item in items) {
        UIView *v = item[@"view"];
        v.autoresizingMask = UIViewAutoresizingNone;
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(layoutPan:)];
        [v addGestureRecognizer:pan];
        v.userInteractionEnabled = YES;
    }
}

- (void)exitLayoutEditMode:(BOOL)save {
    _layoutEditMode = NO;
    // Nascondi la pill edit (sparisce completamente)
    self.layoutEditOverlay.hidden = YES;
    
    if (save) [self saveLayoutPositions];
    else [self loadSavedLayout];
    
    // Rimuovi pan gesture
    for (NSDictionary *item in self.layoutItems) {
        UIView *v = item[@"view"];
        NSMutableArray *toRemove = [NSMutableArray array];
        for (UIGestureRecognizer *g in v.gestureRecognizers) {
            if ([g isKindOfClass:[UIPanGestureRecognizer class]])
                [toRemove addObject:g];
        }
        for (UIGestureRecognizer *g in toRemove)
            [v removeGestureRecognizer:g];
    }
    self.layoutItems = nil;
    // Se la pillola nome via era stata mostrata solo per edit, nascondila di nuovo
    if (self.roadNameLabel.tag == 9999) {
        self.roadNameLabel.hidden = YES;
        self.roadStreetLabel.text = @"";
        self.roadETALabel.text = @"";
        self.roadTimeLabel.text = @"";
        self.roadDistLabel.text = @"";
        self.roadNameLabel.tag = 0;
    }
}

- (void)layoutPan:(UIPanGestureRecognizer *)pan {
    UIView *v = pan.view;
    CGPoint t = [pan translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [pan setTranslation:CGPointZero inView:v.superview];
}

- (void)layoutSaveTapped {
    [self exitLayoutEditMode:YES];
}

- (void)layoutCancelTapped {
    [self exitLayoutEditMode:NO];
}

- (void)saveLayoutPositions {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    for (NSDictionary *item in self.layoutItems) {
        UIView *v = item[@"view"];
        NSString *key = item[@"id"];
        [ud setFloat:v.frame.origin.x forKey:[NSString stringWithFormat:@"layout_%@_x", key]];
        [ud setFloat:v.frame.origin.y forKey:[NSString stringWithFormat:@"layout_%@_y", key]];
        [ud setFloat:v.frame.size.width forKey:[NSString stringWithFormat:@"layout_%@_w", key]];
        [ud setFloat:v.frame.size.height forKey:[NSString stringWithFormat:@"layout_%@_h", key]];
    }
    [ud synchronize];
}

- (void)loadSavedLayout {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    void(^apply)(UIView*, NSString*, CGRect) = ^(UIView *v, NSString *key, CGRect defFrame) {
        if (!v) return;
        float x = [ud objectForKey:[NSString stringWithFormat:@"layout_%@_x", key]] ? [ud floatForKey:[NSString stringWithFormat:@"layout_%@_x", key]] : defFrame.origin.x;
        float y = [ud objectForKey:[NSString stringWithFormat:@"layout_%@_y", key]] ? [ud floatForKey:[NSString stringWithFormat:@"layout_%@_y", key]] : defFrame.origin.y;
        float w = [ud objectForKey:[NSString stringWithFormat:@"layout_%@_w", key]] ? [ud floatForKey:[NSString stringWithFormat:@"layout_%@_w", key]] : defFrame.size.width;
        float h = [ud objectForKey:[NSString stringWithFormat:@"layout_%@_h", key]] ? [ud floatForKey:[NSString stringWithFormat:@"layout_%@_h", key]] : defFrame.size.height;
        v.frame = CGRectMake(x, y, w, h);
        v.autoresizingMask = UIViewAutoresizingNone;
    };
    
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    apply(self.modalitaButton, @"modalita", CGRectMake(w - 112, 54, 100, 40));
    apply(self.mapButton, @"map", CGRectMake(w - 48, 54, 40, 40));
    apply(self.searchButton, @"search", CGRectMake(w - 112, h * 0.35 + 10, 100, 40));
    apply(self.trackingButton, @"tracking", CGRectMake(w - 112, h - 120, 100, 40));
    apply(self.settingsButton, @"settings", CGRectMake(w - 112, h - 60, 100, 40));
    apply(self.compassButton, @"compass", CGRectMake(12, h - 110, 52, 52));
    apply(self.logButton, @"log", CGRectMake(12, h - 170, 44, 44));
    apply(self.roadNameLabel, @"streetname", CGRectMake(12, h - 220, w - 24, 140));
    apply(self.stopNavButton, @"stopnav", CGRectMake(12, h - 260, 52, 52));
    // Anche la pill edit (per ricordare posizione, ma è nascosta in modalità normale)
    if (self.layoutEditOverlay) {
        apply(self.layoutEditOverlay, @"editpill", CGRectMake(w - 112, 54, 100, 40));
        self.layoutEditOverlay.hidden = YES; // sempre nascosta in modalità normale
    }
}

#pragma mark - Missing Methods

- (void)applyArrowTransform {
    // Arrow rotation gestita dal JS rAF engine
}

- (void)recalculateRoute {
    if (_isRecalculating || !_pendingDestDict) return;
    _isRecalculating = YES;
    
    CGFloat destLat = [_pendingDestDict[@"lat"] doubleValue];
    CGFloat destLon = [_pendingDestDict[@"lon"] doubleValue];
    NSString *name = _pendingDestDict[@"name"] ?: @"Destinazione";
    
    [self.webView evaluateJavaScript:@"recalculateRoute();"
        completionHandler:^(id result, NSError *error) {
        self->_isRecalculating = NO;
    }];
    // Timeout fallback: unlock after 5s even if JS fails
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->_isRecalculating = NO;
    });
}

@end
