# 《烧烤消消消》V1 开发 Plan

> 用途：交给 Codex / AI Coding Agent 直接进入开发  
> 平台：微信小游戏  
> 版本：V1.0  
> 核心玩法参考：Grill Match - Food Sort Puzzle  
> 项目定位：中国烧烤主题、竖屏、轻量 Sort + Match-3 益智小游戏  
> 文档状态：V1 核心规则已确认；传送带等扩展机制放到 V2

---

## 0. 开发目标

V1 先验证最核心的玩法闭环：

**拖拽食材 → Move / Swap → 同烤架 3 个相同食材自动消除 → 烤架清空后补货 → 连续整理 → 倒计时内清空全部食材。**

V1 的重点不是堆系统，而是：

1. 操作手感清晰、顺滑；
2. Swap 对调必须可靠；
3. Match / Refill 节奏短、脆、快；
4. 支持多个烤架并行动画，不因一个烤架动画而锁死全盘；
5. 前 10 关能够形成完整的新手学习曲线；
6. 架构为 V2 的传送带、道具、广告复活预留扩展点。

---

# 1. V1 范围

## 1.1 V1 必须实现

- 微信小游戏竖屏
- 6 / 9 个固定烤架
- 每个烤架固定 3 个 Slot
- 单食材拖拽
- Move：拖到空 Slot
- Swap：拖到其他食材上进行位置对调
- 同一烤架 3 个相同食材自动 Match
- 一次 Swap 可同时触发两个烤架 Match
- 补货碟 Plate
- 每个 Plate 可包含 1 / 2 / 3 个食材
- 烤架完全清空时自动取下一 Plate
- 每次只补 1 个 Plate，不自动补满
- 只预览“下一碟”食材
- 多层 Plate Queue
- Combo / 连消反馈
- 倒计时
- 胜利 / 失败
- Lv.1～Lv.10
- 首页
- 关卡选择
- 暂停
- 胜利结算
- 失败结算
- 本地关卡进度
- 音效开关
- 震动开关预留

## 1.2 V1 明确不做

以下全部留到 V2 或后续：

- 传送带 / 移动烤架
- 道具
- 锁定格
- 冰冻格
- 特殊 Grill
- 商城
- 每日签到
- 抽奖
- 任务
- 图鉴
- 星级评价
- 随机关卡生成
- 中途运行状态存档
- 广告复活
- Banner 广告业务逻辑

> 代码层可以预留扩展接口，但 V1 不实现对应玩法。

---

# 2. 核心名词

| 名称 | 含义 |
|---|---|
| Food | 单个可操作烧烤食材 |
| Slot | 烤架上的一个食材位置 |
| Grill | 一个 3 Slot 烤架 |
| Plate | 烤架下方的一次补货碟 |
| PlateQueue | 某个 Grill 后续所有 Plate |
| Move | Food 从 Source Slot 移动到空 Target Slot |
| Swap | 两个不同 Grill 上的 Food 交换位置 |
| Match | 某 Grill 的 3 Slot 为同一 FoodType 时三消 |
| Refill | Grill 清空后，从 PlateQueue 取出下一碟 |
| Resolve | 一次操作后进行 Match / Clear / Refill / Chain 检查 |
| Combo | 规定时间内连续发生 Match 的计数 |

---

# 3. 食材体系

V1 前 10 关使用 8 种食材。

| ID | 食材 | 首次出现 |
|---|---|---:|
| `L` | 羊肉串 | Lv.1 |
| `C` | 玉米 | Lv.1 |
| `J` | 韭菜 | Lv.1 |
| `S` | 淀粉肠 | Lv.2 |
| `W` | 鸡翅 | Lv.4 |
| `M` | 香菇 | Lv.6 |
| `E` | 烤茄子 | Lv.8 |
| `O` | 生蚝 | Lv.9 |

视觉原则：

- 缩小到手机尺寸仍需一眼可辨；
- 不要把所有食物都烤成同一种棕红色；
- 强调轮廓和主色差异；
- V1 暂不同时放入过多外形相近的肉串。

后续可扩展：

- 五花肉
- 鱿鱼
- 大虾
- 烤面筋
- 青椒
- 扇贝
- 烤馒头片等

---

# 4. 棋盘规则

## 4.1 Grill

每个 Grill 固定：

```text
Slot0 | Slot1 | Slot2
```

最大容纳 3 个 Food。

一个关卡：

- Lv.1：6 个 Grill；
- Lv.2～Lv.10：标准 9 个 Grill；
- V1 不出现移动 Grill。

## 4.2 Food 数量约束

一关内：

```text
初始棋盘 Food
+
所有 Plate 内 Food
```

一起统计。

**每一种 FoodType 的总数量必须是 3 的倍数。**

例如：

```text
L × 9
C × 12
J × 6
```

合法。

这一规则必须由 LevelValidator 自动验证。

---

# 5. 玩家操作规则

## 5.1 一次只能操作 1 个 Food

不支持：

- 一次移动连续同类；
- 一次抓多串；
- 整个 Grill 搬动。

## 5.2 Move

Food 拖到另一个 Grill 的空 Slot：

```text
Source: [🌽][🍖][_]
Target: [🌿][_][_]

拖动 🌽 →

Source: [_][🍖][_]
Target: [🌿][🌽][_]
```

