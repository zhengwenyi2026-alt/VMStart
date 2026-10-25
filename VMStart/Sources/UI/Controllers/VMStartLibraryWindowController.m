//
//  VMStartLibraryWindowController.m
//  VMStart
//
//  Copyright (c) 2024 zhengwenyi2026-alt. Licensed under GPLv2.
//

#import "VMStartLibraryWindowController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "VMStartVirtualMachine.h"
#import "VMStartArchitectureManager.h"
#import "VMStartConfigWindowController.h"
#import "VMStartConsoleWindowController.h"
#import "VMStartNetworkEditorController.h"
#import "VMStartLocalization.h"
#import "VMStartCardView.h"
#import "VMStartEngineSelector.h"
#import "VMStartSettingsWindowController.h"

// 自上而下布局的容器，供详情页滚动区域使用
@interface VMStartFlippedView : NSView
@end

@implementation VMStartFlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface VMStartLibraryWindowController () <VMStartConfigDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSMenuDelegate>
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSView *sidebarView;
@property (nonatomic, strong) NSView *mainContentView;
@property (nonatomic, strong) NSView *welcomeView;
@property (nonatomic, strong) NSView *detailsView;
@property (nonatomic, strong) VMStartConfigWindowController *configWC;
@property (nonatomic, strong) NSMutableDictionary<NSString *, VMStartConsoleWindowController *> *consoleControllers;
@property (nonatomic, copy) NSArray<VMStartVirtualMachine *> *filteredVMs;
@property (nonatomic, strong) NSTextField *statusBarLabel;
@property (nonatomic, strong) VMStartModeSwitcher *modeSwitcher;
@property (nonatomic, assign) VMStartAppMode appMode;
@property (nonatomic, strong) VMStartCardView *notesCardRef;
@property (nonatomic, strong) NSView *diskProgressBg;
@property (nonatomic, strong) NSView *diskProgressFill;
@property (nonatomic, strong) NSMenu *contextMenu;
@property (nonatomic, assign) BOOL showFavoritesOnly;
@property (nonatomic, strong) NSButton *favoritesButton;
@property (nonatomic, strong) VMStartNetworkEditorController *networkEditorWC;
// 日志与打印
@property (nonatomic, strong) NSWindow *logPanel;
@property (nonatomic, strong) NSTextView *logTextView;
@property (nonatomic, strong) NSButton *viewLogButton;
@property (nonatomic, strong) NSButton *printLogButton;
@property (nonatomic, strong) NSButton *autoPrintButton;
@property (nonatomic, assign) BOOL autoPrintEnabled;
@property (nonatomic, assign) BOOL printerAvailable;
@property (nonatomic, strong) NSMutableArray<NSString *> *logEntries;
@end

@implementation VMStartLibraryWindowController

- (instancetype)init {
    NSRect frame = NSMakeRect(0, 0, 1100, 720);
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame styleMask:style backing:NSBackingStoreBuffered defer:NO];
    window.title = @"VMStart";
    window.minSize = NSMakeSize(900, 600);
    [window center];
    window.titlebarAppearsTransparent = YES;
    window.titleVisibility = NSWindowTitleHidden;
    window.backgroundColor = [NSColor windowBackgroundColor];
    self = [super initWithWindow:window];
    if (self) {
        _virtualMachines = [NSMutableArray array];
        _consoleControllers = [NSMutableDictionary dictionary];
        _vmDirectory = [self defaultVMDirectory];
        _appMode = VMStartAppModeStandard;
        _showFavoritesOnly = NO;
        _logEntries = [NSMutableArray array];
        _autoPrintEnabled = NO;
        _printerAvailable = NO;
        [self setupContextMenu];
        [self checkPrinterAvailability];
        [self setupUI];
        [self refreshVMList];
    }
    return self;
}

- (NSString *)defaultVMDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *appSupport = [paths firstObject];
    NSString *vmDir = [appSupport stringByAppendingPathComponent:@"VMStart/VirtualMachines"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:vmDir]) {
        [fm createDirectoryAtPath:vmDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return vmDir;
}

#pragma mark - UI Setup

- (void)setupUI {
    NSView *root = self.window.contentView;
    CGFloat sidebarW = 260;
    CGFloat windowH = root.bounds.size.height;

    // ─── Sidebar (VMware-style clean panel) ───
    self.sidebarView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, sidebarW, windowH)];
    self.sidebarView.wantsLayer = YES;
    self.sidebarView.layer.backgroundColor = [NSColor colorWithRed:0.17 green:0.17 blue:0.20 alpha:1.0].CGColor;
    self.sidebarView.autoresizingMask = NSViewHeightSizable;
    // 侧栏为固定深色背景，强制深色外观使搜索框等控件在浅色模式下也协调
    self.sidebarView.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    [root addSubview:self.sidebarView];

    // Sidebar right edge line
    NSView *sepLine = [[NSView alloc] initWithFrame:NSMakeRect(sidebarW, 0, 1, windowH)];
    sepLine.wantsLayer = YES;
    sepLine.layer.backgroundColor = [NSColor colorWithRed:0.12 green:0.12 blue:0.14 alpha:1.0].CGColor;
    sepLine.autoresizingMask = NSViewMaxXMargin | NSViewHeightSizable;
    [root addSubview:sepLine];

    // "Devices" header
    NSTextField *sideHeader = [[NSTextField alloc] initWithFrame:NSMakeRect(16, windowH - 36, sidebarW - 32, 20)];
    sideHeader.stringValue = AMLocalizedString(@"sidebar.devices");
    sideHeader.font = [NSFont boldSystemFontOfSize:14];
    sideHeader.textColor = [NSColor colorWithRed:0.85 green:0.85 blue:0.9 alpha:1.0];
    sideHeader.bezeled = NO; sideHeader.drawsBackground = NO; sideHeader.editable = NO;
    sideHeader.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
    [self.sidebarView addSubview:sideHeader];

    // Search field (dark style)
    self.searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(12, windowH - 66, sidebarW - 24, 26)];
    self.searchField.placeholderString = AMLocalizedString(@"lib.searchPlaceholder");
    self.searchField.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
    self.searchField.delegate = self;
    self.searchField.wantsLayer = YES;
    [self.sidebarView addSubview:self.searchField];

    // "My Computer" section header
    NSTextField *mcHeader = [[NSTextField alloc] initWithFrame:NSMakeRect(16, windowH - 98, sidebarW - 32, 18)];
    mcHeader.stringValue = AMLocalizedString(@"sidebar.myComputer");
    mcHeader.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    mcHeader.textColor = [NSColor colorWithRed:0.55 green:0.55 blue:0.6 alpha:1.0];
    mcHeader.bezeled = NO; mcHeader.drawsBackground = NO; mcHeader.editable = NO;
    mcHeader.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
    [self.sidebarView addSubview:mcHeader];

    // Favorites filter button (compact)
    self.favoritesButton = [NSButton buttonWithTitle:[@"\u2606 " stringByAppendingString:AMLocalizedString(@"sidebar.favorites")] target:self action:@selector(toggleFavoritesFilter:)];
    self.favoritesButton.frame = NSMakeRect(sidebarW - 100, windowH - 98, 88, 18);
    self.favoritesButton.bezelStyle = NSBezelStyleInline;
    self.favoritesButton.font = [NSFont systemFontOfSize:9 weight:NSFontWeightMedium];
    self.favoritesButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [self.favoritesButton setContentTintColor:[NSColor colorWithRed:0.6 green:0.6 blue:0.65 alpha:1.0]];
    [self.sidebarView addSubview:self.favoritesButton];

    // VM list
    self.scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 40, sidebarW, windowH - 104 - 40)];
    self.scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.scrollView.borderType = NSNoBorder;
    self.scrollView.drawsBackground = NO;
    self.scrollView.autohidesScrollers = YES;

    self.tableView = [[NSTableView alloc] initWithFrame:self.scrollView.bounds];
    self.tableView.headerView = nil;
    self.tableView.rowHeight = 60;
    self.tableView.intercellSpacing = NSMakeSize(0, 2);
    self.tableView.backgroundColor = [NSColor clearColor];
    // 普通高亮样式：源列表样式会附带半透明背景，窗口化与全屏下颜色不一致
    self.tableView.style = NSTableViewStyleFullWidth;
    self.tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.floatsGroupRows = NO;

    // Drag & drop support
    [self.tableView registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    self.tableView.allowsMultipleSelection = YES;
    self.tableView.menu = self.contextMenu;

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"vm"];
    col.width = sidebarW - 4;
    col.resizingMask = NSTableColumnAutoresizingMask;
    [self.tableView addTableColumn:col];

    self.scrollView.documentView = self.tableView;
    [self.sidebarView addSubview:self.scrollView];

    // Sidebar bottom toolbar (dark style)
    NSView *sidebarToolbar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, sidebarW, 40)];
    sidebarToolbar.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    sidebarToolbar.wantsLayer = YES;
    sidebarToolbar.layer.backgroundColor = [NSColor colorWithRed:0.14 green:0.14 blue:0.17 alpha:1.0].CGColor;
    [self.sidebarView addSubview:sidebarToolbar];

    // Bottom toolbar - only mode switcher (dropdown)
    NSColor *btnColor = [NSColor colorWithRed:0.7 green:0.7 blue:0.75 alpha:1.0];
    self.modeSwitcher = [[VMStartModeSwitcher alloc] initWithFrame:NSMakeRect(8, 8, 100, 24)];
    self.modeSwitcher.currentMode = self.appMode;
    __weak typeof(self) weakSelf = self;
    self.modeSwitcher.onModeChange = ^(VMStartAppMode mode) {
        weakSelf.appMode = mode;
        [weakSelf updateDetailsForCurrentSelection];
    };
    self.modeSwitcher.autoresizingMask = NSViewMaxYMargin;
    [sidebarToolbar addSubview:self.modeSwitcher];

    // Settings button (top-right corner)
    NSButton *settingsBtn = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:nil]
                                              target:self action:@selector(openSettings:)];
    settingsBtn.frame = NSMakeRect(sidebarW - 36, 8, 28, 24);
    settingsBtn.bezelStyle = NSBezelStyleInline;
    settingsBtn.imageScaling = NSImageScaleProportionallyDown;
    [settingsBtn setContentTintColor:btnColor];
    settingsBtn.toolTip = AMLocalizedString(@"detail.settings");
    [sidebarToolbar addSubview:settingsBtn];

    // ─── Main content (dark background like UTM) ───
    self.mainContentView = [[NSView alloc] initWithFrame:NSMakeRect(sidebarW + 1, 0, root.bounds.size.width - sidebarW - 1, windowH)];
    self.mainContentView.wantsLayer = YES;
    self.mainContentView.layer.backgroundColor = [NSColor colorWithRed:0.18 green:0.18 blue:0.20 alpha:1.0].CGColor;
    self.mainContentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [root addSubview:self.mainContentView];

    // ─── Top-right toolbar buttons (查看日志 / 打印日志) ───
    NSView *topToolbar = [[NSView alloc] initWithFrame:NSMakeRect(sidebarW + 1, windowH - 44, root.bounds.size.width - sidebarW - 1, 44)];
    topToolbar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [root addSubview:topToolbar];

    CGFloat toolbarRightX = topToolbar.bounds.size.width - 20;

    // 自动打印按钮
    self.autoPrintButton = [NSButton buttonWithTitle:@"" target:self action:@selector(toggleAutoPrint:)];
    self.autoPrintButton.frame = NSMakeRect(toolbarRightX - 28, 10, 28, 24);
    self.autoPrintButton.bezelStyle = NSBezelStyleInline;
    self.autoPrintButton.image = [NSImage imageWithSystemSymbolName:@"printer.fill" accessibilityDescription:nil];
    self.autoPrintButton.imageScaling = NSImageScaleProportionallyDown;
    self.autoPrintButton.toolTip = AMLocalizedString(@"toolbar.autoPrint");
    [self.autoPrintButton setContentTintColor:[NSColor colorWithRed:0.5 green:0.5 blue:0.55 alpha:1.0]];
    self.autoPrintButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [topToolbar addSubview:self.autoPrintButton];

    // 打印日志按钮（仅当检测到打印机时亮起）
    self.printLogButton = [NSButton buttonWithTitle:AMLocalizedString(@"toolbar.printLog") target:self action:@selector(printLogs:)];
    self.printLogButton.frame = NSMakeRect(toolbarRightX - 28 - 8 - 90, 10, 90, 24);
    self.printLogButton.bezelStyle = NSBezelStyleRounded;
    self.printLogButton.font = [NSFont systemFontOfSize:12];
    self.printLogButton.enabled = self.printerAvailable;
    self.printLogButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    if (!self.printerAvailable) {
        [self.printLogButton setContentTintColor:[NSColor colorWithRed:0.4 green:0.4 blue:0.4 alpha:1.0]];
    }
    [topToolbar addSubview:self.printLogButton];

    // 查看日志按钮
    self.viewLogButton = [NSButton buttonWithTitle:AMLocalizedString(@"toolbar.viewLog") target:self action:@selector(showLogPanel:)];
    self.viewLogButton.frame = NSMakeRect(toolbarRightX - 28 - 8 - 90 - 8 - 90, 10, 90, 24);
    self.viewLogButton.bezelStyle = NSBezelStyleRounded;
    self.viewLogButton.font = [NSFont systemFontOfSize:12];
    self.viewLogButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [topToolbar addSubview:self.viewLogButton];

    [self setupWelcomeView];
    [self setupDetailsView];
    [self updateContentVisibility];

    // Status bar
    self.statusBarLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(sidebarW + 16, 6, root.bounds.size.width - sidebarW - 32, 16)];
    self.statusBarLabel.font = [NSFont systemFontOfSize:10];
    self.statusBarLabel.bezeled = NO; self.statusBarLabel.drawsBackground = NO; self.statusBarLabel.editable = NO;
    self.statusBarLabel.textColor = [NSColor colorWithRed:0.5 green:0.5 blue:0.55 alpha:1.0];
    self.statusBarLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [root addSubview:self.statusBarLabel];
    [self updateStatusBar];
}

