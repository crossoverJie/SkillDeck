# 三栏宽度限制与侧栏工具栏溢出修复（已实现）

**Goal:** 解决三个相关问题：(1) 中间 skill 列表列被硬性封顶在 450pt，用户无法拖宽，导致长 skill 名折成两行；(2) skill 行右侧的 Agent 图标簇无上限，进一步挤占标题宽度；(3) 左侧导航列封顶 300pt，导致侧栏工具栏的「刷新技能」按钮被永久收进系统溢出菜单（chevron）。

**Architecture:** 纯 SwiftUI 布局层修复，不涉及 Service / Model / 文件系统语义。三处改动：`ContentView` 的两个 `navigationSplitViewColumnWidth`、`SkillRowView` 的标题行与图标簇、`SidebarView` 的工具栏项（4 个图标按钮合并成 1 个 split 按钮）。

**Tech Stack:** Swift 5.9、SwiftUI（macOS 14+）、`NavigationSplitView`、`navigationSplitViewColumnWidth`、`Menu(primaryAction:)`、AppKit Accessibility（仅用于验证时读取运行时几何）。

> **范围说明:** 只调整布局与工具栏组织方式。不改 `SkillManager` 的刷新/检查/批量更新 API，不改 Registry / ClawHub 两个面板的列宽（`min: 300, ideal: 400, max: 600` 保持不变），不引入新的窗口尺寸持久化逻辑。

---

## 1. 已确认的问题

所有结论都做了运行时实测（`swift build` 后启动 debug 实例，用 AppleScript + Accessibility API 读取工具栏元素的真实 `position` / `size` 与分栏宽度），不是纯静态推断。

> **测量前提（踩过的坑）:** 机器上同时跑着 `/Applications/SkillDeck.app` 和 `.build/debug/SkillDeck` 两个同名进程时，`first process whose unix id is X` 会读到错误的那一个，两次 dump 的结果完全相同。测量前必须先退出 `/Applications` 实例，只保留一个 `SkillDeck` 进程。

### 1.1 中间 skill 列表被硬性封顶 450pt

`Sources/SkillDeck/Views/ContentView.swift`

```swift
.navigationSplitViewColumnWidth(min: 250, ideal: 320, max: 450)   // 改动前
```

`defaults read com.github.skilldeck` 中 `NSSplitView Subview Frames ... SidebarNavigationSplitView` 的多条历史记录里，中间列宽度几乎每次都正好是 **450**，即用户每次都拖到上限后再也拖不动。

### 1.2 行内布局会二次放大「窄」的问题

`Sources/SkillDeck/Views/Dashboard/SkillRowView.swift`

```swift
Text(skill.displayName).appFont(.headline)   // 改动前：无 lineLimit，可无限换行
```

同一 `HStack` 尾部的图标簇是 `ForEach(skill.installations)` 全量渲染；`AgentType` 现有 14 个 case，即最多 14 个图标 × 约 17pt ≈ **240pt**。所以即使列宽 450，长名也可能只剩几十 pt，必然折成两行。只放宽列宽无法解决这一半问题。

### 1.3 侧栏工具栏溢出与「侧栏列宽」绑定（不是窗口宽度）

侧栏的 `ToolbarItem` 排在**侧栏列那一条带子里**，可用带宽为：

```
sidebarWidth - ~117pt（交通灯与左侧留白） - ~47pt（折叠按钮） ≈ sidebarWidth - 151pt
```

改动前在 300pt 侧栏（当时的上限）实测的元素占位：

| 元素 | 宽度 | 备注 |
|---|---|---|
| `+` 安装 split menu | 57pt | 保留 |
| 检查更新 `arrow.triangle.2.circlepath` | 44pt | 一个图标 |
| 全部更新 `arrow.down.circle` | 44pt | 一个图标 |
| 系统「隐藏侧栏」折叠按钮 | 47pt | 固定在列右边界 |
| **刷新技能 `arrow.clockwise`** | 44pt | **永远放不下 → 进 overflow** |

算式：`117 + 57 + 44 + 44 + 47 + 44 = 353 > 300`。窗口拉到 2324pt 宽时依然出现 `more toolbar items`，证明这是列宽问题，加宽窗口无效。