## 5.3 Swap

Food 拖到另一个 Grill 的已有 Food 上：

```text
A: [🌽][🍖][🌿]
B: [🍆][🌽][🌽]

把 A 的 🍖 拖到 B 的 🍆：

A: [🌽][🍆][🌿]
B: [🍖][🌽][🌽]
```

**即使 Target Grill 还有其他空 Slot，只要玩家明确落在某个 Food 上，仍执行 Swap。**

## 5.4 同 Grill 内不允许 Swap

若：

```text
sourceGrillId === targetGrillId
```

则 Cancel。

原因：

- 同 Grill 内重新排序不影响 Match；
- 减少误操作；
- 简化交互与逻辑。

## 5.5 无效 Drop

以下情况 Cancel：

- 放到棋盘空白；
- 放到 UI；
- 放到无效区域；
- 放到正在锁定的 Grill；
- 放回同 Grill；
- Drop 时目标已因并行动画发生变化。

Cancel 后 Food 回弹原位。

---

# 6. Drag 事务规则

这是实现时必须遵守的关键点。

玩家抓起 Food 时：

```text
InteractionState = DRAGGING
```

但 **不要立即修改棋盘逻辑数据**。

原 Slot 在逻辑上保持占用，并进入：

```text
reserved
```

只有 Drop 成功后，才一次性 Commit：

```text
Move / Swap transaction
```

这样可以避免：

- 拿起某 Grill 最后一串时误触发 Refill；
- 拖拽取消后状态难恢复；
- 暂停 / 超时过程中产生半完成状态。

---

# 7. Drop 命中规则

建议使用宽松触控。

优先级：

1. Pointer 明确落在 Food HitArea → Swap；
2. Pointer 落在空 Slot HitArea → Move；
3. Pointer 落在 Grill 内 Slot 间隙 → 选择最近的合法 Slot；
4. 没有合法 Target → Cancel。

建议：

- Slot 视觉尺寸与逻辑 HitArea 分离；
- HitArea 可以略大于食材；
- 不要求用户精确点击串本体。

---

# 8. Match 规则

某 Grill 满足：

```text
slot0 != null
slot1 != null
slot2 != null

slot0.foodType === slot1.foodType
slot1.foodType === slot2.foodType
```

立即触发 Match。

不需要玩家二次确认。

一次 Move / Swap Commit 后：

**同时检查 Source Grill 与 Target Grill。**

结果可能是：

| Source | Target | 结果 |
|---|---|---|
| 无 Match | 无 Match | 正常结束 |
| Match | 无 Match | 单消 |
| 无 Match | Match | 单消 |
| Match | Match | 双重消除 |

双消必须同时开始，不要 A 播完再播 B。

---

# 9. 空 Grill 与 Refill

## 9.1 触发条件

只要一个 Grill 从非空变成：

```text
[_, _, _]
```

就进入 Empty 检查。

触发来源可能是：

### A. Match 清空

```text
[🌽, 🌽, 🌽]
↓
Match
↓
[_, _, _]
```

### B. 玩家主动搬空

```text
[🌽, _, _]
↓ Move
[_, _, _]
```

两种情况都必须触发 Refill。

## 9.2 Plate 数量

每个 Plate 可以包含：

```text
1 个 Food
2 个 Food
3 个 Food
```

例如：

```text
P1: [C]
P2: [J, L]
P3: [S, C, W]
```

## 9.3 每次只能补一碟

例如：

```text
Grill: [_, _, _]
P1: [C, L]
P2: [J]
```

触发 Refill 后：

```text
Grill: [C, _, L]
P2: [J]
```

到此结束。

**不能因为还有空 Slot，就继续自动取 P2。**

只有 Grill 以后再次完全清空，才取 P2。

## 9.4 Plate 初始 Slot 布局

1 个：

```text
[_, C, _]
```

2 个：

```text
[C, _, L]
```

3 个：

```text
[C, L, J]
```

该规则只用于刚 Refill 时。

玩家后续 Move / Swap 后，不自动重新居中。

## 9.5 多层 Plate 显示

玩家只看到：

- 当前下一碟的具体食材；
- 下方仍有更多 Plate 时，用叠盘视觉表示“还有后续”。

不要直接把后续所有 FoodType 都展示出来。

---

# 10. Refill 后自动 Match

Refill 完成后重新检测当前 Grill。

如果：

```text
[C, C, C]
```

则等待短暂可读停顿后：

```text
Refill
→ Match
→ Clear
→ Refill ...
```

允许形成自动 Chain。

前 10 关关卡配置尽量避免直接使用“三个完全相同 Food 的 Plate”，但状态机必须支持。

---

# 11. 胜负条件

## 11.1 胜利

必须同时满足：

```text
所有 Grill 的所有 Slot 都为空
AND
所有 Grill 的 PlateQueue 都为空
```

才进入：

```text
GameState = WIN
```

不要只依赖 UI 进度数字。

## 11.2 失败

```text
remainingTime <= 0
```

立即：

```text
Cancel current drag
GameState = FAIL
```

不允许“最后一拖”继续结算。

V1 不设置“无路可走失败”，因为自由 Swap 允许继续整理。

---

# 12. 三消进度

