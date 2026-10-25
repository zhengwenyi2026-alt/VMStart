//
//  VMStartConsoleWindowController.m
//  VMStart
//
//  Copyright (c) 2024 zhengwenyi2026-alt. Licensed under GPLv2.
//

#import "VMStartConsoleWindowController.h"
#import "VMStartLocalization.h"
#import "VMStartEngineSelector.h"
#import "VMStartCardView.h"
#import <QuartzCore/QuartzCore.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "VMStart-Swift.h"

static const NSInteger kVNCPort = 5900;
static const NSInteger kSerialPort = 4321;

@interface VMStartConsoleWindowController ()
@property (nonatomic, strong) NSTextView *logView;
@property (nonatomic, strong) NSScrollView *logScroll;
@property (nonatomic, strong) NSTextField *statusBar;
@property (nonatomic, strong) NSButton *startStopButton;
@property (nonatomic, strong) NSButton *pauseResumeButton;
@property (nonatomic, strong) NSButton *screenshotButton;
@property (nonatomic, strong) NSButton *mediaButton;
@property (nonatomic, strong) NSButton *fullscreenButton;
@property (nonatomic, strong) NSView *toolbar;
@property (nonatomic, strong) NSView *splashView;
@property (nonatomic, strong) NSTextField *splashTitle;
@property (nonatomic, strong) NSTextField *splashSubtitle;
@property (nonatomic, strong) NSProgressIndicator *splashSpinner;
@property (nonatomic, strong) NSTextField *toolbarVMName;
// Tab system
@property (nonatomic, strong) NSView *tabBar;
@property (nonatomic, strong) NSButton *tabDisplay;
@property (nonatomic, strong) NSButton *tabLog;
@property (nonatomic, strong) NSButton *tabSerial;
@property (nonatomic, strong) NSButton *tabMonitor;
@property (nonatomic, strong) NSView *displayContainer;
@property (nonatomic, strong) NSView *logContainer;
@property (nonatomic, strong) NSView *serialContainer;
@property (nonatomic, strong) NSView *monitorContainer;
// VNC & Serial (Swift components)
@property (nonatomic, strong) VMStartVNCViewer *vncViewer;
@property (nonatomic, strong) VMStartSerialTerminal *serialTerminal;
@property (nonatomic, strong) VMStartResourceMonitor *resourceMonitor;
@property (nonatomic, assign) NSInteger activeTab; // 0=display,1=log,2=serial,3=monitor
@property (nonatomic, assign) BOOL isRecording;
@property (nonatomic, strong) NSButton *recordButton;
@property (nonatomic, strong) NSTimer *recordTimer;
@property (nonatomic, strong) NSMutableArray<NSImage *> *recordedFrames;
@property (nonatomic, strong) NSPopUpButton *monitorPopup;
// Auto-snapshot
@property (nonatomic, strong) NSTimer *autoSnapshotTimer;
@property (nonatomic, assign) NSInteger autoSnapshotCounter;
@end

@implementation VMStartConsoleWindowController