#pragma mark - Welcome View (UTM Style)

- (void)setupWelcomeView {
    self.welcomeView = [[NSView alloc] initWithFrame:self.mainContentView.bounds];
    self.welcomeView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.welcomeView.wantsLayer = YES;
    self.welcomeView.layer.backgroundColor = [NSColor colorWithRed:0.18 green:0.18 blue:0.20 alpha:1.0].CGColor;

    // ─── Title "欢迎使用 VMStart" ───
    NSTextField *title = [[NSTextField alloc] initWithFrame:NSZeroRect];
    title.stringValue = AMLocalizedString(@"welcome_title");
    title.font = [NSFont systemFontOfSize:20 weight:NSFontWeightMedium];
    title.alignment = NSTextAlignmentCenter;
    title.textColor = [NSColor whiteColor];
    title.bezeled = NO; title.drawsBackground = NO; title.editable = NO;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.welcomeView addSubview:title];

    // ─── 2x2 Grid of action buttons ───
    CGFloat btnW = 140;
    CGFloat btnH = 130;
    CGFloat gridSpacingX = 16;
    CGFloat gridSpacingY = 16;
    CGFloat gridTotalW = btnW * 2 + gridSpacingX;
    CGFloat gridTotalH = btnH * 2 + gridSpacingY;

    // 固定尺寸容器整体居中，避免磁贴随窗口缩放被拉散
    NSView *grid = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, gridTotalW, gridTotalH)];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    [self.welcomeView addSubview:grid];

    NSArray *gridButtons = @[
        @{@"icon": @"plus.circle", @"text": AMLocalizedString(@"welcome.createVM"), @"sel": @"addVM:"},
        @{@"icon": @"globe", @"text": AMLocalizedString(@"welcome.downloadImage"), @"sel": @"downloadImage:"},
        @{@"icon": @"book.circle", @"text": AMLocalizedString(@"welcome.userGuide"), @"sel": @"openUserGuide:"},
        @{@"icon": @"questionmark.circle", @"text": AMLocalizedString(@"welcome.support"), @"sel": @"openSupport:"},
    ];

    for (NSInteger i = 0; i < gridButtons.count; i++) {
        NSInteger row = i / 2;
        NSInteger col = i % 2;
        CGFloat x = col * (btnW + gridSpacingX);
        CGFloat y = (1 - row) * (btnH + gridSpacingY);

        NSDictionary *btnDef = gridButtons[i];

        NSView *tile = [[NSView alloc] initWithFrame:NSMakeRect(x, y, btnW, btnH)];
        tile.wantsLayer = YES;
        tile.layer.cornerRadius = 12;
        tile.layer.backgroundColor = [NSColor colorWithRed:0.28 green:0.28 blue:0.30 alpha:1.0].CGColor;
        tile.layer.borderWidth = 1;
        tile.layer.borderColor = [NSColor colorWithRed:0.35 green:0.35 blue:0.37 alpha:1.0].CGColor;

        NSImageView *iconView = [[NSImageView alloc] initWithFrame:NSMakeRect((btnW - 48) / 2, btnH - 72, 48, 48)];
        iconView.image = [NSImage imageWithSystemSymbolName:btnDef[@"icon"] accessibilityDescription:nil];
        iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
        [iconView setContentTintColor:[NSColor whiteColor]];
        [tile addSubview:iconView];

        NSTextField *textLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 12, btnW - 20, 44)];
        textLabel.stringValue = btnDef[@"text"];
        textLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
        textLabel.textColor = [NSColor whiteColor];
        textLabel.alignment = NSTextAlignmentCenter;
        textLabel.bezeled = NO; textLabel.drawsBackground = NO; textLabel.editable = NO;
        textLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [tile addSubview:textLabel];

        NSButton *tileBtn = [NSButton buttonWithTitle:@"" target:self action:NSSelectorFromString(btnDef[@"sel"])];
        tileBtn.bezelStyle = NSBezelStyleRegularSquare;
        tileBtn.frame = tile.bounds;
        tileBtn.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        tileBtn.wantsLayer = YES;
        tileBtn.layer.backgroundColor = [NSColor clearColor].CGColor;
        tileBtn.alphaValue = 0.001;
        [tile addSubview:tileBtn];

        [grid addSubview:tile];
    }

    // ── "查看许可证" link button ───
    NSButton *licensesBtn = [NSButton buttonWithTitle:AMLocalizedString(@"licenses.viewLicenses") target:self action:@selector(showLicensesPanel:)];
    licensesBtn.bezelStyle = NSBezelStyleInline;
    licensesBtn.font = [NSFont systemFontOfSize:11 weight:NSFontWeightLight];
    [licensesBtn setContentTintColor:[NSColor colorWithRed:0.5 green:0.7 blue:1.0 alpha:1.0]];
    licensesBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.welcomeView addSubview:licensesBtn];

    // ─── Constraints ───
    [NSLayoutConstraint activateConstraints:@[
        [grid.widthAnchor constraintEqualToConstant:gridTotalW],
        [grid.heightAnchor constraintEqualToConstant:gridTotalH],
        [grid.centerXAnchor constraintEqualToAnchor:self.welcomeView.centerXAnchor],
        [grid.centerYAnchor constraintEqualToAnchor:self.welcomeView.centerYAnchor constant:20],
        [title.centerXAnchor constraintEqualToAnchor:self.welcomeView.centerXAnchor],
        [title.bottomAnchor constraintEqualToAnchor:grid.topAnchor constant:-24],
        [licensesBtn.centerXAnchor constraintEqualToAnchor:self.welcomeView.centerXAnchor],
        [licensesBtn.bottomAnchor constraintEqualToAnchor:self.welcomeView.bottomAnchor constant:-32],
    ]];

    [self.mainContentView addSubview:self.welcomeView];
}

- (void)connectRemote:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = AMLocalizedString(@"lib.remote.title");
    alert.informativeText = AMLocalizedString(@"lib.remote.message");
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    input.placeholderString = AMLocalizedString(@"lib.remote.placeholder");
    alert.accessoryView = input;
    [alert addButtonWithTitle:AMLocalizedString(@"lib.connect")];
    [alert addButtonWithTitle:AMLocalizedString(@"common.cancel")];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

#pragma mark - Details View

