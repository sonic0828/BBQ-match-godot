# 烧烤消消消

基于 Godot 4.7.2 / GDScript / Compatibility 渲染器的竖屏食材整理三消游戏。

游戏名为「烧烤消消消」，美术沿用提供的烧烤食材与烤架，玩法按原始开发文档实现。已提供 **Godot 可玩首版和微信小游戏导出工程**；微信已通过本机模拟器验证，真机仍需验收，抖音尚未适配。

**换电脑或新建 Codex 项目时，先读 [新 Mac 迁移与构建交接](docs/new_mac_setup.md)。** 包含工具版本、首次构建、目录边界和可直接交给新机 Codex 的初始化提示词。iPhone 16 Pro 已确认首页正常：后台开通高性能模式后，还需彻底退出并重启手机微信，让高性能 Plus 模式生效。完整玩法验收仍待完成，详见 [微信导出与排错记录](docs/wechat_export.md)。

## 运行

在 Godot 中打开 `project.godot`，按 **F5**。主场景是 `scenes/main.tscn`。UI 在运行时由脚本生成，编辑器画布中的空根节点是正常的。

点击「开摊啦」开始。按住一串食材拖到另一烤架：空位执行移动，已有食材的位置执行交换。同一烤架集齐 3 串相同食材自动消除。清空烤架后，仅补入下方的下一碟。清空全部食材与所有补货碟即可过关。

暂停按钮或 Esc 暂停；失去应用焦点也会暂停，恢复焦点后手动继续。移动设备通过 Godot 的触摸转鼠标事件操作。

## 已实现

- 固定 JSON 配置的 10 关，6 / 9 个烤架，8 种食材。
- 拖拽事务、跨烤架 Move / Swap、无效落点回弹、局部动画锁。
- 双消、每碟 1–3 串、逐碟补货、自动连消、2 秒 Combo 窗口。
- Lv.1 移动教学、Lv.2 补货提示、Lv.3 交换教学。
- 倒计时、逐组进度反馈、独立音乐／音效／移动设备震动开关。
- 首页、选关、暂停、胜利、失败、关卡解锁和本地设置。
- 720 × 1280 基准布局，按可用窗口等比适配，移动系统安全区处理。
- 夜市背景、炭火烤架、食材图集、原创合成循环音乐与分层操作音效、中文字体子集。

## 目录

| 路径 | 用途 |
| --- | --- |
| `scripts/core/board_model.gd` | 纯规则与独立烤架状态机；由逻辑时钟推进，动画回调不修改业务状态 |
| `scripts/ui/board_view.gd` | 命中、拖拽、交换／消除／补货绘制 |
| `scripts/game_app.gd` | 页面、HUD、教程文案、生命周期与结算 |
| `scripts/core/level_loader.gd` | 关卡载入与校验 |
| `scripts/core/save_store.gd` | 本地进度和设置 |
| `data/level_01.json` … `level_10.json` | 原文档关卡数据及时间 |
| `docs/original_plan.md` | 原始开发文档副本 |
| `docs/verification.md` | 测试结果与验收限制 |
| `docs/platform_notes.md` | 平台发布准备情况 |
| `docs/new_mac_setup.md` | 新 Mac 环境接续、微信构建步骤与 Codex 初始化提示词 |
| `docs/assets.md` | 素材来源、字体许可与背景生成提示词 |

## 测试

在项目目录运行：

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/run_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/ui_smoke.gd -- --test-session
```

规则测试包含 10 关自动通关。界面测试通过 Viewport 输入事件走真实场景的拖拽与页面流程；测试存档写入 `/private/tmp/hotpot-ui-progress.cfg`，不修改玩家进度。

开发预览参数（Godot 引擎参数后的 `--` 之后）：

```bash
--level=3 --skip-tutorial --test-session
```

`--capture=/absolute/path.png` 在实际渲染后保存画面并退出，仅用于开发取图。普通运行不执行取图逻辑。

## 本地存档

`user://progress.cfg` 保存最高解锁关、已过关列表、上次选择关、音乐、音效和震动设置。不保存半局状态。首次游玩三个开关默认开启，音乐在首次交互后启播；老玩家保留已保存的开关选择。旧存档的音效静音也会应用于新增音乐，避免升级后突然出声。

音乐在首次点击／触摸后开始，跨首页和对局连续播放；暂停或切后台时冻结，继续后从原位置恢复。成盘声对齐动画约 0.27 秒的盘子出现时刻；补位按落点错峰发声，连消 3／5／8 次增加有上限的奖励音。音频检查用原生音频驱动运行 `Godot --path . --script tests/audio_smoke.gd -- --test-session`；压缩素材的可复现生成脚本为 `tools/generate_audio.py`（NumPy、ffmpeg）。

macOS 默认目录：`~/Library/Application Support/Godot/app_userdata/烧烤消消消/`。首次更名运行会按时间顺序优先读取前一版游戏名、再读取最早「火锅串串消」目录中的进度与设置，原存档保留。

微信通过原生短震动接口提供轻反馈：成盘时单消一下、双消／第二次连消两下、三次以上连消最多三下，间隔 120 ms。同帧合并，暂停、离开页面、失败、切后台和关闭震动都会清除待播反馈；重新开启震动会轻震一下供确认。设备实际支持情况与强度需真机验收。

## 后续验收

对局底部已按最新 UI 需求预留 4 个锁定功能按钮和 568×86 逻辑像素的广告区域；尚未接入广告、道具或平台账号。发布前仍需完成微信真机的生命周期、音频与性能验收；抖音需独立适配。同时按实际玩家反馈调整操作手感与关卡时间。

## 微信小游戏导出

首次按 [新 Mac 指南](docs/new_mac_setup.md) 完成资源导入和环境检查。日常关闭微信工程窗口后运行 `python3 tools/export_wechat.py`，再将生成的 `build/wechat/` 打开到微信开发者工具。AppID 已配置为 `wxd575463c13869e7d`。版本、依赖和验证结果见 [微信导出说明](docs/wechat_export.md)。

微信工程始终覆盖 `build/wechat/`，默认不生成 ZIP；仅在明确需要压缩包时添加 `--zip`。功能演示 GIF／MP4 另存 `build/previews/YYYY-MM-DD/<功能名>/`，不放入微信工程。