- (instancetype)initWithVM:(VMStartVirtualMachine *)vm {
    NSRect frame = NSMakeRect(0, 0, 920, 640);
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame styleMask:style backing:NSBackingStoreBuffered defer:NO];
    window.title = [NSString stringWithFormat:@"%@ - VMStart", vm.name];
    window.minSize = NSMakeSize(680, 480);
    [window center];
    window.backgroundColor = [NSColor colorWithRed:0.10 green:0.10 blue:0.12 alpha:1.0];
    self = [super initWithWindow:window];
    if (self) {
        _virtualMachine = vm;
        _engine = [VMStartEngineSelector engineForVM:vm];
        _engine.delegate = self;
        if ([_engine isKindOfClass:[VMStartQEMUProcess class]]) {
            _qemuProcess = (VMStartQEMUProcess *)_engine;
            _qemuProcess.delegate = self;
        }
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    NSView *content = self.window.contentView;
    content.wantsLayer = YES;
    content.layer.backgroundColor = [[NSColor colorWithRed:0.10 green:0.10 blue:0.12 alpha:1.0] CGColor];

    CGFloat toolbarH = 44;
    CGFloat windowW = content.bounds.size.width;
    CGFloat windowH = content.bounds.size.height;

    // ─── Toolbar ───
    self.toolbar = [[NSView alloc] initWithFrame:NSMakeRect(0, windowH - toolbarH, windowW, toolbarH)];
    self.toolbar.wantsLayer = YES;
    self.toolbar.layer.backgroundColor = [[NSColor colorWithRed:0.15 green:0.15 blue:0.18 alpha:1.0] CGColor];
    self.toolbar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [content addSubview:self.toolbar];

    // Toolbar bottom line
    NSView *tborder = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, windowW, 1)];
    tborder.wantsLayer = YES;
    tborder.layer.backgroundColor = [[NSColor colorWithWhite:0.3 alpha:1.0] CGColor];
    tborder.autoresizingMask = NSViewWidthSizable;
    [self.toolbar addSubview:tborder];

    // Buttons
    CGFloat bx = 12;
    self.startStopButton = [self makeToolbarBtn:AMLocalizedString(@"console.start") icon:@"play.fill" x:bx];
    self.startStopButton.target = self;
    self.startStopButton.action = @selector(toggleStartStop:);
    [self.toolbar addSubview:self.startStopButton];
    bx += 88;

    self.pauseResumeButton = [self makeToolbarBtn:AMLocalizedString(@"console.pause") icon:@"pause.fill" x:bx];
    self.pauseResumeButton.target = self;
    self.pauseResumeButton.action = @selector(togglePauseResume:);
    self.pauseResumeButton.enabled = NO;
    [self.toolbar addSubview:self.pauseResumeButton];
    bx += 88;

    self.mediaButton = [self makeToolbarBtn:AMLocalizedString(@"console.media") icon:@"opticaldisc" x:bx];
    self.mediaButton.target = self;
    self.mediaButton.action = @selector(showMediaMenu:);
    [self.toolbar addSubview:self.mediaButton];
    bx += 88;

    self.screenshotButton = [self makeToolbarBtn:AMLocalizedString(@"console_capture") icon:@"camera" x:bx];
    self.screenshotButton.target = self;
    self.screenshotButton.action = @selector(takeScreenshot:);
    [self.toolbar addSubview:self.screenshotButton];
    bx += 88;

    self.recordButton = [self makeToolbarBtn:AMLocalizedString(@"console.record") icon:@"record.circle" x:bx];
    self.recordButton.target = self;
    self.recordButton.action = @selector(toggleRecording:);
    [self.toolbar addSubview:self.recordButton];
    bx += 88;

    self.fullscreenButton = [self makeToolbarBtn:AMLocalizedString(@"console.full") icon:@"arrow.up.left.and.arrow.down.right" x:bx];
    self.fullscreenButton.target = self;
    self.fullscreenButton.action = @selector(toggleFullscreen:);
    [self.toolbar addSubview:self.fullscreenButton];

    // VM name on right side
    self.toolbarVMName = [[NSTextField alloc] initWithFrame:NSMakeRect(windowW - 260, 14, 244, 18)];
    self.toolbarVMName.stringValue = self.virtualMachine.name;
    self.toolbarVMName.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    self.toolbarVMName.textColor = [NSColor colorWithWhite:0.85 alpha:1.0];
    self.toolbarVMName.bezeled = NO; self.toolbarVMName.drawsBackground = NO; self.toolbarVMName.editable = NO;
    self.toolbarVMName.alignment = NSTextAlignmentRight;
    self.toolbarVMName.autoresizingMask = NSViewMinXMargin;
    [self.toolbar addSubview:self.toolbarVMName];

    // ─── Tab bar ───
    CGFloat tabH = 30;
    self.tabBar = [[NSView alloc] initWithFrame:NSMakeRect(0, windowH - toolbarH - tabH, windowW, tabH)];
    self.tabBar.wantsLayer = YES;
    self.tabBar.layer.backgroundColor = [[NSColor colorWithRed:0.12 green:0.12 blue:0.16 alpha:1.0] CGColor];
    self.tabBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [content addSubview:self.tabBar];

    CGFloat tx = 8;
    self.tabDisplay = [self makeTabBtn:[@"🖥 " stringByAppendingString:AMLocalizedString(@"console.tab.display")] tag:0 x:tx];
    [self.tabBar addSubview:self.tabDisplay]; tx += 90;
    self.tabLog = [self makeTabBtn:[@"📋 " stringByAppendingString:AMLocalizedString(@"console.tab.log")] tag:1 x:tx];
    [self.tabBar addSubview:self.tabLog]; tx += 70;
    self.tabSerial = [self makeTabBtn:[@"🔌 " stringByAppendingString:AMLocalizedString(@"console.tab.serial")] tag:2 x:tx];
    [self.tabBar addSubview:self.tabSerial]; tx += 80;
    self.tabMonitor = [self makeTabBtn:[@"📊 " stringByAppendingString:AMLocalizedString(@"console.tab.monitor")] tag:3 x:tx];
    [self.tabBar addSubview:self.tabMonitor];

    // ─── Display container (VNC) ───
    CGFloat contentTop = windowH - toolbarH - tabH;
    self.displayContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 28, windowW, contentTop - 28)];
    self.displayContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.displayContainer.wantsLayer = YES;
    self.displayContainer.layer.backgroundColor = [[NSColor blackColor] CGColor];
    [content addSubview:self.displayContainer];

    self.vncViewer = [[VMStartVNCViewer alloc] initWithFrame:self.displayContainer.bounds];
    self.vncViewer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.displayContainer addSubview:self.vncViewer];

    // ─── Log container ───
    self.logContainer = [[NSView alloc] initWithFrame:self.displayContainer.frame];
    self.logContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.logContainer.hidden = YES;
    [content addSubview:self.logContainer];

    self.logScroll = [[NSScrollView alloc] initWithFrame:self.logContainer.bounds];
    self.logScroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.logScroll.borderType = NSNoBorder;
    self.logScroll.drawsBackground = NO;
    self.logScroll.autohidesScrollers = YES;

    self.logView = [[NSTextView alloc] initWithFrame:self.logScroll.contentView.bounds];
    self.logView.editable = NO;
    self.logView.drawsBackground = NO;
    self.logView.textColor = [NSColor colorWithRed:0.7 green:0.92 blue:0.7 alpha:1.0];
    self.logView.font = [NSFont userFixedPitchFontOfSize:12];
    self.logView.backgroundColor = [NSColor clearColor];
    self.logView.textContainerInset = NSMakeSize(12, 12);
    self.logScroll.documentView = self.logView;
    [self.logContainer addSubview:self.logScroll];

    // ─── Serial container ───
    self.serialContainer = [[NSView alloc] initWithFrame:self.displayContainer.frame];
    self.serialContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.serialContainer.hidden = YES;
    [content addSubview:self.serialContainer];

    self.serialTerminal = [[VMStartSerialTerminal alloc] initWithFrame:self.serialContainer.bounds];
    self.serialTerminal.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.serialContainer addSubview:self.serialTerminal];

    // ─── Monitor container ───
    self.monitorContainer = [[NSView alloc] initWithFrame:self.displayContainer.frame];
    self.monitorContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.monitorContainer.hidden = YES;
    [content addSubview:self.monitorContainer];

    self.resourceMonitor = [[VMStartResourceMonitor alloc] initWithFrame:self.monitorContainer.bounds];
    self.resourceMonitor.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.monitorContainer addSubview:self.resourceMonitor];

    self.activeTab = 0;
    [self updateTabHighlight];

    // ─── Status bar ───
    self.statusBar = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 4, windowW - 24, 20)];
    self.statusBar.font = [NSFont systemFontOfSize:10];
    self.statusBar.bezeled = NO; self.statusBar.drawsBackground = NO; self.statusBar.editable = NO;
    self.statusBar.textColor = [NSColor colorWithWhite:0.5 alpha:1.0];
    self.statusBar.stringValue = AMLocalizedString(@"console.ready");
    self.statusBar.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [content addSubview:self.statusBar];

    // ─── Splash overlay ───
    [self setupSplashView];

    [self appendLog:[AMLocalizedStringF(@"console.log.header",
                     self.virtualMachine.name, self.virtualMachine.architectureDisplayName) stringByAppendingString:@"\n\n"]];
}