### 1.4 附带发现：列宽约束只约束「拖拽」

把侧栏 `min` 临时改成 460 重新构建后，恢复的窗口仍然是 300pt；反向把中间列请求成 900pt，恢复后是 908pt（超过 `max: 720`）。说明 `navigationSplitViewColumnWidth` 的 min/max **只在用户拖拽时生效**，窗口状态恢复出来的宽度可以越界。因此工具栏项数必须按「最小宽度也能放下」来设计，不能靠 modifier 兜底。

---

## 2. 最终方案（已落地）

### P1 中间列：放开上限

`ContentView.swift`

```swift
.navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 720)
```

`min` 承担原注释的初衷（首次打开 / 窗口变窄时列表不被压瘪），`max` 从 450 提到 720：允许用户按需拉宽，同时保留上限防止右侧 Markdown 正文被挤到不可用（detail 面板本身没有最小宽度约束）。

### P2 行内布局：单行 + 截断 + 图标簇限流

`SkillRowView.swift` 标题行：

```swift
Text(skill.displayName)
    .appFont(.headline)
    .lineLimit(1)                 // 永不换行
    .truncationMode(.middle)      // 保留 "...-development" 这类尾部信息
    .help(skill.displayName)      // 悬停看完整名字
    .layoutPriority(1)            // 宽度不足时优先保名字
```

图标簇：`prefix(5)` + `+N` 计数，`+N` 的 tooltip 列出被折叠的 Agent（复用单个图标同一套文案逻辑：继承安装显示 `Copilot CLI (via ~/.claude/skills)`）。

### P3 侧栏工具栏：4 个图标 → 1 个 split 按钮 + 放宽列宽

`SidebarView.swift`：把「检查更新」「全部更新」「刷新」三个 `ToolbarItem` 合并为一个 `Menu`（带 `primaryAction`，与已有安装按钮同一套模式）：

- **主按钮（单击）= 刷新技能** —— 最高频动作仍是一键，不退化；
- **下拉菜单** = 刷新技能 / 检查更新 / 更新全部技能（各自的 disabled 条件原样保留）；
- **label 保留忙碌态**：检查更新中显示 `ProgressView + 3/12`，批量更新中显示 `ProgressView + 2/5`。

侧栏最终只有两个控件：`+` 安装 split（65pt）+ 同步 split（65pt）。实测 280pt 与 392pt 侧栏均**无 `more toolbar items` 溢出**。

`ContentView.swift` 侧栏宽度：

```swift
.navigationSplitViewColumnWidth(min: 280, ideal: 290, max: 400)
```

- `min` 从 180 → 280：180pt 时可用带宽只有 ~29pt，任何工具项都放不下，该下限无实际意义；两个 split 按钮需要 ~118pt，即侧栏至少 ~270pt。
- `max` 从 300 → 400：给未来的工具项留余量。

**为什么不用「保留刷新为独立按钮 + 合并另两个」**（最初的设计）：那需要 3 个控件（145pt），侧栏得 ≥ ~300pt 才能常显，且默认宽度下必然溢出。split 按钮方案在同等点击成本下把占用降到 118pt。

### 本地化

新增 4 个 key（`L10nKeys.swift` 定义并注册进 `allKeys`，两个 `Localizable.strings` 各加 4 条）：

| key | en | zh-Hans |
|---|---|---|
| `sidebar.menu.refreshSkills` | `Refresh Skills` | `刷新技能` |
| `sidebar.menu.checkAllUpdates` | `Check for Updates` | `检查更新` |
| `sidebar.menu.updateAllSkills` | `Update All Skills` | `更新全部技能` |
| `sidebar.help.syncMenu` | `Check for updates or update all skills` | `检查更新或更新全部技能` |

不复用 `sidebar.help.*` 文案：那些是完整句子，用作 tooltip；菜单行需要短动词短语。

---

## 3. 明确不做