HUD：

```text
8 / 15
```

含义：

```text
已完成 Match 组数 / 本关总 Match 组数
```

总组数：

```text
totalFoodCount / 3
```

每消除一组：

```text
+1
```

双消：

```text
+2
```

显示动画：

```text
8 → 9 → 10
```

不要直接 8 → 10。

---

# 13. Combo

定义：

**距离上一次 Match 不超过 2 秒，新 Match 延续 Combo。**

示例：

```text
Match
1.2s
Match → 连消 ×2
1.5s
Match → 连消 ×3
```

超过 2 秒无 Match：

```text
combo = 0
```

一次 Swap 同时触发两个 Match：

```text
直接按 2 个 Match Event 计数
```

可显示：

```text
双重消除！
连消 ×2
```

V1 Combo：

- 只做视觉 / 音效反馈；
- 不加时间；
- 不影响胜负；
- 不做分数系统。

---

# 14. 三层状态机

不要把所有动画状态都塞到 GameState。

## 14.1 GameState

```text
INIT
TUTORIAL
PLAYING
PAUSED
WIN
FAIL
```

## 14.2 InteractionState

```text
IDLE
DRAGGING
COMMITTING
CANCELING
```

## 14.3 每个 Grill 独立 GrillState

```text
STABLE
MATCHING
CLEARING
EMPTY
REFILLING
```

基本流：

```text
STABLE
↓
MATCHING
↓
CLEARING
↓
EMPTY
├─ 无 Plate → STABLE
└─ 有 Plate → REFILLING → STABLE / MATCHING
```

---

# 15. 并行 Resolve 原则

**只锁正在动画中的 Grill，不锁整个棋盘。**

例如 G1 正在 Match：

- 不能从 G1 拿 Food；
- 不能往 G1 放 Food；
- G2～G9 继续可操作。

因此多个 Grill 可以：

```text
G1: MATCHING
G2: REFILLING
G3: STABLE
G4: DRAGGING Target
```

同时存在。

这是 V1 手感的关键要求。

---

# 16. 一次 Move 可能同时触发多个结果

例如：

```text
A: [C, _, _]
B: [C, C, _]
```

A 的 C → B：

```text
A: [_, _, _]
B: [C, C, C]
```

需要并行：

```text
A → EMPTY → REFILL
B → MATCH → CLEAR → REFILL
```

不能全局串行排队。

---

# 17. 动画与反馈参数

V1 总原则：

**短、脆、快。**

| 动作 | 建议时长 |
|---|---:|
| Food 拿起 | 80ms |
| Move | 120～160ms |
| Swap | 160～220ms |
| Cancel 回弹 | 140～180ms |
| Match 预亮 | 60～80ms |
| Match 主动画 | 220～300ms |
| Refill | 250～350ms |
| Combo 文案 | 400～600ms |
| Win 过渡 | 600～900ms |

---

# 18. 拿起与 Drag 反馈

按下 Food：

```text
scale 1.00 → 1.08
```

同时：

- 提高 zIndex；
- 增加轻微阴影；
- 可加轻描边；
- Origin Slot 显示淡占位影子；
- 食材视觉位置建议高于手指中心 15～25px，避免手指遮挡。

Drag 本身实时跟手，不使用慢补间。

---

# 19. Hover 反馈

空 Slot：

- 轻微高亮；
- 表示松手将 Move。

Food：

```text
target scale 1.00 → 1.08
```

可加极轻微摆动，表示 Swap。

不要一直弹文字“移动 / 交换”。

---

# 20. Cancel 动画

无效 Drop：

```text
Food → Origin Slot
```

时长：

```text
140～180ms
```

建议轻微 EaseOutBack。

不要：

- 弹错误框；
- 屏幕闪红；
- 震屏；
- 显示“操作错误”。

---

# 21. Move 动画

Commit 后：

```text
Source → Target
```

120～160ms。

建议：

- 轻微弧线；
- 到达时 `1.00 → 1.05 → 1.00`；
- 动画结束后进入 Resolve。

---

# 22. Swap 动画

两个 Food 必须同时交换。

不要：

```text
A 先过去
B 再回来
```

建议：

```text
160～220ms
```

两条略微错开的弧线，避免完全重叠。

Swap 结束：

```text
约 60～80ms
```

后立即 Match Resolve。

---

# 23. Match 动画

建议：

```text
0ms      Match 成立
0～70ms  三个 Food 高亮 + scale 1.10
70～230ms 火星 / 炭火亮 / 滋滋效果
230～300ms scale → 0.2，alpha → 0
```

主题反馈应是：

- 炭火
- 火星
- 热气
- 烧烤“滋滋”感

不要做夸张炸弹爆炸。

---

# 24. 双重消除

如果 Source 与 Target 同时 Match：

- 两个 Grill 同时播放 Match；
- 中央短暂显示：

```text
双重消除！
```

- Combo 按 2 个 Match Event 计入。

不要串行播放两个 Match。

---

# 25. Refill 动画

流程：

```text
Plate 上浮
↓
Food 离开 Plate
↓
Food 同时飞入目标 Slot
↓
空 Plate 淡出
↓
下一 Plate 轻微上移
```

总时长：

```text
250～350ms
```

数量：

### 1 Food

