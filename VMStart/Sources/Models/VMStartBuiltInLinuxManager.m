//
//  VMStartBuiltInLinuxManager.m
//  VMStart
//
//  内置 Linux 系统管理器
//  管理预安装的 Ubuntu Server 和 Desktop 的启动

#import "VMStartBuiltInLinuxManager.h"

@interface VMStartBuiltInLinuxManager ()
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSTask *> *runningProcesses;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *imagePaths;
@end

@implementation VMStartBuiltInLinuxManager

+ (instancetype)sharedManager {
    static VMStartBuiltInLinuxManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VMStartBuiltInLinuxManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _runningProcesses = [NSMutableDictionary dictionary];
        _imagePaths = [NSMutableDictionary dictionary];
        [self scanForImages];
    }
    return self;
}

#pragma mark - Image Discovery

- (void)scanForImages {
    NSBundle *mainBundle = [NSBundle mainBundle];
    
    // Server 镜像
    NSString *serverDir = [mainBundle pathForResource:@"BuiltInImages/UbuntuServer" ofType:nil];
    if (!serverDir) {
        // 尝试从资源目录查找
        serverDir = [[mainBundle resourcePath] stringByAppendingPathComponent:@"BuiltInImages/UbuntuServer"];
    }
    if (serverDir) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *files = [fm contentsOfDirectoryAtPath:serverDir error:nil];
        for (NSString *file in files) {
            if ([file hasSuffix:@".qcow2"]) {
                self.imagePaths[@(VMStartBuiltInLinuxTypeServer)] = [serverDir stringByAppendingPathComponent:file];
                break;
            }
        }
    }
    
    // Desktop 镜像
    NSString *desktopDir = [mainBundle pathForResource:@"BuiltInImages/UbuntuDesktop" ofType:nil];
    if (!desktopDir) {
        desktopDir = [[mainBundle resourcePath] stringByAppendingPathComponent:@"BuiltInImages/UbuntuDesktop"];
    }
    if (desktopDir) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *files = [fm contentsOfDirectoryAtPath:desktopDir error:nil];
        for (NSString *file in files) {
            if ([file hasSuffix:@".qcow2"]) {
                self.imagePaths[@(VMStartBuiltInLinuxTypeDesktop)] = [desktopDir stringByAppendingPathComponent:file];
                break;
            }
        }
    }
}

#pragma mark - Public Methods

