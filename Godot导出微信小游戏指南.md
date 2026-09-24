# Godot 项目导出为微信小游戏版本指南

Godot 项目可以导出到微信小游戏，但通常需要：

**Godot 项目 → 微信小游戏适配插件 → 导出小游戏工程 → 微信开发者工具 → 手机测试**

Godot 官方的 Web 导出主要面向浏览器，并不能直接在导出菜单中选择“微信小游戏”。因此，需要借助第三方适配插件和对应版本的小游戏导出模板。

> 对于以 2D 为主的小游戏项目，建议使用 **Compatibility（兼容）渲染器**。

---

## 一、先确认项目是否符合基础条件

下面按 **Godot 4 项目**说明。

| 项目 | 建议或限制 |
|---|---|
| 渲染器 | 使用 **Compatibility**。Godot 4 的 Web 导出不支持 Forward+ 和 Mobile。 |
| 脚本语言 | 优先使用 **GDScript**。Godot 4 的 C# 项目目前不能通过官方 Web 路线直接导出。 |
| 线程设置 | 首次验证建议使用单线程；涉及 Web 导出时，可先关闭 `Thread Support`。 |
| 原生扩展 | 如果使用 C++ / Rust 等 GDExtension，需要额外确认扩展是否支持目标环境。 |

建议：

> **先不要为了导出随意升级或降级 Godot。应先确认当前 Godot 版本，再寻找与之匹配的小游戏导出模板。**

参考：

- Godot Web 导出文档  
  https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html

---

## 二、目前可以优先验证的小游戏适配插件

### 方案：`godothub/godot-minigame`

这是一个第三方 Godot 小游戏导出插件。

项目地址：

https://github.com/godothub/godot-minigame

它主要提供：

- 小游戏模板版本匹配
- 模板下载
- 模板缓存
- 小游戏工程导出

目前项目主要面向较新的 **Godot 4.x** 版本。

> 注意：  
> “有对应模板”不代表整个项目一定兼容。首次验证应尽量选择 **Godot 引擎版本与模板版本明确对应** 的组合。

---

## 三、不建议优先使用的旧方案

网上很多旧教程会提到：

`godot-love-wechat`

项目地址：

https://github.com/yuchenyang1994/godot-love-wechat

这个项目已经停止维护，主要面向较老版本的 Godot。

如果当前主要使用：

- macOS
- 新版 Godot 4.x
- 微信小游戏
- 抖音小游戏
- TapTap 小游戏

则不建议把它作为新项目的首选方案。

---

# 四、推荐的实际导出流程

## 第 1 步：先复制项目，做一个最小测试工程

不要一开始直接拿完整游戏做兼容性排查。

建议复制当前项目，只保留：

- 一个场景
- 一个按钮
- 一张图片
- 一段音效
- 一次本地存档

例如：

```text
MiniGameExportTest/
├── project.godot
├── main.tscn
├── main.gd
├── icon.png
└── test_audio.mp3
```

这个最小测试工程主要验证：

1. 游戏能否启动
2. 2D 是否正常渲染
3. 点击 / 触摸是否正常
4. 音效是否正常
5. 存档是否正常
6. 手机端是否能够正常运行

---

## 第 2 步：安装小游戏导出插件

一般将插件放到：

```text
你的Godot项目/
├── project.godot
├── addons/
│   └── godot-minigame/
└── 其他游戏文件
```

也就是：

```text
res://addons/godot-minigame/
```

然后在 Godot 中进入：

```text
项目
→ 项目设置
→ 插件
```

启用对应插件。

---

## 第 3 步：Mac 用户注意插件编译版本

如果使用 macOS，需要确认下载的是：

**可以在 macOS 上直接运行的插件版本**

而不是只有源码。

如果仓库中只有源码，则需要按照项目说明自行构建。

该项目中提供了类似：

```text
build_osx.sh
```

这样的 macOS 构建脚本。

所以需要特别注意：

