//
//  VMStartBuiltInLinuxManager.h
//  VMStart
//
//  内置 Linux 系统管理器
//  管理预安装的 Ubuntu Server 和 Desktop 的启动

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, VMStartBuiltInLinuxType) {
    VMStartBuiltInLinuxTypeServer,
    VMStartBuiltInLinuxTypeDesktop
};

@interface VMStartBuiltInLinuxManager : NSObject

+ (instancetype)sharedManager;

/// 检查内置 Linux 镜像是否已就绪
- (BOOL)isImageReadyForType:(VMStartBuiltInLinuxType)type;

/// 获取镜像路径
- (nullable NSString *)imagePathForType:(VMStartBuiltInLinuxType)type;

/// 获取镜像元数据
- (nullable NSDictionary *)metadataForType:(VMStartBuiltInLinuxType)type;

/// 启动内置 Linux
- (void)launchBuiltInLinux:(VMStartBuiltInLinuxType)type completion:(void(^)(BOOL success, NSError * _Nullable error))completion;

/// 停止内置 Linux
- (void)stopBuiltInLinux:(VMStartBuiltInLinuxType)type;

/// 检查内置 Linux 是否正在运行
- (BOOL)isRunning:(VMStartBuiltInLinuxType)type;

/// 获取推荐配置
- (NSDictionary *)recommendedConfigForType:(VMStartBuiltInLinuxType)type;

@end

NS_ASSUME_NONNULL_END
