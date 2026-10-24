//
//  VMStartDiskManagerController.m
//  VMStart
//
//  Copyright (c) 2024 zhengwenyi2026-alt. Licensed under GPLv2.
//

#import "VMStartDiskManagerController.h"
#import "VMStartLocalization.h"

@interface VMStartDiskManagerController ()
@property (nonatomic, copy) NSString *diskPath;
@property (nonatomic, strong) NSTextField *infoLabel;
@property (nonatomic, strong) NSTextField *sizeField;
@property (nonatomic, strong) NSPopUpButton *unitPopup;
@property (nonatomic, strong) NSPopUpButton *formatPopup;
@property (nonatomic, strong) NSTextField *statusLabel;
@end

@implementation VMStartDiskManagerController

- (instancetype)initWithDiskPath:(NSString *)diskPath {
    NSRect frame = NSMakeRect(0, 0, 500, 380);
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame styleMask:style backing:NSBackingStoreBuffered defer:NO];
    window.title = AMLocalizedString(@"diskManager.title");
    [window center];
    self = [super initWithWindow:window];
    if (self) {
        _diskPath = [diskPath copy];
        [self setupUI];
        [self loadDiskInfo];
    }
    return self;
}

- (void)setupUI {
    NSView *content = self.window.contentView;
    CGFloat y = content.bounds.size.height - 40;

    // Disk path
    NSTextField *pathLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 60, 20)];
    pathLabel.stringValue = AMLocalizedString(@"disk.diskLabel");
    pathLabel.font = [NSFont systemFontOfSize:12];
    pathLabel.bezeled = NO; pathLabel.drawsBackground = NO; pathLabel.editable = NO;
    [content addSubview:pathLabel];

    NSTextField *pathField = [[NSTextField alloc] initWithFrame:NSMakeRect(80, y, 400, 20)];
    pathField.stringValue = self.diskPath ?: AMLocalizedString(@"detail.noDisk");
    pathField.font = [NSFont systemFontOfSize:11];
    pathField.textColor = [NSColor secondaryLabelColor];
    pathField.bezeled = NO; pathField.drawsBackground = NO; pathField.editable = NO;
    pathField.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [content addSubview:pathField];
    y -= 40;

    // Info section
    self.infoLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 460, 60)];
    self.infoLabel.font = [NSFont systemFontOfSize:12];
    self.infoLabel.bezeled = NO; self.infoLabel.drawsBackground = NO; self.infoLabel.editable = NO;
    self.infoLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [content addSubview:self.infoLabel];
    y -= 80;

    // Resize section
    NSTextField *resizeTitle = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 200, 20)];
    resizeTitle.stringValue = AMLocalizedString(@"disk.resizeTitle");
    resizeTitle.font = [NSFont boldSystemFontOfSize:13];
    resizeTitle.bezeled = NO; resizeTitle.drawsBackground = NO; resizeTitle.editable = NO;
    [content addSubview:resizeTitle];
    y -= 30;

    NSTextField *sizeLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 80, 22)];
    sizeLabel.stringValue = AMLocalizedString(@"disk.newSize");
    sizeLabel.font = [NSFont systemFontOfSize:12];
    sizeLabel.alignment = NSTextAlignmentRight;
    sizeLabel.bezeled = NO; sizeLabel.drawsBackground = NO; sizeLabel.editable = NO;
    [content addSubview:sizeLabel];

    self.sizeField = [[NSTextField alloc] initWithFrame:NSMakeRect(110, y, 100, 24)];
    self.sizeField.bezelStyle = NSTextFieldSquareBezel;
    self.sizeField.placeholderString = AMLocalizedString(@"disk.sizePlaceholder");
    [content addSubview:self.sizeField];

    self.unitPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(220, y, 80, 26)];
    [self.unitPopup addItemsWithTitles:@[@"GB", @"MB", @"TB"]];
    [content addSubview:self.unitPopup];

    NSButton *resizeBtn = [NSButton buttonWithTitle:AMLocalizedString(@"diskManager.resize") target:self action:@selector(resizeDisk:)];
    resizeBtn.frame = NSMakeRect(310, y, 80, 26);
    resizeBtn.bezelStyle = NSBezelStyleRounded;
    [content addSubview:resizeBtn];
    y -= 50;

    // Convert section
    NSTextField *convertTitle = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 200, 20)];
    convertTitle.stringValue = AMLocalizedString(@"disk.convertTitle");
    convertTitle.font = [NSFont boldSystemFontOfSize:13];
    convertTitle.bezeled = NO; convertTitle.drawsBackground = NO; convertTitle.editable = NO;
    [content addSubview:convertTitle];
    y -= 30;

    NSTextField *fmtLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 80, 22)];
    fmtLabel.stringValue = AMLocalizedString(@"disk.format");
    fmtLabel.font = [NSFont systemFontOfSize:12];
    fmtLabel.alignment = NSTextAlignmentRight;
    fmtLabel.bezeled = NO; fmtLabel.drawsBackground = NO; fmtLabel.editable = NO;
    [content addSubview:fmtLabel];

    self.formatPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(110, y, 120, 26)];
    [self.formatPopup addItemsWithTitles:@[@"qcow2", @"vmdk", @"vdi", @"raw", @"vhd"]];
    [content addSubview:self.formatPopup];

    NSButton *convertBtn = [NSButton buttonWithTitle:AMLocalizedString(@"diskManager.convert") target:self action:@selector(convertDisk:)];
    convertBtn.frame = NSMakeRect(240, y, 80, 26);
    convertBtn.bezelStyle = NSBezelStyleRounded;
    [content addSubview:convertBtn];

    NSButton *compressBtn = [NSButton buttonWithTitle:AMLocalizedString(@"diskManager.compress") target:self action:@selector(compressDisk:)];
    compressBtn.frame = NSMakeRect(330, y, 90, 26);
    compressBtn.bezelStyle = NSBezelStyleRounded;
    [content addSubview:compressBtn];
    y -= 50;

    // Status
    self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 20, 460, 20)];
    self.statusLabel.font = [NSFont systemFontOfSize:11];
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
    self.statusLabel.bezeled = NO; self.statusLabel.drawsBackground = NO; self.statusLabel.editable = NO;
    [content addSubview:self.statusLabel];
}