- (NSButton *)makeTabBtn:(NSString *)title tag:(NSInteger)tag x:(CGFloat)x {
    NSButton *btn = [[NSButton alloc] initWithFrame:NSMakeRect(x, 3, 80, 24)];
    btn.title = title;
    btn.bezelStyle = NSBezelStyleInline;
    btn.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    btn.wantsLayer = YES;
    btn.layer.cornerRadius = 4;
    btn.tag = tag;
    btn.target = self;
    btn.action = @selector(switchTab:);
    [btn setContentTintColor:[NSColor colorWithWhite:0.7 alpha:1.0]];
    return btn;
}

- (void)switchTab:(id)sender {
    NSInteger tag = ((NSButton *)sender).tag;
    self.activeTab = tag;
    self.displayContainer.hidden = (tag != 0);
    self.logContainer.hidden = (tag != 1);
    self.serialContainer.hidden = (tag != 2);
    self.monitorContainer.hidden = (tag != 3);
    [self updateTabHighlight];
}

- (void)updateTabHighlight {
    NSColor *active = [NSColor colorWithRed:0.15 green:0.45 blue:0.9 alpha:1.0];
    NSColor *inactive = [NSColor clearColor];
    self.tabDisplay.layer.backgroundColor = self.activeTab == 0 ? active.CGColor : inactive.CGColor;
    self.tabLog.layer.backgroundColor = self.activeTab == 1 ? active.CGColor : inactive.CGColor;
    self.tabSerial.layer.backgroundColor = self.activeTab == 2 ? active.CGColor : inactive.CGColor;
    self.tabMonitor.layer.backgroundColor = self.activeTab == 3 ? active.CGColor : inactive.CGColor;
}

- (NSButton *)makeToolbarBtn:(NSString *)title icon:(NSString *)symbol x:(CGFloat)x {
    NSImage *img = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
    NSButton *btn = [NSButton buttonWithTitle:title target:nil action:nil];
    btn.frame = NSMakeRect(x, 8, 78, 28);
    btn.bezelStyle = NSBezelStyleInline;
    btn.image = img;
    btn.imagePosition = NSImageLeading;
    btn.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    btn.wantsLayer = YES;
    btn.layer.cornerRadius = 5;
    [btn setContentTintColor:[NSColor colorWithWhite:0.9 alpha:1.0]];
    return btn;
}

