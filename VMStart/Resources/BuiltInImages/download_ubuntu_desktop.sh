#!/bin/bash
# VMStart - Ubuntu Desktop 内置镜像下载与商标去除脚本
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/UbuntuDesktop"
TEMP_DIR="/tmp/vmstart_ubuntu_desktop_build"
UBUNTU_VERSION="24.04"
IMAGE_NAME="ubuntu-${UBUNTU_VERSION}-desktop-cloudimg-amd64.img"
OUTPUT_IMAGE="vmstart-ubuntu-desktop-${UBUNTU_VERSION}.qcow2"

echo "=== VMStart Ubuntu Desktop 镜像构建工具 ==="
echo ""

# 检查依赖
echo "[1/5] 检查依赖..."
for cmd in wget qemu-img; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "  缺少: $cmd - 请安装: brew install $cmd"
        exit 1
    fi
    echo "  OK: $cmd"
done

# 下载基础镜像
echo "[2/5] 下载 Ubuntu Desktop ${UBUNTU_VERSION}..."
mkdir -p "$TEMP_DIR" "$OUTPUT_DIR"

if [ -f "$OUTPUT_DIR/$OUTPUT_IMAGE" ]; then
    echo "  镜像已存在，跳过"
else
    wget -c "https://cloud-images.ubuntu.com/releases/${UBUNTU_VERSION}/release/$IMAGE_NAME" \
        -O "$TEMP_DIR/$IMAGE_NAME" || {
        echo "  下载失败，尝试备用源..."
        wget -c "https://cloud-images.ubuntu.com/jammy/current/$IMAGE_NAME" \
            -O "$TEMP_DIR/$IMAGE_NAME" || {
            echo "  下载失败"
            exit 1
        }
    }
    echo "  下载完成"
fi

# 去除 Ubuntu 商标
echo "[3/5] 去除 Ubuntu 商标..."
qemu-img convert -f qcow2 -O qcow2 "$TEMP_DIR/$IMAGE_NAME" "$TEMP_DIR/$OUTPUT_IMAGE"

# 调用商标去除脚本
if [ -f "$SCRIPT_DIR/remove_ubuntu_branding.sh" ]; then
    echo "  运行商标去除脚本..."
    chmod +x "$SCRIPT_DIR/remove_ubuntu_branding.sh"
    bash "$SCRIPT_DIR/remove_ubuntu_branding.sh" "$TEMP_DIR/$OUTPUT_IMAGE" || echo "  警告: 商标去除失败，请手动运行 remove_ubuntu_branding.sh"
else
    echo "  警告: remove_ubuntu_branding.sh 未找到"
fi

# 安装到资源目录
echo "[4/5] 安装镜像..."
mv "$TEMP_DIR/$OUTPUT_IMAGE" "$OUTPUT_DIR/$OUTPUT_IMAGE"

# 创建元数据
echo "[5/5] 创建元数据..."
cat > "$OUTPUT_DIR/metadata.json" << META_EOF
{
    "name": "VMStart Linux Desktop",
    "version": "${UBUNTU_VERSION}",
    "type": "desktop",
    "format": "qcow2",
    "architecture": "x86_64",
    "description": "Pre-installed Linux desktop with GUI, Ubuntu trademarks removed",
    "recommended_memory": "4096",
    "recommended_memory_unit": "MB",
    "recommended_cpus": 2,
    "recommended_disk": "30GB",
    "engine": "qemu-system-x86_64",
    "display": "gtk"
}
META_EOF

# 清理
rm -rf "$TEMP_DIR"
echo ""
echo "=== Ubuntu Desktop 镜像构建完成 ==="
echo "输出: $OUTPUT_DIR/$OUTPUT_IMAGE"