- (void)loadDiskInfo {
    if (!self.diskPath) {
        self.infoLabel.stringValue = AMLocalizedString(@"disk.noDiskSelected");
        return;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:self.diskPath error:nil];
    if (attrs) {
        NSNumber *size = attrs[NSFileSize];
        self.infoLabel.stringValue = AMLocalizedStringF(@"disk.info", size);
    } else {
        self.infoLabel.stringValue = AMLocalizedString(@"disk.cannotRead");
    }
}

- (NSString *)qemuImgPath {
    NSString *path = @"/opt/homebrew/bin/qemu-img";
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return path;
    path = @"/usr/local/bin/qemu-img";
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return path;
    return nil;
}

- (void)resizeDisk:(id)sender {
    NSString *qemuImg = [self qemuImgPath];
    if (!qemuImg) { [self showStatus:AMLocalizedString(@"disk.qemuImgNotFound")]; return; }
    NSInteger sizeVal = self.sizeField.integerValue;
    if (sizeVal <= 0) { [self showStatus:AMLocalizedString(@"disk.invalidSize")]; return; }
    NSString *unit = self.unitPopup.titleOfSelectedItem ?: @"GB";
    NSString *sizeStr = [NSString stringWithFormat:@"%ld%@", (long)sizeVal, unit];

    self.statusLabel.stringValue = AMLocalizedString(@"disk.resizing");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:qemuImg];
        task.arguments = @[@"resize", @"-f", @"qcow2", self.diskPath, sizeStr];
        [task launch]; [task waitUntilExit];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (task.terminationStatus == 0) {
                [self showStatus:AMLocalizedString(@"disk.resizeSuccess")];
                [self loadDiskInfo];
            } else {
                [self showStatus:AMLocalizedString(@"disk.resizeFailed")];
            }
        });
    });
}

- (void)convertDisk:(id)sender {
    NSString *qemuImg = [self qemuImgPath];
    if (!qemuImg) { [self showStatus:AMLocalizedString(@"disk.qemuImgNotFound")]; return; }
    NSString *format = self.formatPopup.titleOfSelectedItem ?: @"qcow2";
    NSString *outputPath = [self.diskPath stringByDeletingPathExtension];
    outputPath = [outputPath stringByAppendingPathExtension:format];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = AMLocalizedString(@"disk.convertAlertTitle");
    alert.informativeText = AMLocalizedStringF(@"disk.convertAlertMessage", format, outputPath);
    [alert addButtonWithTitle:AMLocalizedString(@"diskManager.convert")]; [alert addButtonWithTitle:AMLocalizedString(@"config.cancel")];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    self.statusLabel.stringValue = AMLocalizedString(@"disk.converting");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:qemuImg];
        task.arguments = @[@"convert", @"-f", @"qcow2", @"-O", format, self.diskPath, outputPath];
        [task launch]; [task waitUntilExit];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showStatus:task.terminationStatus == 0 ? AMLocalizedString(@"disk.convertSuccess") : AMLocalizedString(@"disk.convertFailed")];
        });
    });
}

- (void)compressDisk:(id)sender {
    NSString *qemuImg = [self qemuImgPath];
    if (!qemuImg) { [self showStatus:AMLocalizedString(@"disk.qemuImgNotFound")]; return; }
    NSString *outputPath = [self.diskPath stringByDeletingPathExtension];
    outputPath = [outputPath stringByAppendingString:@"_compressed.qcow2"];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = AMLocalizedString(@"disk.compressAlertTitle");
    alert.informativeText = AMLocalizedStringF(@"disk.compressAlertMessage", outputPath);
    [alert addButtonWithTitle:AMLocalizedString(@"diskManager.compress")]; [alert addButtonWithTitle:AMLocalizedString(@"config.cancel")];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    self.statusLabel.stringValue = AMLocalizedString(@"disk.compressing");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:qemuImg];
        task.arguments = @[@"convert", @"-c", @"-f", @"qcow2", @"-O", @"qcow2", self.diskPath, outputPath];
        [task launch]; [task waitUntilExit];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showStatus:task.terminationStatus == 0 ? AMLocalizedString(@"disk.compressSuccess") : AMLocalizedString(@"disk.compressFailed")];
        });
    });
}

- (void)showStatus:(NSString *)msg {
    self.statusLabel.stringValue = msg;
}

@end