- (void)setupSplashView {
    NSView *content = self.window.contentView;
    self.splashView = [[NSView alloc] initWithFrame:content.bounds];
    self.splashView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.splashView.wantsLayer = YES;
    self.splashView.layer.backgroundColor = [[NSColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0] CGColor];
    [content addSubview:self.splashView];

    // Gradient background
    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.frame = self.splashView.bounds;
    grad.colors = @[
        (__bridge id)[NSColor colorWithRed:0.06 green:0.06 blue:0.10 alpha:1.0].CGColor,
        (__bridge id)[NSColor colorWithRed:0.10 green:0.10 blue:0.18 alpha:1.0].CGColor
    ];
    [self.splashView.layer insertSublayer:grad atIndex:0];

    // VMStart title
    self.splashTitle = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.splashTitle.stringValue = @"VMStart";
    self.splashTitle.font = [NSFont systemFontOfSize:72 weight:NSFontWeightBold];
    self.splashTitle.textColor = [NSColor whiteColor];
    self.splashTitle.alignment = NSTextAlignmentCenter;
    self.splashTitle.bezeled = NO; self.splashTitle.drawsBackground = NO; self.splashTitle.editable = NO;
    self.splashTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.splashView addSubview:self.splashTitle];

    // Subtitle
    self.splashSubtitle = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.splashSubtitle.stringValue = AMLocalizedString(@"console.starting");
    self.splashSubtitle.font = [NSFont systemFontOfSize:14 weight:NSFontWeightLight];
    self.splashSubtitle.textColor = [NSColor colorWithWhite:0.6 alpha:1.0];
    self.splashSubtitle.alignment = NSTextAlignmentCenter;
    self.splashSubtitle.bezeled = NO; self.splashSubtitle.drawsBackground = NO; self.splashSubtitle.editable = NO;
    self.splashSubtitle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.splashView addSubview:self.splashSubtitle];

    // Spinner
    self.splashSpinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, 32, 32)];
    self.splashSpinner.style = NSProgressIndicatorStyleSpinning;
    self.splashSpinner.indeterminate = YES;
    self.splashSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.splashView addSubview:self.splashSpinner];

    // Version label
    NSTextField *versionLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    versionLabel.stringValue = AMLocalizedStringF(@"console.version", @"1.0");
    versionLabel.font = [NSFont systemFontOfSize:10];
    versionLabel.textColor = [NSColor colorWithWhite:0.35 alpha:1.0];
    versionLabel.alignment = NSTextAlignmentCenter;
    versionLabel.bezeled = NO; versionLabel.drawsBackground = NO; versionLabel.editable = NO;
    versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.splashView addSubview:versionLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.splashTitle.centerXAnchor constraintEqualToAnchor:self.splashView.centerXAnchor],
        [self.splashTitle.centerYAnchor constraintEqualToAnchor:self.splashView.centerYAnchor constant:-20],
        [self.splashSubtitle.topAnchor constraintEqualToAnchor:self.splashTitle.bottomAnchor constant:16],
        [self.splashSubtitle.centerXAnchor constraintEqualToAnchor:self.splashView.centerXAnchor],
        [self.splashSpinner.topAnchor constraintEqualToAnchor:self.splashSubtitle.bottomAnchor constant:24],
        [self.splashSpinner.centerXAnchor constraintEqualToAnchor:self.splashView.centerXAnchor],
        [self.splashSpinner.widthAnchor constraintEqualToConstant:32],
        [self.splashSpinner.heightAnchor constraintEqualToConstant:32],
        [versionLabel.bottomAnchor constraintEqualToAnchor:self.splashView.bottomAnchor constant:-20],
        [versionLabel.centerXAnchor constraintEqualToAnchor:self.splashView.centerXAnchor],
    ]];

    self.splashView.hidden = YES;
}

#pragma mark - VM Control

- (void)startVM {
    if (self.engine.isRunning) return;
    [self showSplash];
    [self appendLog:[AMLocalizedString(@"console.starting") stringByAppendingString:@"\n"]];
    self.statusBar.stringValue = AMLocalizedString(@"status.starting");
    self.startStopButton.title = AMLocalizedString(@"console.stop");

    // 内嵌 VNC 显示与终端串口只用于本次启动，启动后恢复原配置，避免写入 vm.json 后越积越多
    NSString *serialArg = [NSString stringWithFormat:@"telnet:127.0.0.1:%ld,server,nowait", (long)kSerialPort];
    NSMutableArray *savedArgs = [NSMutableArray array];
    NSArray *oldArgs = self.virtualMachine.additionalArgs ?: @[];
    for (NSUInteger i = 0; i < oldArgs.count; i++) {
        if ([oldArgs[i] isEqualToString:@"-serial"] && i + 1 < oldArgs.count && [oldArgs[i + 1] isEqualToString:serialArg]) {
            i++;
            continue;
        }
        [savedArgs addObject:oldArgs[i]];
    }
    NSString *savedDisplay = self.virtualMachine.displayType;
    if ([savedDisplay isEqualToString:@"none"]) savedDisplay = @"cocoa";
    NSInteger savedVNC = self.virtualMachine.vncPort;

    self.virtualMachine.displayType = @"none";
    self.virtualMachine.vncPort = kVNCPort;
    self.virtualMachine.additionalArgs = [savedArgs arrayByAddingObjectsFromArray:@[@"-serial", serialArg]];

    NSError *error = nil;
    BOOL started = [self.engine startWithError:&error];
    self.virtualMachine.displayType = savedDisplay;
    self.virtualMachine.vncPort = savedVNC;
    self.virtualMachine.additionalArgs = savedArgs;
    [self.virtualMachine saveToBundle];
    if (!started) {
        [self hideSplash];
        [self appendLog:[NSString stringWithFormat:@"[ERROR] %@\n", error.localizedDescription]];
        self.statusBar.stringValue = AMLocalizedString(@"status.error");
        self.startStopButton.title = AMLocalizedString(@"console.start");
    }
}

