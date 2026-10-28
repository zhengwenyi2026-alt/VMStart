#!/bin/bash
# VMStart 一键安装：curl -fsSL https://zhengwenyi2026-alt.github.io/VMStart/install.sh | bash
# 通过 curl 下载的文件不带隔离标记，安装后可直接打开，不会出现“无法验证开发者”的提示
set -euo pipefail

BASE="${VMSTART_BASE:-https://zhengwenyi2026-alt.github.io/VMStart}"
VERSION="1.0.0"
APP="/Applications/VMStart.app"

say() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
die() { printf '\033[1;31m错误：\033[0m%s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || die "此脚本仅支持 macOS"
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 14 ] || die "需要 macOS 14 或更高版本"

# Rosetta 下运行的终端 uname 会报 x86_64，以硬件为准
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = 1 ]; then arch=arm64; else arch=x86_64; fi
pkg="VMStart-$VERSION-macOS-$arch.zip"

tmp="$(mktemp -d)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

say "下载 $pkg"
curl -fL --progress-bar "$BASE/$pkg" -o "$tmp/$pkg" || die "下载失败，请检查网络"

say "安装到“应用程序”"
ditto -x -k "$tmp/$pkg" "$tmp" || die "无法解压安装包"
osascript -e 'quit app "VMStart"' 2>/dev/null || true
sudo_if() { if [ -w /Applications ]; then "$@"; else sudo "$@"; fi; }
sudo_if rm -rf "$APP"
sudo_if ditto "$tmp/VMStart.app" "$APP"
sudo_if xattr -r -d com.apple.quarantine "$APP" 2>/dev/null || true

# 命令行工具：优先放到已在 PATH 中且可写的目录
cli="$APP/Contents/Resources/CLI/vmstart"
if [ -x "$cli" ]; then
  for dir in /opt/homebrew/bin /usr/local/bin; do
    if [ -d "$dir" ] && [ -w "$dir" ]; then ln -sf "$cli" "$dir/vmstart"; say "已安装命令行工具：$dir/vmstart"; break; fi
  done
fi

say "安装完成，正在打开 VMStart"
open "$APP"
