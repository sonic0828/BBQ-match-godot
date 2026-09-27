# 素材记录

- `assets/art/foods.png`：用户提供的图 3，透明食材 Sprite 原图。`FoodArt` 使用 AtlasTexture 区域取图；未重绘或改变食材原图。
- `assets/art/food-combo-sprite.png`：用户于 2026-09-26 提供的透明成盘图集，原样复制。`FoodArt.COMBO_REGIONS` 对应当前全部 8 种食材（L/C/J/S/W/M/E/O），共用一张纹理；成盘使用位移、缩放、透明度和程序绘制星芒，不使用逐帧图片序列。
- `assets/art/grill.png`：2026-09-26 更换为用户提供的带炭火 `kaolu.png`（1254×1254，1,160,868 字节）。按 `(61,258)-(1194,983)` 裁去外围留白，Lanczos 缩为 800×512 的透明 PNG，592,190 字节；Godot 使用有损纹理导入、质量 0.85，实际 `.ctex` 为 68,340 字节。首页约 470 逻辑像素宽、棋盘约 222 像素宽，共用这一张纹理。
- 用户图 1、图 2 作为风格与构图参考，未把带按钮的完整参考界面当作运行界面。
- `assets/art/night_market.png`：本次通过内置 imagegen 工具生成的背景，已复制进项目。
- `assets/fonts/game.ttf`：Noto Sans SC 650 字重的游戏字符子集，约 60 KB。源字体来自 [Google Fonts](https://github.com/google/fonts/tree/main/ofl/notosanssc)，OFL 许可位于同目录 `OFL.txt`。新增中文文案后需运行 `tools/build_font.py` 更新字集。
- `audio/*.wav`：2026-09-26 按用户选择的纯音效试听方向更新为 12 个原创合成音效，包含木质拿起／落位、移动气流、聚拢、滋啦与瓷盘成盘、逐串补位、连消奖励及结算。22.05 kHz 单声道，Godot QOA 压缩；未采样参考游戏音轨。
- `audio/night_market.ogg`：用户选择的 C「松弛夜市」方向，92 BPM 柔和旋律与轻节奏，约 41.74 秒完整乐句循环，22.05 kHz 双声道 Vorbis，190,522 字节。`tools/generate_audio.py` 可复现全部音频，依赖 NumPy 和 ffmpeg；Godot 正常导入与打包不需要这些生成依赖。
- `icon.svg`：本次制作的矢量串串图标。
- `assets/ui/*.svg`：按最新界面参考制作的矢量倒计时框、圆形暂停按钮和蓝色锁定功能位，随窗口缩放，未新增玩法或广告素材。
- `assets/ui/grill_lid.svg`：2026-09-27 制作的金属锅盖矢量图，铜色把手和食材标牌沿用夜市配色；标牌上的玉米直接复用食材图集。开盖用透明度变化，未打包动画帧序列。
- `audio/lid.wav`：2026-09-27 新增的第 13 个原创合成音效，0.36 秒轻金属敲击；22.05 kHz 单声道、QOA 导入。可通过 `tools/generate_audio.py` 的 `render_lid()` 单独复现，不需要重新生成音乐或其他音效。

## 背景生成记录

模式：内置 image_gen（未使用 CLI 或外部 API 密钥）。

最终文件：`assets/art/night_market.png`。

完整提示词：

> Use case: stylized-concept. Asset type: vertical mobile game background, 1024x1536. Create a polished richly rendered 3D illustrated Chinese night-market barbecue stall background for a cozy food sorting puzzle game. Warm glowing red lantern strings against indigo night sky, small traditional wood food stalls at left and right and a softly blurred lively alley in the distance. Composition is critical: only the TOP 28% contains the market skyline and lanterns, the LOWER 72% is a very large COMPLETELY EMPTY honey-brown wooden countertop seen at a steep nearly top-down angle, extending past every edge, with subtle vertical woodgrain planks and warm amber light. The table must be uninterrupted and simple so separate grill sprites can be placed on it. Gentle darker vignette at bottom edges. Beautiful warm amber / burnt orange / dark teal palette, painterly premium casual mobile game aesthetic. No food, no skewers, no plates, no grills, no UI, no buttons, no readable text, no logos, no characters in foreground. This is background art only, not a UI mockup.

## 2026-09-28 打包袋

- `assets/art/takeaway-bag.png`：使用内置 imagegen，按用户最终设计稿提取／重绘为透明纸袋，供道具按钮、弹层和打包动画共用。保持红色烤串标识、烧烤文字、牛皮纸与棋盘格纸袋。原图约 1.3 MB，Godot 导入限制长边 512、0.85 有损质量，实际纹理约 37 KB，保留透明边缘。
- `assets/ui/bag_panel.svg`、`bag_slot.svg`、`bag_green.svg`、`bag_orange.svg`、`coin.svg`、`video.svg`：沿用项目 SVG 资源方式，按设计稿还原蓝金面板、奶油色光芒展示区、绿色兑换按钮、橙色广告按钮。文字、计数和命中区域由 Godot 独立绘制。
- `audio/bag.wav`：原创纸袋折叠沙沙声，0.95 秒／22050 Hz／单声道，生成方法在 `tools/generate_audio.py::render_bag()`；未采样参考游戏声音。
- 图像生成提示词（内置工具）：`Use case: background-extraction. Extract and faithfully recreate ONLY the kraft paper barbecue takeaway bag in the cream display area of the reference as one isolated mobile game sprite, transparent alpha background. Preserve its warm tan paper texture, open top, three-quarter view with left side visible, red skewer emblem, red lower band, cream Chinese text 烧烤 and red/tan checkerboard bottom. Remove the surrounding UI, ×1 label, rays, sparkles, shadows outside the bag, all buttons and background. Bag fully visible, centered with small padding; crisp polished hand-painted casual mobile game artwork matching reference. One bag only. Output intended for both a small powerup icon and a 260px tall animation sprite.`
