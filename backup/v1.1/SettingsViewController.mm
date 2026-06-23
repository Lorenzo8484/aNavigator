#import "SettingsViewController.h"
#import "MapViewController.h"
#import "BusViewController.h"
#import "LocalizationManager.h"
#import <objc/runtime.h>
#import "SettingsStore.h"

static NSString *transportModeName(TransportMode m) {
    switch(m){ case TransportModeAuto: return LOC(@"Auto"); case TransportModeBus: return LOC(@"Autobus"); case TransportModeTruck: return LOC(@"Camion"); }
}

static NSString *alertLevelName(AlertLevel a) {
    switch(a){ case AlertLevelNone: return LOC(@"No avvisi"); case AlertLevelImportant: return LOC(@"Avvisi importanti"); case AlertLevelFull: return LOC(@"Avvisi completi"); }
}

static NSString *sectionTitle(SettingsSection s) {
    switch (s) { case 0: return LOC(@"NAVIGAZIONE"); case 1: return LOC(@"MAPPA"); case 2: return LOC(@"AVVISI"); case 3: return LOC(@"SISTEMA"); case 4: return LOC(@"SCHERMO"); }
}
static NSString *sectionIcon(SettingsSection s) {
    switch (s) { case 0: return @"location.fill"; case 1: return @"map.fill"; case 2: return @"exclamationmark.triangle.fill"; case 3: return @"gearshape.fill"; case 4: return @"display"; }
}
static NSString *sectionLabel(SettingsSection s) {
    switch (s) { case 0: return LOC(@"Navigazione"); case 1: return LOC(@"Mappa"); case 2: return LOC(@"Avvisi"); case 3: return LOC(@"Sistema"); case 4: return LOC(@"Schermo"); }
}

typedef NS_ENUM(NSInteger, RowType) { RowTypeChevron, RowTypeSwitch };
@interface SettingsRow : NSObject
@property (nonatomic,copy) NSString *title,*value,*key; @property (nonatomic) RowType type; @property (nonatomic) BOOL on;
+ (instancetype)chevron:(NSString*)t v:(NSString*)v; + (instancetype)toggle:(NSString*)t on:(BOOL)on;
@end
@implementation SettingsRow
+ (instancetype)chevron:(NSString*)t v:(NSString*)v { SettingsRow *r=[SettingsRow new]; r.title=t; r.key=t; r.value=v; r.type=RowTypeChevron; return r; }
+ (instancetype)toggle:(NSString*)t on:(BOOL)on { SettingsRow *r=[SettingsRow new]; r.title=t; r.key=t; r.type=RowTypeSwitch; r.on=on; return r; }
@end

static NSArray<SettingsRow*>* sectionRows(SettingsSection s) {
    SettingsStore *st=[SettingsStore shared];
    switch (s) {
        case 0: return @[
            [SettingsRow chevron:@"Modalità" v:transportModeName(st.transportMode)],
            [SettingsRow chevron:@"Percorso preferito" v:LOC(st.preferredRoute)],
            [SettingsRow toggle:@"Evitare pedaggi" on:st.avoidTolls],[SettingsRow toggle:@"Evitare autostrade" on:st.avoidHighways],[SettingsRow toggle:@"Evitare traghetti" on:st.avoidFerries],
            [SettingsRow toggle:@"Ricalcolo automatico" on:st.autoReroute],[SettingsRow toggle:@"Mostra alternative" on:st.showAlternatives],[SettingsRow toggle:@"Indicazioni vocali" on:st.voiceGuidance],
            [SettingsRow chevron:@"Volume guida" v:[NSString stringWithFormat:@"%.0f%%",st.voiceVolume*100]],
            [SettingsRow toggle:@"Traffico in tempo reale" on:st.liveTraffic],[SettingsRow toggle:@"POI lungo il percorso" on:st.showPOIAlongRoute],[SettingsRow toggle:@"Avviso autovelox" on:st.speedCameraAlert],
            [SettingsRow toggle:@"Velocità corrente" on:st.showCurrentSpeed],[SettingsRow toggle:@"Navigazione offline" on:st.offlineNavigation],
            [SettingsRow chevron:@"Voci" v:st.voiceLanguage]];
        case 1: return @[
            [SettingsRow chevron:@"Tipo mappa" v:(st.mapType==0?LOC(@"Standard"):st.mapType==1?LOC(@"Satellite"):LOC(@"Hybrid"))],
            [SettingsRow chevron:@"Vista 3D predefinita" v:(st.view3DDefault?LOC(@"Attiva"):LOC(@"Disattiva"))],
            [SettingsRow toggle:@"Mostra edifici 3D" on:st.show3DBuildings],[SettingsRow toggle:@"Mostra traffico" on:st.showTraffic],
            [SettingsRow toggle:@"Fermate autobus" on:st.showBusStops],[SettingsRow toggle:@"Modalità notturna" on:st.nightMode],
            [SettingsRow toggle:@"Zoom automatico" on:st.autoZoom],[SettingsRow chevron:@"Orientamento mappa" v:LOC(st.mapOrientation)],
            [SettingsRow toggle:@"Mostra bussola" on:st.showCompass],[SettingsRow toggle:@"Mostra scala" on:st.showScale],[SettingsRow chevron:@"Etichette POI" v:LOC(st.poiLabels)]];
        case 2: return @[
            [SettingsRow chevron:@"Livello avvisi" v:alertLevelName(st.alertLevel)],
            [SettingsRow toggle:@"Limite velocità" on:st.alertSpeedLimit],[SettingsRow toggle:@"Autovelox fisso" on:st.alertFixedCamera],[SettingsRow toggle:@"Autovelox mobile" on:st.alertMobileCamera],
            [SettingsRow toggle:@"Incidenti" on:st.alertAccidents],[SettingsRow toggle:@"Lavori in corso" on:st.alertRoadworks],[SettingsRow toggle:@"Strade chiuse" on:st.alertClosedRoads],
            [SettingsRow toggle:@"Condizioni meteo" on:st.alertWeather],[SettingsRow toggle:@"Pericolo ghiaccio" on:st.alertIce],[SettingsRow toggle:@"Zona scolastica" on:st.alertSchoolZone]];
        case 3: return @[
            [SettingsRow chevron:@"Unità di misura" v:LOC(st.unitSystem)],
            [SettingsRow chevron:@"Lingua" v:[[LocalizationManager shared] languageNameForCode:st.language]],
            [SettingsRow toggle:@"Feedback aptico" on:st.hapticFeedback],[SettingsRow toggle:@"Risparmio batteria" on:st.batterySaver],
            [SettingsRow chevron:@"Cache mappe" v:[NSString stringWithFormat:@"%.1f GB",st.cacheSize]],
            [SettingsRow chevron:@"Privacy & dati" v:@""],
            [SettingsRow chevron:@"Crediti e attribuzioni" v:@"OSM, Overpass, ..."],
            [SettingsRow chevron:@"Info su Autista" v:st.appVersion]];
        case 4: return @[
            [SettingsRow toggle:@"Luminosità automatica" on:st.autoBrightness],[SettingsRow toggle:@"Tema scuro" on:st.darkTheme],
            [SettingsRow chevron:@"Dimensione testo" v:LOC(st.textSize)],
            [SettingsRow toggle:@"Mostra tachimetro" on:st.showSpeedometer],[SettingsRow toggle:@"Mostra ETA" on:st.showETA],
            [SettingsRow toggle:@"Barra stato trasparente" on:st.transparentStatusBar],[SettingsRow toggle:@"Animazioni ridotte" on:st.reducedAnimations],
            [SettingsRow toggle:@"Always-on display" on:st.alwaysOnDisplay]];
    }
}