- (void)setupDetailsView {
    self.detailsView = [[NSView alloc] initWithFrame:self.mainContentView.bounds];
    self.detailsView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.detailsView.hidden = YES;
    self.detailsView.wantsLayer = YES;
    self.detailsView.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;

    CGFloat dw = self.detailsView.bounds.size.width;
    CGFloat dh = self.detailsView.bounds.size.height;

    // ─── Header area (Fusion-style, light gray bar) ───
    NSView *header = [[NSView alloc] initWithFrame:NSMakeRect(0, dh - 120, dw, 120)];
    header.wantsLayer = YES;
    header.layer.backgroundColor = [NSColor colorWithRed:0.95 green:0.95 blue:0.96 alpha:1.0].CGColor;
    // 浅色背景强制使用浅色外观，避免深色模式下文字和图标变白看不清
    header.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    header.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [self.detailsView addSubview:header];

    // Bottom border line
    NSView *hdrLine = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, dw, 1)];
    hdrLine.wantsLayer = YES;
    hdrLine.layer.backgroundColor = [NSColor colorWithRed:0.82 green:0.82 blue:0.84 alpha:1.0].CGColor;
    hdrLine.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [header addSubview:hdrLine];

    // OS icon (72x72)
    NSImageView *osIconView = [[NSImageView alloc] initWithFrame:NSMakeRect(24, 24, 72, 72)];
    osIconView.image = [NSImage imageWithSystemSymbolName:@"desktopcomputer" accessibilityDescription:nil];
    osIconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    osIconView.autoresizingMask = NSViewMaxXMargin;
    osIconView.tag = 50;
    [header addSubview:osIconView];

    // VM name
    NSTextField *nameLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(112, 76, dw - 360, 28)];
    nameLabel.font = [NSFont systemFontOfSize:22 weight:NSFontWeightBold];
    nameLabel.textColor = [NSColor labelColor];
    nameLabel.bezeled = NO; nameLabel.drawsBackground = NO; nameLabel.editable = NO;
    nameLabel.autoresizingMask = NSViewWidthSizable;
    nameLabel.tag = 1;
    [header addSubview:nameLabel];

    // OS name label
    NSTextField *osLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(112, 54, 200, 16)];
    osLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    osLabel.textColor = [NSColor secondaryLabelColor];
    osLabel.bezeled = NO; osLabel.drawsBackground = NO; osLabel.editable = NO;
    osLabel.autoresizingMask = NSViewMaxXMargin;
    osLabel.tag = 4;
    [header addSubview:osLabel];

    // Architecture badge
    NSTextField *archBadge = [[NSTextField alloc] initWithFrame:NSMakeRect(112, 30, 120, 18)];
    archBadge.font = [NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightMedium];
    archBadge.textColor = [NSColor whiteColor];
    archBadge.bezeled = NO; archBadge.editable = NO;
    archBadge.wantsLayer = YES;
    archBadge.layer.backgroundColor = [NSColor colorWithRed:0.35 green:0.55 blue:0.85 alpha:1.0].CGColor;
    archBadge.layer.cornerRadius = 9;
    archBadge.drawsBackground = YES;
    archBadge.backgroundColor = [NSColor colorWithRed:0.35 green:0.55 blue:0.85 alpha:1.0];
    archBadge.alignment = NSTextAlignmentCenter;
    archBadge.autoresizingMask = NSViewMaxXMargin;
    archBadge.tag = 2;
    [header addSubview:archBadge];

    // Status badge
    NSTextField *statusBadge = [[NSTextField alloc] initWithFrame:NSMakeRect(240, 30, 90, 18)];
    statusBadge.font = [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold];
    statusBadge.textColor = [NSColor whiteColor];
    statusBadge.bezeled = NO; statusBadge.editable = NO;
    statusBadge.wantsLayer = YES;
    statusBadge.layer.cornerRadius = 9;
    statusBadge.alignment = NSTextAlignmentCenter;
    statusBadge.autoresizingMask = NSViewMaxXMargin;
    statusBadge.tag = 3;
    [header addSubview:statusBadge];

    // Action buttons (right side)
    NSButton *startBtn = [NSButton buttonWithTitle:AMLocalizedString(@"detail.start") target:self action:@selector(startVM:)];
    startBtn.bezelStyle = NSBezelStyleRounded;
    startBtn.frame = NSMakeRect(dw - 130, 48, 110, 30);
    startBtn.autoresizingMask = NSViewMinXMargin;
    startBtn.bezelColor = [NSColor colorWithRed:0.25 green:0.7 blue:0.35 alpha:1.0];
    startBtn.image = [NSImage imageWithSystemSymbolName:@"play.fill" accessibilityDescription:nil];
    startBtn.imagePosition = NSImageLeading;
    startBtn.tag = 10;
    [header addSubview:startBtn];

    NSButton *editBtn = [NSButton buttonWithTitle:AMLocalizedString(@"detail.settings") target:self action:@selector(editVM:)];
    editBtn.bezelStyle = NSBezelStyleRounded;
    editBtn.frame = NSMakeRect(dw - 130, 12, 110, 30);
    editBtn.autoresizingMask = NSViewMinXMargin;
    editBtn.image = [NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:nil];
    editBtn.imagePosition = NSImageLeading;
    [header addSubview:editBtn];

    // ─── 详情主体：可滚动、居中且限宽，窗口过矮时滚动、全屏时不被拉满 ───
    CGFloat rowH = 44;
    CGFloat colW = MIN(dw - 48, 860);
    CGFloat rowsTop = 44;
    CGFloat notesTop = rowsTop + 9 * rowH + 16;
    CGFloat colH = notesTop + 70 + 20;

    NSScrollView *body = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 24, dw, dh - 120 - 24)];
    body.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    body.drawsBackground = NO;
    body.hasVerticalScroller = YES;
    body.autohidesScrollers = YES;
    body.borderType = NSNoBorder;
    [self.detailsView addSubview:body];

    VMStartFlippedView *doc = [[VMStartFlippedView alloc] initWithFrame:NSMakeRect(0, 0, dw, colH)];
    doc.translatesAutoresizingMaskIntoConstraints = NO;
    body.documentView = doc;

    VMStartFlippedView *column = [[VMStartFlippedView alloc] initWithFrame:NSMakeRect(0, 0, colW, colH)];
    column.translatesAutoresizingMaskIntoConstraints = NO;
    [doc addSubview:column];

    NSLayoutConstraint *fillW = [column.widthAnchor constraintEqualToAnchor:doc.widthAnchor constant:-48];
    // 优先级须低于窗口尺寸保持优先级，否则会反向限制窗口（全屏时无法铺满）
    fillW.priority = NSLayoutPriorityDefaultLow;
    [NSLayoutConstraint activateConstraints:@[
        [doc.leadingAnchor constraintEqualToAnchor:body.contentView.leadingAnchor],
        [doc.trailingAnchor constraintEqualToAnchor:body.contentView.trailingAnchor],
        [doc.topAnchor constraintEqualToAnchor:body.contentView.topAnchor],
        [doc.heightAnchor constraintEqualToConstant:colH],
        [column.topAnchor constraintEqualToAnchor:doc.topAnchor],
        [column.heightAnchor constraintEqualToConstant:colH],
        [column.centerXAnchor constraintEqualToAnchor:doc.centerXAnchor],
        [column.widthAnchor constraintLessThanOrEqualToConstant:860],
        fillW,
    ]];

    // ─── "HARDWARE" section title ───
    NSTextField *hwTitle = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 16, 200, 18)];
    hwTitle.stringValue = AMLocalizedString(@"detail.hardware");
    hwTitle.font = [NSFont systemFontOfSize:11 weight:NSFontWeightBold];
    hwTitle.textColor = [NSColor secondaryLabelColor];
    hwTitle.bezeled = NO; hwTitle.drawsBackground = NO; hwTitle.editable = NO;
    [column addSubview:hwTitle];

    // ─── Fusion-style hardware rows ───
    NSArray *hwItems = @[
        @{@"icon": @"cpu",              @"label": AMLocalizedString(@"detail.processor"),  @"tag": @(100)},
        @{@"icon": @"memorychip",       @"label": AMLocalizedString(@"detail.memory"),     @"tag": @(101)},
        @{@"icon": @"internaldrive",    @"label": AMLocalizedString(@"detail.hardDisk"),  @"tag": @(102)},
        @{@"icon": @"network",          @"label": AMLocalizedString(@"detail.network"),    @"tag": @(103)},
        @{@"icon": @"display",          @"label": AMLocalizedString(@"detail.display"),    @"tag": @(104)},
        @{@"icon": @"speaker.wave.2",   @"label": AMLocalizedString(@"detail.soundCard"), @"tag": @(105)},
        @{@"icon": @"cable.connector",  @"label": AMLocalizedString(@"detail.usb"),        @"tag": @(106)},
        @{@"icon": @"speedometer",      @"label": AMLocalizedString(@"detail.acceleration"), @"tag": @(107)},
        @{@"icon": @"info.circle",      @"label": AMLocalizedString(@"detail.engine"),     @"tag": @(108)},
    ];

    CGFloat rowW = colW;
    for (NSInteger i = 0; i < hwItems.count; i++) {
        CGFloat y = rowsTop + i * rowH;
        // Row background
        NSView *row = [[NSView alloc] initWithFrame:NSMakeRect(0, y, rowW, rowH)];
        row.wantsLayer = YES;
        row.autoresizingMask = NSViewWidthSizable;
        [column addSubview:row];

        // Separator line at bottom
        NSView *sep = [[NSView alloc] initWithFrame:NSMakeRect(36, 0, rowW - 36, 1)];
        sep.wantsLayer = YES;
        sep.layer.backgroundColor = [NSColor separatorColor].CGColor;
        sep.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
        [row addSubview:sep];

        // Icon
        NSImageView *icon = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 10, 24, 24)];
        icon.image = [NSImage imageWithSystemSymbolName:hwItems[i][@"icon"] accessibilityDescription:nil];
        icon.imageScaling = NSImageScaleProportionallyUpOrDown;
        [icon setContentTintColor:[NSColor colorWithRed:0.4 green:0.4 blue:0.45 alpha:1.0]];
        [row addSubview:icon];

        // Label
        NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(36, 12, 100, 18)];
        label.stringValue = hwItems[i][@"label"];
        label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        label.textColor = [NSColor labelColor];
        label.bezeled = NO; label.drawsBackground = NO; label.editable = NO;
        [row addSubview:label];

        // Value (right-aligned)
        NSTextField *value = [[NSTextField alloc] initWithFrame:NSMakeRect(140, 12, rowW - 150, 18)];
        value.font = [NSFont systemFontOfSize:13];
        value.textColor = [NSColor secondaryLabelColor];
        value.bezeled = NO; value.drawsBackground = NO; value.editable = NO;
        value.alignment = NSTextAlignmentRight;
        value.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
        value.tag = [hwItems[i][@"tag"] integerValue];
        [row addSubview:value];

        // Disk usage progress bar (only for Hard Disk row, tag=102)
        if ([hwItems[i][@"tag"] integerValue] == 102) {
            // 进度条位于标签与右侧数值之间，右侧预留 260pt 给数值文字
            NSView *progressBg = [[NSView alloc] initWithFrame:NSMakeRect(140, 19, rowW - 140 - 260, 6)];
            progressBg.wantsLayer = YES;
            progressBg.layer.cornerRadius = 3;
            progressBg.layer.backgroundColor = [NSColor colorWithWhite:0.5 alpha:0.3].CGColor;
            progressBg.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
            self.diskProgressBg = progressBg;
            [row addSubview:progressBg];

            NSView *progressFill = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 0, 6)];
            progressFill.wantsLayer = YES;
            progressFill.layer.cornerRadius = 3;
            progressFill.layer.backgroundColor = [NSColor colorWithRed:0.3 green:0.65 blue:0.95 alpha:1.0].CGColor;
            self.diskProgressFill = progressFill;
            [progressBg addSubview:progressFill];
        }
    }

    // ─── Notes section (bottom) ───
    VMStartCardView *notesCard = [[VMStartCardView alloc] initWithFrame:NSMakeRect(0, notesTop, colW, 70)];
    notesCard.autoresizingMask = NSViewWidthSizable;
    notesCard.cornerRadius = 10;
    self.notesCardRef = notesCard;
    [column addSubview:notesCard];

    NSTextField *notesTitle = [[NSTextField alloc] initWithFrame:NSMakeRect(14, 48, 80, 14)];
    notesTitle.stringValue = AMLocalizedString(@"detail.notes");
    notesTitle.font = [NSFont systemFontOfSize:10 weight:NSFontWeightBold];
    notesTitle.textColor = [NSColor secondaryLabelColor];
    notesTitle.bezeled = NO; notesTitle.drawsBackground = NO; notesTitle.editable = NO;
    [notesCard addSubview:notesTitle];

    NSTextField *notesValue = [[NSTextField alloc] initWithFrame:NSMakeRect(14, 12, notesCard.bounds.size.width - 28, 30)];
    notesValue.font = [NSFont systemFontOfSize:11];
    notesValue.textColor = [NSColor textColor];
    notesValue.bezeled = NO; notesValue.drawsBackground = NO; notesValue.editable = NO;
    notesValue.tag = 201;
    notesValue.autoresizingMask = NSViewWidthSizable;
    notesValue.lineBreakMode = NSLineBreakByWordWrapping;
    [notesCard addSubview:notesValue];

    [self.mainContentView addSubview:self.detailsView];

    // Keyboard shortcut: Command+, (macOS) or Ctrl+, (Windows/Linux)
    [self.window makeFirstResponder:self];
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)keyDown:(NSEvent *)event {
    // Check for Command+, or Ctrl+,
    if ((event.modifierFlags & NSEventModifierFlagCommand) || (event.modifierFlags & NSEventModifierFlagControl)) {
        if ([event.characters isEqualToString:@","]) {
            [self openSettings:nil];
            return;
        }
    }
    [super keyDown:event];
}

- (void)updateContentVisibility {
    NSInteger row = self.tableView.selectedRow;
    BOOL hasSelection = row >= 0 && row < (NSInteger)[self visibleVMs].count;
    self.welcomeView.hidden = hasSelection;
    self.detailsView.hidden = !hasSelection;
    // 右上角按钮叠在详情页浅色头部或欢迎页深色背景上，外观随之切换
    self.viewLogButton.superview.appearance = [NSAppearance appearanceNamed:hasSelection ? NSAppearanceNameAqua : NSAppearanceNameDarkAqua];
    if (hasSelection) {
        [self updateDetailsForVM:[self visibleVMs][row]];
    }
}

- (void)updateDetailsForCurrentSelection {
    NSInteger row = self.tableView.selectedRow;
    if (row >= 0 && row < (NSInteger)[self visibleVMs].count) {
        [self updateDetailsForVM:[self visibleVMs][row]];
    }
}

#pragma mark - Table View

- (NSArray<VMStartVirtualMachine *> *)visibleVMs {
    NSArray *vms = self.filteredVMs ?: self.virtualMachines;
    if (self.showFavoritesOnly) {
        NSMutableArray *favs = [NSMutableArray array];
        for (VMStartVirtualMachine *vm in vms) {
            if (vm.isFavorite) [favs addObject:vm];
        }
        return favs;
    }
    return vms;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
    return [self visibleVMs].count;
}

- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)tc row:(NSInteger)row {
    NSTableCellView *cell = [tv makeViewWithIdentifier:@"vmCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tc.width, 60)];
        cell.identifier = @"vmCell";

        // Icon background (rounded square, UTM style)
        NSView *iconBg = [[NSView alloc] initWithFrame:NSMakeRect(12, 10, 40, 40)];
        iconBg.wantsLayer = YES;
        iconBg.layer.cornerRadius = 8;
        iconBg.layer.backgroundColor = [NSColor colorWithRed:0.22 green:0.22 blue:0.26 alpha:1.0].CGColor;
        [cell addSubview:iconBg];

        // OS icon (larger, UTM style)
        NSImageView *iv = [[NSImageView alloc] initWithFrame:NSMakeRect(4, 4, 32, 32)];
        iv.image = [NSImage imageWithSystemSymbolName:@"desktopcomputer" accessibilityDescription:nil];
        iv.imageScaling = NSImageScaleProportionallyUpOrDown;
        [iv setContentTintColor:[NSColor colorWithRed:0.75 green:0.75 blue:0.8 alpha:1.0]];
        iv.tag = 12;
        [iconBg addSubview:iv];

        // Status dot (8px, on icon corner)
        NSTextField *dot = [[NSTextField alloc] initWithFrame:NSMakeRect(42, 10, 8, 8)];
        dot.wantsLayer = YES;
        dot.layer.cornerRadius = 4;
        dot.bordered = NO;
        dot.editable = NO;
        dot.tag = 10;
        [cell addSubview:dot];

        // Name (light text for dark bg)
        NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(62, 32, tc.width - 74, 18)];
        nameField.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
        nameField.textColor = [NSColor colorWithRed:0.9 green:0.9 blue:0.95 alpha:1.0];
        nameField.bezeled = NO; nameField.drawsBackground = NO; nameField.editable = NO;
        nameField.lineBreakMode = NSLineBreakByTruncatingTail;
        cell.textField = nameField;
        [cell addSubview:nameField];

        // Subtitle (arch)
        NSTextField *subField = [[NSTextField alloc] initWithFrame:NSMakeRect(62, 12, tc.width - 130, 16)];
        subField.font = [NSFont systemFontOfSize:10 weight:NSFontWeightRegular];
        subField.bezeled = NO; subField.drawsBackground = NO; subField.editable = NO;
        subField.textColor = [NSColor colorWithRed:0.5 green:0.5 blue:0.55 alpha:1.0];
        subField.tag = 100;
        subField.lineBreakMode = NSLineBreakByTruncatingTail;
        [cell addSubview:subField];

        // Status label (right-aligned, colored)
        NSTextField *statusField = [[NSTextField alloc] initWithFrame:NSMakeRect(tc.width - 66, 12, 56, 16)];
        statusField.font = [NSFont systemFontOfSize:9 weight:NSFontWeightMedium];
        statusField.bezeled = NO; statusField.drawsBackground = NO; statusField.editable = NO;
        statusField.alignment = NSTextAlignmentRight;
        statusField.tag = 101;
        statusField.autoresizingMask = NSViewMinXMargin;
        [cell addSubview:statusField];
    }

    VMStartVirtualMachine *vm = [self visibleVMs][row];
    cell.textField.stringValue = vm.name;

    // Update OS icon (UTM style)
    NSImageView *osIconView = [cell viewWithTag:12];
    if (osIconView) {
        osIconView.image = vm.osIcon;
        [osIconView setContentTintColor:nil]; // Use original colors
    }

    // Update subtitle: OS name + arch
    NSTextField *sub = [cell viewWithTag:100];
    sub.stringValue = [NSString stringWithFormat:@"%@ • %@", vm.osDisplayName, vm.architectureDisplayName];

    NSTextField *statusLbl = [cell viewWithTag:101];
    statusLbl.stringValue = vm.statusDisplayName;
    statusLbl.textColor = [self statusColorForVM:vm];

    NSView *dot = [cell viewWithTag:10];
    dot.layer.backgroundColor = [self statusColorForVM:vm].CGColor;

    return cell;
}