- 不改 `SkillManager.checkAllUpdates` / `updateAllSkills` / `refresh` 的实现与调用时机。
- 不改 Registry / ClawHub 中间列宽。
- 不引入 `NSSplitView` autosave 的手动清理（恢复宽度可越界，但不影响功能，清理会丢用户偏好）。
- 不动 `SkillRowView` 第二、三行（description / author / version）。
- 不新增 UI 自动化测试（仓库无 UI 测试基建），改用手动 + Accessibility 脚本回归。
- 不改「有新版本」提醒按钮（`arrow.up.circle.fill`）：它是条件显示项，窄侧栏下可能进 overflow，但同一入口在设置页也有。

---

## 4. 改动文件

```text
CLAUDE.md                                              # 删除指向已不存在文件的引用
Sources/SkillDeck/Views/ContentView.swift               # 两个 navigationSplitViewColumnWidth
Sources/SkillDeck/Views/Dashboard/SkillRowView.swift    # 标题单行截断 + 图标簇限流 + 2 个 tooltip helper
Sources/SkillDeck/Views/Sidebar/SidebarView.swift       # 3 个 ToolbarItem → 1 个 split Menu + syncMenuLabel
Sources/SkillDeck/Utilities/Localization/L10nKeys.swift # 4 个新 key
Sources/SkillDeck/Resources/Localizations/{en,zh-Hans}.lproj/Localizable.strings  # 各 4 条
```

---

## 5. 验证记录

| 项 | 方法 | 结果 |
|---|---|---|
| 构建 | `swift build` | 通过 |
| 单测 | `swift test` | 334 tests, 0 failures |
| 侧栏 280pt（min） | Accessibility 读工具栏 | 无 `more toolbar items` |
| 侧栏 392pt（max 附近） | 同上 | 无 `more toolbar items` |
| 默认 1000×700 冷启动（清空 prefs） | 同上 | 无 `more toolbar items`，侧栏 2 个 split 按钮 + 折叠按钮 |
| 中间列宽度 | 直接改持久化分栏frame后重启 | 可到 908（> 旧 450），说明 450 封顶已解除 |
| 标题单行 / `+N` 图标 | 代码审阅（无 UI 测试基建，需人工目视） | 待人工确认 |

复现脚本思路：退出 `/Applications` 实例 → 启动 debug 实例 → 用 AppleScript 遍历 `toolbar 1` 的 `UI element`，检查是否存在 `description is "more toolbar items"`；用 `defaults write SkillDeck "<NSSplitView Subview Frames 键>" -array ...` 可在重启后强制指定起始列宽（debug 实例的偏好域是 `SkillDeck`，与正式包的 `com.github.skilldeck` 相互独立）。

---

## 6. 验收标准

1. 中间列可拖到 720pt；默认窗口首次打开仍是 `ideal: 380`。
2. 任意 skill 行标题**永远单行**，截断后 hover 显示完整名字；装了 14 个 Agent 的 skill 也不折行。
3. 侧栏 280–400pt 全区间无 `more toolbar items` 溢出；刷新、检查更新、更新全部技能都能触发，忙碌进度与 disabled 逻辑与改动前一致。
4. 中英文切换后新增菜单项文案正确。
5. `swift build` 与 `swift test` 通过。

## 7. 风险与回滚

| 风险 | 说明 | 缓解 |
|---|---|---|
| 侧栏最小宽度从 180 → 280 | 侧面空间变「胖」，1000pt 窗口下 detail 更窄 | 三个动作合并为一个 split 按钮换来的空间；用户可加宽窗口 |
| 「检查更新 / 全部更新」多一次点击 | 从独立按钮变为菜单行 | 刷新仍是一键（primaryAction） |
| 标题截断丢信息 | 长名只看得到首尾 | `truncationMode(.middle)` + `.help()` |
| 恢复宽度可越界 | 已在 1.4 实测 | 工具栏按「最小宽度可容纳」设计 |

回滚：三处改动彼此独立，可单独 revert；本地化新增 key 为纯增量。

## 8. 后续可选改进

- `Syncing`（检查更新）与 Dashboard 的「重新扫描 usage」共用 `arrow.triangle.2.circlepath`，同屏出现时易混淆，可换符号。
- Dashboard 中间列工具栏在 300pt 宽度下自身已接近溢出（排序菜单 + 语言菜单 + usage 刷新 + 搜索框），可参照本次思路做一次梳理。