// ── Settings Cell ──────────────────────────────────────────────
@interface SettingsCell : UITableViewCell
@property (nonatomic,strong) UILabel *rowTitle,*rowValue; @property (nonatomic,strong) UIImageView *rowChevron; @property (nonatomic,strong) UISwitch *rowSwitch; @property (nonatomic,strong) UIView *divider;
@property (nonatomic,copy) NSString *rowKey;
- (void)config:(SettingsRow*)row;
@end
@implementation SettingsCell
- (instancetype)initWithStyle:(UITableViewCellStyle)s reuseIdentifier:(NSString*)rid {
    if(self=[super initWithStyle:s reuseIdentifier:rid]){
        self.backgroundColor=[UIColor clearColor]; self.selectionStyle=UITableViewCellSelectionStyleNone;
        _rowTitle=[[UILabel alloc] init]; _rowTitle.font=[UIFont systemFontOfSize:15]; _rowTitle.textColor=[UIColor whiteColor]; _rowTitle.translatesAutoresizingMaskIntoConstraints=NO; [self.contentView addSubview:_rowTitle];
        _rowValue=[[UILabel alloc] init]; _rowValue.font=[UIFont systemFontOfSize:15]; _rowValue.textColor=[[UIColor whiteColor] colorWithAlphaComponent:0.85]; _rowValue.textAlignment=NSTextAlignmentRight; _rowValue.translatesAutoresizingMaskIntoConstraints=NO; [self.contentView addSubview:_rowValue];
        _rowChevron=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]]; _rowChevron.tintColor=[[UIColor whiteColor] colorWithAlphaComponent:0.5]; _rowChevron.translatesAutoresizingMaskIntoConstraints=NO; [self.contentView addSubview:_rowChevron];
        _rowSwitch=[[UISwitch alloc] init]; _rowSwitch.onTintColor=[UIColor colorWithRed:0.18 green:0.49 blue:0.97 alpha:1.0]; _rowSwitch.translatesAutoresizingMaskIntoConstraints=NO; _rowSwitch.hidden=YES; [self.contentView addSubview:_rowSwitch];
        _divider=[[UIView alloc] init]; _divider.backgroundColor=[[UIColor whiteColor] colorWithAlphaComponent:0.10]; _divider.translatesAutoresizingMaskIntoConstraints=NO; [self.contentView addSubview:_divider];
        [NSLayoutConstraint activateConstraints:@[
            [_rowTitle.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:24],[_rowTitle.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_rowValue.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-24],[_rowValue.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_rowChevron.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-22],[_rowChevron.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_rowSwitch.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-22],[_rowSwitch.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_divider.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:24],[_divider.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor], [_divider.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],[_divider.heightAnchor constraintEqualToConstant:0.5],
        ]];
    } return self;
}
- (void)config:(SettingsRow*)row {
    self.rowKey=row.key;
    _rowTitle.text=LOC(row.title); BOOL s=(row.type==RowTypeSwitch);
    _rowChevron.hidden=s; _rowValue.hidden=s; _rowSwitch.hidden=!s; _rowSwitch.on=row.on; [_rowSwitch addTarget:self action:@selector(rowSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    if(!s){ _rowValue.text=row.value; _rowValue.textColor=row.value.length?[[UIColor whiteColor] colorWithAlphaComponent:0.55]:[[UIColor whiteColor] colorWithAlphaComponent:0.25]; }
    _rowTitle.textColor=s&&row.on?[UIColor whiteColor]:[[UIColor whiteColor] colorWithAlphaComponent:s?0.65:1.0];
}

- (void)rowSwitchChanged:(UISwitch*)sw {
    SettingsStore *st=[SettingsStore shared];
    NSString *t=self.rowKey;
    BOOL on=sw.on;
    if([t isEqualToString:@"Evitare pedaggi"]) st.avoidTolls=on;
    else if([t isEqualToString:@"Evitare autostrade"]) st.avoidHighways=on;
    else if([t isEqualToString:@"Evitare traghetti"]) st.avoidFerries=on;
    else if([t isEqualToString:@"Ricalcolo automatico"]) st.autoReroute=on;
    else if([t isEqualToString:@"Mostra alternative"]) st.showAlternatives=on;
    else if([t isEqualToString:@"Indicazioni vocali"]) st.voiceGuidance=on;
    else if([t isEqualToString:@"Traffico in tempo reale"]) st.liveTraffic=on;
    else if([t isEqualToString:@"POI lungo il percorso"]) st.showPOIAlongRoute=on;
    else if([t isEqualToString:@"Avviso autovelox"]) st.speedCameraAlert=on;
    else if([t isEqualToString:@"Velocità corrente"]) st.showCurrentSpeed=on;
    else if([t isEqualToString:@"Navigazione offline"]) st.offlineNavigation=on;
    else if([t isEqualToString:@"Mostra edifici 3D"]) st.show3DBuildings=on;
    else if([t isEqualToString:@"Mostra traffico"]) st.showTraffic=on;
    else if([t isEqualToString:@"Fermate autobus"]) st.showBusStops=on;
    else if([t isEqualToString:@"Modalità notturna"]) st.nightMode=on;
    else if([t isEqualToString:@"Zoom automatico"]) st.autoZoom=on;
    else if([t isEqualToString:@"Mostra bussola"]) st.showCompass=on;
    else if([t isEqualToString:@"Mostra scala"]) st.showScale=on;
    else if([t isEqualToString:@"Limite velocità"]) st.alertSpeedLimit=on;
    else if([t isEqualToString:@"Autovelox fisso"]) st.alertFixedCamera=on;
    else if([t isEqualToString:@"Autovelox mobile"]) st.alertMobileCamera=on;
    else if([t isEqualToString:@"Incidenti"]) st.alertAccidents=on;
    else if([t isEqualToString:@"Lavori in corso"]) st.alertRoadworks=on;
    else if([t isEqualToString:@"Strade chiuse"]) st.alertClosedRoads=on;
    else if([t isEqualToString:@"Condizioni meteo"]) st.alertWeather=on;
    else if([t isEqualToString:@"Pericolo ghiaccio"]) st.alertIce=on;
    else if([t isEqualToString:@"Zona scolastica"]) st.alertSchoolZone=on;
    else if([t isEqualToString:@"Feedback aptico"]) st.hapticFeedback=on;
    else if([t isEqualToString:@"Risparmio batteria"]) st.batterySaver=on;
    else if([t isEqualToString:@"Luminosità automatica"]) st.autoBrightness=on;
    else if([t isEqualToString:@"Tema scuro"]) st.darkTheme=on;
    else if([t isEqualToString:@"Mostra tachimetro"]) st.showSpeedometer=on;
    else if([t isEqualToString:@"Mostra ETA"]) st.showETA=on;
    else if([t isEqualToString:@"Barra stato trasparente"]) st.transparentStatusBar=on;
    else if([t isEqualToString:@"Animazioni ridotte"]) st.reducedAnimations=on;
    else if([t isEqualToString:@"Always-on display"]) st.alwaysOnDisplay=on;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MapSettingsChanged" object:nil];
    [st save];
}

@end

#pragma mark - Blur + Glass

// ── Main Implementation ────────────────────────────────────────
@interface SettingsViewController () <UITableViewDataSource,UITableViewDelegate>
@property (nonatomic,strong) UIView *mainBlur; // NON UIVisualEffectView, UIView
@property (nonatomic,strong) CAGradientLayer *glassReflection;
@property (nonatomic,strong) UIView *sidebarPanel;
@property (nonatomic,strong) UIScrollView *sidebarScroll;
@property (nonatomic,strong) UIStackView *sidebarStack;
@property (nonatomic,strong) NSMutableArray<UIButton*> *tabButtons;
@property (nonatomic,strong) NSMutableArray<UILabel*> *tabLabels;
@property (nonatomic,strong) NSMutableArray<UIView*> *glowBars;
@property (nonatomic,strong) NSLayoutConstraint *sidebarWidthConstraint;
@property (nonatomic,assign) SettingsSection selectedSection;
@property (nonatomic,strong) UIView *contentPanel;
@property (nonatomic,strong) UILabel *sectionLabel;
@property (nonatomic,strong) UILabel *sidebarTitleLabel; // "Impostazioni" DENTRO sidebar
@property (nonatomic,strong) UITableView *tableView;
@property (nonatomic,strong) UIScrollView *slidersScroll;
@property (nonatomic,strong) UIView *slidersView;
@property (nonatomic,strong) UISlider *altS,*pitS,*offS,*headS,*traspS,*busYS,*busXS,*busSS,*busRS,*arrowRS;
@property (nonatomic,strong) UILabel *altV,*pitV,*offV,*headV,*traspV,*busYV,*busXV,*busSV,*busRV,*arrowRV;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=[UIColor clearColor];
    self.selectedSection=SettingsSectionNavigation;
    [self setupBlur];
    [self setupSidebar];
    [self setupContent];
    [self setupSliders];
    [self setupBack];
    [self setupParallax];
    [self selectTab:0 animated:NO];
    // Osserva cambi lingua
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(languageDidChange) name:kLanguageChangedNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateLayoutForSize:self.view.bounds.size];
    self.glassReflection.frame=self.mainBlur.bounds;
    // Aggiorna contentSize scroll slider (essenziale per scroll portrait/landscape)
    if(!self.slidersScroll.hidden){
        self.slidersScroll.contentSize=CGSizeMake(self.slidersScroll.bounds.size.width, 1000);
    }
}

#pragma mark - Localization

- (void)languageDidChange {
    self.sidebarTitleLabel.text = LOC(@"Impostazioni");
    self.sectionLabel.text = sectionTitle(self.selectedSection);
    [self.tableView reloadData];
    [self updateSidebarLabels];
    [self rebuildSliders];
}

