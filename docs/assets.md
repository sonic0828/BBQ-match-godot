# 素材记录

- `assets/art/foods.png`：用户提供的图 3，透明食材 Sprite 原图。`FoodArt` 使用 AtlasTexture 区域取图；未重绘或改变食材原图。
- `assets/art/grill.png`：用户提供的图 4，透明烤架原图。保留原图，通过 AtlasTexture 跳过外围留白。
- 用户图 1、图 2 作为风格与构图参考，未把带按钮的完整参考界面当作运行界面。
- `assets/art/night_market.png`：本次通过内置 imagegen 工具生成的背景，已复制进项目。
- `assets/fonts/game.ttf`：Noto Sans SC 650 字重的游戏字符子集，约 60 KB。源字体来自 [Google Fonts](https://github.com/google/fonts/tree/main/ofl/notosanssc)，OFL 许可位于同目录 `OFL.txt`。新增中文文案后需运行 `tools/build_font.py` 更新字集。
- `audio/*.wav`：本次以正弦音、包络和少量噪声合成的短反馈音效，共 10 个。当前为首版音效，未配背景音乐。
- `icon.svg`：本次制作的矢量串串图标。
- `assets/ui/*.svg`：按最新界面参考制作的矢量倒计时框、圆形暂停按钮和蓝色锁定功能位，随窗口缩放，未新增玩法或广告素材。

## 背景生成记录

模式：内置 image_gen（未使用 CLI 或外部 API 密钥）。

最终文件：`assets/art/night_market.png`。

完整提示词：

> Use case: stylized-concept. Asset type: vertical mobile game background, 1024x1536. Create a polished richly rendered 3D illustrated Chinese night-market barbecue stall background for a cozy food sorting puzzle game. Warm glowing red lantern strings against indigo night sky, small traditional wood food stalls at left and right and a softly blurred lively alley in the distance. Composition is critical: only the TOP 28% contains the market skyline and lanterns, the LOWER 72% is a very large COMPLETELY EMPTY honey-brown wooden countertop seen at a steep nearly top-down angle, extending past every edge, with subtle vertical woodgrain planks and warm amber light. The table must be uninterrupted and simple so separate grill sprites can be placed on it. Gentle darker vignette at bottom edges. Beautiful warm amber / burnt orange / dark teal palette, painterly premium casual mobile game aesthetic. No food, no skewers, no plates, no grills, no UI, no buttons, no readable text, no logos, no characters in foreground. This is background art only, not a UI mockup.