- (void)stopVM {
    if (!self.engine.isRunning) return;
    [self appendLog:[AMLocalizedString(@"console.stopping") stringByAppendingString:@"\n"]];
    self.statusBar.stringValue = AMLocalizedString(@"status.stopping");
    [self.engine stop];
}

- (void)toggleStartStop:(id)sender {
    if (self.engine.isRunning) [self stopVM]; else [self startVM];
}

- (void)togglePauseResume:(id)sender {
    if (self.virtualMachine.status == VMStartStatusPaused) {
        if ([self.engine respondsToSelector:@selector(resume)]) [self.engine resume];
        [self appendLog:[AMLocalizedString(@"console.resumed") stringByAppendingString:@"\n"]];
        self.pauseResumeButton.title = AMLocalizedString(@"console.pause");
    } else {
        if ([self.engine respondsToSelector:@selector(pause)]) [self.engine pause];
        [self appendLog:[AMLocalizedString(@"console.paused") stringByAppendingString:@"\n"]];
        self.pauseResumeButton.title = AMLocalizedString(@"console.resume");
    }
}

- (void)toggleFullscreen:(id)sender {
    [self.window toggleFullScreen:nil];
}

- (void)takeScreenshot:(id)sender {
    // Capture from VNC viewer directly
    NSImage *captured = [self captureVNCSnapshot];
    if (captured) {
        // Save as PNG to desktop
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"yyyyMMdd_HHmmss";
        NSString *timestamp = [fmt stringFromDate:[NSDate date]];
        NSString *filename = [NSString stringWithFormat:@"VMStart_%@.png", timestamp ?: @"screenshot"];
        NSString *path = [[NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES) firstObject]
                          stringByAppendingPathComponent:filename];
        NSData *tiffData = [captured TIFFRepresentation];
        NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:tiffData];
        NSData *pngData = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if (pngData) {
            [pngData writeToFile:path atomically:YES];
            [self appendLog:[NSString stringWithFormat:@"[INFO] %@\n", AMLocalizedStringF(@"console.screenshotSaved", path)]];
        }
    } else {
        // Fallback to QEMU monitor
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"vmstart_screenshot.ppm"];
        if (self.qemuProcess && [self.qemuProcess captureScreenshotToPath:path]) {
            [self appendLog:[NSString stringWithFormat:@"[INFO] %@\n", AMLocalizedStringF(@"console.screenshotSaved", path)]];
        }
    }
}

- (NSImage *)captureVNCSnapshot {
    if (!self.vncViewer || self.displayContainer.hidden) return nil;
    // Use dataWithPDFInsideRect to capture the view
    NSData *pdfData = [self.vncViewer dataWithPDFInsideRect:self.vncViewer.bounds];
    if (!pdfData) return nil;
    NSImage *img = [[NSImage alloc] initWithData:pdfData];
    return img;
}

- (void)toggleRecording:(id)sender {
    if (self.isRecording) {
        [self stopRecording];
    } else {
        [self startRecording];
    }
}

- (void)startRecording {
    self.isRecording = YES;
    self.recordedFrames = [NSMutableArray array];
    self.recordButton.title = AMLocalizedString(@"console.stopRecording");
    [self.recordButton setContentTintColor:[NSColor systemRedColor]];
    [self appendLog:[NSString stringWithFormat:@"[INFO] %@\n", AMLocalizedString(@"console.log.recordingStarted")]];
    self.recordTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(captureRecordFrame) userInfo:nil repeats:YES];
}

- (void)captureRecordFrame {
    NSImage *frame = [self captureVNCSnapshot];
    if (frame) {
        [self.recordedFrames addObject:frame];
    }
}