- (void)updateSidebarLabels {
    NSArray *labels=@[LOC(@"Navigazione"),LOC(@"Mappa"),LOC(@"Avvisi"),LOC(@"Sistema"),LOC(@"Schermo")];
    for(NSInteger i=0;i<(NSInteger)self.tabLabels.count;i++){
        self.tabLabels[i].text=labels[i];
    }
}

- (void)setupBlur {
    // VETRO REALE: sfondo scuro semitrasparente (non UIVisualEffectView che non funziona)
    self.mainBlur=[[UIView alloc] init]; // NON UIVisualEffectView, UIView normale
    self.mainBlur.backgroundColor=[[UIColor blackColor] colorWithAlphaComponent:0.45];
    self.mainBlur.translatesAutoresizingMaskIntoConstraints=NO;
    self.mainBlur.layer.cornerRadius=24; self.mainBlur.clipsToBounds=YES;
    self.mainBlur.layer.borderWidth=1.5;
    self.mainBlur.layer.borderColor=[[UIColor whiteColor] colorWithAlphaComponent:0.25].CGColor;
    [self.view addSubview:self.mainBlur];
    
    self.glassReflection=[CAGradientLayer layer];
    self.glassReflection.colors=@[(id)[[UIColor whiteColor] colorWithAlphaComponent:0.08].CGColor,(id)[UIColor clearColor].CGColor];
    self.glassReflection.startPoint=CGPointMake(0,0); self.glassReflection.endPoint=CGPointMake(1,1);
    self.glassReflection.frame=self.mainBlur.bounds;
    [self.mainBlur.layer addSublayer:self.glassReflection];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.mainBlur.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
        [self.mainBlur.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [self.mainBlur.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],
        [self.mainBlur.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-10],
    ]];
}

#pragma mark - Parallasse

- (void)setupParallax {
    UIInterpolatingMotionEffect *mx=[[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.x" type:UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis];
    mx.minimumRelativeValue=@(-8); mx.maximumRelativeValue=@(8);
    UIInterpolatingMotionEffect *my=[[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.y" type:UIInterpolatingMotionEffectTypeTiltAlongVerticalAxis];
    my.minimumRelativeValue=@(-8); my.maximumRelativeValue=@(8);
    UIMotionEffectGroup *g=[UIMotionEffectGroup new]; g.motionEffects=@[mx,my];
    [self.mainBlur addMotionEffect:g];
}

#pragma mark - Sidebar ("Impostazioni" CENTRATO dentro sidebar, sopra i tab)

- (void)setupSidebar {
    self.sidebarPanel=[[UIView alloc] init]; self.sidebarPanel.translatesAutoresizingMaskIntoConstraints=NO;
    self.sidebarPanel.backgroundColor=[UIColor clearColor];
    self.sidebarPanel.clipsToBounds=NO;
    [self.mainBlur addSubview:self.sidebarPanel];
    
    self.sidebarScroll=[[UIScrollView alloc] init]; self.sidebarScroll.translatesAutoresizingMaskIntoConstraints=NO;
    self.sidebarScroll.showsVerticalScrollIndicator=NO; self.sidebarScroll.bounces=YES; self.sidebarScroll.alwaysBounceVertical=YES;
    self.sidebarScroll.clipsToBounds=NO;
    [self.sidebarPanel addSubview:self.sidebarScroll];
    
    self.sidebarStack=[[UIStackView alloc] init]; self.sidebarStack.axis=UILayoutConstraintAxisVertical; self.sidebarStack.spacing=10;
    self.sidebarStack.translatesAutoresizingMaskIntoConstraints=NO;
    self.sidebarStack.clipsToBounds=NO;
    self.sidebarStack.alignment=UIStackViewAlignmentCenter;
    [self.sidebarScroll addSubview:self.sidebarStack];
    
    self.sidebarWidthConstraint=[self.sidebarPanel.widthAnchor constraintEqualToConstant:76];
    [NSLayoutConstraint activateConstraints:@[
        [self.sidebarPanel.leadingAnchor constraintEqualToAnchor:self.mainBlur.leadingAnchor constant:14],
        [self.sidebarPanel.topAnchor constraintEqualToAnchor:self.mainBlur.topAnchor constant:10],
        [self.sidebarPanel.bottomAnchor constraintEqualToAnchor:self.mainBlur.bottomAnchor constant:-86],
        self.sidebarWidthConstraint,
        [self.sidebarScroll.topAnchor constraintEqualToAnchor:self.sidebarPanel.topAnchor constant:4],
        [self.sidebarScroll.leadingAnchor constraintEqualToAnchor:self.sidebarPanel.leadingAnchor],
        [self.sidebarScroll.trailingAnchor constraintEqualToAnchor:self.sidebarPanel.trailingAnchor],
        [self.sidebarScroll.bottomAnchor constraintEqualToAnchor:self.sidebarPanel.bottomAnchor constant:-4],
        [self.sidebarStack.topAnchor constraintEqualToAnchor:self.sidebarScroll.topAnchor constant:4],
        [self.sidebarStack.leadingAnchor constraintEqualToAnchor:self.sidebarScroll.leadingAnchor],
        [self.sidebarStack.trailingAnchor constraintEqualToAnchor:self.sidebarScroll.trailingAnchor],
        [self.sidebarStack.bottomAnchor constraintEqualToAnchor:self.sidebarScroll.bottomAnchor],
    ]];
    
    // ── "Impostazioni" CENTRATO dentro sidebar, sopra i tab ──
    self.sidebarTitleLabel=[[UILabel alloc] init]; 
    self.sidebarTitleLabel.text=LOC(@"Impostazioni");
    self.sidebarTitleLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    self.sidebarTitleLabel.textColor=[[UIColor whiteColor] colorWithAlphaComponent:0.85];
    self.sidebarTitleLabel.textAlignment=NSTextAlignmentCenter;
    self.sidebarTitleLabel.translatesAutoresizingMaskIntoConstraints=NO;
    [self.sidebarPanel addSubview:self.sidebarTitleLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.sidebarTitleLabel.topAnchor constraintEqualToAnchor:self.sidebarPanel.topAnchor constant:4],
        [self.sidebarTitleLabel.centerXAnchor constraintEqualToAnchor:self.sidebarPanel.centerXAnchor],
    ]];
    
    NSArray *icons=@[@"location.fill",@"map.fill",@"exclamationmark.triangle.fill",@"gearshape.fill",@"display"];
    NSArray *labels=@[LOC(@"Navigazione"),LOC(@"Mappa"),LOC(@"Avvisi"),LOC(@"Sistema"),LOC(@"Schermo")];
    self.tabButtons=[NSMutableArray array]; self.tabLabels=[NSMutableArray array]; self.glowBars=[NSMutableArray array];
    
    for(NSInteger i=0;i<5;i++){
        UIButton *btn=[UIButton buttonWithType:UIButtonTypeSystem]; btn.tag=i;
        btn.backgroundColor=[[UIColor whiteColor] colorWithAlphaComponent:0.04];
        btn.layer.cornerRadius=10; btn.clipsToBounds=NO;
        btn.layer.borderWidth=1;
        btn.layer.borderColor=[[UIColor whiteColor] colorWithAlphaComponent:0.06].CGColor;
        [btn.heightAnchor constraintEqualToConstant:44].active=YES;
        [btn.widthAnchor constraintGreaterThanOrEqualToConstant:60].active=YES;
        
        UIStackView *row=[[UIStackView alloc] init]; row.axis=UILayoutConstraintAxisHorizontal;
        row.spacing=6; row.alignment=UIStackViewAlignmentCenter; row.distribution=UIStackViewDistributionEqualSpacing;
        row.translatesAutoresizingMaskIntoConstraints=NO; row.userInteractionEnabled=NO; row.tag=50;
        [btn addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.centerXAnchor constraintEqualToAnchor:btn.centerXAnchor],
            [row.centerYAnchor constraintEqualToAnchor:btn.centerYAnchor],
            [row.leadingAnchor constraintGreaterThanOrEqualToAnchor:btn.leadingAnchor constant:10],
            [row.trailingAnchor constraintLessThanOrEqualToAnchor:btn.trailingAnchor constant:-10],
        ]];
        
        UIImageView *iv=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:icons[i]]];
        iv.tintColor=[UIColor whiteColor]; iv.contentMode=UIViewContentModeScaleAspectFit;
        iv.translatesAutoresizingMaskIntoConstraints=NO; iv.tag=100;
        [iv.widthAnchor constraintEqualToConstant:24].active=YES;
        [iv.heightAnchor constraintEqualToConstant:24].active=YES;
        [row addArrangedSubview:iv];
        
        UILabel *lb=[[UILabel alloc] init]; lb.text=labels[i];
        lb.font=[UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        lb.textColor=[UIColor whiteColor];
        lb.translatesAutoresizingMaskIntoConstraints=NO; lb.tag=101; lb.hidden=YES;
        [row addArrangedSubview:lb];
        
        UIView *glow=[[UIView alloc] init]; glow.translatesAutoresizingMaskIntoConstraints=NO;
        glow.backgroundColor=[UIColor systemBlueColor]; glow.layer.cornerRadius=2;
        glow.layer.shadowColor=[UIColor systemBlueColor].CGColor;
        glow.layer.shadowOpacity=0; glow.layer.shadowRadius=18; glow.layer.shadowOffset=CGSizeZero;
        glow.alpha=0; glow.tag=200; [btn addSubview:glow];
        [NSLayoutConstraint activateConstraints:@[
            [glow.trailingAnchor constraintEqualToAnchor:btn.trailingAnchor],
            [glow.centerYAnchor constraintEqualToAnchor:btn.centerYAnchor],
            [glow.widthAnchor constraintEqualToConstant:4],[glow.heightAnchor constraintEqualToConstant:18],
        ]];
        
        [btn addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
        [btn addTarget:self action:@selector(tabDown:) forControlEvents:UIControlEventTouchDown];
        [btn addTarget:self action:@selector(tabUp:) forControlEvents:UIControlEventTouchUpOutside|UIControlEventTouchCancel];
        
        [self.sidebarStack addArrangedSubview:btn];
        [self.tabButtons addObject:btn]; [self.tabLabels addObject:lb]; [self.glowBars addObject:glow];
    }
}