- (NSColor *)statusColorForVM:(VMStartVirtualMachine *)vm {
    switch (vm.status) {
        case VMStartStatusRunning: return [NSColor colorWithRed:0.25 green:0.75 blue:0.35 alpha:1.0];
        case VMStartStatusPaused: return [NSColor colorWithRed:0.95 green:0.65 blue:0.1 alpha:1.0];
        case VMStartStatusStarting: return [NSColor colorWithRed:0.2 green:0.55 blue:0.95 alpha:1.0];
        case VMStartStatusError: return [NSColor colorWithRed:0.9 green:0.25 blue:0.25 alpha:1.0];
        default: return [NSColor colorWithRed:0.55 green:0.55 blue:0.58 alpha:1.0];
    }
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self updateContentVisibility];
    [self updateStatusBar];
}

- (void)updateDetailsForVM:(VMStartVirtualMachine *)vm {
    NSTextField *nameLabel = [self.detailsView viewWithTag:1];
    NSTextField *archBadge = [self.detailsView viewWithTag:2];
    NSTextField *statusBadge = [self.detailsView viewWithTag:3];
    NSTextField *osLabel = [self.detailsView viewWithTag:4];
    NSImageView *osIconView = [self.detailsView viewWithTag:50];

    nameLabel.stringValue = vm.name;
    archBadge.stringValue = [NSString stringWithFormat:@"  %@  ", vm.architectureDisplayName];

    statusBadge.stringValue = [NSString stringWithFormat:@"  %@  ", vm.statusDisplayName];
    statusBadge.backgroundColor = [self statusColorForVM:vm];
    statusBadge.layer.backgroundColor = [self statusColorForVM:vm].CGColor;

    // OS info
    if (osLabel) osLabel.stringValue = vm.osDisplayName;
    if (osIconView) osIconView.image = vm.osIcon;

    // Hardware info (Fusion-style rows)
    NSString *cpu = AMLocalizedStringF(@"lib.cpuCores", vm.cpuModel.length > 0 && ![vm.cpuModel isEqualToString:@"default"] ? vm.cpuModel : AMLocalizedString(@"lib.cpuDefault"), (long)vm.cpuCores);
    NSString *mem = [NSString stringWithFormat:@"%ld %@", (long)vm.memoryValue, vm.memoryUnit ?: @"MB"];
    NSString *disk = [vm.diskSizeUnit isEqualToString:@"none"] ? AMLocalizedString(@"detail.noDisk") : [NSString stringWithFormat:@"%ld %@", (long)vm.diskSizeValue, vm.diskSizeUnit ?: @"GB"];
    NSDictionary *netNames = @{@"user": AMLocalizedString(@"network_nat"), @"bridge": AMLocalizedString(@"network_bridge"),
                               @"host-only": AMLocalizedString(@"network_hostonly"), @"modem": AMLocalizedString(@"network_modem"),
                               @"terminal": AMLocalizedString(@"network_terminal"), @"none": AMLocalizedString(@"network_none")};
    NSString *net = netNames[vm.networkMode ?: @"user"] ?: vm.networkMode;
    NSDictionary *dispNames = @{@"cocoa": AMLocalizedString(@"lib.display.cocoa"), @"vnc": @"VNC", @"none": AMLocalizedString(@"lib.display.none")};
    NSString *disp = dispNames[vm.displayType ?: @"cocoa"] ?: vm.displayType;
    NSString *sound = vm.enableSoundCard ? (vm.soundCardModel.length > 0 ? vm.soundCardModel.uppercaseString : @"Intel HDA") : AMLocalizedString(@"detail.disabled");
    NSString *usb = vm.enableUSB ? [@"USB " stringByAppendingString:vm.usbVersion ?: @""] : AMLocalizedString(@"detail.disabled");
    
    // Acceleration mode
    NSString *accel = AMLocalizedString(@"detail.accelDisabled");
    if (vm.enableAcceleration) {
        if ([vm isAppleSiliconHost] && (vm.architecture == VMStartArchAArch64 || vm.architecture == VMStartArchX86_64)) {
            accel = AMLocalizedString(@"detail.accelHVF");
        } else {
            accel = AMLocalizedString(@"detail.accelTCG");
        }
    }
    
    VMStartEngineType engineType = [VMStartEngineSelector engineTypeForMachine:vm.machineType];
    NSString *engine = [VMStartEngineSelector nameForEngineType:engineType];

    // Order matches hwItems array: Processor, Memory, Hard Disk, Network, Display, Sound Card, USB, Acceleration, Engine
    NSArray *values = @[cpu, mem, disk, net, disp, sound, usb, accel, engine ?: @"QEMU"];
    for (NSInteger i = 0; i < values.count; i++) {
        NSTextField *tf = [self.detailsView viewWithTag:100 + i];
        if (tf) tf.stringValue = values[i];
    }

    // Update disk usage progress bar
    if (self.diskProgressBg && self.diskProgressFill) {
        CGFloat percent = [vm diskUsagePercent];
        if (percent > 0) {
            CGFloat fillWidth = self.diskProgressBg.bounds.size.width * percent;
            self.diskProgressFill.frame = NSMakeRect(0, 0, fillWidth, 6);
            self.diskProgressBg.hidden = NO;
            self.diskProgressFill.hidden = NO;
            // Update disk label to show usage
            NSTextField *diskLabel = [self.detailsView viewWithTag:102];
            if (diskLabel) {
                NSInteger usedMB = [vm diskUsedBytes] / (1024 * 1024);
                NSInteger totalMB = [vm diskTotalBytes] / (1024 * 1024);
                diskLabel.stringValue = AMLocalizedStringF(@"lib.diskUsed", disk, (long)usedMB, (long)totalMB);
            }
        } else {
            self.diskProgressBg.hidden = YES;
            self.diskProgressFill.hidden = YES;
        }
    }

    // Start/Stop button
    NSButton *startBtn = [self.detailsView viewWithTag:10];
    if (vm.status == VMStartStatusRunning) {
        startBtn.title = AMLocalizedString(@"detail.stop");
        startBtn.image = [NSImage imageWithSystemSymbolName:@"stop.fill" accessibilityDescription:nil];
        startBtn.bezelColor = [NSColor systemRedColor];
    } else {
        startBtn.title = AMLocalizedString(@"detail.start");
        startBtn.image = [NSImage imageWithSystemSymbolName:@"play.fill" accessibilityDescription:nil];
        startBtn.bezelColor = [NSColor colorWithRed:0.25 green:0.7 blue:0.35 alpha:1.0];
    }

    // Notes
    NSTextField *notesVal = [self.detailsView viewWithTag:201];
    if (notesVal) {
        notesVal.stringValue = vm.notes ?: AMLocalizedString(@"detail.noNotes");
    }

    // Hide/show notes card based on mode
    if (self.notesCardRef) self.notesCardRef.hidden = (self.appMode == VMStartAppModeSimple);
}

#pragma mark - Search

- (void)controlTextDidChange:(NSNotification *)obj {
    [self applyFilters];
}

- (void)applyFilters {
    NSString *query = self.searchField.stringValue.lowercaseString;
    BOOL hasQuery = query.length > 0;
    
    if (!hasQuery) {
        self.filteredVMs = nil;
    } else {
        NSMutableArray *arr = [NSMutableArray array];
        for (VMStartVirtualMachine *vm in self.virtualMachines) {
            BOOL match = [vm.name.lowercaseString containsString:query] ||
                         [vm.architectureDisplayName.lowercaseString containsString:query] ||
                         [vm.osDisplayName.lowercaseString containsString:query] ||
                         [vm.statusDisplayName.lowercaseString containsString:query];
            if (match) [arr addObject:vm];
        }
        self.filteredVMs = arr;
    }
    [self.tableView reloadData];
    [self updateContentVisibility];
}

#pragma mark - Batch Operations

- (NSArray<VMStartVirtualMachine *> *)selectedVMs {
    NSIndexSet *rows = self.tableView.selectedRowIndexes;
    NSMutableArray *vms = [NSMutableArray array];
    NSArray *visible = [self visibleVMs];
    [rows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        if (idx < visible.count) [vms addObject:visible[idx]];
    }];
    return vms;
}

- (void)batchStart:(id)sender {
    for (VMStartVirtualMachine *vm in [self selectedVMs]) {
        if (vm.status != VMStartStatusRunning) [self launchVM:vm];
    }
}

- (void)batchStop:(id)sender {
    for (VMStartVirtualMachine *vm in [self selectedVMs]) {
        if (vm.status == VMStartStatusRunning) [self stopVM:vm];
    }
}

- (void)batchDelete:(id)sender {
    NSArray *vms = [self selectedVMs];
    if (vms.count == 0) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = AMLocalizedStringF(@"lib.batchDelete.title", (unsigned long)vms.count);
    alert.informativeText = AMLocalizedString(@"lib.batchDelete.message");
    [alert addButtonWithTitle:AMLocalizedString(@"alert.delete")];
    [alert addButtonWithTitle:AMLocalizedString(@"common.cancel")];
    alert.alertStyle = NSAlertStyleWarning;
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        for (VMStartVirtualMachine *vm in vms) {
            NSURL *bundleURL = [NSURL fileURLWithPath:vm.vmBundlePath];
            [[NSWorkspace sharedWorkspace] recycleURLs:@[bundleURL] completionHandler:nil];
            [self.virtualMachines removeObject:vm];
        }
        self.filteredVMs = nil;
        [self.tableView reloadData];
        [self updateContentVisibility];
        [self updateStatusBar];
    }
}

- (void)launchVM:(VMStartVirtualMachine *)vm {
    // Placeholder - actual launch logic is in startVM/console
    vm.status = VMStartStatusRunning;
    [self.tableView reloadData];
}

- (void)stopVM:(VMStartVirtualMachine *)vm {
    vm.status = VMStartStatusStopped;
    [self.tableView reloadData];
}

#pragma mark - Actions

- (void)addVM:(id)sender {
    VMStartVirtualMachine *vm = [VMStartVirtualMachine virtualMachineWithName:AMLocalizedString(@"lib.newVMName") architecture:VMStartArchX86_64];
    NSString *vmPath = [self.vmDirectory stringByAppendingPathComponent:
                        [NSString stringWithFormat:@"%@.vmstart", vm.vmIdentifier]];
    vm.vmBundlePath = vmPath;
    self.configWC = [[VMStartConfigWindowController alloc] initWithVM:vm isNew:YES];
    self.configWC.delegate = self;
    [self.window beginSheet:self.configWC.window completionHandler:nil];
}

- (void)openExistingVM:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = YES;
    panel.allowedContentTypes = @[];
    panel.title = AMLocalizedString(@"lib.openVM");
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSInteger result) {
        if (result == NSModalResponseOK) {
            for (NSURL *url in panel.URLs) {
                if ([url.pathExtension isEqualToString:@"vmstart"]) {
                    VMStartVirtualMachine *vm = [[VMStartVirtualMachine alloc] init];
                    if ([vm loadFromBundle:url.path]) {
                        NSString *destPath = [self.vmDirectory stringByAppendingPathComponent:url.lastPathComponent];
                        if (![destPath isEqualToString:url.path]) {
                            [[NSFileManager defaultManager] copyItemAtPath:url.path toPath:destPath error:nil];
                            vm.vmBundlePath = destPath;
                        }
                        [self.virtualMachines addObject:vm];
                    }
                }
            }
            [self sortVMs];
            [self.tableView reloadData];
            [self updateContentVisibility];
            [self updateStatusBar];
        }
    }];
}

