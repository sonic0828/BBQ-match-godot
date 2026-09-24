# 微信小游戏导出

## 本次交付

- AppID：`wxd575463c13869e7d`；游戏名：烧烤串串消。
- 工程：`build/wechat/`，压缩包：`build/wechat.zip`。
- 导入微信开发者工具时选择 **`build/wechat`**，不要选择 Godot 项目根目录。
- 竖屏、Compatibility、单线程；十关资源、中文字体和短音效均在本地包内。
- 构建目录被 Git 忽略，提交的是导出脚本、启动配置和说明。

## 导出方法与版本

沿用用户提供指南中的 [godothub/godot-minigame](https://github.com/godothub/godot-minigame) 适配路线。下载其 [4.7.0.8 模板](https://github.com/godothub/godot-minigame/releases/tag/4.7)，使用 Godot 命令行打包资源，再组装微信运行时工程。

本机 Xcode 尚未接受许可，无法编译该插件的 macOS C++ 编辑器面板。本次没有安装面板，也没有替用户接受许可；命令行脚本复用了该插件发布的适配层、引擎和启动器，不需要官方 Web 导出模板，不生成 HTML 套壳。

| 部件 | 实际版本 |
| --- | --- |
| 开发用 Godot | `4.7.2.stable.official.ed1daf0bf` |
| 微信模板 | `minigame4.7.0.8.tpz` |
| 微信运行内核 | `4.7.2.rc.custom_build.a71c91099` |
| 开发者工具 | Stable `2.02.2608070` |
| 微信基础库 | `3.15.2`（模板原配置） |

编辑器与模板内核不是完全相同的构建，已在本机模拟器验证兼容。微信预设使用 GDScript 文本导出，避免跨构建的脚本二进制标记差异。模板固定 SHA-256：

```text
6e9938ec4f8de0cd9b693a1d851a6b361a7397d6f3ee6a6de4909b053bac8a23
```

## 再次导出

在仓库根目录运行：

```bash
python3 tools/export_wechat.py
```

首次下载模板到 `build/cache/`，后续复用本地缓存，使用前仍校验 SHA-256。可通过 `--godot /path/to/godot` 指定引擎，通过 `--template /path/to/minigame4.7.0.8.tpz` 使用已有模板，通过 `--appid wx...` 指定其他小游戏。

脚本将替换其先前生成的 `build/wechat/`，因此不要直接在构建目录维护代码。启动逻辑编辑 `platform/wechat/game.js`，资源过滤编辑 `export_presets.cfg` 的 `WeChat Resources` 预设。

输出结构：

```text
build/wechat/
├── game.js
├── game.json
├── project.config.json
├── weapp-adapter.js
├── glx-config.js
├── godot-loader.js
├── THIRD_PARTY_NOTICES.txt
├── export-info.json
├── images/
└── engine/
    ├── game.js
    ├── bbq.bin
    ├── godot.js
    ├── godot-sdk.js
    └── godot.wasm.br
```

`bbq.bin` 内部是 Godot PCK。必须保留 `.bin` 扩展名：本次实测 `.pck` 被微信打包文件过滤器排除，运行时无法打开资源。引擎与资源作为 `engine` 分包加载，模板示例资源、示例分包和私人编辑器配置不进入交付包。`export-info.json` 记录模板来源、校验值和文件大小。

本机开发者工具对 Emscripten 引擎执行二次压缩时，预览打包线程会退出。导出配置已关闭 SWC 和额外 JS 压缩，重新生成预览成功。关闭“忽略未使用文件”，保证动态加载的 WASM 和资源包被打入预览。

微信启动文件将 `wx.onHide` / `wx.onShow` 转发到 Godot 适配层的失焦／聚焦事件，使用游戏现有的失焦暂停逻辑。存档沿用 `user://progress.cfg`，由模板文件系统适配持久化；当前音效均为短 WAV，继续通过 Godot 混音播放。

## 验证记录（2026-09-24）

1. 独立最小工程成功导出、显示图片和按钮；随后验证完整游戏。
2. 完整导出包在微信模拟器启动，中文、透明食材、烤盘和背景正常。
3. 实际拖拽完成第一关：移动、交换、三消、连消、结算、解锁和进入第二关。
4. 停止并重新编译模拟器后，首页恢复“继续第 2 关 · 1/10 已完成”，确认小游戏存档持久化。
5. 运行日志未检出脚本／资源错误；Godot 资源包也通过桌面引擎启动检查。
6. 微信开发预览包生成成功：服务端反馈总包体 13,134,589 字节，主包 101,535 字节，engine 分包 13,033,054 字节；本地预览二维码为 `build/wechat-preview.png`。
7. 游戏核心规则没有修改，复用此前核心测试结果；本次主要验证新的导出与微信运行路径。

通关与重启证据：

![微信模拟器通关](wechat/level-01-win.png)

![重启后保留进度](wechat/progress-restored.png)

手机端尚需验收：iOS / Android 真机触摸、音效听感、前后台切换暂停、异形屏安全区域和性能。模板保留 `iOSHighPerformance` / `iOSHighPerformance+` 配置；iOS 对应能力是否可用，以小游戏后台实际开通状态为准。未接入广告、分享、登录或付费能力，未提交审核或正式发布。

## 手机开发预览

本次已生成 `build/wechat-preview.png`，可用有开发权限的微信扫码。二维码会过期；届时在开发者工具中点“预览”重新生成，或在已授权服务端口／CLI 的环境执行：

```bash
/Applications/wechatwebdevtools.app/Contents/MacOS/cli preview --project "$PWD/build/wechat" --qr-format image --qr-output "$PWD/build/wechat-preview.png"
```

已完成的是开发预览包生成，手机上的实际运行仍需扫码验收。
