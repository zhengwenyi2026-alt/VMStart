#!/bin/bash
# VMStart - Chromium 浏览器集成下载脚本
# 下载 Chromium 用于内置镜像下载浏览器
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/Chromium"
TEMP_DIR="/tmp/vmstart_chromium_download"

echo "=== VMStart Chromium 集成下载工具 ==="
echo ""

# 检测系统架构
ARCH=$(uname -m)
OS=$(uname -s)

echo "[1/4] 系统检测: $OS $ARCH"

# 确定下载 URL
if [ "$OS" = "Darwin" ]; then
    if [ "$ARCH" = "arm64" ]; then
        CHROMIUM_URL="https://download-chromium.appspot.com/dl/Mac_Arm?type=snapshots"
        PLATFORM="mac-arm64"
    else
        CHROMIUM_URL="https://download-chromium.appspot.com/dl/Mac?type=snapshots"
        PLATFORM="mac-x64"
    fi
elif [ "$OS" = "Linux" ]; then
    CHROMIUM_URL="https://download-chromium.appspot.com/dl/Linux_x64?type=snapshots"
    PLATFORM="linux-x64"
else
    echo "不支持的系统: $OS"
    exit 1
fi

echo "[2/4] 平台: $PLATFORM"
echo "  下载地址: $CHROMIUM_URL"

# 下载 Chromium
echo "[3/4] 下载 Chromium..."
mkdir -p "$TEMP_DIR" "$OUTPUT_DIR"

if [ -f "$OUTPUT_DIR/Chromium.app/Contents/MacOS/Chromium" ] || [ -f "$OUTPUT_DIR/chromium" ]; then
    echo "  Chromium 已存在，跳过下载"
else
    # 尝试使用 brew 安装
    if command -v brew &> /dev/null; then
        echo "  尝试通过 Homebrew 安装 Chromium..."
        brew install --cask chromium 2>/dev/null || {
            echo "  Homebrew 安装失败，尝试手动下载..."
            wget -c "$CHROMIUM_URL" -O "$TEMP_DIR/chromium.zip" || {
                echo "  下载失败"
                exit 1
            }
        }
    else
        wget -c "$CHROMIUM_URL" -O "$TEMP_DIR/chromium.zip" || {
            echo "  下载失败"
            exit 1
        }
    fi
    echo "  下载完成"
fi

# 安装到资源目录
echo "[4/4] 安装 Chromium..."
if [ -d "/Applications/Chromium.app" ]; then
    cp -R "/Applications/Chromium.app" "$OUTPUT_DIR/Chromium.app"
    echo "  从 /Applications 复制"
elif [ -f "$TEMP_DIR/chromium.zip" ]; then
    unzip -o "$TEMP_DIR/chromium.zip" -d "$OUTPUT_DIR/"
    echo "  从压缩包解压"
fi

# 创建元数据
cat > "$OUTPUT_DIR/metadata.json" << META_EOF
{
    "name": "Chromium",
    "type": "browser",
    "description": "内置浏览器，用于镜像下载和网页浏览",
    "platform": "${PLATFORM}",
    "integration": "embedded",
    "features": [
        "web_browsing",
        "iso_download",
        "search",
        "bookmark_manager"
    ]
}
META_EOF

# 清理
rm -rf "$TEMP_DIR"
echo ""
echo "=== Chromium 集成完成 ==="
echo "路径: $OUTPUT_DIR/Chromium.app"