```text
[_, C, _]
```

### 2 Food

```text
[C, _, L]
```

两串同时进入。

### 3 Food

```text
[C, L, J]
```

三串同时进入。

不要一个个慢慢排队飞入。

---

# 26. 音效

V1 最小音效集：

```text
food_pick
food_drop
food_swap
food_return
match
combo
refill
timer_warning
win
fail
```

优先打磨：

1. `match`
2. `refill`
3. `food_swap`

Match 建议体现：

```text
清脆反馈 + 轻微烧烤滋滋声
```

而不是纯电子三消音。

---

# 27. 震动

建议：

- Move：不震
- Swap：不震
- 普通 Match：可选轻震
- 双消：稍强
- Win / Fail：轻反馈

用户可以关闭。

若 V1 时间不足，震动可作为非阻塞项。

---

# 28. Timer

PLAYING 时 Timer 持续减少，包括：

- Dragging
- Matching
- Clearing
- Refilling

Timer 暂停：

- TUTORIAL
- PAUSED
- WIN
- FAIL
- 微信小游戏切后台

## 28.1 警告反馈

`00:30`：

- 时间颜色稍变暖。

`00:10`：

- 数字每秒轻微 Pulse；
- 可播放轻 tick。

最后 5 秒可加强一点，但不要全屏震动。

---

# 29. 暂停 / 切后台

点击暂停：

```text
Cancel current Drag
freeze timer
pause animations
GameState = PAUSED
```

暂停面板：

- 继续游戏
- 重新开始
- 返回首页
- 音效 ON / OFF
- 震动 ON / OFF

微信小游戏进入后台：

```text
Cancel Drag
Auto Pause
```

回前台后显示暂停面板。

**不要自动恢复倒计时。**

---

# 30. 页面流程

```text
Loading
↓
首页
↓
开始游戏 / 关卡选择
↓
必要时 Tutorial
↓
Game
├─ Pause
├─ Win → 下一关 / 再玩一次 / 首页
└─ Fail → 再试一次 / 首页
```

---

# 31. 首页

保持极简。

核心：

```text
《烧烤消消消》

[ 开始游戏 ]
[ 关卡选择 ]

右上：设置
```

开始游戏：

- 新用户 → Lv.1；
- 老用户 → 当前最高已解锁且未通关关卡；
- 全通时 → 可进入最高关或关卡选择。

---

# 32. 关卡选择

V1：

```text
1  2  3  4  5
6  7  8  9 10
```

状态：

- 已通关
- 当前可玩
- 未解锁

前一关通过 → 下一关解锁。

V1 不做 1～3 星。

---

# 33. 游戏 HUD

顶部推荐：

```text
[ LV.5 ]   [ ⏱ 01:36 ]   [ 8 / 15 ]   [ II ]
```

从左到右：

1. Level
2. Timer
3. Match Progress
4. Pause

Timer 视觉优先级最高。

---

# 34. 棋盘布局

Lv.1：

```text
G1 G2 G3
G4 G5 G6
```

Lv.2～Lv.10：

```text
G1 G2 G3
G4 G5 G6
G7 G8 G9
```

保持 3 列。

每个 Grill：

```text
Food Slot ×3
↓
Grill
↓
Next Plate Preview
```

Plate 必须与所属 Grill 水平对齐。

---

# 35. V1 底部区域

不放参考游戏中的 4 个锁定道具按钮。

底部保留合理安全空间，以后可扩展：

- 道具
- 广告
- 其他功能

但 V1 的棋盘逻辑不能依赖该区域存在。

---

# 36. 教学

V1 只做 3 次关键教学。

## Lv.1：Move + Match

暂停 Timer。

手指演示：

```text
C → [C, C, _]
```

提示：

```text
拖动食材，凑齐 3 个相同食材
```

玩家亲自完成后关闭教程并开始计时。

## Lv.2：Refill

第一次发生 Refill 时短提示：

```text
烤架清空后，下方食材会自动补上
```

约 1.2～1.5 秒后自动消失。

## Lv.3：Swap

构造：

```text
G1: [C, C, S]
G2: [S, S, C]
```

提示：

```text
拖到另一串食材上，可以交换位置
```

玩家完成 Swap 后结束教学。

Lv.4～Lv.10 不再弹教学。

---

# 37. Win 界面

所有 Resolve 稳定且 Victory Check 成立：

```text
最后 Match
↓
约 250ms
↓
火星 / 少量庆祝效果
↓
烧烤完成！
```

面板：

```text
烧烤完成！

第 5 关完成
用时 01:12

[ 下一关 ]
[ 再玩一次 ]
[ 返回首页 ]
```

“下一关”为主按钮。

Lv.10：

```text
全部通关！
```

不虚构 Lv.11，除非后续已实现。

---

# 38. Fail 界面

Timer：

```text
00:00
```

显示：

```text
时间到！

完成 12 / 15

[ 再试一次 ]
[ 返回首页 ]
```

V1 不实现“看广告 +30 秒”，但建议预留：

```ts
revive()
```

扩展点。

---

# 39. 本地存储

V1 只需保存：

```ts
highestUnlockedLevel
completedLevels
lastSelectedLevel
audioEnabled
vibrationEnabled
```

不保存：

