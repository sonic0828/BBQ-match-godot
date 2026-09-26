# 新 Mac 迁移、微信构建与 Codex 交接

核对日期：2026-09-25。适用于本仓库的 **Godot 版本**「烧烤串串消」。先复用已验证的脚本与固定模板，再按实际故障排查；首次安装、资源导入和下载完成后，日常导出可复用模板缓存。构建耗时取决于机器、缓存和网络，不承诺固定分钟数。

## 1. 先同步旧电脑的成果

GitHub 仓库：[sonic0828/BBQ-match-godot](https://github.com/sonic0828/BBQ-match-godot)。新电脑只能克隆已推送的提交，旧电脑的本地 commit 不会自动出现。

在旧电脑的仓库根目录检查：

```bash
git status --short --branch
git log --oneline origin/main..HEAD
git rev-parse HEAD
```

确认本次交接文档和此前修复都已提交后，由用户执行或明确授权 Codex 执行：

```bash
git push origin main
```

记录旧电脑的 `git rev-parse HEAD`，新机克隆后核对。交接代码应包含 `3e5ab5f`（加载器清理与首帧诊断）及后续文档提交。若还有未提交改动，先辨认归属再处理；不要用重置命令覆盖它们。

## 2. 工具与已验证版本

下表是旧电脑的验证基线，不代表每个工具的最低支持版本，也不代表未来最新版已验证。

| 工具 | 已验证版本／要求 | 用途 |
| --- | --- | --- |
| Godot 标准版 | `4.7.2.stable.official.ed1daf0bf` | 编辑、资源导入、资源包导出 |
| 微信模板 | `minigame4.7.0.8.tpz`，SHA-256 固定 | 微信适配层与 WASM 内核 |
| 模板内核 | `4.7.2.rc.custom_build.a71c91099` | 与编辑器并非同一构建；当前组合已通过本机验证 |
| Python | `3.13.0`，导出脚本仅使用标准库 | 组装微信工程，无需 pip 依赖 |
| Node.js | `22.17.0` | 平台回归测试，使用 `node:test` 与 MockTimers，无需 npm install |
| Git | `2.47.1` | 克隆、同步与提交 |
| curl | `8.7.1` | 下载固定模板；macOS 已有 curl 时先检查可用性 |
| 微信开发者工具 | Stable `2.02.2608070` | 模拟器、预览、手机扫码 |
| 工程基础库配置 | `3.15.2` | 手机实际基础库可能不同，诊断弹窗会记录实际版本 |
| Codex | 能打开本地 Git 项目、执行命令 | 依照仓库文档检查环境、构建与交接 |

从各工具的官方发行渠道安装，选择适合新 Mac 架构的版本。优先复用表中基线；如无法取得对应版本，先记录差异并验证，不直接改写模板版本或校验值。本项目导出脚本只允许 `4.7.*` 引擎，但这不等于整个 4.7 系列都已验收。

当前路线用 Godot `--export-pack` 打包资源，再组装已发布的微信模板。无需为此编译第三方 C++ 编辑器插件，也无需先安装官方 Web 导出模板。Git 若缺失，可通过系统提示安装 Command Line Tools；不要为了微信导出额外从源码编译 Godot 或安装整套 Xcode。

## 3. 克隆和首次导入

新电脑尚无本仓库时执行：

```bash
mkdir -p "$HOME/Project/GodotProjects"
cd "$HOME/Project/GodotProjects"
git clone https://github.com/sonic0828/BBQ-match-godot.git
cd BBQ-match-godot
git status --short --branch
git rev-parse HEAD
git merge-base --is-ancestor 3e5ab5f HEAD
```

最后一条正常时无输出，退出码为 0。若新电脑已经克隆过，在对应仓库检查工作区，再用 `git pull --ff-only` 更新；不要重复 clone 到现有目录。

以下命令均在本仓库根目录运行。可在 Godot 项目管理器导入 `project.godot`，等待资源导入结束，再按 F5 验证首页。也可先在终端导入：

```bash
BBQ_GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
"$BBQ_GODOT" --version
python3 --version
node --version
git --version
curl --version
python3 tools/export_wechat.py --help
"$BBQ_GODOT" --headless --path . --import
```

若 Godot 在其他位置，调整 `BBQ_GODOT`。后续导出显式传入 `--godot "$BBQ_GODOT"`，避免 PATH 中另一版本被优先选中。变量仅在当前终端会话有效，新开终端需要重新设置。

`.godot/` 未纳入 Git，新机会重新生成导入缓存。素材、字体和音效成品已在仓库中，常规构建无需运行 `tools/build_font.py` 或重新生成美术资源。

## 4. 固定模板与首次构建

默认模板下载地址：

[下载 minigame4.7.0.8.tpz](https://github.com/godothub/godot-minigame/releases/download/4.7/minigame4.7.0.8.tpz)

默认缓存：`build/cache/minigame4.7.0.8.tpz`。固定 SHA-256：

```text
6e9938ec4f8de0cd9b693a1d851a6b361a7397d6f3ee6a6de4909b053bac8a23
```

导出脚本会在缓存不存在时下载，每次使用前校验。也可从旧电脑复制这一个原始模板文件到相同缓存位置，以减少下载等待；导出脚本仍会校验它。若仅通过 `--template /其他位置/文件.tpz` 指定模板，平台测试仍会查找默认缓存路径，运行测试前需准备默认缓存。

首次导出前，若微信开发者工具已经打开此工程，先关闭该工程窗口。执行：

```bash
BBQ_GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
python3 tools/export_wechat.py --godot "$BBQ_GODOT"
shasum -a 256 build/cache/minigame4.7.0.8.tpz
```

期望输出：微信工程路径、zip 路径和包体大小。以下文件应存在：

| 文件 | 用途 |
| --- | --- |
| `build/wechat/project.config.json` | AppID、小游戏工程及打包设置 |
| `build/wechat/game.js`、`engine/game.js` | 微信启动入口、引擎启动入口 |
| `build/wechat/boot-options.js` | 本次构建编号、是否启用诊断 |
| `build/wechat/engine/bbq.bin` | Godot 资源包，内部是 PCK |
| `build/wechat/engine/godot.wasm.br` | 固定微信内核 |
| `build/wechat/export-info.json` | 模板校验值、编辑器版本、补丁、构建编号和文件大小 |
| `build/wechat.zip` | 仅在用户明确要求并添加 `--zip` 时生成 |
| `build/previews/YYYY-MM-DD/<功能名>/` | GIF／MP4 等演示文件，独立于微信工程 |
| `build/wechat-export.log` | Godot 资源导出日志 |

用构建清单核对：AppID 为 `wxd575463c13869e7d`，普通构建 `diagnostics` 为 `false`，`runtime_patches` 包含 `sdk-preserve-device-pixel-ratio` 与 `loader-stop-after-cleanup`。

首次迁移时完成一次基线测试，后续按改动范围复用结果：

```bash
BBQ_GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
node --test tests/wechat_boot.test.cjs tests/wechat_sdk.test.cjs tests/wechat_loader.test.cjs
"$BBQ_GODOT" --headless --path . --script tests/run_tests.gd
"$BBQ_GODOT" --headless --path . --script tests/ui_smoke.gd -- --test-session
```

平台测试要在默认模板缓存准备好后运行。旧机最近记录为平台 26 项、页面／输入 18 项通过；核心测试会逐关输出求解结果。以新机实际退出码及日志为准，不照抄旧机的通过结论。

## 5. 微信开发者工具和手机预览

1. 在新 Mac 安装并打开微信开发者工具，由用户登录具有该小游戏开发权限的微信账号。
2. 导入本仓库的 `build/wechat/`，确认工程类型为“小游戏”、AppID 为 `wxd575463c13869e7d`。编译后应看到游戏首页；点击“开摊啦”检查触摸／鼠标输入。
3. 手动点“预览”即可生成手机二维码。需要 Codex/CLI 自动预览时，在工具的安全设置中开启“服务端口”，并完成工具弹出的调用授权。旧 Mac 的登录、端口和授权不会随 Git 迁移；端口号不固定照搬。
4. 命令行预览前确认安装路径。以下变量和命令均在本仓库根目录执行：

```bash
BBQ_WXCLI="/Applications/wechatwebdevtools.app/Contents/MacOS/cli"
"$BBQ_WXCLI" --help
"$BBQ_WXCLI" preview \
  --project "$PWD/build/wechat" \
  --qr-format image \
  --qr-output "$PWD/build/wechat-preview.png" \
  --info-output "$PWD/build/wechat-preview.json"
```

预览命令返回成功后，用有权限的微信扫码。二维码可能过期，重新执行即可。生成预览包不等于上传正式版本、提交审核或发布。

账号持有人已于 2026-09-25 开通后台高性能模式；iPhone 16 Pro 彻底退出并重启微信后，同一预览包进入高性能 Plus 模式并正常显示首页。代码保留两个 iOS 高性能开关，但代码配置和后台开通都不能单独证明手机模式已生效，应核对真机标志。iOS 真机调试的 USB 要求与普通扫码预览是两条流程，详见[导出排错说明](wechat_export.md)。

## 6. 日常更新与空白页诊断

日常顺序：同步仓库 → Godot 修改并验证 → 关闭微信工程窗口 → 导出 → 重新打开 `build/wechat/` → 编译和预览 → 手机验证。保留 `build/cache/` 可以复用模板；`build/wechat/` 会被脚本重新生成。修改导出产物会在下次构建时丢失，应修改 `platform/wechat/` 或导出脚本中的维护源。

所有微信构建统一覆盖 `build/wechat/`，不要按功能另设输出目录。默认不生成 ZIP，用户明确要求时才添加 `--zip`。功能演示按日期和功能名保存到 `build/previews/`，同日重复迭代可追加构建号；不要将演示文件放入微信工程。

普通导出：

```bash
python3 tools/export_wechat.py --godot /Applications/Godot.app/Contents/MacOS/Godot
```

手机仍空白或卡在加载页时，先关闭微信工程窗口，再生成诊断包，重新打开工程并预览：

```bash
python3 tools/export_wechat.py --godot /Applications/Godot.app/Contents/MacOS/Godot --diagnostics
```

构建成功后，在微信开发者工具重新打开 `build/wechat/`，再执行：

```bash
/Applications/wechatwebdevtools.app/Contents/MacOS/cli preview \
  --project "$PWD/build/wechat" \
  --qr-format image \
  --qr-output "$PWD/build/wechat-diagnostic-preview.png" \
  --info-output "$PWD/build/wechat-diagnostic-preview.json"
```

诊断包在收到首帧约 3 秒后显示状态，30 秒内未确认首帧也会报告状态。保留弹窗截图、构建编号、手机型号、系统／微信版本，以及关闭弹窗后是否仍空白的描述。

诊断应逐层判断：引擎未启动看初始化错误；场景未确认看脚本／资源错误；场景已有但首帧未确认看渲染初始化；首帧已绘制仍空白则结合实际 WebGL 模式、画布／缓冲尺寸、上下文状态继续排查。首帧信号或 GL 0 都不能单独证明真机画面正确。

恢复普通包时，再导出一次且不带 `--diagnostics`，然后重新生成二维码。诊断包的成功弹窗不应用于正常交付。

## 7. 两个同名游戏目录的边界

2026-09-25 已读取旧电脑两个工程的入口，情况如下：

| 目录 | 实际内容 | 本轮迁移用途 |
| --- | --- | --- |
| `GodotProjects/BBQ-match-godot/` | Godot 源码、素材、平台启动文件、导出脚本 | 本指南的源码入口和 Codex 项目根目录 |
| 本仓库的 `build/wechat/` | 自动生成的 Godot 微信工程 | 微信开发者工具编译、扫码预览入口 |
| `miniProgram/bbqMatch-2026/` | 已有独立的原生 JavaScript + Canvas 2D 实现，入口 `game.js` 加载 `js/app.js` | 单独保留；不作为 Godot 产物目录，不在本轮合并或覆盖 |

两个源码工程不会自动同步。Godot 版本目前只需克隆本仓库并生成 `build/wechat/`。若日后决定统一到某个外部目录，应先确定保留哪套实现及同步方式；当前脚本遇到没有 `export-info.json` 的已有输出目录会拒绝覆盖，不能删除此保护来套用另一套项目。

## 8. 当前交接状态和新机验收

- 已验证：旧机 Godot 页面／输入、微信模拟器首页与对局、存档恢复；Android 曾由用户反馈可进入并操作。
- 已修复并做回归测试：iOS SDK 写入只读像素比例、加载器清理后继续绘制；普通扫码诊断已能记录场景和首帧状态。
- **真机启动已通过：2026-09-25，iPhone 16 Pro 在开通后台能力并彻底重启微信后，同包进入高性能 Plus 模式，首页正常、首帧已绘制、GL 0、启动错误 0 条。** 具体日志证据见微信导出记录，不将首页成功扩大为完整玩法已验收。
- 待核实：手机拖拽与关卡流程、音效、前后台暂停、安全区、持续运行性能和不同平台的完整验收。
- 本文整理时未在新 Mac 实际执行。新机应留下：Git 提交号、各工具版本、构建清单、测试结果、模拟器截图和两端真机结果，并将新结论补到 `docs/wechat_export.md`。

本轮文档验证仅包括：Shell 命令语法、仓库内链接和文件存在性、导出参数与本地工具帮助、模板版本／SHA-256 与脚本及缓存的一致性。既有游戏测试和模拟器结论沿用上次记录，没有将本次文档检查记为新机构建通过。

## 9. 新电脑的 Codex 项目初始化后怎么做

在 Codex 中添加／打开**克隆得到的仓库根目录**（其中有 `project.godot` 和 `AGENTS.md`）。首次环境接续使用这份本地检出，确保 Codex、Godot 和微信工具指向同一份仓库；若后来在独立 worktree 开发，微信工具也要指向该 worktree 下生成的 `build/wechat/`。

先把下面这段提示词发给新电脑的 Codex：

```text
这是从旧 Mac 迁移的“烧烤串串消”Godot 项目，请先完成新机环境接续。

1. 阅读 AGENTS.md、README.md、docs/new_mac_setup.md 和 docs/wechat_export.md。
2. 确认当前目录是 Godot 仓库根目录，检查 Git 状态、远端和提交号；确认包含 3e5ab5f 及新 Mac 交接文档。如果源码未同步齐，先报告缺失情况，不覆盖本地改动。
3. 检查本机 Godot、Python、Node.js、Git、curl、微信开发者工具的版本和真实安装路径。对照文档基线，缺少工具或账号授权时集中告诉我需要做什么，不把旧机路径和登录状态视为已存在。
4. 复用 tools/export_wechat.py、固定 4.7.0.8 模板及 SHA-256。完成首次资源导入、普通导出和文档中的基线检查；不升级模板，不重建导出链路，不编译 C++ 插件。
5. 将当前检出下的 build/wechat 导入微信开发者工具。已有窗口时先关闭再导出，完成编译、首页与输入验证，再生成普通预览二维码。登录或服务端口／工具授权需要我操作时明确说明。
6. 不修改或覆盖 miniProgram/bbqMatch-2026，它是独立的原生 JavaScript 实现。
7. iPhone 16 Pro 首页已真机验收通过。若开通高性能模式后仍显示普通模式，先彻底退出并重启手机微信，再扫同包二维码核对模式与首帧；无需先删存档。玩法、音效、前后台和性能仍需实际验收，不能用首页正常代替。
8. 汇总新机版本、源码提交号、构建路径和通过／失败／待手机验证的项目。此次先接通环境，不改游戏玩法。必要修改按 AGENTS.md 使用两个 -m 参数创建本地 commit；推送、审核或发布另行按我的授权执行。
```

收到 Codex 的环境核对结果后，完成需要本人操作的微信登录与授权，再扫描新生成的二维码。后续每次功能更新都沿用第 6 节的流程；不要重复安装依赖、换模板或重做首次兼容性探索。