#pragma mark - Tab Actions

- (void)tabTapped:(UIButton*)s { 
    if (self.selectedSection == (SettingsSection)s.tag) return;
    [self selectTab:s.tag animated:YES]; 
}

- (void)selectTab:(NSInteger)idx animated:(BOOL)animated {
    self.selectedSection = (SettingsSection)idx;
    NSTimeInterval dur = animated ? 0.25 : 0.0;
    
    UIColor *activeBlue = [UIColor colorWithRed:0.47 green:0.75 blue:1.0 alpha:0.90];
    UIColor *shadowBlue = [UIColor colorWithRed:0.31 green:0.67 blue:1.0 alpha:1.0];
    
    for(NSInteger i=0;i<(NSInteger)self.tabButtons.count;i++){
        UIButton *btn=self.tabButtons[i]; UIImageView *iv=[btn viewWithTag:100];
        UILabel *lb=[btn viewWithTag:101]; UIView *glow=self.glowBars[i];
        BOOL active=(i==idx);
        
        [UIView animateWithDuration:dur animations:^{
            if(active){
                btn.backgroundColor=[[UIColor whiteColor] colorWithAlphaComponent:0.08];
                btn.layer.borderWidth=1; btn.layer.borderColor=activeBlue.CGColor;
                btn.layer.shadowColor=shadowBlue.CGColor; btn.layer.shadowOpacity=0.45; btn.layer.shadowRadius=24; btn.layer.shadowOffset=CGSizeZero;
                iv.tintColor=[UIColor colorWithRed:0.47 green:0.75 blue:1.0 alpha:0.95];
                lb.textColor=[UIColor whiteColor];
                glow.alpha=1; glow.layer.shadowOpacity=0.35;
                btn.transform=CGAffineTransformMakeScale(1.015,1.015);
            } else {
                btn.backgroundColor=[UIColor clearColor];
                btn.layer.borderWidth=0;
                btn.layer.shadowOpacity=0;
                iv.tintColor=[[UIColor whiteColor] colorWithAlphaComponent:0.65];
                lb.textColor=[[UIColor whiteColor] colorWithAlphaComponent:0.65];
                glow.alpha=0; glow.layer.shadowOpacity=0;
                btn.transform=CGAffineTransformIdentity;
            }
        }];
    }
    
    if(animated){
        [UIView transitionWithView:self.contentPanel duration:0.25 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
            [self reloadContent];
        } completion:nil];
    } else {
        [self reloadContent];
    }
}

- (void)tabDown:(UIButton*)btn {
    [UIView animateWithDuration:0.08 animations:^{
        btn.transform=CGAffineTransformConcat(CGAffineTransformMakeScale(0.97,0.97),CGAffineTransformMakeTranslation(0,4));
    }];
}
- (void)tabUp:(UIButton*)btn {
    NSInteger idx=self.selectedSection;
    [UIView animateWithDuration:0.15 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0 options:0 animations:^{
        btn.transform=(btn.tag==idx)?CGAffineTransformMakeScale(1.015,1.015):CGAffineTransformIdentity;
    } completion:nil];
}

#pragma mark - Content Pane

- (void)setupContent {
    self.contentPanel=[[UIView alloc] init]; self.contentPanel.translatesAutoresizingMaskIntoConstraints=NO;
    self.contentPanel.backgroundColor=[[UIColor whiteColor] colorWithAlphaComponent:0.02];
    self.contentPanel.layer.cornerRadius=24; self.contentPanel.layer.borderWidth=1;
    self.contentPanel.layer.borderColor=[[UIColor whiteColor] colorWithAlphaComponent:0.08].CGColor;
    self.contentPanel.clipsToBounds=YES;
    [self.mainBlur addSubview:self.contentPanel];
    
    // FONT 2X per titolo sezione (26pt invece di 13pt)
    self.sectionLabel=[[UILabel alloc] init]; 
    self.sectionLabel.font=[UIFont systemFontOfSize:26 weight:UIFontWeightSemibold];
    self.sectionLabel.textColor=[UIColor colorWithRed:0.55 green:0.75 blue:1.0 alpha:1.0];
    self.sectionLabel.translatesAutoresizingMaskIntoConstraints=NO; [self.contentPanel addSubview:self.sectionLabel];
    
    self.tableView=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints=NO; self.tableView.dataSource=self; self.tableView.delegate=self;
    self.tableView.backgroundColor=[UIColor clearColor]; self.tableView.separatorStyle=UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight=68; self.tableView.showsVerticalScrollIndicator=YES; self.tableView.indicatorStyle=UIScrollViewIndicatorStyleWhite;
    self.tableView.alwaysBounceVertical=YES; self.tableView.scrollEnabled=YES;
    self.tableView.decelerationRate=UIScrollViewDecelerationRateNormal;
    [self.tableView registerClass:[SettingsCell class] forCellReuseIdentifier:@"cell"];
    [self.contentPanel addSubview:self.tableView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.contentPanel.leadingAnchor constraintEqualToAnchor:self.sidebarPanel.trailingAnchor constant:4],
        [self.contentPanel.trailingAnchor constraintEqualToAnchor:self.mainBlur.trailingAnchor constant:-10],
        [self.contentPanel.topAnchor constraintEqualToAnchor:self.mainBlur.topAnchor constant:10],
        [self.contentPanel.bottomAnchor constraintEqualToAnchor:self.mainBlur.bottomAnchor constant:-10],
        [self.sectionLabel.topAnchor constraintEqualToAnchor:self.contentPanel.topAnchor constant:10],
        [self.sectionLabel.leadingAnchor constraintEqualToAnchor:self.contentPanel.leadingAnchor constant:18],
        [self.sectionLabel.trailingAnchor constraintEqualToAnchor:self.contentPanel.trailingAnchor constant:-18],
        [self.sectionLabel.heightAnchor constraintEqualToConstant:30],
        [self.tableView.topAnchor constraintEqualToAnchor:self.sectionLabel.bottomAnchor constant:4],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.contentPanel.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.contentPanel.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.contentPanel.bottomAnchor],
    ]];
}

- (void)reloadContent {
    self.sectionLabel.text=sectionTitle(self.selectedSection);
    BOOL d=(self.selectedSection==SettingsSectionDisplay);
    self.slidersScroll.hidden=!d; self.tableView.hidden=d;
    if(d){
        // Forza layout per avere bounds corretti prima di impostare contentSize
        [self.slidersScroll layoutIfNeeded];
        self.slidersScroll.contentSize=CGSizeMake(self.slidersScroll.bounds.size.width>0?self.slidersScroll.bounds.size.width:self.slidersView.bounds.size.width, 1000);
    }
    [self.tableView reloadData]; [self.tableView setContentOffset:CGPointZero animated:NO];
}