- (void)removeVM:(id)sender {
    NSInteger row = self.tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)[self visibleVMs].count) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = AMLocalizedString(@"alert.deleteVM.title");
    alert.informativeText = AMLocalizedString(@"lib.delete.message");
    [alert addButtonWithTitle:AMLocalizedString(@"alert.delete")];
    [alert addButtonWithTitle:AMLocalizedString(@"common.cancel")];
    alert.alertStyle = NSAlertStyleWarning;
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        VMStartVirtualMachine *vm = [self visibleVMs][row];
        NSURL *bundleURL = [NSURL fileURLWithPath:vm.vmBundlePath];
        [[NSWorkspace sharedWorkspace] recycleURLs:@[bundleURL] completionHandler:nil];
        [self.virtualMachines removeObject:vm];
        self.filteredVMs = nil;
        [self.tableView reloadData];
        [self updateContentVisibility];
        [self updateStatusBar];
    }
}

- (void)editVM:(id)sender {
    NSInteger row = self.tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)[self visibleVMs].count) return;
    VMStartVirtualMachine *vm = [self visibleVMs][row];
    self.configWC = [[VMStartConfigWindowController alloc] initWithVM:vm isNew:NO];
    self.configWC.delegate = self;
    [self.window beginSheet:self.configWC.window completionHandler:nil];
}

- (void)openSettings:(id)sender {
    VMStartSettingsWindowController *settingsWC = [[VMStartSettingsWindowController alloc] init];
    [settingsWC showWindow:nil];
    [settingsWC.window makeKeyAndOrderFront:nil];
}

- (void)startVM:(id)sender {
    NSInteger row = self.tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)[self visibleVMs].count) return;
    VMStartVirtualMachine *vm = [self visibleVMs][row];
    NSString *key = vm.vmIdentifier;
    VMStartConsoleWindowController *console = self.consoleControllers[key];
    if (!console) {
        console = [[VMStartConsoleWindowController alloc] initWithVM:vm];
        self.consoleControllers[key] = console;
    }
    [console showWindow:nil];
    [console.window makeKeyAndOrderFront:nil];
    [console startVM];
}

- (void)configDidSaveVM:(VMStartVirtualMachine *)vm {
    [vm saveToBundle];
    NSUInteger idx = NSNotFound;
    for (NSUInteger i = 0; i < self.virtualMachines.count; i++) {
        if ([self.virtualMachines[i].vmIdentifier isEqualToString:vm.vmIdentifier]) {
            idx = i;
            break;
        }
    }
    if (idx == NSNotFound) {
        [self.virtualMachines addObject:vm];
    } else {
        self.virtualMachines[idx] = vm;
    }
    self.filteredVMs = nil;
    [self.tableView reloadData];
    [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:self.virtualMachines.count - 1] byExtendingSelection:NO];
    [self updateContentVisibility];
    [self updateStatusBar];
}

