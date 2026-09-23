# 平台准备与边界

核实日期：2026-09-23。

## 当前状态

- 开发机 Godot：4.7.2.stable.official.ed1daf0bf。
- 纯 GDScript、2D、Compatibility；无第三方运行时插件。
- 已配置 `Web Preview` 导出预设：单线程、竖屏布局、包含关卡 JSON、排除测试和文档。
- 本机尚无 Godot 导出模板，尚未生成或验证 Web、Android、微信、抖音或 Steam 发布包。
- Godot 桌面存档及焦点变化处理已验证；小游戏宿主回调和存储尚未对接。

## 微信 / 抖音

Godot 的标准 Web 导出面向浏览器，要求 WebAssembly / WebGL 2.0；不能据此认定生成的 HTML 目录就是小游戏发布包。参见 [Godot Web 导出文档](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)。

已调研的候选方案 [Godot Mini Game](https://github.com/AnranS/godot_for_minigame) 声明支持微信 `wx` 与抖音 `tt`。该仓库当前公布的验证组合为插件 v0.3.0 + Godot 4.6.1.stable（14d19694e0c8），并明确要求其他编辑器版本使用对应模板。因此不能直接假设其模板与本项目 4.7.2 兼容。本次未安装该插件、未更换现有引擎版本。

下一步先完成小规模导出验证：

1. 确定匹配 4.7.2 的适配器／模板，或在项目副本中验证候选 4.6.1 组合。
2. 在微信、抖音开发者工具中验证首屏加载、透明纹理、中文、音频和拖拽。
3. 将宿主 onHide 接到暂停入口；onShow 保持暂停，不自动恢复计时。
4. 将本地进度读写和震动接到宿主能力，并检查失败／重启恢复。
5. 使用各平台 AppID 做真机测试：iOS / Android、刘海安全区、不同屏幕比例、双消与补货并行帧率、切后台、触摸取消、资源与引擎包体。

## TapTap / Steam（第二阶段候选）

保持当前核心规则、关卡与画面复用。确定发布方向后再补原生导出模板、安卓签名与包名、桌面分辨率体验及对应平台能力。当前未集成任何商业平台 SDK，未上传或发布。
