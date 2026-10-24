# VMStart

**多引擎虚拟机管理器** — 16 个仿真引擎 · 33+ CPU 架构 · macOS & Windows 原生支持

## 许可证

VMStart 采用 **GNU General Public License Version 2 or later** 许可证。

- 15 个引擎采用 GPLv2
- 1 个引擎（ScummVM）采用 GPLv3
- 项目整体许可证为 GPLv2-or-later，与所有组件兼容

完整许可证文本见 [LICENSE](LICENSE) 文件。各引擎独立许可证见 `VMStart/Resources/Licenses/` 目录。

## 引擎列表

| 引擎 | 架构 | 许可证 |
|------|------|--------|
| QEMU | 30 个二进制 · 29+ 架构 | GPLv2 |
| Mini vMac | Motorola 68000 | GPLv2 |
| BasiliskII | 68020/030/040 | GPLv2 |
| SheepShaver | PowerPC G3/G4 | GPLv2 |
| DOSBox Staging | x86 DOS | GPLv2 |
| DOSBox-X | x86 增强版 | GPLv2 |
| PCem | x86 PC 模拟 | GPLv2 |
| 86Box | x86 全平台 | GPLv2 |
| VICE | MOS 6502 (Commodore) | GPLv2 |
| FS-UAE | 68000 (Amiga) | GPLv2 |
| Hatari | 68000 (Atari) | GPLv2 |
| ARAnyM | 68000 (Atari) | GPLv2 |
| OpenMSX | Z80 (MSX) | GPLv2 |
| Fuse | Z80 (ZX Spectrum) | GPLv3 |
| ScummVM | 多平台冒险游戏 | GPLv3 |
| Mednafen | 多平台游戏机 | GPLv2 |

## 下载

访问官网获取最新版本：https://zhengwenyi2026-alt.github.io/VMStart/

| 平台 | 架构 | 格式 |
|------|------|------|
| macOS | Apple Silicon (arm64) | DMG |
| macOS | Intel (x86_64) | DMG |
| Windows | x86_64 | ZIP (含 EXE) |
| Windows | ARM64 | ZIP (含 EXE) |

## 构建

```bash
# macOS DMG
./build_all.sh arm64
./build_all.sh x86_64

# Windows EXE（需要 Docker）
./build_all.sh win-x64
./build_all.sh win-arm64

# 全部架构
./build_all.sh all
```

## 商标声明

- **Ubuntu** 是 Canonical Ltd. 的注册商标。
- **Chromium** 是 Google Inc. 的商标。本项目集成 Chromium 浏览器用于 ISO 下载。
- **QEMU** 是 Fabrice Bellard 的商标。
- **Apple**、**macOS** 是 Apple Inc. 的注册商标。
- **Windows** 是 Microsoft Corporation 的注册商标。
- 其他所有第三方商标归其各自所有者所有。

## 源码

完整源码（含 16 个引擎）：https://github.com/zhengwenyi2026-alt/VMStart

## 版权

Copyright (C) 2026 VMStart Project.

本程序是自由软件，你可以在自由软件基金会发布的 GNU 通用公共许可证（版本 2 或更高版本）下重新发布和/或修改它。
