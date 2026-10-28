# 原作及第三方说明

## 原模拟器和适配发行包

原模拟器的发布者为 B 站用户「秋天的你远离天空」：[绝欧米茄模拟器发布与更新说明](https://www.bilibili.com/video/BV1i84y1p7Sk/)，[联机说明](https://www.bilibili.com/video/BV19m4y1z73t/)。对照其 Ver1.4 发行文件，本仓原发行包中的模拟器主程序及全部主要 Unreal 资源包的 SHA-256 均一致，确认是同一底层构建。感谢原作者制作和发布模拟器。

本仓库整理自 [mygo11111/p5-mlm-](https://github.com/mygo11111/p5-mlm-) 的 [v1 发行包](https://github.com/mygo11111/p5-mlm-/releases/tag/v1)，其中提供莫灵喵打法适配及运行文件。感谢该发行包的发布者和相关贡献者；原项目说明见 [上游 README](https://github.com/mygo11111/p5-mlm-/blob/6b72f7361c777bc91d684af3e62c310d82bf348d/README.md)。本仓后续维护、练习面板及启动器不代表原模拟器或上游适配均由本仓编写。

以上归属不覆盖所有第三方组件、游戏素材及攻略的权利，也不表示已获得对这些内容的统一许可。

## UE4SS

- 来源：[UE4SS-RE/RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)。
- 原包记录版本：`v3.0.1-1181-g83330635`。
- 原包许可：MIT，`Copyright (c) 2022 Narknon`。
- [UE4SS 许可文本](_moling_probe/MPTestingCPP/Binaries/Win64/ue4ss/LICENSE) 与运行依赖一起保留。
- UE4SS 的许可不覆盖模拟器、MolingDelta、攻略或游戏素材。

## 攻略与规则参考

原研究材料记载：P5 二运前半使用 yzLIsten 的 [绝欧米茄 P5 二运前半拉线踩塔无脑思路](https://www.bilibili.com/video/BV1gs4y1H7kP/)，其他莫灵喵适配参考「塔塔露用了也会打绝欧米茄 v2.2」及「欧米茄画图-v2.1更新.txt」。`omega_source.lua` 保留原来的生成来源注释；本仓未重新提取、修改或宣称原创这些规则。

## 运行依赖和资源

MPTestingCPP、Unreal Engine 运行组件、Boost、Intel TBB、OpenImageDenoise、Steamworks、音频库、字体及其他运行依赖来自原发行包，并随仓库保留在实际运行位置。已有字体元信息和 UE4SS 许可一并保留。

FFXIV 及其相关名称、素材的归属不因仓库维护而改变。原项目没有覆盖全部内容的统一许可证；本仓不为这些内容添加统一的 MIT 或其他许可证。

## 启动器

`launcher/` 中的 C# 启动器及根目录对应 EXE 负责在本地校验、还原随附运行文件，并定位和启动原模拟器。这些功能不改变模拟器本体、既有 Lua 攻略适配或第三方资源的许可。