- 当前棋盘状态
- 当前 PlateQueue 消耗进度
- 剩余时间
- Combo
- 半局游戏

退出中途关卡后，下次从该关重新开始。

---

# 40. 推荐数据结构

以下仅作为逻辑建议，可按现有项目技术栈调整。

```ts
type FoodType =
  | 'L'
  | 'C'
  | 'J'
  | 'S'
  | 'W'
  | 'M'
  | 'E'
  | 'O';

interface Food {
  id: string;
  type: FoodType;
}

interface Slot {
  index: 0 | 1 | 2;
  food: Food | null;
  reservedByDragId?: string;
}

interface PlateConfig {
  foods: FoodType[]; // length: 1..3
}

type GrillState =
  | 'STABLE'
  | 'MATCHING'
  | 'CLEARING'
  | 'EMPTY'
  | 'REFILLING';

interface GrillRuntime {
  id: string;
  slots: [Slot, Slot, Slot];
  plateQueue: PlateConfig[];
  state: GrillState;
  locked: boolean;
}

interface LevelConfig {
  level: number;
  timeLimitSec: number;
  grills: GrillConfig[];
  tutorial?: 'MOVE' | 'REFILL' | 'SWAP';
}

interface GrillConfig {
  id: string;
  initial: Array<FoodType | null>; // exactly 3
  plates: PlateConfig[];
}
```

---

# 41. 推荐关卡 JSON Schema 示例

```json
{
  "level": 3,
  "timeLimitSec": 100,
  "tutorial": "SWAP",
  "grills": [
    {
      "id": "G1",
      "initial": ["C", "C", "S"],
      "plates": []
    },
    {
      "id": "G2",
      "initial": ["S", "S", "C"],
      "plates": []
    },
    {
      "id": "G3",
      "initial": ["L", "L", "J"],
      "plates": [
        { "foods": ["L", "S"] }
      ]
    }
  ]
}
```

运行时不要直接修改原始 LevelConfig。

加载时：

```text
LevelConfig
↓ clone
LevelRuntime
```

---

# 42. LevelValidator

进入开发模式或载入关卡时验证：

1. Grill 数量是否合法；
2. 每个 Grill initial 必须恰好 3 Slot；
3. Plate foods 数量必须为 1～3；
4. FoodType 必须存在；
5. 每种 FoodType 总量必须 `% 3 === 0`；
6. `totalFoodCount % 3 === 0`；
7. `timeLimitSec > 0`；
8. 所有 ID 唯一；
9. 不能出现非法 Slot；
10. 计算并输出 `totalMatchGroups = totalFoodCount / 3`。

开发环境发现错误应直接报出关卡 ID 与具体字段。

---

# 43. 前 10 关总览

| Level | Grill | 食材种类 | 总 Food | Match 组数 | 时间 | 重点 |
|---|---:|---:|---:|---:|---:|---|
| 1 | 6 | 3 | 15 | 5 | 75s | Move + Match |
| 2 | 9 | 4 | 30 | 10 | 90s | Refill |
| 3 | 9 | 4 | 36 | 12 | 100s | Swap |
| 4 | 9 | 5 | 36 | 12 | 110s | 双消 |
| 5 | 9 | 5 | 45 | 15 | 120s | 多层补货 |
| 6 | 9 | 6 | 48 | 16 | 130s | 香菇 + Combo |
| 7 | 9 | 6 | 54 | 18 | 140s | Swap 强化 |
| 8 | 9 | 7 | 60 | 20 | 150s | 烤茄子 |
| 9 | 9 | 8 | 60 | 20 | 165s | 生蚝 + 8 食材 |
| 10 | 9 | 8 | 66 | 22 | 180s | 综合毕业关 |

时间为首轮测试值，实际 Demo 后再调。

---

# 44. Lv.1 配置

食材总量：

```text
L ×6
C ×6
J ×3
```

配置：

```text
G1: [C, C, _]
G2: [L, L, J]
G3: [L, C, J]

G4: [C, L, _]
G5: [L, C, J]
G6: [_, L, C]
```

无 Plate。

教学目标：

```text
G3 的 C → G1 空位
```

形成第一组三消。

---

# 45. Lv.2 配置

总量：

```text
L ×9
C ×9
J ×6
S ×6
```

```text
G1: [C, C, _]
    P1: [L, C]

G2: [L, L, J]

G3: [S, C, L]

G4: [J, S, _]
    P1: [L]

G5: [C, L, S]

G6: [L, J, C]

G7: [S, L, _]
    P1: [C, J, S]

G8: [J, C, L]

G9: [C, S, J]
```

第一次 Refill 时显示短教程。

---

# 46. Lv.3 配置

总量：

```text
L ×9
C ×9
J ×9
S ×9
```

```text
G1: [C, C, S]

G2: [S, S, C]

G3: [L, L, J]
    P1: [L, S]

G4: [J, J, L]

G5: [L, C, J]
    P1: [C, J]

G6: [S, C, L]

G7: [J, S, C]
    P1: [S]

G8: [L, J, S]
    P1: [L, C, J]

G9: [C, L, J]
    P1: [S]
```

教学：

```text
G1: [C, C, S]
G2: [S, S, C]
```

交换：

```text
G1 的 S ↔ G2 的 C
```