- (BOOL)isImageReadyForType:(VMStartBuiltInLinuxType)type {
    NSString *path = self.imagePaths[@(type)];
    if (!path) return NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

- (nullable NSString *)imagePathForType:(VMStartBuiltInLinuxType)type {
    return self.imagePaths[@(type)];
}

- (nullable NSDictionary *)metadataForType:(VMStartBuiltInLinuxType)type {
    NSString *basePath = nil;
    NSBundle *mainBundle = [NSBundle mainBundle];
    
    if (type == VMStartBuiltInLinuxTypeServer) {
        basePath = [[mainBundle resourcePath] stringByAppendingPathComponent:@"BuiltInImages/UbuntuServer"];
    } else {
        basePath = [[mainBundle resourcePath] stringByAppendingPathComponent:@"BuiltInImages/UbuntuDesktop"];
    }
    
    if (!basePath) return nil;
    
    NSString *metadataPath = [basePath stringByAppendingPathComponent:@"metadata.json"];
    NSData *data = [NSData dataWithContentsOfFile:metadataPath];
    if (!data) return nil;
    
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

- (void)launchBuiltInLinux:(VMStartBuiltInLinuxType)type completion:(void(^)(BOOL success, NSError * _Nullable error))completion {
    
    if ([self isRunning:type]) {
        NSError *error = [NSError errorWithDomain:@"VMStartBuiltInLinux"
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"该 Linux 系统已在运行"}];
        if (completion) completion(NO, error);
        return;
    }
    
    NSString *imagePath = [self imagePathForType:type];
    if (!imagePath || ![[NSFileManager defaultManager] fileExistsAtPath:imagePath]) {
        NSError *error = [NSError errorWithDomain:@"VMStartBuiltInLinux"
                                             code:2
                                         userInfo:@{NSLocalizedDescriptionKey: @"内置 Linux 镜像未找到，请先运行下载脚本"}];
        if (completion) completion(NO, error);
        return;
    }
    
    NSDictionary *config = [self recommendedConfigForType:type];
    NSDictionary *metadata = [self metadataForType:type];
    
    // 构建 QEMU 命令
    NSString *qemuBinary = @"qemu-system-x86_64";
    NSString *memoryMB = config[@"memory"] ?: @"2048";
    NSString *cpus = config[@"cpus"] ?: @"2";
    NSString *display = metadata[@"display"] ?: @"cocoa";
    
    NSMutableArray *args = [NSMutableArray array];
    [args addObject:@"-m"];
    [args addObject:memoryMB];
    [args addObject:@"-smp"];
    [args addObject:cpus];
    [args addObject:@"-drive"];
    [args addObject:[NSString stringWithFormat:@"file=%@,format=qcow2", imagePath]];
    [args addObject:@"-display"];
    [args addObject:display];
    [args addObject:@"-enable-hvf"]; // macOS 硬件加速
    [args addObject:@"-netdev"];
    [args addObject:@"user,id=net0"];
    [args addObject:@"-device"];
    [args addObject:@"virtio-net-pci,netdev=net0"];
    
    // Desktop 模式需要更多配置
    if (type == VMStartBuiltInLinuxTypeDesktop) {
        [args addObject:@"-device"];
        [args addObject:@"virtio-vga"];
        [args addObject:@"-device"];
        [args addObject:@"usb-ehci,id=usb"];
        [args addObject:@"-device"];
        [args addObject:@"usb-kbd"];
        [args addObject:@"-device"];
        [args addObject:@"usb-mouse"];
    }
    
    // 启动 QEMU 进程
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:[self findQEMUBinary:qemuBinary]];
    task.arguments = args;
    
    // 设置标准输出管道（用于日志）
    NSPipe *outputPipe = [NSPipe pipe];
    task.standardOutput = outputPipe;
    task.standardError = outputPipe;
    
    self.runningProcesses[@(type)] = task;
    
    @try {
        [task launch];
        if (completion) completion(YES, nil);
    } @catch (NSException *exception) {
        NSError *error = [NSError errorWithDomain:@"VMStartBuiltInLinux"
                                             code:3
                                         userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"启动失败"}];
        [self.runningProcesses removeObjectForKey:@(type)];
        if (completion) completion(NO, error);
    }
}

- (void)stopBuiltInLinux:(VMStartBuiltInLinuxType)type {
    NSTask *task = self.runningProcesses[@(type)];
    if (task && task.isRunning) {
        [task terminate];
        [self.runningProcesses removeObjectForKey:@(type)];
    }
}

- (BOOL)isRunning:(VMStartBuiltInLinuxType)type {
    NSTask *task = self.runningProcesses[@(type)];
    return task != nil && task.isRunning;
}

- (NSDictionary *)recommendedConfigForType:(VMStartBuiltInLinuxType)type {
    if (type == VMStartBuiltInLinuxTypeServer) {
        return @{
            @"memory": @"2048",
            @"cpus": @"2",
            @"disk": @"20GB",
            @"network": @"user",
            @"display": @"cocoa"
        };
    } else {
        return @{
            @"memory": @"4096",
            @"cpus": @"2",
            @"disk": @"30GB",
            @"network": @"user",
            @"display": @"cocoa",
            @"usb": @"ehci",
            @"audio": @"coreaudio"
        };
    }
}

#pragma mark - Private Methods

- (NSString *)findQEMUBinary:(NSString *)name {
    // 搜索路径
    NSArray *searchPaths = @[
        @"/usr/local/bin",
        @"/opt/homebrew/bin",
        [[NSBundle mainBundle] resourcePath],
        @"/usr/bin"
    ];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in searchPaths) {
        NSString *fullPath = [path stringByAppendingPathComponent:name];
        if ([fm isExecutableFileAtPath:fullPath]) {
            return fullPath;
        }
    }
    
    return @"/usr/local/bin/qemu-system-x86_64"; // 默认回退
}

@end
