# 贡献说明

项目整理自 [mygo11111/p5-mlm-](https://github.com/mygo11111/p5-mlm-) 的发行内容。请保留原作者及第三方署名，并在提交说明中区分既有内容和新增工作。

## 开发位置

仓库包含运行所需的程序和资源。Lua 与配置直接位于模拟器加载的位置，修改后可运行根目录 `FFXIV-Omega-Sim.exe` 验证：

- `_moling_probe/MPTestingCPP/Binaries/Win64/ue4ss/Mods/MolingDelta/Scripts/`：P5 攻略适配 Lua。
- `_moling_probe/MPTestingCPP/Binaries/Win64/ue4ss/UE4SS-settings.ini`：UE4SS 配置。
- `_moling_probe/MPTestingCPP/Binaries/Win64/ue4ss/Mods/mods.txt`：模组启用列表。
- `launcher/`：启动器 C# 源码及应用清单。

修改启动器后，在仓库根目录的 PowerShell 中执行 `.\tools\Build-Launcher.ps1 -Force`，更新随仓库提供的 EXE。构建使用 .NET Framework C# 编译器。仓库不含完整 Unreal 工程，无法重建原模拟器本体。

较大的运行文件以分片随仓库提供，启动器会在本地还原。需要只还原文件而不启动模拟器时，可执行 `.\FFXIV-Omega-Sim.exe --prepare-only`。不要提交还原生成的 `MPTestingCPP/Binaries/Win64/MPTestingCPP.exe` 和 `MPTestingCPP/Content/Paks/MPTestingCPP-Windows.ucas`（均位于 `_moling_probe/` 下）。有意更新这些二进制文件后，运行 `.\tools\Split-Runtime.ps1 -UpdateManifest -Force` 更新分片及清单，再运行 `.\tools\Build-Launcher.ps1 -Force`，将新清单嵌入启动器。Lua 和配置仍直接在运行目录修改，无需重新分片。

## 提交检查

```powershell
.\tools\Test-Repository.ps1
git diff --check
```

工具测试使用原创假数据。涉及机制、界面或启动行为的修改，还应启动模拟器验证相应流程，并在提交说明中注明检查结果和未执行的检查。不要提交运行日志、个人存档、个人配置更改、崩溃转储、个人研究材料或凭据。

提交和 PR 标题使用 Conventional Commits，例如 `fix: correct role selection labels`。用户可见的变化记录在 `CHANGELOG.md` 的 `Unreleased` 下，遵循 Keep a Changelog 格式；版本使用 Semantic Versioning，发布标签使用 annotated tag。
