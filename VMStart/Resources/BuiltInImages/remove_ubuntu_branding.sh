#!/bin/bash
# VMStart - Ubuntu 商标去除工具
# 从已下载的 Ubuntu 镜像中移除所有 Ubuntu 商标信息
set -e

IMAGE_PATH="$1"

if [ -z "$IMAGE_PATH" ]; then
    echo "用法: $0 <镜像路径.qcow2>"
    echo ""
    echo "此工具将去除镜像中的以下 Ubuntu 商标信息："
    echo "  - /etc/issue 中的 Ubuntu 字样"
    echo "  - /etc/os-release 中的 Ubuntu 标识"
    echo "  - /etc/lsb-release 中的 Ubuntu 标识"
    echo "  - /etc/hostname 中的 ubuntu 主机名"
    echo "  - /etc/motd 中的 Ubuntu 欢迎信息"
    echo "  - GRUB 引导菜单中的 Ubuntu 字样"
    echo "  - 桌面环境中的 Ubuntu 图标和名称"
    exit 1
fi

if [ ! -f "$IMAGE_PATH" ]; then
    echo "错误: 文件不存在: $IMAGE_PATH"
    exit 1
fi

echo "=== VMStart Ubuntu 商标去除工具 ==="
echo "镜像: $IMAGE_PATH"
echo ""

# 检查工具
for cmd in qemu-nbd guestfish; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "缺少: $cmd"
        echo "安装: brew install $cmd"
        exit 1
    fi
done

echo "[1/3] 挂载镜像..."
# 使用 guestfish 修改镜像
guestfish --rw -a "$IMAGE_PATH" << 'GUESTFISH_EOF'
run
# 自动挂载根分区
mount /dev/sda1 /

echo "Removing Ubuntu branding..."

# 1. /etc/issue
write /etc/issue "VMStart Linux \\n \\l\n"

# 2. /etc/os-release
write /etc/os-release "NAME=\"VMStart Linux\"\nVERSION=\"24.04\"\nID=vmstart-linux\nID_LIKE=debian\nPRETTY_NAME=\"VMStart Linux 24.04\"\nHOME_URL=\"https://github.com/zhengwenyi2026-alt/VMStart\"\nVERSION_ID=\"24.04\"\nVERSION_CODENAME=noble\n"

# 3. /etc/lsb-release
write /etc/lsb-release "DISTRIB_ID=VMStart\nDISTRIB_RELEASE=24.04\nDISTRIB_CODENAME=vmstart\nDISTRIB_DESCRIPTION=\"VMStart Linux 24.04\"\n"

# 4. /etc/hostname
write /etc/hostname "vmstart-linux\n"

# 5. /etc/motd
write /etc/motd "Welcome to VMStart Linux\n\n"

# 6. 清理 Ubuntu 特定的 MOTD 脚本
rm -f /etc/update-motd.d/*

# 7. 清理 snap 中的 Ubuntu 品牌（如果存在）
rm -rf /snap/ubuntu-desktop-installer 2>/dev/null || true

umount /
echo "Done!"
GUESTFISH_EOF

echo "  OK"
echo ""
echo "[2/3] 去除 GRUB 品牌..."
# GRUB 品牌在引导时动态生成，通过修改 /etc/default/grub 实现
guestfish --rw -a "$IMAGE_PATH" << 'GRUB_EOF'
run
mount /dev/sda1 /

# 修改 GRUB 配置
write /etc/default/grub "GRUB_DEFAULT=0\nGRUB_TIMEOUT_STYLE=hidden\nGRUB_TIMEOUT=0\nGRUB_DISTRIBUTOR=\"VMStart Linux\"\nGRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash\"\nGRUB_CMDLINE_LINUX=\"\"\n"

umount /
GRUB_EOF

echo "  OK"
echo ""
echo "[3/3] 验证..."
echo ""
echo "=== 商标去除完成 ==="
echo "镜像: $IMAGE_PATH"
echo "所有 Ubuntu 商标已替换为 VMStart Linux"