触发双消。

---

# 47. Lv.4 配置

总量：

```text
L ×9
C ×9
J ×6
S ×6
W ×6
```

```text
G1: [C, C, S]

G2: [S, S, C]

G3: [L, L, W]
    P1: [L, C]

G4: [W, W, L]
    P1: [C, J]

G5: [J, C, L]

G6: [W, J, C]
    P1: [L, W]

G7: [L, S, J]

G8: [C, L, W]
    P1: [C, J, S]

G9: [J, S, L]
```

目标：

- 不再手把手提示；
- 玩家主动发现 AAB + BBA；
- 第一次自己制造双消。

---

# 48. Lv.5 配置

总量：

```text
L ×9
C ×9
J ×9
S ×9
W ×9
```

```text
G1: [L, L, C]
    P1: [J, S]
    P2: [W]

G2: [C, C, J]
    P1: [L, C]
    P2: [J]

G3: [J, J, S]
    P1: [S, W]
    P2: [L]

G4: [S, S, W]
    P1: [C, J]
    P2: [S]

G5: [W, W, L]
    P1: [W, L]
    P2: [C]

G6: [L, C, J]
    P1: [J, S, W]

G7: [S, W, L]

G8: [C, J, S]

G9: [W, L, C]
```

重点验证：

```text
P1: [J, S]
```

补货后只能成为：

```text
[J, _, S]
```

不能顺带取 P2 填满。

---

# 49. Lv.6 配置

总量：

```text
L ×9
C ×9
J ×9
S ×9
W ×6
M ×6
```

```text
G1: [L, L, C]
    P1: [S, C]
    P2: [L]

G2: [C, C, J]
    P1: [J, S, W]

G3: [J, J, S]
    P1: [L, C]
    P2: [M]

G4: [S, S, W]
    P1: [J, S]
    P2: [C]

G5: [W, W, M]
    P1: [L, W]
    P2: [S]

G6: [M, M, L]
    P1: [C, J, M]

G7: [L, C, J]
    P1: [L, S, J]

G8: [S, W, M]

G9: [L, C, J]
```

新增香菇，不新增机制。

---

# 50. Lv.7 配置

总量：

```text
L ×9
C ×9
J ×9
S ×9
W ×9
M ×9
```

```text
G1: [C, C, S]
    P1: [S, W]
    P2: [M, L, C]

G2: [S, S, C]
    P1: [J, S]
    P2: [W, M]

G3: [W, W, M]
    P1: [L, C, J]
    P2: [S, W]

G4: [M, M, W]
    P1: [M, L]
    P2: [C, J, S]

G5: [L, L, J]
    P1: [W, M]
    P2: [L, C]

G6: [J, J, L]
    P1: [J, S, W]
    P2: [M]

G7: [L, C, J]

G8: [S, W, M]

G9: [L, C, J]
```

开局包含 3 组明显双消结构，强化 Swap 思维。

---

# 51. Lv.8 配置

总量：

```text
L ×9
C ×9
J ×9
S ×9
W ×9
M ×9
E ×6
```

```text
G1: [C, C, S]
    P1: [L, C]
    P2: [J]

G2: [S, S, C]
    P1: [L, S]
    P2: [C, J]

G3: [W, W, M]
    P1: [W, M, E]

G4: [M, M, W]
    P1: [L, C, J]

G5: [L, L, J]
    P1: [L, C, E]

G6: [J, J, L]
    P1: [J, S]
    P2: [S, W, M]

G7: [E, E, C]
    P1: [W, M]
    P2: [S, W, M]

G8: [L, J, E]
    P1: [L, C, J]

G9: [S, W, M]
    P1: [E]
    P2: [S, W, M]
```

重点使用 1 Food Plate：

```text
P1: [E]
→
[_, E, _]
```

---

# 52. Lv.9 配置

总量：

```text
L ×9
C ×9
J ×9
S ×9
W ×6
M ×6
E ×6
O ×6
```

```text
G1: [C, C, S]
    P1: [L, S]
    P2: [C, J]

G2: [S, S, C]
    P1: [S, W, M]
    P2: [E, O]

G3: [W, W, M]
    P1: [L, C, J]
    P2: [S]

G4: [M, M, W]
    P1: [L, W, E]
    P2: [C, O]

G5: [E, E, O]
    P1: [J, S, M]
    P2: [L, C]

G6: [O, O, E]
    P1: [E, O, S]
    P2: [J]

G7: [L, L, J]
    P1: [L, C, J]
    P2: [W, M]

G8: [J, J, L]
    P1: [S]

G9: [L, C, J]
```

从 7 种增加到 8 种，但总 Food 数保持 60，难度主要来自辨识与规划。

---

# 53. Lv.10 配置

总量：

```text
L ×9
C ×9
J ×9
S ×9
W ×9
M ×9
E ×6
O ×6
```

共：

```text
66 Food
22 Match Groups
180s
```

```text
G1: [L, L, C]
    P1: [L, C, J]
    P2: [S, E, O]

G2: [C, C, L]
    P1: [S, W, M]

G3: [J, J, S]
    P1: [L, S, W]
    P2: [W, E, O]

G4: [S, S, J]
    P1: [C, J, M]

G5: [W, W, M]
    P1: [L, C, S]
    P2: [M, E, O]

G6: [M, M, W]
    P1: [J, W, M]

G7: [E, E, O]
    P1: [L, S, M]

G8: [O, O, E]
    P1: [C, J, W]

G9: [L, C, J]
    P1: [L, S, W]
    P2: [C, J, M]
```