- (void)addVMFromImageURL:(NSURL *)imageURL {
    NSString *path = imageURL.path.stringByStandardizingPath;
    NSSet *allowed = [NSSet setWithArray:@[@"iso", @"img", @"qcow2", @"vmdk", @"vdi", @"vhd", @"vhdx"]];
    BOOL isDirectory = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory];
    if (!exists || isDirectory || ![allowed containsObject:path.pathExtension.lowercaseString]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = AMLocalizedString(@"browserImport.invalid.title");
        alert.informativeText = AMLocalizedString(@"browserImport.invalid.message");
        [alert runModal];
        return;
    }

    NSString *filename = path.lastPathComponent;
    NSString *name = [[filename stringByDeletingPathExtension] stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    VMStartOSType osType = [VMStartVirtualMachine osTypeForImageFilename:filename];
    VMStartArchitecture architecture = [VMStartVirtualMachine architectureForImageFilename:filename];
    NSDictionary *config = [VMStartVirtualMachine bestConfigForOSType:osType architecture:architecture];
    VMStartVirtualMachine *vm = [VMStartVirtualMachine virtualMachineWithName:name architecture:architecture];
    vm.osType = osType;
    vm.machineType = config[@"machine"];
    vm.cpuModel = config[@"cpu"];
    vm.cpuCores = [config[@"cores"] integerValue];
    vm.cpuSockets = 1;
    vm.cpuCoresPerSocket = vm.cpuCores;
    vm.memoryValue = [config[@"memMB"] integerValue];
    vm.memoryUnit = @"MB";
    vm.diskSizeValue = [config[@"diskGB"] integerValue];
    vm.diskSizeUnit = @"GB";
    vm.vramSizeMB = [config[@"vram"] integerValue];
    vm.enableTPM = [config[@"tpm"] boolValue];
    vm.enableAcceleration = [config[@"acceleration"] boolValue];
    vm.enable3DAcceleration = vm.enableAcceleration;
    vm.enableHiDPI = YES;
    vm.performanceProfile = @"performance";
    vm.diskController = @"VirtIO";
    vm.networkMode = @"user";
    vm.notes = AMLocalizedStringF(@"browserImport.notes", filename);

    NSString *vmPath = [self.vmDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.vmstart", vm.vmIdentifier]];
    vm.vmBundlePath = vmPath;
    [[NSFileManager defaultManager] createDirectoryAtPath:vmPath withIntermediateDirectories:YES attributes:nil error:nil];
    BOOL opticalImage = [@[@"iso", @"img"] containsObject:path.pathExtension.lowercaseString];
    if (opticalImage) {
        vm.bootISOPath = path;
        vm.diskImagePath = [vmPath stringByAppendingPathComponent:@"disk.qcow2"];
        NSString *qemuImg = [[NSFileManager defaultManager] isExecutableFileAtPath:@"/opt/homebrew/bin/qemu-img"] ? @"/opt/homebrew/bin/qemu-img" : @"/usr/local/bin/qemu-img";
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:qemuImg]) {
            NSTask *task = [[NSTask alloc] init];
            task.executableURL = [NSURL fileURLWithPath:qemuImg];
            task.arguments = @[@"create", @"-f", @"qcow2", vm.diskImagePath, [NSString stringWithFormat:@"%ldG", (long)vm.diskSizeValue]];
            [task launchAndReturnError:nil];
            [task waitUntilExit];
        }
    } else {
        vm.diskImagePath = path;
        vm.diskSizeUnit = @"none";
    }

    [vm saveToBundle];
    [self.virtualMachines addObject:vm];
    [self sortVMs];
    self.filteredVMs = nil;
    [self.tableView reloadData];
    NSInteger row = [[self visibleVMs] indexOfObject:vm];
    if (row != NSNotFound) [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [self updateContentVisibility];
    [self updateStatusBar];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

#pragma mark - VM List

- (void)refreshVMList {
    [self.virtualMachines removeAllObjects];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *contents = [fm contentsOfDirectoryAtPath:self.vmDirectory error:nil];
    for (NSString *item in contents) {
        if ([item.pathExtension isEqualToString:@"vmstart"]) {
            NSString *path = [self.vmDirectory stringByAppendingPathComponent:item];
            VMStartVirtualMachine *vm = [[VMStartVirtualMachine alloc] init];
            if ([vm loadFromBundle:path]) {
                [self.virtualMachines addObject:vm];
            }
        }
    }
    [self sortVMs];
    self.filteredVMs = nil;
    [self.tableView reloadData];
    [self updateContentVisibility];
    [self updateStatusBar];
}

- (void)updateStatusBar {
    NSString *qemuVer = [[VMStartArchitectureManager sharedManager] qemuVersionString];
    NSInteger total = self.virtualMachines.count;
    NSInteger running = 0;
    NSInteger favCount = 0;
    for (VMStartVirtualMachine *vm in self.virtualMachines) {
        if (vm.status == VMStartStatusRunning) running++;
        if (vm.isFavorite) favCount++;
    }
    NSString *extra = self.showFavoritesOnly ? AMLocalizedStringF(@"lib.status.favorites", (long)favCount) : @"";
    self.statusBarLabel.stringValue = AMLocalizedStringF(@"lib.status.format", (long)total, (long)running, extra, qemuVer ?: AMLocalizedString(@"lib.status.noEngine"));
}

#pragma mark - Context Menu

- (void)setupContextMenu {
    self.contextMenu = [[NSMenu alloc] init];
    self.contextMenu.delegate = self;
    // Will be assigned to tableView after setupUI

    [self.contextMenu addItem:[self menuItem:AMLocalizedString(@"detail.start") action:@selector(ctxStart:) icon:@"play.fill"]];
    [self.contextMenu addItem:[self menuItem:AMLocalizedString(@"detail.stop") action:@selector(ctxStop:) icon:@"stop.fill"]];
    [self.contextMenu addItem:[self menuItem:AMLocalizedString(@"status.paused") action:@selector(ctxPause:) icon:@"pause.fill"]];
    [self.contextMenu addItem:[NSMenuItem separatorItem]];
    [self.contextMenu addItem:[self menuItem:[NSString stringWithFormat:@"%@...", AMLocalizedString(@"detail.settings")] action:@selector(ctxEdit:) icon:@"gearshape"]];
    [self.contextMenu addItem:[self menuItem:AMLocalizedString(@"lib.ctx.openConsole") action:@selector(ctxOpenConsole:) icon:@"terminal"]];
    [self.contextMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *favItem = [self menuItem:AMLocalizedString(@"lib.ctx.toggleFavorite") action:@selector(ctxToggleFavorite:) icon:@"star"];
    favItem.tag = 999;
    [self.contextMenu addItem:favItem];

    NSMenuItem *groupItem = [[NSMenuItem alloc] initWithTitle:AMLocalizedString(@"lib.ctx.setGroup") action:@selector(ctxSetGroup:) keyEquivalent:@""];
    groupItem.target = self;
    [self.contextMenu addItem:groupItem];

    [self.contextMenu addItem:[NSMenuItem separatorItem]];

    // Snapshots submenu
    NSMenuItem *snapshotMenu = [[NSMenuItem alloc] initWithTitle:AMLocalizedString(@"lib.ctx.snapshots") action:nil keyEquivalent:@""];
    NSMenu *snapMenu = [[NSMenu alloc] init];
    [snapMenu addItem:[self menuItem:AMLocalizedString(@"lib.ctx.takeSnapshot") action:@selector(ctxTakeSnapshot:) icon:@"camera"]];
    [snapMenu addItem:[self menuItem:AMLocalizedString(@"lib.ctx.restoreSnapshot") action:@selector(ctxRestoreSnapshot:) icon:@"arrow.uturn.backward"]];
    [snapMenu addItem:[self menuItem:AMLocalizedString(@"lib.ctx.deleteSnapshot") action:@selector(ctxDeleteSnapshot:) icon:@"trash"]];
    snapshotMenu.submenu = snapMenu;
    [self.contextMenu addItem:snapshotMenu];

    // Clone submenu
    NSMenuItem *cloneMenu = [[NSMenuItem alloc] initWithTitle:AMLocalizedString(@"lib.ctx.clone") action:nil keyEquivalent:@""];
    NSMenu *cloneSub = [[NSMenu alloc] init];
    [cloneSub addItem:[self menuItem:AMLocalizedString(@"lib.ctx.fullClone") action:@selector(ctxFullClone:) icon:@"doc.on.doc"]];
    [cloneSub addItem:[self menuItem:AMLocalizedString(@"lib.ctx.linkedClone") action:@selector(ctxLinkedClone:) icon:@"link"]];
    cloneMenu.submenu = cloneSub;
    [self.contextMenu addItem:cloneMenu];

    [self.contextMenu addItem:[NSMenuItem separatorItem]];
    [self.contextMenu addItem:[self menuItem:AMLocalizedString(@"lib.ctx.exportOVF") action:@selector(ctxExportOVF:) icon:@"square.and.arrow.up"]];
    [self.contextMenu addItem:[self menuItem:AMLocalizedString(@"lib.ctx.encrypt") action:@selector(ctxEncrypt:) icon:@"lock"]];
    [self.contextMenu addItem:[NSMenuItem separatorItem]];
    [self.contextMenu addItem:[self menuItem:AMLocalizedString(@"lib.ctx.batchStart") action:@selector(batchStart:) icon:@"play.circle"]];
    [self.contextMenu addItem:[self menuItem:AMLocalizedString(@"lib.ctx.batchStop") action:@selector(batchStop:) icon:@"stop.circle"]];
    [self.contextMenu addItem:[self menuItem:AMLocalizedString(@"lib.ctx.batchDelete") action:@selector(batchDelete:) icon:@"trash.circle"]];
    [self.contextMenu addItem:[NSMenuItem separatorItem]];
    [self.contextMenu addItem:[self menuItem:AMLocalizedString(@"alert.delete") action:@selector(ctxDelete:) icon:@"trash"]];
}

- (NSMenuItem *)menuItem:(NSString *)title action:(SEL)action icon:(NSString *)icon {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    if (icon) {
        item.image = [NSImage imageWithSystemSymbolName:icon accessibilityDescription:nil];
    }
    return item;
}

- (void)menuWillOpen:(NSMenu *)menu {
    NSInteger row = self.tableView.clickedRow;
    if (row >= 0 && row < (NSInteger)[self visibleVMs].count) {
        VMStartVirtualMachine *vm = [self visibleVMs][row];
        NSMenuItem *favItem = [menu itemWithTag:999];
        favItem.title = vm.isFavorite ? [@"\u2605 " stringByAppendingString:AMLocalizedString(@"lib.ctx.unfavorite")] : [@"\u2606 " stringByAppendingString:AMLocalizedString(@"lib.ctx.favorite")];
    }
}

- (VMStartVirtualMachine *)contextMenuVM {
    NSInteger row = self.tableView.clickedRow;
    if (row >= 0 && row < (NSInteger)[self visibleVMs].count) {
        return [self visibleVMs][row];
    }
    return nil;
}

// Context menu actions
- (void)ctxStart:(id)sender { VMStartVirtualMachine *vm = [self contextMenuVM]; if (vm) [self startVMByID:vm.vmIdentifier]; }
- (void)ctxStop:(id)sender { VMStartVirtualMachine *vm = [self contextMenuVM]; if (vm) [self stopVMByID:vm.vmIdentifier]; }
- (void)ctxPause:(id)sender { VMStartVirtualMachine *vm = [self contextMenuVM]; if (vm) [self pauseVMByID:vm.vmIdentifier]; }
- (void)ctxEdit:(id)sender { NSInteger row = self.tableView.clickedRow; if (row >= 0) { [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO]; [self editVM:sender]; } }
- (void)ctxOpenConsole:(id)sender { VMStartVirtualMachine *vm = [self contextMenuVM]; if (vm) [self startVMByID:vm.vmIdentifier]; }
- (void)ctxToggleFavorite:(id)sender {
    VMStartVirtualMachine *vm = [self contextMenuVM];
    if (vm) {
        vm.isFavorite = !vm.isFavorite;
        [vm saveToBundle];
        [self.tableView reloadData];
        [self updateStatusBar];
    }
}
- (void)ctxSetGroup:(id)sender {
    VMStartVirtualMachine *vm = [self contextMenuVM];
    if (!vm) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = AMLocalizedString(@"lib.group.title");
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    input.stringValue = vm.group ?: @"";
    input.placeholderString = AMLocalizedString(@"lib.group.placeholder");
    alert.accessoryView = input;
    [alert addButtonWithTitle:AMLocalizedString(@"alert.ok")];
    [alert addButtonWithTitle:AMLocalizedString(@"common.cancel")];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        vm.group = input.stringValue ?: @"";
        [vm saveToBundle];
        [self sortVMs];
        [self.tableView reloadData];
    }
}
- (void)ctxTakeSnapshot:(id)sender {
    VMStartVirtualMachine *vm = [self contextMenuVM];
    if (!vm) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = AMLocalizedString(@"lib.snapshot.take");
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    input.placeholderString = AMLocalizedString(@"lib.snapshot.placeholder");
    alert.accessoryView = input;
    [alert addButtonWithTitle:AMLocalizedString(@"common.save")];
    [alert addButtonWithTitle:AMLocalizedString(@"common.cancel")];
    if ([alert runModal] == NSAlertFirstButtonReturn && input.stringValue.length > 0) {
        NSString *snapName = input.stringValue;
        NSString *snapDate = [[NSDate date] description];
        NSString *snapPath = [vm.vmBundlePath stringByAppendingPathComponent:[NSString stringWithFormat:@"snapshots/%@.qcow2", snapName]];
        // Create snapshot directory
        [[NSFileManager defaultManager] createDirectoryAtPath:[snapPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
        // Use qemu-img to create a snapshot
        NSString *qemuImg = @"/opt/homebrew/bin/qemu-img";
        if (![[NSFileManager defaultManager] fileExistsAtPath:qemuImg]) qemuImg = @"/usr/local/bin/qemu-img";
        if (vm.diskImagePath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:qemuImg]) {
            NSTask *task = [[NSTask alloc] init];
            task.executableURL = [NSURL fileURLWithPath:qemuImg];
            task.arguments = @[@"snapshot", @"-c", snapName, vm.diskImagePath];
            [task launch];
        }
        NSMutableArray *snaps = [vm.snapshots mutableCopy] ?: [NSMutableArray array];
        [snaps addObject:@{@"name": snapName, @"date": snapDate, @"path": snapPath}];
        vm.snapshots = snaps;
        [vm saveToBundle];
    }
}
- (void)ctxRestoreSnapshot:(id)sender {
    VMStartVirtualMachine *vm = [self contextMenuVM];
    if (!vm || vm.snapshots.count == 0) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = AMLocalizedString(@"lib.snapshot.restore");
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 200, 26)];
    for (NSDictionary *snap in vm.snapshots) {
        [popup addItemWithTitle:snap[@"name"] ?: AMLocalizedString(@"lib.snapshot.unnamed")];
    }
    alert.accessoryView = popup;
    [alert addButtonWithTitle:AMLocalizedString(@"lib.restore")];
    [alert addButtonWithTitle:AMLocalizedString(@"common.cancel")];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *snapName = popup.titleOfSelectedItem;
        if (snapName && vm.diskImagePath.length > 0) {
            NSString *qemuImg = @"/opt/homebrew/bin/qemu-img";
            if (![[NSFileManager defaultManager] fileExistsAtPath:qemuImg]) qemuImg = @"/usr/local/bin/qemu-img";
            NSTask *task = [[NSTask alloc] init];
            task.executableURL = [NSURL fileURLWithPath:qemuImg];
            task.arguments = @[@"snapshot", @"-a", snapName, vm.diskImagePath];
            [task launch];
        }
    }
}
- (void)ctxDeleteSnapshot:(id)sender {
    VMStartVirtualMachine *vm = [self contextMenuVM];
    if (!vm || vm.snapshots.count == 0) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = AMLocalizedString(@"lib.snapshot.delete");
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 200, 26)];
    for (NSDictionary *snap in vm.snapshots) {
        [popup addItemWithTitle:snap[@"name"] ?: AMLocalizedString(@"lib.snapshot.unnamed")];
    }
    alert.accessoryView = popup;
    [alert addButtonWithTitle:AMLocalizedString(@"alert.delete")];
    [alert addButtonWithTitle:AMLocalizedString(@"common.cancel")];
    alert.alertStyle = NSAlertStyleWarning;
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSInteger idx = popup.indexOfSelectedItem;
        NSString *snapName = popup.titleOfSelectedItem;
        if (snapName && vm.diskImagePath.length > 0) {
            NSString *qemuImg = @"/opt/homebrew/bin/qemu-img";
            if (![[NSFileManager defaultManager] fileExistsAtPath:qemuImg]) qemuImg = @"/usr/local/bin/qemu-img";
            NSTask *task = [[NSTask alloc] init];
            task.executableURL = [NSURL fileURLWithPath:qemuImg];
            task.arguments = @[@"snapshot", @"-d", snapName, vm.diskImagePath];
            [task launch];
        }
        NSMutableArray *snaps = [vm.snapshots mutableCopy];
        if (idx < (NSInteger)snaps.count) [snaps removeObjectAtIndex:idx];
        vm.snapshots = snaps;
        [vm saveToBundle];
    }
}
- (void)ctxFullClone:(id)sender {
    VMStartVirtualMachine *vm = [self contextMenuVM];
    if (!vm) return;
    // Clone wizard dialog
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = AMLocalizedString(@"lib.clone.title");
    alert.informativeText = AMLocalizedStringF(@"lib.clone.message", vm.name);
    [alert addButtonWithTitle:AMLocalizedString(@"lib.clone.button")];
    [alert addButtonWithTitle:AMLocalizedString(@"common.cancel")];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    VMStartVirtualMachine *clone = [VMStartVirtualMachine virtualMachineWithName:[NSString stringWithFormat:@"%@ (Clone)", vm.name] architecture:vm.architecture];
    clone.osType = vm.osType;
    clone.machineType = vm.machineType;
    clone.cpuModel = vm.cpuModel;
    clone.cpuCores = vm.cpuCores;
    clone.cpuSockets = vm.cpuSockets;
    clone.cpuCoresPerSocket = vm.cpuCoresPerSocket;
    clone.memoryValue = vm.memoryValue;
    clone.memoryUnit = vm.memoryUnit;
    clone.diskSizeValue = vm.diskSizeValue;
    clone.diskSizeUnit = vm.diskSizeUnit;
    clone.diskController = vm.diskController;
    clone.usbVersion = vm.usbVersion;
    clone.networkMode = vm.networkMode;
    clone.displayType = vm.displayType;
    clone.enableAudio = vm.enableAudio;
    clone.enableUSB = vm.enableUSB;
    clone.enableAcceleration = vm.enableAcceleration;
    clone.enable3DAcceleration = vm.enable3DAcceleration;
    clone.vramSizeMB = vm.vramSizeMB;
    clone.enableTPM = vm.enableTPM;
    // Copy disk image
    NSString *clonePath = [self.vmDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.vmstart", clone.vmIdentifier]];
    clone.vmBundlePath = clonePath;
    [[NSFileManager defaultManager] createDirectoryAtPath:clonePath withIntermediateDirectories:YES attributes:nil error:nil];
    if (vm.diskImagePath.length > 0) {
        NSString *dstDisk = [clonePath stringByAppendingPathComponent:@"disk.qcow2"];
        NSString *qemuImg = @"/opt/homebrew/bin/qemu-img";
        if (![[NSFileManager defaultManager] fileExistsAtPath:qemuImg]) qemuImg = @"/usr/local/bin/qemu-img";
        if ([[NSFileManager defaultManager] fileExistsAtPath:qemuImg]) {
            NSTask *task = [[NSTask alloc] init];
            task.executableURL = [NSURL fileURLWithPath:qemuImg];
            task.arguments = @[@"convert", @"-f", @"qcow2", @"-O", @"qcow2", vm.diskImagePath, dstDisk];
            [task launch];
            [task waitUntilExit];
        }
        clone.diskImagePath = dstDisk;
    }
    [clone saveToBundle];
    [self.virtualMachines addObject:clone];
    [self sortVMs];
    [self.tableView reloadData];
    [self updateContentVisibility];
    [self updateStatusBar];
}
- (void)ctxLinkedClone:(id)sender {
    VMStartVirtualMachine *vm = [self contextMenuVM];
    if (!vm) return;
    VMStartVirtualMachine *clone = [VMStartVirtualMachine virtualMachineWithName:[NSString stringWithFormat:@"%@ (Linked)", vm.name] architecture:vm.architecture];
    clone.machineType = vm.machineType;
    clone.cpuModel = vm.cpuModel;
    clone.cpuCores = vm.cpuCores;
    clone.memoryValue = vm.memoryValue;
    clone.memoryUnit = vm.memoryUnit;
    clone.diskController = vm.diskController;
    clone.networkMode = vm.networkMode;
    clone.displayType = vm.displayType;
    // Linked clone: create qcow2 overlay pointing to original
    NSString *clonePath = [self.vmDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.vmstart", clone.vmIdentifier]];
    clone.vmBundlePath = clonePath;
    [[NSFileManager defaultManager] createDirectoryAtPath:clonePath withIntermediateDirectories:YES attributes:nil error:nil];
    if (vm.diskImagePath.length > 0) {
        NSString *dstDisk = [clonePath stringByAppendingPathComponent:@"disk.qcow2"];
        NSString *qemuImg = @"/opt/homebrew/bin/qemu-img";
        if (![[NSFileManager defaultManager] fileExistsAtPath:qemuImg]) qemuImg = @"/usr/local/bin/qemu-img";
        if ([[NSFileManager defaultManager] fileExistsAtPath:qemuImg]) {
            NSTask *task = [[NSTask alloc] init];
            task.executableURL = [NSURL fileURLWithPath:qemuImg];
            task.arguments = @[@"create", @"-f", @"qcow2", @"-b", vm.diskImagePath, @"-F", @"qcow2", dstDisk];
            [task launch];
            [task waitUntilExit];
        }
        clone.diskImagePath = dstDisk;
        clone.diskSizeValue = vm.diskSizeValue;
        clone.diskSizeUnit = vm.diskSizeUnit;
    }
    [clone saveToBundle];
    [self.virtualMachines addObject:clone];
    [self sortVMs];
    [self.tableView reloadData];
    [self updateContentVisibility];
    [self updateStatusBar];
}
- (void)ctxExportOVF:(id)sender {
    VMStartVirtualMachine *vm = [self contextMenuVM];
    if (!vm) return;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[];
    panel.nameFieldStringValue = [NSString stringWithFormat:@"%@.ovf", vm.name];
    panel.title = AMLocalizedString(@"lib.exportOVF");
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSInteger result) {
        if (result == NSModalResponseOK && panel.URL) {
            // Generate OVF XML
            NSMutableDictionary *ovfDict = [vm toDictionary];
            NSString *ovfXML = [NSString stringWithFormat:@"<?xml version=\"1.0\"?>\n"
                "<Envelope xmlns=\"http://schemas.dmtf.org/ovf/envelope/1\">\n"
                "  <VirtualSystem ovf:id=\"%@\">\n"
                "    <Name>%@</Name>\n"
                "    <Info>VMStart Virtual Machine</Info>\n"
                "  </VirtualSystem>\n"
                "</Envelope>\n", vm.vmIdentifier, vm.name];
            [ovfXML writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    }];
}
- (void)ctxEncrypt:(id)sender {
    VMStartVirtualMachine *vm = [self contextMenuVM];
    if (!vm) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = vm.isEncrypted ? AMLocalizedString(@"lib.encrypt.decryptTitle") : AMLocalizedString(@"lib.encrypt.title");
    alert.informativeText = AMLocalizedString(@"lib.encrypt.message");
    [alert addButtonWithTitle:AMLocalizedString(@"alert.ok")];
    [alert addButtonWithTitle:AMLocalizedString(@"common.cancel")];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        vm.isEncrypted = !vm.isEncrypted;
        [vm saveToBundle];
        [self.tableView reloadData];
    }
}
- (void)ctxDelete:(id)sender {
    NSInteger row = self.tableView.clickedRow;
    if (row >= 0) {
        [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
        [self removeVM:sender];
    }
}

// VM control helpers
- (nullable VMStartVirtualMachine *)vmMatching:(NSString *)key {
    if (key.length == 0) return nil;
    for (VMStartVirtualMachine *vm in self.virtualMachines) {
        if ([vm.vmIdentifier isEqualToString:key] || [vm.name caseInsensitiveCompare:key] == NSOrderedSame) return vm;
    }
    for (VMStartVirtualMachine *vm in self.virtualMachines) {
        if ([vm.name.lowercaseString hasPrefix:key.lowercaseString]) return vm;
    }
    return nil;
}

- (void)selectVMWithID:(NSString *)vmID {
    NSArray *vms = [self visibleVMs];
    for (NSUInteger i = 0; i < vms.count; i++) {
        if ([[vms[i] vmIdentifier] isEqualToString:vmID]) {
            [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
            [self.tableView scrollRowToVisible:i];
            break;
        }
    }
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)startVMByID:(NSString *)vmID {
    for (VMStartVirtualMachine *vm in self.virtualMachines) {
        if ([vm.vmIdentifier isEqualToString:vmID]) {
            NSString *key = vm.vmIdentifier;
            VMStartConsoleWindowController *console = self.consoleControllers[key];
            if (!console) {
                console = [[VMStartConsoleWindowController alloc] initWithVM:vm];
                self.consoleControllers[key] = console;
            }
            [console showWindow:nil];
            [console.window makeKeyAndOrderFront:nil];
            [console startVM];
            break;
        }
    }
}
- (void)stopVMByID:(NSString *)vmID {
    VMStartConsoleWindowController *console = self.consoleControllers[vmID];
    if (console) [console stopVM];
}
- (void)pauseVMByID:(NSString *)vmID {
    // Pause not yet implemented - will be added when QEMU monitor support is added
}

#pragma mark - Favorites & Groups

- (void)toggleFavoritesFilter:(id)sender {
    self.showFavoritesOnly = !self.showFavoritesOnly;
    self.favoritesButton.title = [(self.showFavoritesOnly ? @"\u2605 " : @"\u2606 ") stringByAppendingString:AMLocalizedString(@"sidebar.favorites")];
    [self.tableView reloadData];
    [self updateContentVisibility];
    [self updateStatusBar];
}

#pragma mark - Drag & Drop

- (NSDragOperation)tableView:(NSTableView *)tv validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger *)row proposedDropOperation:(NSTableViewDropOperation *)op {
    NSPasteboard *pb = info.draggingPasteboard;
    if ([pb.types containsObject:NSPasteboardTypeFileURL]) {
        return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView *)tv acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)op {
    NSPasteboard *pb = info.draggingPasteboard;
    NSArray *items = [pb readObjectsForClasses:@[[NSURL class]] options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    for (NSURL *url in items) {
        if ([url.pathExtension isEqualToString:@"vmstart"]) {
            // Import VM bundle
            VMStartVirtualMachine *vm = [[VMStartVirtualMachine alloc] init];
            if ([vm loadFromBundle:url.path]) {
                // Copy to our VM directory
                NSString *destPath = [self.vmDirectory stringByAppendingPathComponent:url.lastPathComponent];
                if (![destPath isEqualToString:url.path]) {
                    [[NSFileManager defaultManager] copyItemAtPath:url.path toPath:destPath error:nil];
                    vm.vmBundlePath = destPath;
                }
                [self.virtualMachines addObject:vm];
            }
        } else if ([url.pathExtension isEqualToString:@"qcow2"] || [url.pathExtension isEqualToString:@"vmdk"] ||
                   [url.pathExtension isEqualToString:@"vdi"] || [url.pathExtension isEqualToString:@"vhd"]) {
            // Import disk image - create VM with this disk
            VMStartVirtualMachine *vm = [VMStartVirtualMachine virtualMachineWithName:[url.lastPathComponent stringByDeletingPathExtension] architecture:VMStartArchX86_64];
            NSString *vmPath = [self.vmDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.vmstart", vm.vmIdentifier]];
            vm.vmBundlePath = vmPath;
            [[NSFileManager defaultManager] createDirectoryAtPath:vmPath withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *destDisk = [vmPath stringByAppendingPathComponent:@"disk.qcow2"];
            [[NSFileManager defaultManager] copyItemAtPath:url.path toPath:destDisk error:nil];
            vm.diskImagePath = destDisk;
            [vm saveToBundle];
            [self.virtualMachines addObject:vm];
        } else if ([url.pathExtension isEqualToString:@"iso"] || [url.pathExtension isEqualToString:@"img"]) {
            // Import ISO - create VM with this as boot ISO
            VMStartVirtualMachine *vm = [VMStartVirtualMachine virtualMachineWithName:[url.lastPathComponent stringByDeletingPathExtension] architecture:VMStartArchX86_64];
            NSString *vmPath = [self.vmDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.vmstart", vm.vmIdentifier]];
            vm.vmBundlePath = vmPath;
            [[NSFileManager defaultManager] createDirectoryAtPath:vmPath withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *destISO = [vmPath stringByAppendingPathComponent:url.lastPathComponent];
            [[NSFileManager defaultManager] copyItemAtPath:url.path toPath:destISO error:nil];
            vm.bootISOPath = destISO;
            [vm saveToBundle];
            [self.virtualMachines addObject:vm];
        } else if ([url.pathExtension isEqualToString:@"ovf"] || [url.pathExtension isEqualToString:@"ova"]) {
            // Import OVF/OVA
            VMStartVirtualMachine *vm = [VMStartVirtualMachine virtualMachineWithName:[url.lastPathComponent stringByDeletingPathExtension] architecture:VMStartArchX86_64];
            NSString *vmPath = [self.vmDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.vmstart", vm.vmIdentifier]];
            vm.vmBundlePath = vmPath;
            [[NSFileManager defaultManager] createDirectoryAtPath:vmPath withIntermediateDirectories:YES attributes:nil error:nil];
            [vm saveToBundle];
            [self.virtualMachines addObject:vm];
        }
    }
    [self sortVMs];
    [self.tableView reloadData];
    [self updateContentVisibility];
    [self updateStatusBar];
    return YES;
}

- (void)sortVMs {
    // Sort by group first, then by name
    [self.virtualMachines sortUsingComparator:^NSComparisonResult(VMStartVirtualMachine *a, VMStartVirtualMachine *b) {
        NSString *ga = a.group ?: @"";
        NSString *gb = b.group ?: @"";
        NSComparisonResult groupCmp = [ga compare:gb options:NSCaseInsensitiveSearch];
        if (groupCmp != NSOrderedSame) return groupCmp;
        // Favorites first within group
        if (a.isFavorite && !b.isFavorite) return NSOrderedAscending;
        if (!a.isFavorite && b.isFavorite) return NSOrderedDescending;
        return [a.name compare:b.name options:NSCaseInsensitiveSearch];
    }];
}

- (void)openNetworkEditor:(id)sender {
    if (!self.networkEditorWC) {
        self.networkEditorWC = [[VMStartNetworkEditorController alloc] init];
    }
    [self.networkEditorWC showWindow:self];
    [self.networkEditorWC.window makeKeyAndOrderFront:self];
}

#pragma mark - Welcome View Actions

- (void)downloadImage:(id)sender {
    // 使用系统默认浏览器打开镜像下载页面
    NSURL *url = [NSURL URLWithString:@"https://cdimage.ubuntu.com/releases/"];
    if (url) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
    [self appendLog:[@"[INFO] " stringByAppendingString:AMLocalizedString(@"lib.log.openDownload")]];
}

- (void)openUserGuide:(id)sender {
    NSURL *url = [NSURL URLWithString:@"https://docs.getutm.app/basics/basics/"];
    if (url) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
    [self appendLog:[@"[INFO] " stringByAppendingString:AMLocalizedString(@"lib.log.openGuide")]];
}

- (void)openSupport:(id)sender {
    NSURL *url = [NSURL URLWithString:@"https://docs.getutm.app/"];
    if (url) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
    [self appendLog:[@"[INFO] " stringByAppendingString:AMLocalizedString(@"lib.log.openSupport")]];
}

#pragma mark - Log & Print

- (void)appendLog:(NSString *)logEntry {
    NSString *timestamp = [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle];
    NSString *fullEntry = [NSString stringWithFormat:@"[%@] %@", timestamp, logEntry];
    [self.logEntries addObject:fullEntry];

    // 更新日志文本视图
    if (self.logTextView) {
        [self.logTextView.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:[fullEntry stringByAppendingString:@"\n"] attributes:@{
            NSFontAttributeName: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular],
            NSForegroundColorAttributeName: [NSColor whiteColor]
        }]];
        // 自动滚动到底部
        [self.logTextView scrollToEndOfDocument:nil];
    }

    // 自动打印
    if (self.autoPrintEnabled && self.printerAvailable) {
        [self printLogs:nil];
    }
}

- (void)showLogPanel:(id)sender {
    if (!self.logPanel) {
        NSRect panelFrame = NSMakeRect(0, 0, 600, 400);
        self.logPanel = [[NSWindow alloc] initWithContentRect:panelFrame
                                                    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
        self.logPanel.title = AMLocalizedString(@"logPanel.title");
        self.logPanel.minSize = NSMakeSize(400, 250);

        NSView *contentView = self.logPanel.contentView;
        contentView.wantsLayer = YES;
        contentView.layer.backgroundColor = [NSColor colorWithRed:0.12 green:0.12 blue:0.14 alpha:1.0].CGColor;

        // 日志文本视图
        NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, contentView.bounds.size.width, contentView.bounds.size.height - 40)];
        scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        scrollView.hasVerticalScroller = YES;
        scrollView.hasHorizontalScroller = YES;
        scrollView.autohidesScrollers = NO;
        scrollView.borderType = NSNoBorder;

        self.logTextView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, scrollView.bounds.size.width, scrollView.bounds.size.height)];
        self.logTextView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        self.logTextView.backgroundColor = [NSColor colorWithRed:0.12 green:0.12 blue:0.14 alpha:1.0];
        self.logTextView.textColor = [NSColor whiteColor];
        self.logTextView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
        self.logTextView.editable = NO;
        self.logTextView.selectable = YES;
        self.logTextView.verticallyResizable = YES;
        self.logTextView.horizontallyResizable = YES;

        // 显示已有日志
        NSMutableAttributedString *fullText = [[NSMutableAttributedString alloc] init];
        for (NSString *entry in self.logEntries) {
            [fullText appendAttributedString:[[NSAttributedString alloc] initWithString:[entry stringByAppendingString:@"\n"] attributes:@{
                NSFontAttributeName: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular],
                NSForegroundColorAttributeName: [NSColor whiteColor]
            }]];
        }
        self.logTextView.textStorage.attributedString = fullText;

        scrollView.documentView = self.logTextView;
        [contentView addSubview:scrollView];

        // 底部工具栏
        NSView *bottomBar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, contentView.bounds.size.width, 40)];
        bottomBar.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
        bottomBar.wantsLayer = YES;
        bottomBar.layer.backgroundColor = [NSColor colorWithRed:0.15 green:0.15 blue:0.17 alpha:1.0].CGColor;
        [contentView addSubview:bottomBar];

        // 清空按钮
        NSButton *clearBtn = [NSButton buttonWithTitle:AMLocalizedString(@"logPanel.clear") target:self action:@selector(clearLogs:)];
        clearBtn.frame = NSMakeRect(12, 8, 70, 24);
        clearBtn.bezelStyle = NSBezelStyleRounded;
        [bottomBar addSubview:clearBtn];

        // 导出按钮
        NSButton *exportBtn = [NSButton buttonWithTitle:AMLocalizedString(@"logPanel.export") target:self action:@selector(exportLogs:)];
        exportBtn.frame = NSMakeRect(90, 8, 70, 24);
        exportBtn.bezelStyle = NSBezelStyleRounded;
        [bottomBar addSubview:exportBtn];
    }

    [self.logPanel center];
    [self.logPanel makeKeyAndOrderFront:nil];
}