> 下载源码 ZIP ≠ 已经安装了可运行插件。

---

## 第 4 步：下载与你 Godot 版本匹配的小游戏模板

插件通常会通过版本配置寻找对应小游戏模板。

例如可能存在：

```text
Godot 4.5.x
Godot 4.6.x
Godot 4.7.x
```

对应的模板。

首次验证建议：

```text
Godot版本
      ↓
找到完全匹配模板
      ↓
小游戏导出
```

尽量避免：

```text
Godot 4.7
      ↓
拿 Godot 4.5 模板强行导出
```

因为即使能够导出，也可能出现：

- WASM 加载失败
- API 不兼容
- 渲染异常
- 输入异常
- iOS 无法运行
- 真机崩溃

---

# 五、通过插件导出微信小游戏工程

通过小游戏插件执行导出。

建议将输出目录单独设置，例如：

```text
build/wechat/
```

最终应该得到一个：

**微信小游戏工程**

而不是一个普通 Web 网站。

---

## 普通 Web 导出与微信小游戏导出的区别

普通 Godot Web 导出通常类似：

```text
index.html
game.wasm
game.pck
game.js
```

但微信小游戏需要额外的：

```text
game.js
game.json
project.config.json
小游戏适配代码
Godot Runtime
游戏资源
```

所以不能简单地：

```text
Godot Web Export
        ↓
把 index.html 拖进微信开发者工具
```

正确逻辑应该是：

```text
Godot
 ↓
Web / WASM Runtime
 ↓
微信小游戏适配层
 ↓
微信小游戏工程
```

---

# 六、导入微信开发者工具

打开：

**微信开发者工具**

选择：

```text
导入项目
```

然后选择刚刚生成的：

```text
build/wechat/
```

填写自己的：

```text
微信小游戏 AppID
```

同时确认项目被识别成：

```text
小游戏
```

而不是：

```text
普通小程序
```

---

# 七、第一轮真机测试建议

不要只在微信开发者工具模拟器里测试。

至少完成：

```text
启动
↓
点击 / 拖动
↓
播放音效
↓
保存游戏
↓
退出小游戏
↓
重新进入
↓
恢复游戏
↓
切后台
↓
重新回到游戏
```

---

## 推荐验证项目

### 1. 启动

检查：

- 黑屏
- 白屏
- WASM 报错
- PCK 加载失败
- 首屏加载过慢

---

### 2. UI

检查：

- 分辨率
- Safe Area
- 刘海屏
- 全面屏
- 横竖屏
- Canvas 缩放

---

### 3. 输入

检查：

- 单击
- 多点触控
- 拖动
- 长按

---

### 4. 音频

检查：

- BGM
- 音效
- 切后台暂停
- 返回游戏恢复

尤其注意 iOS 的音频播放限制。

---

### 5. 存档

测试：

```text
保存
↓
关闭小游戏
↓
微信退出
↓
重新进入
↓
读取存档
```

不能只测试 Godot 编辑器中的本地存档。

---

# 八、微信平台功能需要单独适配

即使 Godot 游戏已经能跑：

**微信平台能力仍然需要单独接入。**

例如：

| 功能 | 是否需要适配 |
|---|---|
| 游戏运行 | 是 |
| 分享 | 是 |
| 激励视频广告 | 是 |
| Banner 广告 | 是 |
| 插屏广告 | 是 |
| 微信登录 | 是 |
| 云存档 | 是 |
| 开放数据域 | 是 |
| 排行榜 | 是 |
| 游戏圈 | 是 |
| 支付 | 是 |
| 生命周期 | 是 |

---

# 九、建议建立统一的平台适配层

不要在每个场景中直接调用微信 API。

建议建立统一模块，例如：

```text
PlatformManager.gd
```

或者：

```text
WeChatPlatform.gd
```

结构可以设计成：

```gdscript
class_name PlatformManager

func init():
    pass

func show_share_menu():
    pass

func share_game():
    pass

func show_rewarded_ad():
    pass

func save_data():
    pass

func load_data():
    pass
```