- (void)stopRecording {
    self.isRecording = NO;
    [self.recordTimer invalidate];
    self.recordTimer = nil;
    self.recordButton.title = AMLocalizedString(@"console.record");
    [self.recordButton setContentTintColor:[NSColor colorWithWhite:0.9 alpha:1.0]];
    NSInteger frameCount = self.recordedFrames.count;
    [self appendLog:[NSString stringWithFormat:@"[INFO] %@\n", AMLocalizedStringF(@"console.log.recordingStopped", (long)frameCount)]];

    // Save frames as individual PNGs to a folder
    if (frameCount > 0) {
        NSDateFormatter *fmt2 = [[NSDateFormatter alloc] init];
        fmt2.dateFormat = @"yyyyMMdd_HHmmss";
        NSString *timestamp = [fmt2 stringFromDate:[NSDate date]];
        NSString *dirPath = [[[NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES) firstObject]
                             stringByAppendingPathComponent:[NSString stringWithFormat:@"VMStart_Recording_%@", timestamp ?: @"rec"]]
                            stringByAppendingPathComponent:@""];
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:nil];

        for (NSInteger i = 0; i < frameCount; i++) {
            NSImage *frame = self.recordedFrames[i];
            NSData *tiffData = [frame TIFFRepresentation];
            NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:tiffData];
            NSData *pngData = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            NSString *framePath = [dirPath stringByAppendingPathComponent:[NSString stringWithFormat:@"frame_%05ld.png", (long)i]];
            [pngData writeToFile:framePath atomically:YES];
        }
        [self appendLog:[NSString stringWithFormat:@"[INFO] %@\n", AMLocalizedStringF(@"console.log.framesSaved", dirPath)]];
    }
    [self.recordedFrames removeAllObjects];
}

#pragma mark - Splash

- (void)showSplash {
    self.splashView.alphaValue = 1.0;
    self.splashView.hidden = NO;
    [self.splashSpinner startAnimation:nil];
    self.splashSubtitle.stringValue = AMLocalizedString(@"console.starting");
}

- (void)hideSplash {
    if (self.splashView.hidden) return;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.3;
        self.splashView.animator.alphaValue = 0.0;
    } completionHandler:^{
        self.splashView.hidden = YES;
        [self.splashSpinner stopAnimation:nil];
    }];
}

#pragma mark - Media Hot-Swap

- (void)showMediaMenu:(id)sender {
    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem *cdromHeader = [[NSMenuItem alloc] init];
    cdromHeader.title = AMLocalizedString(@"console.opticalDrive");
    cdromHeader.enabled = NO;
    [menu addItem:cdromHeader];
    [menu addItemWithTitle:AMLocalizedString(@"console.changeCDROM") action:@selector(changeCDROM:) keyEquivalent:@""];
    [menu addItemWithTitle:AMLocalizedString(@"console.ejectCDROM") action:@selector(ejectCDROM:) keyEquivalent:@""];
    NSArray *opticalDrives = [VMStartVirtualMachine physicalOpticalDrives];
    if (opticalDrives.count > 0) {
        [menu addItem:[NSMenuItem separatorItem]];
        for (NSString *drive in opticalDrives) {
            NSMenuItem *item = [menu addItemWithTitle:AMLocalizedStringF(@"console.physicalDrive", drive) action:@selector(usePhysicalOptical:) keyEquivalent:@""];
            item.representedObject = drive;
        }
    }
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *floppyHeader = [[NSMenuItem alloc] init];
    floppyHeader.title = AMLocalizedString(@"console.floppyDrives");
    floppyHeader.enabled = NO;
    [menu addItem:floppyHeader];
    [menu addItemWithTitle:AMLocalizedString(@"console.changeFloppyA") action:@selector(changeFloppyA:) keyEquivalent:@""];
    [menu addItemWithTitle:AMLocalizedString(@"console.ejectFloppyA") action:@selector(ejectFloppyA:) keyEquivalent:@""];
    [menu addItemWithTitle:AMLocalizedString(@"console.changeFloppyB") action:@selector(changeFloppyB:) keyEquivalent:@""];
    [menu addItemWithTitle:AMLocalizedString(@"console.ejectFloppyB") action:@selector(ejectFloppyB:) keyEquivalent:@""];
    NSArray *floppyDrives = [VMStartVirtualMachine physicalFloppyDrives];
    if (floppyDrives.count > 0) {
        [menu addItem:[NSMenuItem separatorItem]];
        for (NSString *drive in floppyDrives) {
            NSMenuItem *item = [menu addItemWithTitle:AMLocalizedStringF(@"console.physicalDrive", drive) action:@selector(usePhysicalFloppy:) keyEquivalent:@""];
            item.representedObject = drive;
        }
    }
    for (NSMenuItem *item in menu.itemArray) {
        if (item.action) item.target = self;
    }
    NSRect btnRect = self.mediaButton.frame;
    NSPoint location = [self.mediaButton.superview convertPoint:NSMakePoint(btnRect.origin.x, btnRect.origin.y + btnRect.size.height) toView:nil];
    NSPoint screenLoc = [self.window convertPointToScreen:location];
    [menu popUpMenuPositioningItem:nil atLocation:screenLoc inView:nil];
}

- (void)changeCDROM:(id)sender {
    [self openMediaPickerForExtensions:@[@"iso", @"img", @"bin", @"raw"] completion:^(NSString *path) {
        [self.qemuProcess sendMonitorCommand:[NSString stringWithFormat:@"change cdrom %@", path] completion:^(NSString *result) {
            [self appendLog:[NSString stringWithFormat:@"[INFO] %@\n", AMLocalizedStringF(@"console.log.cdromChanged", path)]];
            self.virtualMachine.cdromImagePath = path;
        }];
    }];
}