开局存在 4 套明显：

```text
AAB
BBA
```

让玩家前段连续爽消，随后 Plate 大量补入，进入完整整理阶段。

---

# 54. UI 图层建议

```text
Layer 5  Modal / Tutorial / Pause / Win / Fail
Layer 4  Combo / 双消 / 浮动反馈
Layer 3  Dragging Food
Layer 2  Normal Food / Plate Food
Layer 1  Grill / HUD
Layer 0  Background
```

Dragging Food 必须始终在最上层。

---

# 55. 美术方向

主题：

**中国夜市烧烤。**

背景建议：

- 暖色木桌；
- 夜市氛围；
- 远景灯笼 / 摊位虚化；
- 不要让背景复杂元素穿过棋盘。

核心要求：

**Food > Grill > Plate > Background**

食材永远是第一视觉焦点。

V1 的美术资产必须原创，不直接复制参考游戏素材。

---

# 56. 微信小游戏适配要求

- 竖屏优先；
- 适配不同手机长宽比；
- 考虑顶部安全区；
- HUD 不被刘海 / 状态区遮挡；
- 棋盘保持 3 列；
- 小屏优先缩小纵向间距，不优先把 Food 缩到难辨；
- 主要触摸目标建议约 44 CSS px 或等效小游戏逻辑触控尺寸以上；
- 微信切后台自动 Pause；
- 首屏资源控制体积；
- 非当前关卡资源可延迟加载；
- 尽量保持 60 FPS；
- Match / Refill 同时发生时避免大量临时对象和 GC 抖动。

---

# 57. 推荐模块拆分

建议按职责拆：

```text
GameApp
├─ SceneManager
├─ LevelManager
│  ├─ LevelLoader
│  └─ LevelValidator
├─ GameController
├─ TimerController
├─ ProgressController
├─ InteractionController
│  ├─ DragController
│  ├─ DropResolver
│  └─ SwapController
├─ BoardController
│  ├─ GrillController[]
│  ├─ MatchResolver
│  ├─ RefillResolver
│  └─ VictoryResolver
├─ ComboController
├─ TutorialController
├─ UIController
├─ AudioController
├─ HapticController
├─ StorageService
└─ AssetManager
```

原则：

- Level 数据与表现分离；
- Grill 自己管理自己的动画锁；
- GameController 不要成为“万能上帝类”；
- Resolve 逻辑和 View 动画分离；
- 核心规则尽量可单元测试。

---

# 58. 建议事件

可以使用事件总线或明确的 Controller 回调。

例如：

```text
FOOD_DRAG_START
FOOD_DRAG_CANCEL
MOVE_COMMITTED
SWAP_COMMITTED

MATCH_STARTED
MATCH_COMPLETED

GRILL_EMPTY
REFILL_STARTED
REFILL_COMPLETED

COMBO_CHANGED
PROGRESS_CHANGED
TIMER_WARNING

LEVEL_WIN
LEVEL_FAIL
```

注意：

**不要用 UI 动画完成事件作为唯一业务真相。**

业务状态先明确提交，再让 View 表现对应状态。

---

# 59. 并发与防竞态要求

需要重点测试：

1. G1 Match 时操作 G2；
2. G1 Refill 时 G2 Match；
3. 一个 Move 同时让 Source Empty + Target Match；
4. Swap 同时触发 Source + Target 双 Match；
5. Timer 归零时正在 Drag；
6. Timer 归零时 Match 动画刚开始；
7. 切后台时正在 Swap；
8. Pause 时正在 Refill；
9. Refill 后自动 Match；
10. 快速连续拖拽导致旧动画回调覆盖新状态。

建议每个 Grill 的异步动画使用当前 Resolve Token / Version，避免过期回调修改新状态。

---

# 60. 开发顺序

## Phase 1：纯逻辑原型

先不要追求美术。

完成：

- Food
- Slot
- Grill
- LevelLoader
- LevelValidator
- Move
- Swap
- Match
- Empty
- Refill
- Win
- Fail

使用简单色块 / Emoji 均可。

验收重点：

**规则完全正确。**

## Phase 2：Drag 手感

完成：

- Pointer / Touch Drag；
- Food 跟手；
- Hover；
- Drop；
- Move；
- Swap；
- Cancel；
- HitArea 宽容处理。

验收重点：

**Swap 必须顺。**

## Phase 3：并行状态机

完成：

- GrillState；
- Grill 局部 Lock；
- Match / Refill 并行；
- Source + Target 同时 Resolve；
- Auto Match Chain。

验收重点：

**一个 Grill 动画不能锁死其他 Grill。**

## Phase 4：动画与反馈

完成：

- Pick
- Move
- Swap
- Match
- Double Match
- Refill
- Combo
- Timer Warning
- Win / Fail

## Phase 5：关卡

导入 Lv.1～Lv.10。

加入：

- Lv.1 Move Tutorial；
- Lv.2 Refill Tutorial；
- Lv.3 Swap Tutorial。