最终让游戏逻辑保持：

```text
游戏逻辑
   ↓
PlatformManager
   ↓
微信 / 抖音 / TapTap API
```

而不是：

```text
游戏逻辑
 ├─ wx.xxx
 ├─ tt.xxx
 ├─ TapTap.xxx
 └─ 平台判断代码
```

---

# 十、如果以后还要同时发布微信 + 抖音 + TapTap

对于多平台小游戏项目，建议从一开始就做平台抽象。

例如：

```text
Godot 游戏
      │
      ▼
PlatformManager
      │
 ┌────┼─────┐
 ▼    ▼     ▼
微信  抖音  TapTap
```

这样核心玩法代码完全不关心：

```text
wx
tt
TapTap
```

只调用：

```gdscript
PlatformManager.show_rewarded_ad()
PlatformManager.share_game()
PlatformManager.save_data()
```

---

# 十一、建议的目录结构

```text
res://

├── game/
│   ├── scenes/
│   ├── scripts/
│   ├── ui/
│   └── resources/
│
├── platform/
│   ├── platform_manager.gd
│   ├── platform_web.gd
│   ├── platform_wechat.gd
│   ├── platform_douyin.gd
│   └── platform_taptap.gd
│
├── addons/
│   └── godot-minigame/
│
└── project.godot
```

以后切平台时：

```text
Godot核心游戏逻辑
       ↓
只替换 platform/
```

而不是重写游戏。

---

# 十二、小游戏特别需要关注包体

Godot 导出小游戏后，主要体积通常来自：

```text
Godot Runtime / WASM
+
PCK
+
贴图
+
音频
+
字体
```

所以需要尽早关注：

- PNG / WebP 压缩
- 音频压缩
- 字体裁剪
- 无用资源清理
- 引擎模块裁剪
- 分包
- CDN / 远程资源

不要等游戏全部做完，再处理包体问题。

---

# 十三、推荐的项目推进顺序

不要：

```text
完整游戏开发
↓
最后一天才导出微信
```

建议：

```text
Godot 最小 Demo
      ↓
微信小游戏成功运行
      ↓
触摸输入
      ↓
音频
      ↓
存档
      ↓
分享
      ↓
广告
      ↓
完整游戏
```

也就是先验证：

> **Godot → 微信小游戏**

这条技术链路确实可行，再继续扩大项目规模。

---

# 十四、针对 2D 轻量小游戏的推荐方案

如果项目主要是类似：

- 小球分类
- 烧烤串串消
- 星港补给站
- Ball Sort
- 点击 / 拖动 / 排序类游戏

推荐组合：

```text
Godot 4.x
+
Compatibility Renderer
+
GDScript
+
小游戏导出适配插件
+
统一 PlatformManager
```

平台架构：

```text
                  ┌─ 微信小游戏
Godot Core ───────┼─ 抖音小游戏
                  ├─ TapTap
                  └─ Steam / Desktop
```

这套结构的核心价值是：

> **游戏只开发一次，平台能力分别适配。**

---

# 十五、第一阶段目标

第一阶段不要立即迁移完整游戏。

只需要实现：

```text
Godot Demo
   ↓
微信开发者工具
   ↓
手机扫码
   ↓
iPhone / Android 成功运行
```

并验证：

- 画面
- 输入
- 音效
- 存档
- 前后台切换

全部正常后，再逐步接入：

```text
分享
广告
游戏圈
排行榜
登录
```

---

# 参考资料

Godot 官方 Web 导出文档：

https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html

Godot 编辑器插件安装文档：

https://docs.godotengine.org/en/stable/tutorials/plugins/editor/installing_plugins.html

Godot Minigame：

https://github.com/godothub/godot-minigame

微信小游戏官方 Demo：

https://github.com/wechat-miniprogram/minigame-demo

微信小游戏 API Typings：

https://github.com/wechat-miniprogram/minigame-api-typings
