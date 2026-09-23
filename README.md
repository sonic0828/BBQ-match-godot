# 烧烤串串消

基于 Godot 4.7.2 / GDScript / Compatibility 渲染器的竖屏食材整理三消游戏。

游戏名为「烧烤串串消」，美术沿用提供的烧烤食材与烤架，玩法按原始开发文档实现。本次交付为 **Godot 可玩首版**；微信、抖音尚未打包或真机验收。

## 运行

在 Godot 中打开 `project.godot`，按 **F5**。主场景是 `scenes/main.tscn`。UI 在运行时由脚本生成，编辑器画布中的空根节点是正常的。

点击「开摊啦」开始。按住一串食材拖到另一烤架：空位执行移动，已有食材的位置执行交换。同一烤架集齐 3 串相同食材自动消除。清空烤架后，仅补入下方的下一碟。清空全部食材与所有补货碟即可过关。

暂停按钮或 Esc 暂停；失去应用焦点也会暂停，恢复焦点后手动继续。移动设备通过 Godot 的触摸转鼠标事件操作。

## 已实现

- 固定 JSON 配置的 10 关，6 / 9 个烤架，8 种食材。
- 拖拽事务、跨烤架 Move / Swap、无效落点回弹、局部动画锁。
- 双消、每碟 1–3 串、逐碟补货、自动连消、2 秒 Combo 窗口。
- Lv.1 移动教学、Lv.2 补货提示、Lv.3 交换教学。
- 倒计时、逐组进度反馈、音效、移动设备震动开关。
- 首页、选关、暂停、胜利、失败、关卡解锁和本地设置。
- 720 × 1280 基准布局，按可用窗口等比适配，移动系统安全区处理。
- 夜市背景、食材／烤架原图图集、原创合成短音效、中文字体子集。

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

`user://progress.cfg` 保存最高解锁关、已过关列表、上次选择关、音效和震动设置。不保存半局状态。

macOS 默认目录：`~/Library/Application Support/Godot/app_userdata/烧烤串串消/`。首次更名运行会自动读取旧「火锅串串消」目录中的进度，原存档保留。

## 后续验收

对局底部已按最新 UI 需求预留 4 个锁定功能按钮和 568×86 逻辑像素的广告区域；尚未接入广告、道具或平台账号。发布前仍需选定与引擎匹配的小游戏导出方案，接入平台生命周期／存储／音频，完成微信和抖音真机测试，以及按实际玩家反馈调整操作手感与关卡时间。
