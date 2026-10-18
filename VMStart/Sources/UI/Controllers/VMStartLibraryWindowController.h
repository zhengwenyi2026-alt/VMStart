//
//  VMStartLibraryWindowController.h
//  VMStart
//
//  Copyright (c) 2024 zhengwenyi2026-alt. Licensed under GPLv2.
//

#import <Cocoa/Cocoa.h>
#import "VMStartVirtualMachine.h"

NS_ASSUME_NONNULL_BEGIN

@interface VMStartLibraryWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) NSMutableArray<VMStartVirtualMachine *> *virtualMachines;
@property (nonatomic, strong, nullable) NSString *vmDirectory;

- (void)refreshVMList;
- (void)addVM:(nullable id)sender;
- (void)removeVM:(nullable id)sender;
- (void)editVM:(nullable id)sender;
- (void)startVM:(nullable id)sender;

// 日志与打印
- (void)showLogPanel;
- (void)printLogs;
- (void)appendLog:(NSString *)logEntry;
- (void)checkPrinterAvailability;

@end

NS_ASSUME_NONNULL_END
