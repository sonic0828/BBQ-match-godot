# 安卓再次进入后的 UI 缺失

## 当前范围（2026-09-29）

用户确认完整 D 包 `20260929-103330` 两次进入 UI 正常。新日志实际为标准 WebGL2，未出现 `vertex_attrib`，7 次同实例恢复均有首帧（14～76 ms）；有一条分包阶段宿主 timeout，之后成功启动，不能说整个日志零错误。普通导出据此固定为安卓 D，iOS 保持轻量 Loading；详细诊断需显式 `--diagnostics`。仍需更多安卓机型验证性能与兼容性。

优化在 `codex/ios-startup-optimization` 完成，用户已确认 iPhone 16 Pro 和 Android（OPPO）存档冷启动验收通过，并授权合入本地 main，详见 [微信存档](save_persistence.md)。iPhone 12 Mini 整个微信退出暂不做专项优化。以下 B／D 构建记录保留历史对照。

## 已确认的证据

- 用户三份日志均为 `20260928-232851`，PCK 标识一致，微信 8.0.78／基础库 3.17.3。OPPO 最近使用日志明确为 B＋WXGLX，Loader 实际绘制 0 次；首帧后仍出现 `WAPixi.js` 的 `shader and geometry incompatible, geometry missing the "vertex_attrib" attribute`。背景、食材、纹理按钮仍可见，缺失集中于程序绘制的按钮底板、面板和遮罩。优先调查渲染适配；未证明资源漏打包，也未确定具体故障图元。
- 原报告 `errorCount=0` 未覆盖这条宿主错误。新增 `errorScope` 明确它仅统计微信应用错误回调与 Godot stderr；微信宿主仅在 vConsole 出现的错误仍必须一起检查，不包装或屏蔽宿主错误。
- OPPO 的微信 hide／show 间隔为 1,911 ms，随后帧统计有 1,912 ms 的长帧且没有恢复首帧回执。固定模板注册画布 focus／blur，Godot 将其转成 `NOTIFICATION_WM_WINDOW_FOCUS_IN/OUT`；游戏先前仅处理 APPLICATION 通知。
- 本轮同时处理窗口与应用通知，同一前后台状态只执行一次。后台暂停对局、音频和震动；回前台恢复宿主状态，但对局仍须玩家点击继续。清除后台帧计时，恢复实际绘制后报告首帧。新增 `[BBQ godot lifecycle]` 与有界检查点，可与微信 `[BBQ lifecycle]` 对照。
- 安卓原生等待提示增加接口不存在、请求、API 接受、失败及关闭的日志 `[BBQ native loading]`。API 接受不等于用户肉眼看到了提示。迟到的旧请求失败不会清除新请求的提示所有权。不会通过该提示创建 GL 上下文。

## 对照构建

每次覆盖前仅关闭开发者工具中的烧烤工程，完成后重新打开 `build/wechat/`。不另建微信工程目录，不生成 ZIP。

```bash
# 相同源码 B 基线：保留模板自动渲染路径，跳过自绘 Loading。
python3 tools/export_wechat.py --diagnostics --android-render-probe B

# 当前交付 D：同样跳过自绘 Loading，仅选择标准 WebGL2。
python3 tools/export_wechat.py --diagnostics --android-render-probe D
```

B `20260929-103149` 与 D `20260929-103330` 的 PCK 均为 5,433,028 字节，SHA-256 均为 `952c875f385f89278d3dd782a8246c31cbcbbf4ed27ad7437785e7013d1bb203`；构建清单和校验记录位于 `build/previews/2026-09-29/android-reentry/`。D 包保持 iOS 轻量 Loading 与原渲染路径，未启用 iOS WASM、主画布 DPR 或限帧实验。

## 手机验收

1. **先测 D 包**：重新生成预览二维码并扫码，核对日志构建号、`effective=D`、实际 `renderPath=WebGL2`、`startup_minimal=false`。仅看到 D 配置而实际仍是 WXGLX，不能算有效对照。
2. 首页停留超过 120 秒，再退出小游戏、从微信最近使用进入。查看首页按钮底板、设置／游戏圈底板、关卡卡片、暂停面板和半透明遮罩。重复 10 次，包括短暂切后台与完全重新启动；记录实例 ID 是否变化。
3. 同一实例恢复应依次看到微信 show、Godot 窗口焦点回执、`resume:first-frame`，`resumeFrameElapsedMs` 有值。新实例应有新的 `[BBQ instance]` 和正常启动标记。对局回前台保持暂停、点击继续后倒计时和声音恢复。
4. 收集原始 vConsole，检查 `WAPixi`／`vertex_attrib`，不只看汇总计数。记录可操作时间、卡顿和发热，首页／对局各持续运行 10 分钟。iPhone 16 Pro 做启动与前后台回归；12 Mini 当前只记录结果。

用户已确认 D 恢复完整 UI，并已设为普通导出默认。若后续设备仍复现，可在诊断包仅加 `--no-android-native-loading` 做单项对照，或分别用 B／D 加 `--startup-minimal` 检查缺失图元；不要同时改材质、DPR、资源加载和引擎版本。最小场景测试完成后恢复完整游戏包。

本机检查详见 `docs/verification.md` 同日记录。OPPO 用户复测已通过 UI 显示与存档冷启动；其他安卓机型兼容性和新版正式包的入口回归仍待验证。