- (void)clearLogs:(id)sender {
    [self.logEntries removeAllObjects];
    if (self.logTextView) {
        self.logTextView.string = @"";
    }
}

- (void)exportLogs:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[UTTypePlainText];
    panel.nameFieldStringValue = @"VMStart-logs.txt";
    [panel beginSheetModalForWindow:self.logPanel completionHandler:^(NSInteger result) {
        if (result == NSModalResponseOK && panel.URL) {
            NSString *logText = [self.logEntries componentsJoinedByString:@"\n"];
            [logText writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    }];
}

- (void)printLogs:(id)sender {
    if (!self.printerAvailable) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = AMLocalizedString(@"alert.noPrinter.title");
        alert.informativeText = AMLocalizedString(@"alert.noPrinter.message");
        [alert addButtonWithTitle:AMLocalizedString(@"alert.ok")];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }

    NSPrintInfo *printInfo = [NSPrintInfo sharedPrintInfo];
    printInfo.horizontalPagination = NSFitPagination;
    printInfo.verticalPagination = NSAutoPagination;

    // 构建打印内容
    NSMutableAttributedString *printText = [[NSMutableAttributedString alloc] init];
    [printText appendAttributedString:[[NSAttributedString alloc] initWithString:[AMLocalizedString(@"logPanel.title") stringByAppendingString:@"\n"] attributes:@{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:16],
        NSForegroundColorAttributeName: [NSColor blackColor]
    }]];
    [printText appendAttributedString:[[NSAttributedString alloc] initWithString:@"========================\n\n" attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:10],
        NSForegroundColorAttributeName: [NSColor blackColor]
    }]];

    for (NSString *entry in self.logEntries) {
        [printText appendAttributedString:[[NSAttributedString alloc] initWithString:[entry stringByAppendingString:@"\n"] attributes:@{
            NSFontAttributeName: [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular],
            NSForegroundColorAttributeName: [NSColor blackColor]
        }]];
    }

    NSTextView *printView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 800)];
    printView.textStorage.attributedString = printText;
    printView.editable = NO;

    NSPrintOperation *printOp = [NSPrintOperation printOperationWithView:printView printInfo:printInfo];
    printOp.showsPrintPanel = YES;
    printOp.showsProgressPanel = YES;
    [printOp runOperation];

    [self appendLog:[@"[INFO] " stringByAppendingString:AMLocalizedString(@"lib.log.printed")]];
}