## Phase 6：完整 UI

完成：

- Loading
- Home
- Level Select
- Game HUD
- Pause
- Win
- Fail
- Settings

## Phase 7：微信小游戏适配与 QA

完成：

- 屏幕适配
- 安全区
- 后台暂停
- 本地存储
- 音频恢复
- 性能
- 真机触摸体验

---

# 61. 首轮验收 Checklist

## 核心规则

- [ ] Grill 固定 3 Slot
- [ ] Food 可 Move
- [ ] Food 可跨 Grill Swap
- [ ] 同 Grill Swap 被拒绝
- [ ] 3 个相同 Food 自动 Match
- [ ] Source / Target 同时检测 Match
- [ ] 一次 Swap 可双消
- [ ] Grill 被主动搬空也会 Refill
- [ ] Plate 支持 1 / 2 / 3 Food
- [ ] 一次只补一个 Plate
- [ ] 1 Food 居中
- [ ] 2 Food 左右分布
- [ ] 3 Food 填满
- [ ] Refill 后支持自动 Match
- [ ] 多 Grill 可并行 Resolve

## 输入

- [ ] Drag 不提前修改棋盘数据
- [ ] Drop 成功才 Commit
- [ ] 无效 Drop 回弹
- [ ] Target Food → Swap
- [ ] Target Empty Slot → Move
- [ ] HitArea 手机端足够宽容
- [ ] 动画锁定 Grill 不接受 Drop

## Timer

- [ ] PLAYING 倒计时
- [ ] Tutorial 暂停
- [ ] Pause 暂停
- [ ] 后台暂停
- [ ] 归零立即 Fail
- [ ] 超时时取消 Drag

## 胜负

- [ ] 所有 Slot 空 + PlateQueue 空才 Win
- [ ] 进度数字正确
- [ ] 双消 +2
- [ ] 自动 Match 也计入进度

## 动画

- [ ] Move < 200ms 左右
- [ ] Swap 清楚可读
- [ ] Match 约 300ms
- [ ] Refill 约 300ms
- [ ] 双消同时播放
- [ ] 其他 Grill 在动画期间仍可操作
- [ ] Drag Food 始终位于顶层

## 关卡

- [ ] Lv.1～Lv.10 均通过 Validator
- [ ] 每种 Food 总量为 3 的倍数
- [ ] 每关可正常清空
- [ ] 教程不阻断正常玩法
- [ ] 时间值可从配置修改

---

# 62. V2 预留：传送带

V1 不实现，但设计时避免堵死扩展。

未来可增加：

```ts
interface ConveyorConfig {
  direction: 'LEFT_TO_RIGHT' | 'RIGHT_TO_LEFT';
  speed: number;
  loop: boolean;
}
```

传送烤架本质仍然复用普通 Grill：

- 3 Slot
- Move
- Swap
- Match
- Refill

只是 Grill 自身增加动态位置。

V2 首次出现建议放在约 Lv.6 或后续新章节，不在本 V1 的前 10 关中启用。

---

# 63. V2 其他可扩展点

可预留但不要提前实现：

- `revive(+30s)`：广告复活
- Hint
- 临时盘 / Storage
- Freeze
- Shuffle
- 特殊 Grill
- 连锁奖励
- 更多中国烧烤食材
- 烧烤图鉴
- 更多关卡
- 传送带
- 每日挑战

---

# 64. Codex 开发约束

Codex 开发时请优先遵循：

1. **不要自行修改本 Plan 已锁定的玩法规则。**
2. 如果现有项目已有技术栈 / 目录规范，优先复用现有架构。
3. 先完成可玩的逻辑原型，再做完整视觉。
4. 每一个规则都尽量数据驱动，不要硬编码到关卡逻辑。
5. 前 10 关使用固定 JSON 配置，不做随机生成。
6. 业务逻辑与动画表现分离。
7. 不要因 Match / Refill 动画锁定整个棋盘。
8. Swap 是 V1 一级核心功能，必须重点测试。
9. Plate 必须支持 1～3 Food，不允许默认补满 3 格。
10. V1 不主动增加本 Plan 之外的玩法和系统。
11. 如果实现过程中发现规则冲突，先记录问题并停止对应扩展，不要自行猜测修改设计。

---

# 65. V1 完成定义

满足以下条件，可以认为《烧烤消消消》V1 MVP 完成：

> 玩家能从首页进入 Lv.1，理解 Move、Refill、Swap，在 6 / 9 个固定烤架上顺畅拖拽与交换，通过三同 Match 持续清空食材和 Plate，在倒计时内完成 Lv.1～Lv.10；Match / Refill 可并行执行，动画不阻塞全盘；暂停、失败、胜利、关卡解锁和本地进度工作正常，并能在微信小游戏真机环境稳定运行。

---

## 文档结论

V1 核心体验应始终围绕：

```text
观察
↓
找到 2 + 1
↓
Move / Swap
↓
Match
↓
释放 / 改变棋面
↓
Refill
↓
继续快速整理
```

其中最重要的三个手感点：

1. **Swap 对调必须自然；**
2. **Match / Refill 必须短、脆、快；**
3. **局部动画不能阻塞玩家操作其他 Grill。**

先把这三个点做好，再进入 V2。