- (void)ejectCDROM:(id)sender {
    [self.qemuProcess sendMonitorCommand:@"eject cdrom" completion:^(NSString *result) {
        [self appendLog:[NSString stringWithFormat:@"[INFO] %@\n", AMLocalizedString(@"console.log.cdromEjected")]];
        self.virtualMachine.cdromImagePath = @"";
    }];
}

- (void)usePhysicalOptical:(id)sender {
    NSString *drive = ((NSMenuItem *)sender).representedObject;
    if (drive.length > 0) {
        [self.qemuProcess sendMonitorCommand:[NSString stringWithFormat:@"change cdrom %@", drive] completion:^(NSString *result) {
            [self appendLog:[NSString stringWithFormat:@"[INFO] %@\n", AMLocalizedStringF(@"console.log.physicalOptical", drive)]];
        }];
    }
}

- (void)changeFloppyA:(id)sender {
    [self openMediaPickerForExtensions:@[@"ima", @"img", @"flp", @"dsk", @"vfd", @"bin", @"raw"] completion:^(NSString *path) {
        [self.qemuProcess sendMonitorCommand:[NSString stringWithFormat:@"change floppy %@", path] completion:^(NSString *result) {
            [self appendLog:[NSString stringWithFormat:@"[INFO] %@\n", AMLocalizedStringF(@"console.log.floppyAChanged", path)]];
            self.virtualMachine.floppyAPath = path;
        }];
    }];
}

- (void)ejectFloppyA:(id)sender {
    [self.qemuProcess sendMonitorCommand:@"eject floppy" completion:^(NSString *result) {
        [self appendLog:[NSString stringWithFormat:@"[INFO] %@\n", AMLocalizedString(@"console.log.floppyAEjected")]];
        self.virtualMachine.floppyAPath = @"";
    }];
}

- (void)changeFloppyB:(id)sender {
    [self openMediaPickerForExtensions:@[@"ima", @"img", @"flp", @"dsk", @"vfd", @"bin", @"raw"] completion:^(NSString *path) {
        [self.qemuProcess sendMonitorCommand:[NSString stringWithFormat:@"change floppy1 %@", path] completion:^(NSString *result) {
            [self appendLog:[NSString stringWithFormat:@"[INFO] %@\n", AMLocalizedStringF(@"console.log.floppyBChanged", path)]];
            self.virtualMachine.floppyBPath = path;
        }];
    }];
}

- (void)ejectFloppyB:(id)sender {
    [self.qemuProcess sendMonitorCommand:@"eject floppy1" completion:^(NSString *result) {
        [self appendLog:[NSString stringWithFormat:@"[INFO] %@\n", AMLocalizedString(@"console.log.floppyBEjected")]];
        self.virtualMachine.floppyBPath = @"";
    }];
}

- (void)usePhysicalFloppy:(id)sender {
    NSString *drive = ((NSMenuItem *)sender).representedObject;
    if (drive.length > 0) {
        [self.qemuProcess sendMonitorCommand:[NSString stringWithFormat:@"change floppy %@", drive] completion:^(NSString *result) {
            [self appendLog:[NSString stringWithFormat:@"[INFO] %@\n", AMLocalizedStringF(@"console.log.physicalFloppy", drive)]];
        }];
    }
}

- (void)openMediaPickerForExtensions:(NSArray<NSString *> *)extensions completion:(void(^)(NSString *path))completion {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.title = AMLocalizedString(@"console.selectMedia");
    if (extensions.count > 0) {
        NSMutableArray *types = [NSMutableArray array];
        for (NSString *ext in extensions) {
            if (@available(macOS 11.0, *)) {
                UTType *type = [UTType typeWithFilenameExtension:ext];
                if (type) [types addObject:type];
            }
        }
        panel.allowedContentTypes = types;
        panel.allowsOtherFileTypes = YES;
    }
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSInteger result) {
        if (result == NSModalResponseOK && panel.URL) {
            completion(panel.URL.path);
        }
    }];
}

- (void)appendLog:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.logView.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:text]];
        [self.logView scrollRangeToVisible:NSMakeRange(self.logView.string.length, 0)];
    });
}

#pragma mark - VMStartQEMUProcessDelegate

