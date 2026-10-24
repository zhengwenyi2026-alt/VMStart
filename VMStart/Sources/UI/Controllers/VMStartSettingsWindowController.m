//
//  VMStartSettingsWindowController.m
//  VMStart
//
//  Copyright (c) 2024 zhengwenyi2026-alt. Licensed under GPLv2.
//

#import "VMStartSettingsWindowController.h"
#import "VMStartLocalization.h"

@interface VMStartSettingsWindowController ()

@property (nonatomic, strong) NSView *contentView;
@property (nonatomic, strong) NSTabView *tabView;

@end

@implementation VMStartSettingsWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 400)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = NSLocalizedString(@"settings.title", @"Settings");
    [window center];
    
    self = [super initWithWindow:window];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.contentView = [[NSView alloc] initWithFrame:self.window.contentView.bounds];
    self.contentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.window.contentView = self.contentView;
    
    // Tab view for settings categories
    self.tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(20, 20, self.contentView.bounds.size.width - 40, self.contentView.bounds.size.height - 40)];
    self.tabView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    
    // General tab
    NSTabViewItem *generalTab = [[NSTabViewItem alloc] initWithIdentifier:@"general"];
    generalTab.label = NSLocalizedString(@"settings.general", @"General");
    generalTab.view = [self createGeneralView];
    
    // Advanced tab
    NSTabViewItem *advancedTab = [[NSTabViewItem alloc] initWithIdentifier:@"advanced"];
    advancedTab.label = NSLocalizedString(@"settings.advanced", @"Advanced");
    advancedTab.view = [self createAdvancedView];
    
    self.tabView.tabViewItems = @[generalTab, advancedTab];
    [self.contentView addSubview:self.tabView];
}

- (NSView *)createGeneralView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    
    CGFloat y = 260;

    // 界面语言（写入 AppleLanguages，重启后生效）
    NSTextField *langLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 100, 24)];
    langLabel.stringValue = AMLocalizedString(@"settings.language");
    langLabel.bezeled = NO;
    langLabel.drawsBackground = NO;
    langLabel.editable = NO;
    [view addSubview:langLabel];

    NSPopUpButton *langPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(126, y - 2, 200, 26) pullsDown:NO];
    NSArray *langs = @[@[AMLocalizedString(@"settings.language.system"), @""],
                       @[@"简体中文", @"zh-Hans"],
                       @[@"English", @"en"]];
    NSString *current = [[[NSUserDefaults standardUserDefaults] persistentDomainForName:[NSBundle mainBundle].bundleIdentifier][@"AppleLanguages"] firstObject] ?: @"";
    for (NSArray *lang in langs) {
        [langPopup addItemWithTitle:lang[0]];
        langPopup.lastItem.representedObject = lang[1];
        if ([current isEqualToString:lang[1]]) [langPopup selectItem:langPopup.lastItem];
    }
    langPopup.target = self;
    langPopup.action = @selector(languageChanged:);
    [view addSubview:langPopup];

    y -= 40;

    // QEMU path setting
    NSTextField *qemuLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 100, 24)];
    qemuLabel.stringValue = NSLocalizedString(@"settings.qemuPath", @"QEMU Path:");
    qemuLabel.bezeled = NO;
    qemuLabel.drawsBackground = NO;
    qemuLabel.editable = NO;
    [view addSubview:qemuLabel];
    
    NSTextField *qemuPath = [[NSTextField alloc] initWithFrame:NSMakeRect(130, y, 250, 24)];
    qemuPath.stringValue = @"/opt/homebrew/bin";
    qemuPath.bezeled = YES;
    qemuPath.drawsBackground = YES;
    [view addSubview:qemuPath];
    
    y -= 40;
    
    // VM directory setting
    NSTextField *vmDirLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 100, 24)];
    vmDirLabel.stringValue = NSLocalizedString(@"settings.vmDirectory", @"VM Directory:");
    vmDirLabel.bezeled = NO;
    vmDirLabel.drawsBackground = NO;
    vmDirLabel.editable = NO;
    [view addSubview:vmDirLabel];
    
    NSTextField *vmDirPath = [[NSTextField alloc] initWithFrame:NSMakeRect(130, y, 250, 24)];
    vmDirPath.stringValue = @"~/Library/Application Support/VMStart/VirtualMachines";
    vmDirPath.bezeled = YES;
    vmDirPath.drawsBackground = YES;
    [view addSubview:vmDirPath];
    
    y -= 40;
    
    // Auto-start checkbox
    NSButton *autoStart = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 300, 24)];
    autoStart.title = NSLocalizedString(@"settings.autoStart", @"Auto-start VMs on login");
    autoStart.bezelStyle = NSBezelStyleInline;
    autoStart.state = NSControlStateValueOff;
    [view addSubview:autoStart];
    
    return view;
}

- (void)languageChanged:(NSPopUpButton *)sender {
    NSString *code = sender.selectedItem.representedObject;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (code.length > 0) {
        [defaults setObject:@[code] forKey:@"AppleLanguages"];
    } else {
        [defaults removeObjectForKey:@"AppleLanguages"];
    }
    [defaults synchronize];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = AMLocalizedString(@"settings.language.restartTitle");
    alert.informativeText = AMLocalizedString(@"settings.language.restartMessage");
    [alert addButtonWithTitle:AMLocalizedString(@"settings.language.restartNow")];
    [alert addButtonWithTitle:AMLocalizedString(@"settings.language.later")];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        NSWorkspaceOpenConfiguration *config = [NSWorkspaceOpenConfiguration configuration];
        config.createsNewApplicationInstance = YES;
        [[NSWorkspace sharedWorkspace] openApplicationAtURL:[NSBundle mainBundle].bundleURL
                                              configuration:config
                                          completionHandler:^(NSRunningApplication *app, NSError *error) {
            if (!error) dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
        }];
    }];
}

- (NSView *)createAdvancedView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    
    CGFloat y = 260;
    
    // Enable debug mode
    NSButton *debugMode = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 200, 24)];
    debugMode.title = NSLocalizedString(@"settings.debugMode", @"Enable debug mode");
    debugMode.bezelStyle = NSBezelStyleInline;
    debugMode.state = NSControlStateValueOff;
    [view addSubview:debugMode];
    
    y -= 40;
    
    // Enable experimental features
    NSButton *experimental = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 200, 24)];
    experimental.title = NSLocalizedString(@"settings.experimental", @"Enable experimental features");
    experimental.bezelStyle = NSBezelStyleInline;
    experimental.state = NSControlStateValueOff;
    [view addSubview:experimental];
    
    return view;
}

@end