- (NSInteger)tableView:(UITableView*)tv numberOfRowsInSection:(NSInteger)s { return (NSInteger)sectionRows(self.selectedSection).count; }
- (UITableViewCell*)tableView:(UITableView*)tv cellForRowAtIndexPath:(NSIndexPath*)ip {
    SettingsCell *c=[tv dequeueReusableCellWithIdentifier:@"cell" forIndexPath:ip]; [c config:sectionRows(self.selectedSection)[ip.row]]; return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    SettingsRow *row=sectionRows(self.selectedSection)[ip.row];
    if(row.type!=RowTypeChevron) return;
    SettingsStore *st=[SettingsStore shared];
    NSString *t=row.key;
    
    if([t isEqualToString:@"Modalità"]){
        st.transportMode=(TransportMode)((st.transportMode+1)%3);
        row.value=transportModeName(st.transportMode);
    }else if([t isEqualToString:@"Percorso preferito"]){
        NSArray *opts=@[@"Più veloce",@"Più breve",@"Eco"];
        NSInteger idx=[opts indexOfObject:st.preferredRoute];
        st.preferredRoute=opts[(idx+1)%opts.count]; row.value=LOC(st.preferredRoute);
    }else if([t isEqualToString:@"Volume guida"]){
        st.voiceVolume+=0.25; if(st.voiceVolume>1.0)st.voiceVolume=0.25;
        row.value=[NSString stringWithFormat:@"%.0f%%",st.voiceVolume*100];
    }else if([t isEqualToString:@"Voci"]){
        NSArray *voices=@[@"Italiano - Chiara",@"Italiano - Marco",@"English - Sarah"];
        NSInteger idx=[voices indexOfObject:st.voiceLanguage];
        st.voiceLanguage=voices[(idx+1)%voices.count]; row.value=st.voiceLanguage;
    }else if([t isEqualToString:@"Tipo mappa"]){
        st.mapType=(st.mapType+1)%3;
        row.value=st.mapType==0?LOC(@"Standard"):st.mapType==1?LOC(@"Satellite"):LOC(@"Hybrid");
    }else if([t isEqualToString:@"Vista 3D predefinita"]){
        st.view3DDefault=!st.view3DDefault; row.value=st.view3DDefault?LOC(@"Attiva"):LOC(@"Disattiva");
    }else if([t isEqualToString:@"Orientamento mappa"]){
        st.mapOrientation=[st.mapOrientation isEqualToString:@"Nord in alto"]?@"Rotta in alto":@"Nord in alto";
        row.value=LOC(st.mapOrientation);
    }else if([t isEqualToString:@"Etichette POI"]){
        NSArray *opts=@[@"Tutte",@"Nessuna",@"Solo principali"];
        NSInteger idx=[opts indexOfObject:st.poiLabels];
        st.poiLabels=opts[(idx+1)%opts.count]; row.value=LOC(st.poiLabels);
    }else if([t isEqualToString:@"Livello avvisi"]){
        st.alertLevel=(AlertLevel)((st.alertLevel+1)%3);
        row.value=alertLevelName(st.alertLevel);
    }else if([t isEqualToString:@"Unità di misura"]){
        st.unitSystem=[st.unitSystem isEqualToString:@"Metrico"]?@"Imperiale":@"Metrico";
        row.value=LOC(st.unitSystem);
    }else if([t isEqualToString:@"Lingua"]){
        AppLanguage newLang=(AppLanguage)((st.language+1)%5);
        st.language=newLang;
        [[LocalizationManager shared] setLanguage:newLang];
        row.value=[[LocalizationManager shared] languageNameForCode:newLang];
        [st save];
        [tv reloadData];
        return;
    }else if([t isEqualToString:@"Cache mappe"]){
        row.value=[NSString stringWithFormat:@"%.1f GB",st.cacheSize];
    }else if([t isEqualToString:@"Privacy & dati"]){
        row.value=@"GDPR 2026";
    }else if([t isEqualToString:@"Crediti e attribuzioni"]){
        [self showCreditsModal];
        return; // non ricaricare la riga
    }else if([t isEqualToString:@"Info su Autista"]){
        row.value=st.appVersion;
    }else if([t isEqualToString:@"Dimensione testo"]){
        NSArray *opts=@[@"Normale",@"Grande",@"Molto grande"];
        NSInteger idx=[opts indexOfObject:st.textSize];
        st.textSize=opts[(idx+1)%opts.count]; row.value=LOC(st.textSize);
    }
    [st save];
    [tv reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - Sliders (TUTTI RIPARATI)

- (NSString*)udk:(NSString*)k { return [NSString stringWithFormat:@"autista_%@",k]; }

- (void)setupSliders {
    self.slidersScroll=[[UIScrollView alloc] init]; self.slidersScroll.translatesAutoresizingMaskIntoConstraints=NO;
    self.slidersScroll.showsVerticalScrollIndicator=YES; self.slidersScroll.indicatorStyle=UIScrollViewIndicatorStyleWhite;
    self.slidersScroll.alwaysBounceVertical=YES; self.slidersScroll.hidden=YES;
    self.slidersScroll.delaysContentTouches=NO; self.slidersScroll.canCancelContentTouches=YES; self.slidersScroll.scrollEnabled=YES; self.slidersScroll.bounces=YES;
    [self.contentPanel addSubview:self.slidersScroll];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.slidersScroll.topAnchor constraintEqualToAnchor:self.sectionLabel.bottomAnchor constant:4],
        [self.slidersScroll.leadingAnchor constraintEqualToAnchor:self.contentPanel.leadingAnchor constant:8],
        [self.slidersScroll.trailingAnchor constraintEqualToAnchor:self.contentPanel.trailingAnchor constant:-8],
        [self.slidersScroll.bottomAnchor constraintEqualToAnchor:self.contentPanel.bottomAnchor constant:-4],
    ]];
    
    self.slidersView=[[UIView alloc] init]; self.slidersView.backgroundColor=[UIColor clearColor];
    self.slidersView.translatesAutoresizingMaskIntoConstraints=NO;
    [self.slidersScroll addSubview:self.slidersView];
    // 4 sliders camera (240) + header Temi (20) + 4 sliders temi (240) + header Bus (20) + 4 sliders bus (240) + header Freccia (20) + 1 slider (60) + margin = 900
    CGFloat SDH=900;
    [NSLayoutConstraint activateConstraints:@[
        [self.slidersView.topAnchor constraintEqualToAnchor:self.slidersScroll.topAnchor],
        [self.slidersView.leadingAnchor constraintEqualToAnchor:self.slidersScroll.leadingAnchor],
        [self.slidersView.trailingAnchor constraintEqualToAnchor:self.slidersScroll.trailingAnchor],
        [self.slidersView.widthAnchor constraintEqualToAnchor:self.slidersScroll.widthAnchor],
        [self.slidersView.heightAnchor constraintEqualToConstant:SDH],
    ]];
    self.slidersScroll.contentSize=CGSizeMake(300,1000); // width placeholder, verrà corretto in viewDidLayoutSubviews
    
    NSUserDefaults *ud=[NSUserDefaults standardUserDefaults];
    float alt=[ud objectForKey:[self udk:@"cam_alt"]]?[ud floatForKey:[self udk:@"cam_alt"]]:self.mapVC.cameraAltitude;
    float pit=[ud objectForKey:[self udk:@"cam_pit"]]?[ud floatForKey:[self udk:@"cam_pit"]]:self.mapVC.cameraPitch;
    float off=[ud objectForKey:[self udk:@"cam_off"]]?[ud floatForKey:[self udk:@"cam_off"]]:self.mapVC.cameraOffset;
    float hed=[ud objectForKey:[self udk:@"cam_hed"]]?[ud floatForKey:[self udk:@"cam_hed"]]:self.mapVC.cameraHeadingOffset;
    float mop=[ud objectForKey:[self udk:@"menu_op"]]?[ud floatForKey:[self udk:@"menu_op"]]:0.5;
    self.mapVC.cameraAltitude=alt; self.mapVC.cameraPitch=pit; self.mapVC.cameraOffset=off; self.mapVC.cameraHeadingOffset=hed;
    
    float tin=[ud objectForKey:[self udk:@"theme_tin"]]?[ud floatForKey:[self udk:@"theme_tin"]]:0.0;
    float bor=[ud objectForKey:[self udk:@"theme_bor"]]?[ud floatForKey:[self udk:@"theme_bor"]]:0.25;
    float lum=[ud objectForKey:[self udk:@"theme_lum"]]?[ud floatForKey:[self udk:@"theme_lum"]]:0.0;
    
    [ud setFloat:alt forKey:[self udk:@"cam_alt"]];
    [ud setFloat:pit forKey:[self udk:@"cam_pit"]];
    [ud setFloat:off forKey:[self udk:@"cam_off"]];
    [ud setFloat:hed forKey:[self udk:@"cam_hed"]];
    [ud setFloat:mop forKey:[self udk:@"menu_op"]];
    [ud setFloat:tin forKey:[self udk:@"theme_tin"]];
    [ud setFloat:bor forKey:[self udk:@"theme_bor"]];
    [ud setFloat:lum forKey:[self udk:@"theme_lum"]];
    [ud synchronize];
    [self rebuildSliders];
    [self applySavedThemeValues];
}

