# Changelog

本文件使用 Keep a Changelog 格式。

## [Unreleased]

## [0.1.0-alpha.1] - 2026-10-26

### Added

- 提供 `FFXIV-Omega-Sim.exe` 启动入口及对应源码，首次启动时离线校验并还原运行文件。
- 随仓库提供完整运行程序和资源，支持下载 Source code 或 Releases 中的 ZIP 文件后离线运行。
- 提供运行文件分片工具及完整性检查，支持共同维护较大的运行文件。

### Changed

- 将既有 Lua 和配置放在实际运行目录中维护，保留原模拟器机制和攻略适配行为。