- (void)toggleAutoPrint:(id)sender {
    self.autoPrintEnabled = !self.autoPrintEnabled;
    if (self.autoPrintEnabled) {
        [self.autoPrintButton setContentTintColor:[NSColor colorWithRed:0.25 green:0.7 blue:0.35 alpha:1.0]];
        [self appendLog:[@"[INFO] " stringByAppendingString:AMLocalizedString(@"lib.log.autoPrintOn")]];
    } else {
        [self.autoPrintButton setContentTintColor:[NSColor colorWithRed:0.5 green:0.5 blue:0.55 alpha:1.0]];
        [self appendLog:[@"[INFO] " stringByAppendingString:AMLocalizedString(@"lib.log.autoPrintOff")]];
    }
}

- (void)checkPrinterAvailability {
    // 通过 NSPrintInfo 检查打印机
    NSPrintInfo *printInfo = [NSPrintInfo sharedPrintInfo];
    NSPrinter *printer = printInfo.printer;
    self.printerAvailable = (printer != nil && printer.name != nil && printer.name.length > 0);

    // 更新打印按钮状态
    if (self.printLogButton) {
        self.printLogButton.enabled = self.printerAvailable;
        if (self.printerAvailable) {
            [self.printLogButton setContentTintColor:[NSColor controlAccentColor]];
        } else {
            [self.printLogButton setContentTintColor:[NSColor colorWithRed:0.4 green:0.4 blue:0.4 alpha:1.0]];
        }
    }

    if (self.printerAvailable) {
        [self appendLog:[@"[INFO] " stringByAppendingString:AMLocalizedStringF(@"lib.log.printerFound", printer.name)]];
    } else {
        [self appendLog:[@"[INFO] " stringByAppendingString:AMLocalizedString(@"lib.log.noPrinter")]];
    }
}

#pragma mark - Licenses Panel

- (void)showLicensesPanel:(id)sender {
    NSWindow *panel = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 650, 500)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    panel.title = AMLocalizedString(@"licenses.title");
    panel.minSize = NSMakeSize(450, 350);

    NSView *contentView = panel.contentView;
    contentView.wantsLayer = YES;
    contentView.layer.backgroundColor = [NSColor colorWithRed:0.12 green:0.12 blue:0.14 alpha:1.0].CGColor;

    // Header
    NSTextField *header = [[NSTextField alloc] initWithFrame:NSMakeRect(20, contentView.bounds.size.height - 50, contentView.bounds.size.width - 40, 30)];
    header.stringValue = [NSString stringWithFormat:AMLocalizedString(@"licenses.engineCount"), (long)16];
    header.font = [NSFont systemFontOfSize:16 weight:NSFontWeightBold];
    header.textColor = [NSColor whiteColor];
    header.bezeled = NO; header.drawsBackground = NO; header.editable = NO;
    header.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [contentView addSubview:header];

    // License list
    NSArray *engines = @[
        @{@"name": @"QEMU", @"ver": @"GPLv2", @"arch": AMLocalizedString(@"lib.license.qemuArch")},
        @{@"name": @"Mini vMac", @"ver": @"GPLv2", @"arch": @"Motorola 68000"},
        @{@"name": @"BasiliskII", @"ver": @"GPLv2", @"arch": @"Motorola 68020/030/040"},
        @{@"name": @"SheepShaver", @"ver": @"GPLv2", @"arch": @"PowerPC G3/G4"},
        @{@"name": @"DOSBox Staging", @"ver": @"GPLv2", @"arch": @"x86"},
        @{@"name": @"DOSBox-X", @"ver": @"GPLv2", @"arch": @"x86"},
        @{@"name": @"PCem", @"ver": @"GPLv2", @"arch": @"x86"},
        @{@"name": @"86Box", @"ver": @"GPLv2", @"arch": @"x86"},
        @{@"name": @"VICE", @"ver": @"GPLv2", @"arch": @"MOS 6502"},
        @{@"name": @"FS-UAE", @"ver": @"GPLv2", @"arch": @"Motorola 68000 (Amiga)"},
        @{@"name": @"Hatari", @"ver": @"GPLv2", @"arch": @"Motorola 68000 (Atari)"},
        @{@"name": @"ARAnyM", @"ver": @"GPLv2", @"arch": @"Motorola 68000 (Atari)"},
        @{@"name": @"OpenMSX", @"ver": @"GPLv2", @"arch": @"Z80 (MSX)"},
        @{@"name": @"Fuse", @"ver": @"GPLv2", @"arch": @"Z80 (ZX Spectrum)"},
        @{@"name": @"ScummVM", @"ver": @"GPLv3", @"arch": AMLocalizedString(@"lib.license.multiPlatform")},
        @{@"name": @"Mednafen", @"ver": @"GPLv2", @"arch": AMLocalizedString(@"lib.license.multiPlatform")},
    ];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 50, contentView.bounds.size.width - 20, contentView.bounds.size.height - 110)];
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scrollView.hasVerticalScroller = YES;
    scrollView.autohidesScrollers = NO;
    scrollView.borderType = NSNoBorder;

    CGFloat rowH = 32;
    NSView *listView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, scrollView.bounds.size.width - 16, engines.count * rowH)];
    listView.autoresizingMask = NSViewWidthSizable;

    for (NSInteger i = 0; i < engines.count; i++) {
        NSDictionary *engine = engines[i];
        CGFloat y = (engines.count - 1 - i) * rowH;

        // Row background (alternating)
        NSView *row = [[NSView alloc] initWithFrame:NSMakeRect(0, y, listView.bounds.size.width, rowH)];
        row.wantsLayer = YES;
        row.layer.backgroundColor = (i % 2 == 0)
            ? [NSColor colorWithRed:0.16 green:0.16 blue:0.18 alpha:1.0].CGColor
            : [NSColor colorWithRed:0.13 green:0.13 blue:0.15 alpha:1.0].CGColor;
        row.autoresizingMask = NSViewWidthSizable;
        [listView addSubview:row];

        // Index
        NSTextField *idx = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 6, 24, 20)];
        idx.stringValue = [NSString stringWithFormat:@"%ld", (long)(i + 1)];
        idx.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
        idx.textColor = [NSColor colorWithRed:0.5 green:0.5 blue:0.55 alpha:1.0];
        idx.bezeled = NO; idx.drawsBackground = NO; idx.editable = NO;
        [row addSubview:idx];

        // Engine name
        NSTextField *name = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 6, 130, 20)];
        name.stringValue = engine[@"name"];
        name.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
        name.textColor = [NSColor whiteColor];
        name.bezeled = NO; name.drawsBackground = NO; name.editable = NO;
        [row addSubview:name];

        // License badge
        NSTextField *badge = [[NSTextField alloc] initWithFrame:NSMakeRect(175, 6, 50, 20)];
        badge.stringValue = engine[@"ver"];
        badge.font = [NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightMedium];
        badge.textColor = [NSColor whiteColor];
        badge.bezeled = NO; badge.editable = NO;
        badge.wantsLayer = YES;
        badge.layer.backgroundColor = [NSColor colorWithRed:0.25 green:0.55 blue:0.35 alpha:1.0].CGColor;
        badge.layer.cornerRadius = 8;
        badge.drawsBackground = YES;
        badge.backgroundColor = [NSColor colorWithRed:0.25 green:0.55 blue:0.35 alpha:1.0];
        badge.alignment = NSTextAlignmentCenter;
        [row addSubview:badge];

        // Architecture
        NSTextField *arch = [[NSTextField alloc] initWithFrame:NSMakeRect(235, 6, listView.bounds.size.width - 245, 20)];
        arch.stringValue = engine[@"arch"];
        arch.font = [NSFont systemFontOfSize:11];
        arch.textColor = [NSColor colorWithRed:0.6 green:0.6 blue:0.65 alpha:1.0];
        arch.bezeled = NO; arch.drawsBackground = NO; arch.editable = NO;
        arch.autoresizingMask = NSViewWidthSizable;
        [row addSubview:arch];
    }

    scrollView.documentView = listView;
    [contentView addSubview:scrollView];

    // Footer
    NSTextField *footer = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 14, contentView.bounds.size.width - 40, 20)];
    footer.stringValue = AMLocalizedString(@"licenses.allGPLv2");
    footer.font = [NSFont systemFontOfSize:10 weight:NSFontWeightLight];
    footer.textColor = [NSColor colorWithRed:0.5 green:0.5 blue:0.55 alpha:1.0];
    footer.alignment = NSTextAlignmentCenter;
    footer.bezeled = NO; footer.drawsBackground = NO; footer.editable = NO;
    footer.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [contentView addSubview:footer];

    [panel center];
    [panel makeKeyAndOrderFront:nil];

    [self appendLog:[@"[INFO] " stringByAppendingString:AMLocalizedString(@"lib.log.openLicenses")]];
}

@end