- (void)applySavedThemeValues {
    // Trasparenza: applica blur style salvato
    NSUserDefaults *ud=[NSUserDefaults standardUserDefaults];
    float mop=[ud floatForKey:[self udk:@"menu_op"]];
    if(mop>0) [self applyBlurStyle:mop];
}

- (void)rebuildSliders {
    NSUserDefaults *ud=[NSUserDefaults standardUserDefaults];
    float altV=[ud floatForKey:[self udk:@"cam_alt"]];
    float pitV=[ud floatForKey:[self udk:@"cam_pit"]];
    float offV=[ud floatForKey:[self udk:@"cam_off"]];
    float hedV=[ud floatForKey:[self udk:@"cam_hed"]];
    float mopV=[ud floatForKey:[self udk:@"menu_op"]];
    float tinV=[ud floatForKey:[self udk:@"theme_tin"]];
    float borV=[ud floatForKey:[self udk:@"theme_bor"]];
    float lumV=[ud floatForKey:[self udk:@"theme_lum"]];
    
    for(UIView *v in self.slidersView.subviews) [v removeFromSuperview];
    
    // ── 📷 Camera 3D ──
    UILabel *st=[[UILabel alloc] init]; st.text=LOC(@"📷 Camera 3D"); st.font=[UIFont boldSystemFontOfSize:14];
    st.textColor=[[UIColor whiteColor] colorWithAlphaComponent:0.65]; st.translatesAutoresizingMaskIntoConstraints=NO;
    [self.slidersView addSubview:st];
    [NSLayoutConstraint activateConstraints:@[
        [st.topAnchor constraintEqualToAnchor:self.slidersView.topAnchor constant:4],
        [st.leadingAnchor constraintEqualToAnchor:self.slidersView.leadingAnchor constant:4],
    ]];
    
    UISlider *a1,*a2,*a3,*a4,*a5,*a6,*a7,*a8,*a9,*a10,*a11,*a12,*a13;
    UILabel *v1,*v2,*v3,*v4,*v5,*v6,*v7,*v8,*v9,*v10,*v11,*v12,*v13;
    [self mkSX:0 top:30  t:LOC(@"Altezza")         mn:50  mx:2500 val:altV fn:^(UISlider*sl){ self.mapVC.cameraAltitude=sl.value; self.altV.text=[NSString stringWithFormat:@"%.0f m",sl.value]; } minL:@"50m" midL:@"1500" maxL:@"2500" s:&a1 l:&v1 save:@"cam_alt" cam:YES];
    [self mkSX:1 top:90  t:LOC(@"Angolazione")     mn:0   mx:75   val:pitV fn:^(UISlider*sl){ self.mapVC.cameraPitch=sl.value; self.pitV.text=[NSString stringWithFormat:@"%.0f°",sl.value]; } minL:@"0°" midL:@"37°" maxL:@"75°" s:&a2 l:&v2 save:@"cam_pit" cam:YES];
    [self mkSX:2 top:150 t:LOC(@"Destra/Sinistra") mn:-50 mx:50   val:offV fn:^(UISlider*sl){ self.mapVC.cameraOffset=sl.value; self.offV.text=[NSString stringWithFormat:@"%.0f m",sl.value]; } minL:@"SX" midL:@"0" maxL:@"DX" s:&a3 l:&v3 save:@"cam_off" cam:YES];
    [self mkSX:3 top:210 t:LOC(@"Tilt visuale")    mn:-45 mx:45   val:hedV fn:^(UISlider*sl){ self.mapVC.cameraHeadingOffset=sl.value; self.headV.text=[NSString stringWithFormat:@"%.0f°",sl.value]; } minL:@"-45°" midL:@"0°" maxL:@"+45°" s:&a4 l:&v4 save:@"cam_hed" cam:YES];
    _altS=a1;_pitS=a2;_offS=a3;_headS=a4; _altV=v1;_pitV=v2;_offV=v3;_headV=v4;
    
    // ── 🗺️ Freccia ──
    float arrR = [SettingsStore shared].arrowRotation;
    
    UILabel *ah = [[UILabel alloc] init]; ah.text = LOC(@"🗺️ Freccia");
    ah.font = [UIFont boldSystemFontOfSize:14];
    ah.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.65]; ah.translatesAutoresizingMaskIntoConstraints=NO;
    [self.slidersView addSubview:ah];
    [NSLayoutConstraint activateConstraints:@[
        [ah.topAnchor constraintEqualToAnchor:self.slidersView.topAnchor constant:250],
        [ah.leadingAnchor constraintEqualToAnchor:self.slidersView.leadingAnchor constant:4],
    ]];
    
    [self mkSX:12 top:270 t:LOC(@"Rotazione") mn:-180 mx:180 val:arrR fn:^(UISlider*sl){
        [SettingsStore shared].arrowRotation = sl.value; [[SettingsStore shared] save];
        [self.mapVC applyArrowTransform];
        self->_arrowRV.text=[NSString stringWithFormat:@"%.0f°",sl.value];
    } minL:LOC(@"-180°") midL:LOC(@"0°") maxL:LOC(@"+180°") s:&a13 l:&v13 save:@"arrR" cam:NO];
    _arrowRS=a13; _arrowRV=v13;
    [a13 addTarget:self action:@selector(arrowSliderDown:) forControlEvents:UIControlEventTouchDown];
    [a13 addTarget:self action:@selector(arrowSliderUp:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];
    
    // ── 🎨 Temi ──
    UILabel *th=[[UILabel alloc] init]; th.text=LOC(@"🎨 Temi"); th.font=[UIFont boldSystemFontOfSize:14];
    th.textColor=[[UIColor whiteColor] colorWithAlphaComponent:0.65]; th.translatesAutoresizingMaskIntoConstraints=NO;
    [self.slidersView addSubview:th];
    [NSLayoutConstraint activateConstraints:@[
        [th.topAnchor constraintEqualToAnchor:self.slidersView.topAnchor constant:310],
        [th.leadingAnchor constraintEqualToAnchor:self.slidersView.leadingAnchor constant:4],
    ]];
    
    // 1. TRASPARENZA — effetto blur (vetro smerigliato)
    [self mkSX:4 top:336 t:LOC(@"Trasparenza") mn:0.1 mx:1.0 val:mopV fn:^(UISlider*sl){
        [self applyBlurStyle:sl.value];
        [self.mapVC applyMenuOpacity];
        self.traspV.text=[NSString stringWithFormat:@"%.0f%%",sl.value*100];
        [[NSUserDefaults standardUserDefaults] setFloat:sl.value forKey:[self udk:@"menu_op"]];
        [[NSUserDefaults standardUserDefaults] synchronize];
    } minL:LOC(@"Vetro") midL:@"" maxL:LOC(@"Pieno") s:&a5 l:&v5 save:@"menu_op" cam:NO];
    _traspS=a5; _traspV=v5;
    
    // 2. LUMINOSITÀ — overlay BIANCO (illumina la finestra)
    [self mkSX:5 top:396 t:LOC(@"Luminosità") mn:0.0 mx:0.4 val:lumV fn:^(UISlider*sl){
        UIView *lumOverlay=[self.mainBlur viewWithTag:888];
        if(!lumOverlay){
            lumOverlay=[[UIView alloc] init]; lumOverlay.tag=888; lumOverlay.userInteractionEnabled=NO;
            lumOverlay.translatesAutoresizingMaskIntoConstraints=NO;
            [self.mainBlur addSubview:lumOverlay];
            [NSLayoutConstraint activateConstraints:@[
                [lumOverlay.topAnchor constraintEqualToAnchor:self.mainBlur.topAnchor],
                [lumOverlay.bottomAnchor constraintEqualToAnchor:self.mainBlur.bottomAnchor],
                [lumOverlay.leadingAnchor constraintEqualToAnchor:self.mainBlur.leadingAnchor],
                [lumOverlay.trailingAnchor constraintEqualToAnchor:self.mainBlur.trailingAnchor],
            ]];
        }
        lumOverlay.backgroundColor=[[UIColor whiteColor] colorWithAlphaComponent:sl.value];
    } minL:LOC(@"Spenta") midL:@"" maxL:LOC(@"Accesa") s:&a6 l:&v6 save:@"theme_lum" cam:NO];
    
    // 3. SPESSORE BORDO — UIView border (semplice, funziona)
    [self mkSX:6 top:456 t:LOC(@"Spessore bordo") mn:0.0 mx:1.0 val:borV fn:^(UISlider*sl){
        UIView *borderView=[self.mainBlur viewWithTag:555];
        if(!borderView){
            borderView=[[UIView alloc] init]; borderView.tag=555; borderView.userInteractionEnabled=NO;
            borderView.backgroundColor=[UIColor clearColor];
            borderView.translatesAutoresizingMaskIntoConstraints=NO;
            [self.mainBlur addSubview:borderView];
            [NSLayoutConstraint activateConstraints:@[
                [borderView.topAnchor constraintEqualToAnchor:self.mainBlur.topAnchor],
                [borderView.bottomAnchor constraintEqualToAnchor:self.mainBlur.bottomAnchor],
                [borderView.leadingAnchor constraintEqualToAnchor:self.mainBlur.leadingAnchor],
                [borderView.trailingAnchor constraintEqualToAnchor:self.mainBlur.trailingAnchor],
            ]];
            borderView.layer.cornerRadius=24;
        }
        borderView.layer.borderColor=[[UIColor whiteColor] colorWithAlphaComponent:0.5].CGColor;
        borderView.layer.borderWidth=sl.value*4; // 0-4px
    } minL:LOC(@"Sottile") midL:@"" maxL:LOC(@"Spesso") s:&a7 l:&v7 save:@"theme_bor" cam:NO];
    
    // 4. TINTA
    [self mkSX:7 top:516 t:LOC(@"Tinta calda/fredda") mn:-1.0 mx:1.0 val:tinV fn:^(UISlider*sl){
        UIView *tint=[self.mainBlur viewWithTag:999];
        if(!tint){ tint=[[UIView alloc] init]; tint.tag=999; tint.userInteractionEnabled=NO; tint.translatesAutoresizingMaskIntoConstraints=NO; [self.mainBlur addSubview:tint]; [NSLayoutConstraint activateConstraints:@[ [tint.topAnchor constraintEqualToAnchor:self.mainBlur.topAnchor], [tint.bottomAnchor constraintEqualToAnchor:self.mainBlur.bottomAnchor], [tint.leadingAnchor constraintEqualToAnchor:self.mainBlur.leadingAnchor], [tint.trailingAnchor constraintEqualToAnchor:self.mainBlur.trailingAnchor] ]]; }
        CGFloat absv=fabs(sl.value);
        UIColor *c;
        if(sl.value>0) c=[UIColor colorWithRed:1.0 green:0.65 blue:0.3 alpha:absv*0.12];
        else if(sl.value<0) c=[UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:absv*0.12];
        else c=[UIColor clearColor];
        tint.backgroundColor=c;
    } minL:LOC(@"Calda") midL:LOC(@"Neutra") maxL:LOC(@"Fredda") s:&a8 l:&v8 save:@"theme_tin" cam:NO];
    
    // ── 🚌 Autobus ──
    SettingsStore *store=[SettingsStore shared];
    float busY=[ud objectForKey:[self udk:@"busY"]]?[ud floatForKey:[self udk:@"busY"]]:store.busOffsetY;
    float busX=[ud objectForKey:[self udk:@"busX"]]?[ud floatForKey:[self udk:@"busX"]]:store.busOffsetX;
    float busS=[ud objectForKey:[self udk:@"busS"]]?[ud floatForKey:[self udk:@"busS"]]:store.busScale;
    float busR=[ud objectForKey:[self udk:@"busR"]]?[ud floatForKey:[self udk:@"busR"]]:store.busRotation;
    
    UILabel *bh=[[UILabel alloc] init]; bh.text=LOC(@"🚌 Autobus"); bh.font=[UIFont boldSystemFontOfSize:14];
    bh.textColor=[[UIColor whiteColor] colorWithAlphaComponent:0.65]; bh.translatesAutoresizingMaskIntoConstraints=NO;
    [self.slidersView addSubview:bh];
    [NSLayoutConstraint activateConstraints:@[
        [bh.topAnchor constraintEqualToAnchor:self.slidersView.topAnchor constant:576],
        [bh.leadingAnchor constraintEqualToAnchor:self.slidersView.leadingAnchor constant:4],
    ]];
    
    [self mkSX:8 top:596 t:LOC(@"Alto/Basso") mn:-3 mx:3 val:busY fn:^(UISlider*sl){
        store.busOffsetY=sl.value; [store save];
        [self.mapVC.busVC updateBusScale];
        self->_busYV.text=[NSString stringWithFormat:@"%.1f",sl.value];
    } minL:LOC(@"Alto") midL:@"" maxL:LOC(@"Basso") s:&a9 l:&v9 save:@"busY" cam:NO];
    
    [self mkSX:9 top:656 t:LOC(@"Sinistra/Destra") mn:-3 mx:3 val:busX fn:^(UISlider*sl){
        store.busOffsetX=sl.value; [store save];
        [self.mapVC.busVC updateBusScale];
        self->_busXV.text=[NSString stringWithFormat:@"%.1f",sl.value];
    } minL:LOC(@"SX") midL:@"" maxL:LOC(@"DX") s:&a10 l:&v10 save:@"busX" cam:NO];
    
    [self mkSX:10 top:716 t:LOC(@"Ingrandimento") mn:-0.5 mx:2.5 val:busS fn:^(UISlider*sl){
        store.busScale=sl.value; [store save];
        [self.mapVC.busVC updateBusScale];
        self->_busSV.text=[NSString stringWithFormat:@"%.1fx",sl.value];
    } minL:LOC(@"-0.5x") midL:@"" maxL:LOC(@"2.5x") s:&a11 l:&v11 save:@"busS" cam:NO];
    
    [self mkSX:11 top:776 t:LOC(@"Rotazione") mn:-270 mx:270 val:busR fn:^(UISlider*sl){
        store.busRotation=sl.value; [store save];
        [self.mapVC.busVC applyBusRotation];
        self->_busRV.text=[NSString stringWithFormat:@"%.0f°",sl.value];
    } minL:LOC(@"-270°") midL:@"" maxL:LOC(@"+270°") s:&a12 l:&v12 save:@"busR" cam:NO];
    
    _busYS=a9; _busXS=a10; _busSS=a11; _busRS=a12; _busYV=v9; _busXV=v10; _busSV=v11; _busRV=v12;
    // Touch handlers: fade impostazioni quando modifichi autobus
    for (UISlider *bs in @[a9,a10,a11,a12]) {
        [bs addTarget:self action:@selector(busSliderDown:) forControlEvents:UIControlEventTouchDown];
        [bs addTarget:self action:@selector(busSliderUp:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];
    }
    
}

// Helper: Trasparenza = alpha del background (0.15=molto vetro, 0.7=quasi opaco)
- (void)applyBlurStyle:(float)v {
    self.mainBlur.backgroundColor=[[UIColor blackColor] colorWithAlphaComponent:0.15 + v*0.55];
}

static char kFn,kVl,kKey;

- (void)mkSX:(int)tag top:(CGFloat)top t:(NSString*)t mn:(float)mn mx:(float)mx val:(float)val fn:(void(^)(UISlider*))fn minL:(NSString*)minL midL:(NSString*)midL maxL:(NSString*)maxL s:(UISlider**)sp l:(UILabel**)lp save:(NSString*)key cam:(BOOL)isCam {
    UILabel *lb=[[UILabel alloc] init]; lb.text=t; lb.font=[UIFont systemFontOfSize:10];
    lb.textColor=[[UIColor whiteColor] colorWithAlphaComponent:0.65]; lb.translatesAutoresizingMaskIntoConstraints=NO;
    [self.slidersView addSubview:lb];
    
    UILabel *vl=[[UILabel alloc] init]; vl.text=[NSString stringWithFormat:isCam?@"%.0f":(mx>1?@"%.0f%%":@"%.1f"),val*(mx>1&&!isCam?100:1)];
    vl.font=[UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium];
    vl.textColor=[UIColor whiteColor]; vl.textAlignment=NSTextAlignmentRight; vl.translatesAutoresizingMaskIntoConstraints=NO;
    [self.slidersView addSubview:vl];
    
    UISlider *sl=[[UISlider alloc] init]; sl.minimumValue=mn; sl.maximumValue=mx; sl.value=val;
    sl.tintColor=[UIColor systemBlueColor]; sl.tag=tag; sl.userInteractionEnabled=YES;
    sl.translatesAutoresizingMaskIntoConstraints=NO;
    sl.continuous=YES;
    [sl addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    if(isCam){
        [sl addTarget:self action:@selector(camSliderDown:) forControlEvents:UIControlEventTouchDown];
        [sl addTarget:self action:@selector(camSliderUp:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];
    }
    objc_setAssociatedObject(sl,&kFn,fn,OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(sl,&kVl,vl,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(sl,&kKey,key,OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self.slidersView addSubview:sl];
    
    [NSLayoutConstraint activateConstraints:@[
        [lb.topAnchor constraintEqualToAnchor:self.slidersView.topAnchor constant:top], [lb.leadingAnchor constraintEqualToAnchor:self.slidersView.leadingAnchor constant:4],
        [sl.topAnchor constraintEqualToAnchor:lb.bottomAnchor constant:2], [sl.leadingAnchor constraintEqualToAnchor:self.slidersView.leadingAnchor constant:4],
        [sl.trailingAnchor constraintEqualToAnchor:vl.leadingAnchor constant:-6],
        [vl.trailingAnchor constraintEqualToAnchor:self.slidersView.trailingAnchor constant:-4], [vl.centerYAnchor constraintEqualToAnchor:sl.centerYAnchor], [vl.widthAnchor constraintEqualToConstant:50],
    ]];
    
    UILabel *minLab=[[UILabel alloc] init]; minLab.text=minL; minLab.font=[UIFont systemFontOfSize:9];
    minLab.textColor=[[UIColor whiteColor] colorWithAlphaComponent:0.4]; minLab.translatesAutoresizingMaskIntoConstraints=NO;
    [self.slidersView addSubview:minLab];
    [NSLayoutConstraint activateConstraints:@[ [minLab.topAnchor constraintEqualToAnchor:sl.bottomAnchor constant:2], [minLab.leadingAnchor constraintEqualToAnchor:sl.leadingAnchor] ]];
    
    if(midL.length){
        UILabel *midLab=[[UILabel alloc] init]; midLab.text=midL; midLab.font=[UIFont systemFontOfSize:9];
        midLab.textColor=[[UIColor whiteColor] colorWithAlphaComponent:0.4]; midLab.textAlignment=NSTextAlignmentCenter; midLab.translatesAutoresizingMaskIntoConstraints=NO;
        [self.slidersView addSubview:midLab];
        [NSLayoutConstraint activateConstraints:@[ [midLab.topAnchor constraintEqualToAnchor:sl.bottomAnchor constant:2], [midLab.centerXAnchor constraintEqualToAnchor:sl.centerXAnchor] ]];
    }
    
    UILabel *maxLab=[[UILabel alloc] init]; maxLab.text=maxL; maxLab.font=[UIFont systemFontOfSize:9];
    maxLab.textColor=[[UIColor whiteColor] colorWithAlphaComponent:0.4]; maxLab.textAlignment=NSTextAlignmentRight; maxLab.translatesAutoresizingMaskIntoConstraints=NO;
    [self.slidersView addSubview:maxLab];
    [NSLayoutConstraint activateConstraints:@[ [maxLab.topAnchor constraintEqualToAnchor:sl.bottomAnchor constant:2], [maxLab.trailingAnchor constraintEqualToAnchor:sl.trailingAnchor] ]];
    
    *sp=sl; *lp=vl;
}

- (void)sliderChanged:(UISlider*)sl {
    void(^fn)(UISlider*)=objc_getAssociatedObject(sl,&kFn);
    UILabel *vl=objc_getAssociatedObject(sl,&kVl);
    NSString *key=objc_getAssociatedObject(sl,&kKey);
    if(fn) fn(sl);
    if(vl){
        float v=sl.value;
        if(sl.tag<4) vl.text=[NSString stringWithFormat:@"%.0f",v];
        else if(sl.tag==4||sl.tag==6) vl.text=[NSString stringWithFormat:@"%.0f%%",v*100];
        else if(sl.tag>=8 && sl.tag<=10) vl.text=[NSString stringWithFormat:@"%.1f",v];
        else if(sl.tag==11) vl.text=[NSString stringWithFormat:@"%.0f°",v];
        else if(sl.tag==12) vl.text=[NSString stringWithFormat:@"%.0f°",v];
        else vl.text=[NSString stringWithFormat:@"%.0f%%",v*100];
    }
    NSUserDefaults *ud=[NSUserDefaults standardUserDefaults];
    [ud setFloat:sl.value forKey:[self udk:key]];
    [ud synchronize];
    if(sl.tag<4) [self.mapVC applyCameraSettings];
    if(sl.tag>=8 && sl.tag<=11) {
        // Mostra il bus durante la modifica
        self.mapVC.busVC.view.hidden = NO;
        self.mapVC.busVC.view.alpha = 1.0;
    }
}

- (void)camSliderDown:(UISlider*)sl { [UIView animateWithDuration:0.2 animations:^{ self.mainBlur.alpha=0.12; }]; }
- (void)camSliderUp:(UISlider*)sl { [UIView animateWithDuration:0.2 animations:^{ self.mainBlur.alpha=1.0; }]; }

- (void)busSliderDown:(UISlider*)sl {
    // Fade impostazioni e mostra autobus in tempo reale
    [UIView animateWithDuration:0.25 animations:^{
        self.mainBlur.alpha = 0.08;
        self.mapVC.busVC.view.hidden = NO;
        self.mapVC.busVC.view.alpha = 1.0;
    }];
}
- (void)busSliderUp:(UISlider*)sl {
    [UIView animateWithDuration:0.25 animations:^{
        self.mainBlur.alpha = 1.0;
    }];
}

- (void)arrowSliderDown:(UISlider*)sl {
    [UIView animateWithDuration:0.2 animations:^{
        self.mainBlur.alpha = 0;
    }];
}
- (void)arrowSliderUp:(UISlider*)sl {
    [UIView animateWithDuration:0.2 animations:^{
        self.mainBlur.alpha = 1.0;
    }];
}

#pragma mark - Layout adattivo

- (void)updateLayoutForSize:(CGSize)size {
    BOOL landscape=(size.width>size.height&&size.width>400);
    self.sidebarWidthConstraint.constant=landscape?175:76;
    for(UILabel *lb in self.tabLabels) lb.hidden=!landscape;
}

#pragma mark - Back

- (void)setupBack {
    UIButton *back=[UIButton buttonWithType:UIButtonTypeSystem]; back.translatesAutoresizingMaskIntoConstraints=NO;
    back.backgroundColor=[[UIColor whiteColor] colorWithAlphaComponent:0.02]; back.layer.cornerRadius=20; back.layer.borderWidth=1;
    back.layer.borderColor=[[UIColor whiteColor] colorWithAlphaComponent:0.08].CGColor;
    [back setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal]; back.tintColor=[UIColor whiteColor];
    [back addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [self.mainBlur addSubview:back];
    [NSLayoutConstraint activateConstraints:@[
        [back.leadingAnchor constraintEqualToAnchor:self.mainBlur.leadingAnchor constant:24],
        [back.bottomAnchor constraintEqualToAnchor:self.mainBlur.bottomAnchor constant:-14],
        [back.widthAnchor constraintEqualToConstant:52],[back.heightAnchor constraintEqualToConstant:52],
    ]];
}
- (void)dismiss {
    [UIView animateWithDuration:0.25 animations:^{
        self.view.alpha = 0;
    } completion:^(BOOL finished){
        [self willMoveToParentViewController:nil];
        [self.view removeFromSuperview];
        [self removeFromParentViewController];
        // Ripristina finestra autobus se era visibile
        [self.mapVC settingsDidClose];
    }];
}

- (void)showCreditsModal {
    NSString *credits = 
        @"━━━━━━━━━━━━━━━━━━━━\n"
        @"🗺️ DATI CARTOGRAFICI\n"
        @"© OpenStreetMap contributors\n"
        @"openstreetmap.org/copyright\n"
        @"Licenza: ODbL 1.0\n\n"
        @"🚏 FERMATE AUTOBUS\n"
        @"Overpass API (OpenStreetMap)\n"
        @"overpass-api.de\n"
        @"Dati: © OSM contributors\n\n"
        @"🚌 MODELLO 3D\n"
        @"Brisbane City Scania L94UB\n"
        @"Autore: Brisbane City Council\n"
        @"Fonte: Sketchfab (CC-BY)\n\n"
        @"🍎 PIATTAFORMA\n"
        @"Apple MapKit & CoreLocation\n"
        @"SF Symbols © Apple Inc.\n"
        @"SceneKit 3D Engine\n"
        @"Metal Graphics Framework\n\n"
        @"🛠️ SVILUPPO\n"
        @"Autista Navigator — Lorenzo8484\n"
        @"github.com/Lorenzo8484/Autista\n"
        @"Build: clang-19 + ld64.lld-19\n"
        @"SDK: iPhoneOS 16.5\n\n"
        @"━━━━━━━━━━━━━━━━━━━━\n"
        @"Grazie a tutti i contributor\n"
        @"open source! ❤️";
    
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"📜 Crediti e attribuzioni"
                                                                 message:credits
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Chiudi" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
