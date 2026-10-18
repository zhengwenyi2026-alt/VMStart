#!/bin/bash
# VMStart - 全架构构建脚本
# 用法: ./build_all.sh [arch]
# arch: arm64 | x86_64 | win-x64 | win-arm64 | all
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${VERSION:-1.0.0}"
TARGET="${1:-all}"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[VMStart Build]${NC} $1"; }
ok()  { echo -e "${GREEN}[OK]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; }

build_macos() {
    local ARCH="$1"
    local RUNNER="$2"
    local OUTPUT_DIR="$SCRIPT_DIR/dmg"
    
    log "构建 macOS DMG ($ARCH)..."
    
    # 生成 Xcode 项目
    xcodegen generate --spec project.yml
    
    # 构建
    xcodebuild -project VMStart.xcodeproj \
        -scheme VMStart \
        -configuration Release \
        -derivedDataPath "build/DerivedData-${ARCH}" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        ONLY_ACTIVE_ARCH=NO \
        ARCHS="${ARCH}" \
        clean build
    
    # 打包 DMG
    mkdir -p "$OUTPUT_DIR/${ARCH}"
    APP_PATH=$(find "build/DerivedData-${ARCH}/Build/Products/Release" -name "VMStart.app" -maxdepth 1 | head -1)
    
    if [ -z "$APP_PATH" ]; then
        err "未找到构建产物"
        return 1
    fi
    
    DMG_TEMP=$(mktemp -d)
    cp -R "$APP_PATH" "$DMG_TEMP/"
    ln -s /Applications "$DMG_TEMP/Applications"
    
    hdiutil create -volname "VMStart" \
        -srcfolder "$DMG_TEMP" \
        -ov -format UDZO \
        "$OUTPUT_DIR/${ARCH}/VMStart-${VERSION}-${ARCH}.dmg"
    
    rm -rf "$DMG_TEMP"
    ok "DMG 已创建: $OUTPUT_DIR/${ARCH}/VMStart-${VERSION}-${ARCH}.dmg"
}

build_windows_docker() {
    local ARCH="$1"
    local OUTPUT_DIR="$SCRIPT_DIR/exe/${ARCH}"
    
    log "通过 Docker 构建 Windows EXE ($ARCH)..."
    mkdir -p "$OUTPUT_DIR"
    
    docker build \
        --build-arg TARGET_ARCH="${ARCH}" \
        --build-arg VERSION="${VERSION}" \
        -f Dockerfile.windows \
        -t vmstart-windows-${ARCH} \
        "$SCRIPT_DIR"
    
    # 从容器中提取 EXE
    CONTAINER_ID=$(docker create vmstart-windows-${ARCH})
    docker cp "${CONTAINER_ID}:/output/VMStart.exe" "$OUTPUT_DIR/VMStart-${VERSION}-${ARCH}.exe"
    docker rm "$CONTAINER_ID"
    
    ok "EXE 已创建: $OUTPUT_DIR/VMStart-${VERSION}-${ARCH}.exe"
}

case "$TARGET" in
    arm64|apple_silicon)
        build_macos "arm64" "macos-15"
        ;;
    x86_64|intel)
        build_macos "x86_64" "macos-13"
        ;;
    win-x64|windows-x64)
        build_windows_docker "win-x64"
        ;;
    win-arm64|windows-arm64)
        build_windows_docker "win-arm64"
        ;;
    all)
        log "=== 全架构构建 ==="
        echo ""
        build_macos "arm64" "macos-15"
        echo ""
        build_macos "x86_64" "macos-13"
        echo ""
        build_windows_docker "win-x64"
        echo ""
        build_windows_docker "win-arm64"
        echo ""
        log "=== 全部构建完成 ==="
        echo ""
        echo "DMG 文件:"
        find "$SCRIPT_DIR/dmg" -name "*.dmg" 2>/dev/null
        echo ""
        echo "EXE 文件:"
        find "$SCRIPT_DIR/exe" -name "*.exe" 2>/dev/null
        ;;
    *)
        err "未知目标: $TARGET"
        echo "用法: $0 [arm64|x86_64|win-x64|win-arm64|all]"
        exit 1
        ;;
esac