- (void)qemuProcessDidStart:(id)sender {
    [self hideSplash];
    [self appendLog:[AMLocalizedString(@"console.started") stringByAppendingString:@"\n"]];
    self.statusBar.stringValue = AMLocalizedString(@"status.running");
    self.startStopButton.title = AMLocalizedString(@"console.stop");
    self.pauseResumeButton.enabled = YES;
    self.screenshotButton.enabled = YES;

    // Connect VNC viewer (delayed to let QEMU start listening)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.vncViewer connectWithHost:@"127.0.0.1" port:kVNCPort];
        [self appendLog:[NSString stringWithFormat:@"[VNC] %@\n", AMLocalizedStringF(@"console.log.vncConnecting", @"127.0.0.1", (long)kVNCPort)]];
    });

    // Connect serial terminal
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.serialTerminal connectWithHost:@"127.0.0.1" port:kSerialPort];
    });

    self.vncViewer.onConnected = ^{
        [self appendLog:[NSString stringWithFormat:@"[VNC] %@\n", AMLocalizedString(@"console.log.vncConnected")]];
        self.statusBar.stringValue = AMLocalizedStringF(@"console.runningResolution",
            (long)self.vncViewer.framebufferWidth, (long)self.vncViewer.framebufferHeight);
    };
    self.vncViewer.onDisconnected = ^{
        [self appendLog:[NSString stringWithFormat:@"[VNC] %@\n", AMLocalizedString(@"console.log.vncDisconnected")]];
    };

    // Start resource monitoring
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        pid_t vmPid = self.qemuProcess ? (pid_t)self.qemuProcess.processIdentifier : 0;
        if (vmPid > 0) {
            [self.resourceMonitor startMonitoringWithProcessID:vmPid];
            [self appendLog:[NSString stringWithFormat:@"[Monitor] %@\n", AMLocalizedStringF(@"console.log.trackingPID", vmPid)]];
        }
    });

    // Auto-snapshot timer
    if (self.virtualMachine.enableAutoSnapshot && self.virtualMachine.autoSnapshotInterval > 0) {
        self.autoSnapshotCounter = 0;
        NSTimeInterval interval = self.virtualMachine.autoSnapshotInterval;
        self.autoSnapshotTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(performAutoSnapshot) userInfo:nil repeats:YES];
        [self appendLog:[NSString stringWithFormat:@"[Snapshot] %@\n", AMLocalizedStringF(@"console.log.autoSnapshotEnabled", interval / 60.0)]];
    }
}

- (void)qemuProcessDidStop:(id)sender exitCode:(NSInteger)code {
    [self appendLog:[AMLocalizedStringF(@"console.stopped", (long)code) stringByAppendingString:@"\n"]];
    self.statusBar.stringValue = AMLocalizedString(@"status.stopped");
    self.startStopButton.title = AMLocalizedString(@"console.start");
    self.pauseResumeButton.enabled = NO;
    self.screenshotButton.enabled = NO;
    [self.autoSnapshotTimer invalidate]; self.autoSnapshotTimer = nil;
}

- (void)qemuProcess:(id)sender didOutputData:(NSData *)data {
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (str) [self appendLog:str];
}

- (void)qemuProcess:(id)sender didOutputError:(NSData *)data {
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (str) [self appendLog:[NSString stringWithFormat:@"[ERR] %@", str]];
}

- (void)qemuProcess:(id)sender didFailWithError:(NSError *)error {
    [self appendLog:[NSString stringWithFormat:@"[ERROR] %@\n", error.localizedDescription]];
}

- (void)windowWillClose:(NSNotification *)notification {
    [self.vncViewer disconnect];
    [self.serialTerminal disconnect];
    [self.resourceMonitor stopMonitoring];
    [self.autoSnapshotTimer invalidate]; self.autoSnapshotTimer = nil;
    if (self.engine.isRunning) [self.engine stop];
}

#pragma mark - VMStartEngineDelegate

- (void)engineDidStart:(id)sender { [self qemuProcessDidStart:sender]; }
- (void)engineDidStop:(id)sender exitCode:(NSInteger)code { [self qemuProcessDidStop:sender exitCode:code]; }
- (void)engine:(id)sender didOutputData:(NSData *)data { [self qemuProcess:sender didOutputData:data]; }
- (void)engine:(id)sender didOutputError:(NSData *)data { [self qemuProcess:sender didOutputError:data]; }
- (void)engine:(id)sender didFailWithError:(NSError *)error { [self qemuProcess:sender didFailWithError:error]; }

#pragma mark - Auto-Snapshot

- (void)performAutoSnapshot {
    if (!self.engine.isRunning) return;
    self.autoSnapshotCounter++;
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *snapName = [NSString stringWithFormat:@"auto_%@_%ld", [fmt stringFromDate:[NSDate date]], (long)self.autoSnapshotCounter];

    // Use QEMU monitor savevm command
    if ([self.engine respondsToSelector:@selector(sendMonitorCommand:completion:)]) {
        [self.engine sendMonitorCommand:[NSString stringWithFormat:@"savevm %@", snapName] completion:^(NSString *result) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (result && ![result containsString:@"Error"]) {
                    // Record in VM model
                    NSMutableArray *snaps = [NSMutableArray arrayWithArray:self.virtualMachine.snapshots ?: @[]];
                    [snaps addObject:@{@"name": snapName, @"date": [fmt stringFromDate:[NSDate date]], @"type": @"auto"}];
                    self.virtualMachine.snapshots = snaps;
                    [self.virtualMachine saveToBundle];
                    [self appendLog:[NSString stringWithFormat:@"[Snapshot] %@\n", AMLocalizedStringF(@"console.log.autoSnapshotSaved", snapName)]];
                } else {
                    [self appendLog:[NSString stringWithFormat:@"[Snapshot] %@\n", AMLocalizedStringF(@"console.log.autoSnapshotFailed", result ?: AMLocalizedString(@"console.unknownError"))]];
                }
            });
        }];
    }
}

@end
