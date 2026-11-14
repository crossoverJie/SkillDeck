# Dashboard 按来源仓库分组（默认分组视图）

**Goal:** Dashboard 列表默认按「技能来源仓库」分段（同一仓库安装的技能永远相邻，如 `crossoverJie/skills` 的 `agent-notifier` + `session-export`、`obra/superpowers` 的 `test-driven-development` + `writing-plans`），分段之间与分段内部仍由现有 4 种排序控制。现有「按名称 / Scope / Agent Count / usage Count 排序」的语义与测试完全不变。

**Architecture:** 纯 ViewModel + SwiftUI 展示层改动。分组是**排序之上的第二层**（orthogonal），不改 `SkillManager` / `SkillScanner` / 锁文件格式 / 文件系统语义。分组键来自已经存在于内存里的 `Skill.lockEntry`，**不新增后台扫描、不新增锁文件读取、不做路径 I/O**（分组只用 `String` 层面的归一化）。

**Tech Stack:** Swift 5.9、SwiftUI（macOS 14+）、`List(selection:)` + `Section`、`ForEach`、`@Observable`（`DashboardViewModel` 已是 `@MainActor @Observable`）。

> **范围说明:** 只影响 Dashboard 中间列。Registry / ClawHub 两个浏览器面板的列表与排序不动；Sidebar 不动；`filteredSkills` 的既有排序分支**一行不动**（只在它的结果上再切一次段）。

---

## 1. 现状

### 1.1 排序链路

`Sources/SkillDeck/ViewModels/DashboardViewModel.swift`

```swift
enum SortOrder: String, CaseIterable {
    case name = "Name"
    case scope = "Scope"
    case agent = "Agent Count"
    case usage = "Usage Count"
}

var sortOrder: SortOrder = .name
var sortDirection: SortDirection = .ascending

/// 搜索 → Agent 过滤 → 排序，一次算完
var filteredSkills: [Skill] { ... }
```

`Sources/SkillDeck/Views/Dashboard/DashboardView.swift` 直接把它铺平成一行一行的 `List`：

```swift
List(viewModel.filteredSkills, selection: $selectedSkillID) { skill in
    SkillRowView(...)
        .tag(skill.id)
        .contextMenu { /* 打开目录 / 禁用 / 删除 / 重装，约 50 行 */ }
}
.listStyle(.inset(alternatesRowBackgrounds: true))
```

排序菜单在中间列工具栏 `ToolbarItemGroup(placement: .navigation)` 里，`Section("Sort By")` + 4 个 `Button`，label 用 `order.rawValue`（**目前没有本地化**，见 P4）；工具栏按钮 label 用 `Text(viewModel.sortOrder.rawValue)`（`DashboardView.swift:169`）。

`DashboardView` **没有** `localized(_:)` 这个私有 helper（那是 `SkillRowView.swift:260`、`AgentToggleView.swift`、`SkillDetailView.swift` 各自定义的），本文件全程用 `L10n.string(key, bundle: localizationBundle, locale: locale)`（`DashboardView.swift:133, 182, 198`）。P2/P3 里所有新文案必须走同一条路。

### 1.2 分组键从哪来

`Skill.lockEntry?.source` 就是 `~/.agents/.skill-lock.json` 里的 `source` 字段（`LockEntry.swift`）：

| 字段 | 示例 | 说明 |
|---|---|---|
| `source` | `crossoverJie/skills` | github 时是 `owner/repo`；`local` 时是绝对路径；`clawhub` 时是 slug |
| `sourceType` | `github` / `local` / `clawhub` / 任意字符串 | 见下 |
| `sourceUrl` | `https://github.com/...git` | 只用于 git 操作 |

`LockEntry` 的两个来源：

1. `SkillManager.refresh()` 用 `lockFile.skills[id]` 赋值（`SkillManager.swift:550`）。
2. 锁文件里没有的，再用 `commitHashCache` 的 linked info **合成**一条 `LockEntry`（`SkillManager.swift:555-572`）。所以「手工 Link to GitHub」的技能会拿到 `sourceType == "github"` 的条目，**会正常归入对应仓库分组**——这是期望行为，不是兜底。

`sourceType` 的取值**不能假设只有三种**：

- 字面量赋值点只有 4 处：`SkillManager.swift:954`（github 安装）、`1019`（local）、`1055`（clawhub）、`2100`（`LinkedSkillInfo`，github）。
- 但 `SkillManager.swift:564` 是把 `linked.sourceType` 从持久化 JSON（`CommitHashCache`）里**原样搬运**，历史数据或手改的 JSON 里可能是任意字符串。

因此分派必须 `switch sourceType` 且带 default 兜底。兜底组的准确含义是「**锁文件没有条目、且没有 linked info（或 sourceType 无法识别）**」，标题用「本地（未记录来源）」只是为了不给用户看技术名词。

**不要用 `metadata.author` 分组**：author 是 SKILL.md 里手写的、可缺可错（有的写人名、有的写组织），跟「哪个仓库装的」不是一回事；而 `lockEntry.source` 是安装时写入的机械事实，且已被「检查更新 / 批量更新 / 重装」复用。

### 1.3 本机真实数据（写方案时的一次快照，**会漂移**）

`~/.agents/skills` 下的技能目录约 34 个、命中锁文件约 31 条、去重后约 22 个 `source`。形态上是这样：

```text
5  anthropics/skills
3  samber/cc-skills-golang
2  mattpocock/skills / obra/superpowers
2  crossoverJie/skills + crossoverjie/skills   ← 同仓库、大小写不同
1  /Users/chenjie/Documents/dev/github/slidev  ← sourceType = local
1  ...（十几个单技能仓库）
无 lockEntry：clipshelf、generate-wiki、starrocks-upgrade   ← 手动复制/本地开发
```

> 具体计数**不要写进代码或验收脚本**，实现/验证时重新数。上面只用来确认三种形态真实存在。

这组真实数据决定了方案必须处理三个边界：

1. **大小写重复**：`crossoverJie/skills` 与 `crossoverjie/skills` 必须并成一组，否则正是用户说的「同一来源没放在一起」。已验证整体小写不会误并：`crossoverJie/SkillDeck` → `crossoverjie/skilldeck`，与 `crossoverjie/skills` 不同键。
2. **`local` 类型**：`source` 是绝对路径，直接当分组标题会撑爆 header，需要截取 + tooltip。
3. **`lockEntry == nil`**：必须有一个兜底分组，否则这些技能在分组视图里会消失（或散落）。

### 1.4 `clawhub` 类型的特殊性

`ClawHub` 安装写入的 `source` 是**技能 slug**（`SkillManager.swift:1054`），一个技能一个 source。按 source 分组会让每个 ClawHub 技能各自占一个分组（标题就是技能名，与行内标题重复、毫无意义）。因此 ClawHub 归为一个固定分组。

---

## 2. 方案

### P1 分组模型（`DashboardViewModel`）

分组与排序**正交**：`groupMode` 决定「怎么切段」，`sortOrder` / `sortDirection` 决定「段内顺序 + 段间顺序」。

```swift
/// How the Dashboard list is segmented.
/// Orthogonal to `SortOrder`: grouping decides WHERE a skill appears, sorting decides
/// the order INSIDE a group (and, indirectly, the order of the groups themselves).
enum GroupMode: CaseIterable {
    case source   // one section per install source (repo / local path / ClawHub)
    case none     // legacy flat list

    var iconName: String {
        switch self {
        case .source: return "square.stack.3d.down.right"
        case .none: return "list.bullet"
        }
    }

    /// Localization key for the menu row. Kept as a key (not a resolved string) for the same
    /// reason `unknownUsageHelpKey` is a key: the ViewModel has no bundle/locale environment.
    var titleKey: String {
        switch self {
        case .source: return L10nKeys.dashboardGroupSource
        case .none: return L10nKeys.dashboardGroupNone
        }
    }
}

/// Where a section header's text comes from.
/// An enum instead of two mutually exclusive optionals: the "exactly one of these is set"
/// invariant is expressed by the type, so no `assert` and no force-unwrap.
/// `Equatable` so tests can write `XCTAssertEqual(group.title, .literal("obra/superpowers"))`
/// (synthesized: neither case has an associated value type that is not Equatable).
enum GroupTitle: Equatable {
    /// Literal text taken from the data, e.g. "obra/superpowers" or "ClawHub".
    case literal(String)
    /// Localization key resolved by the View (e.g. the "no source recorded" bucket).
    case localized(String)
}

/// One rendered section of the Dashboard list.
/// `Identifiable` because `ForEach` needs identity: a string key derived from the lock entry is
/// stable across refreshes, unlike an array index which would make SwiftUI animate rows wrongly.
struct SkillGroup: Identifiable {
    /// Stable identity, e.g. "github:obra/superpowers", "path:/users/x/repo", "marketplace:clawhub".
    let id: String
    let title: GroupTitle
    /// Optional tooltip: full local path, marketplace hint, ...
    let helpText: String?
    /// Members, already ordered by the active SortOrder/SortDirection.
    let skills: [Skill]
}

/// product default: grouped view. Flip ONE line to `.none` to restore the old flat list.
var groupMode: GroupMode = .source
```

分组计算：

```swift
/// Where a single skill's section identity comes from.
/// Internal (not `private`) so `@testable import` can drive `sourceDescriptor(for:)` directly.
struct SourceDescriptor {
    /// Section identity, e.g. "github:obra/superpowers".
    let key: String
    /// Header derived from THIS skill alone. For github groups this is only a fallback: the
    /// group-wide `preferredVariant(...)` vote replaces it once every member is known.
    let title: GroupTitle
    /// Optional tooltip (full local path, ...). Taken from the group's first member.
    let helpText: String?
    /// The raw casing of a github `source`, fed into `preferredVariant`. `nil` for every other
    /// kind of group (there is nothing to vote on).
    let variant: String?
}

/// Groups an already-sorted skill array into sections.
///
/// Deterministic given (`groupMode`, input order): no `filteredSkills` read inside, so the View
/// can pass the ONE snapshot it already computed for the empty-state check. Reading
/// `filteredSkills` here instead would sort the whole array twice per body evaluation (and,
/// under `.usage`, precompute `usageSummary` twice — `DashboardViewModel.swift:290-292`).
/// `internal` (default) instance method is enough for `@testable import`.
///
/// Implementation note for readers coming from Java/Go: this is one pass with a
/// first-appearance list `order` plus two dictionaries. That is cheaper and simpler than
/// `Dictionary(grouping:)` followed by a second sort, and it DEFINES the group order as
/// "the position of the group's highest-ranked skill in the current sort". No extra
/// ordering knob to explain, persist, or get out of sync with `sortOrder`.
func sourceGroups(from skills: [Skill]) -> [SkillGroup] {
    // Defensive only: the `.none` branch of the View keeps the untouched flat `List` and never
    // calls this. Returning [] (not a fake single group) makes a future wiring mistake loud
    // instead of silently rendering an ungrouped list through a section code path.
    guard groupMode == .source else { return [] }

    var order: [String] = []
    var members: [String: [Skill]] = [:]
    var variants: [String: [String: Int]] = [:]   // key -> (source 写法 -> 出现次数)

    for skill in skills {
        let descriptor = Self.sourceDescriptor(for: skill)
        if members[descriptor.key] == nil { order.append(descriptor.key) }
        members[descriptor.key, default: []].append(skill)
        if let variant = descriptor.variant {
            variants[descriptor.key, default: [:]][variant, default: 0] += 1
        }
    }

    return order.compactMap { key in
        guard let groupSkills = members[key] else { return nil }
        let first = Self.sourceDescriptor(for: groupSkills[0])

        // Only `.literal` headers can be re-cased (the localized buckets carry no fallback text).
        // WITHOUT this override the header is "whichever casing the currently first member
        // happens to carry", i.e. it silently changes when the sort order changes — and the
        // `variants` vote above would be a dead computation.
        let title: GroupTitle
        if case .literal(let fallback) = first.title {
            title = .literal(Self.preferredVariant(variants[key] ?? [:], fallback: fallback))
        } else {
            title = first.title
        }

        return SkillGroup(id: key, title: title, helpText: first.helpText, skills: groupSkills)
    }
}
```

`title` 的大小写归一在 descriptor 里做不了（需要全组统计），所以分工是：`sourceDescriptor` 只给「首次出现」的写法当 fallback，`sourceGroups` 用全组的 `variant` 计数投票覆盖。

```swift
/// Deterministic tie-break for "the same repo, two casings": most frequent → most uppercase
/// letters (so `crossoverJie/skills` beats `crossoverjie/skills`) → lexicographic.
/// `static` (not `private`) on purpose: `@testable import` cannot see `private` members, and
/// this rule is exactly the kind of thing that should be pinned by a unit test.
static func preferredVariant(_ counts: [String: Int], fallback: String) -> String {
    counts.max { lhs, rhs in
        if lhs.value != rhs.value { return lhs.value < rhs.value }
        let lhsUpper = lhs.key.reduce(0) { $1.isUppercase ? $0 + 1 : $0 }
        let rhsUpper = rhs.key.reduce(0) { $1.isUppercase ? $0 + 1 : $0 }
        if lhsUpper != rhsUpper { return lhsUpper < rhsUpper }
        return lhs.key > rhs.key          // `max` keeps the greater element → reverse for asc
    }?.key ?? fallback
}
```

分组键规则（`sourceDescriptor(for:)`，`static func` + internal `SourceDescriptor`，**第一分派条件是 `sourceType`**，绝不用 `source.contains("/")` —— ClawHub 的 slug 也可能带 `/`）：

| 条件（**按顺序匹配**，`source` 一律先 `trimmingCharacters(in: .whitespacesAndNewlines)`） | `id` | `title` | `helpText` |
|---|---|---|---|
| `lockEntry == nil` | `unknown:no-entry` | `.localized(dashboardGroupUnknownSource)` | `nil` |
| `sourceType == "github"` 且 trim 后非空 | `github:` + `source.lowercased()` | `.literal(...)`，**最终值**由全组 `preferredVariant` 投票决定（descriptor 只提供 first-seen fallback） | `nil` |
| `sourceType == "local"` 且 trim 后非空 | `path:` + 归一化路径**小写** | `.literal(归一化路径的 lastPathComponent)` | 归一化后的完整路径（**保留原大小写**） |
| `sourceType == "clawhub"` | `marketplace:clawhub` | `.literal("ClawHub")` | `nil` |
| 其它 `sourceType` 且 trim 后非空 | `unknown:` + `source.lowercased()` | `.literal(source)` | `nil` |
| **其余全部**（github / local 的 `source` trim 后为空、其它类型且为空、任何漏网情况） | `unknown:no-entry` | `.localized(dashboardGroupUnknownSource)` | `nil` |

最后一行是**兜底 catch-all**：没有它，`sourceType == "github"` 但 `source` 为空的条目会掉进「无匹配」的缝隙（`switch` 的 `default` 分支必须落到这里，不能靠多个 `if` 拼）。

四处细节：

- **`local` 路径归一化**：`URL(fileURLWithPath: trimmedSource).standardizedFileURL.path`。`standardizedFileURL` 去掉 `./`、`..`、尾部斜杠，且**不碰磁盘**（`sourceGroups(from:)` 每次 body 求值都会跑，不能用 `resolvingSymlinksInPath()` 做 I/O）。`lastPathComponent` 取自归一化结果，保证不为空串。
- **`id` 小写、`helpText` 保留原大小写**：macOS 默认文件系统大小写不敏感，`/Users/x/repo-a` 与 `/users/x/repo-a` 应视为同一组；但 tooltip 要给人看，保留磁盘上的真实写法。
- **`unknown:` 分组不再并吞原始 source**：无效 source 各自成组并把自己当标题，`helpText` 不会因为「组里第一个成员的 helpText 胜出」而丢失（原来把这类并进 `local:none` 的方案就丢在这里）。
- 组键统一加前缀（`github:` / `path:` / `marketplace:` / `unknown:`），避免 `local` 类型和「无来源」共用命名空间造成的误读。

**为什么组顺序跟着排序走（而不是按组名/组大小排）**：
- 按组名排 → 切到 Usage 排序时 header 顺序不变，看起来像「排序没生效」；
- 按组大小排 → 装一个新技能就可能整屏重排，比现在还跳；
- 跟随排序 → 一个心智模型：「先排序，再切片」，且 `.none` 天然等价于「只有一个切片」。

已知退化，见 §6 风险表：`.scope` / `.agent` 两个排序分支没有次级排序键（`DashboardViewModel.swift:268-280`），并列时组顺序源自 `filteredSkills` 的顺序，而 Swift 的 `sort` 不保证稳定。**本次不改 `filteredSkills`**（否则破坏「排序语义与现有测试不变」），只记录触发条件与加固方案。

### P2 视图分层（`DashboardView`）

先补一个本地化的私有 helper（与 `SkillRowView.swift:260` 同款，本文件新增文案全部走它）：

```swift
/// Same tiny wrapper as `SkillRowView.localized(_:)`: SwiftUI `@Environment` values are only
/// reachable from the view, and `L10n.string` needs both bundle and locale. Not a global
/// function on purpose — the repo keeps localization helpers view-local.
private func localized(_ key: String) -> String {
    L10n.string(key, bundle: localizationBundle, locale: locale)
}
```

`filteredSkills` **每次 body 只读一次**（现在 `DashboardView.swift:30` 读一次判空、列表再读一次）：

```swift
var body: some View {
    // Single snapshot for this render pass: `filteredSkills` sorts (and, under `.usage`,
    // precomputes usage counts) on every access.
    let skills = viewModel.filteredSkills
    Group {
        if skillManager.isLoading && skillManager.skills.isEmpty {
            ...
        } else if skills.isEmpty {           // was: viewModel.filteredSkills.isEmpty
            ...
        } else {
            ...
        }
    }
}
```

把 `List` 里的行 + `contextMenu` 抽成一个 `@ViewBuilder` 方法（现在约 60 行内联，分组后要用两次，复制粘贴不可接受）：

```swift
/// One row plus its context menu. Extracted because the grouped and flat branches both need it;
/// duplicating the 50-line context menu would guarantee they drift apart.
@ViewBuilder
private func skillRow(_ skill: Skill) -> some View {
    SkillRowView(
        skill: skill,
        showsSource: viewModel.groupMode == .none,   // 分组时 header 已经是来源，行内不再重复
        usageSummary: viewModel.usageSummary(for: skill),
        showsUnknownUsage: viewModel.sortOrder == .usage,
        usageIsScanning: viewModel.isRelevantUsagePending,
        unknownUsageHelpKey: viewModel.unknownUsageHelpKey
    )
    .tag(skill.id)
    .contextMenu { /* 原逻辑原样搬移 */ }
}
```

列表按 `groupMode` 二选一（**扁平分支保持原代码形状**，把 `.none` 的回归面压到零 —— 这也是不把 `.none` 也塞进 `Section` 的原因）：

```swift
if viewModel.groupMode == .source {
    List(selection: $selectedSkillID) {
        // `ForEach` over sections: each `SkillGroup` owns its `Section`, so no index math.
        ForEach(viewModel.sourceGroups(from: skills)) { group in
            Section {
                // `ForEach(group.skills)` needs `Skill: Identifiable` (already true, id == directory name).
                ForEach(group.skills) { skill in
                    skillRow(skill)
                }
            } header: {
                groupHeader(group)
            }
        }
    }
    .listStyle(.inset(alternatesRowBackgrounds: true))
} else {
    List(skills, selection: $selectedSkillID) { skill in
        skillRow(skill)
    }
    .listStyle(.inset(alternatesRowBackgrounds: true))
}
```

分组头：**单行、caption 字号**，避免 3 行高的 `SkillRowView` 之上再叠一个默认大标题把可视行数砍掉：

```swift
/// Section header: source label + skill count. Kept compact (caption + single line) because the
/// rows are already three lines tall; a default-sized header would cut visible rows by ~20%.
private func groupHeader(_ group: DashboardViewModel.SkillGroup) -> some View {
    // `switch` over the GroupTitle enum: SwiftUI resolves the localized case at render time, so
    // switching app language re-renders headers like every other string.
    let title: String = switch group.title {
    case .literal(let text): text
    case .localized(let key): localized(key)
    }

    return HStack(spacing: 6) {
        Text(title)
            .appFont(.caption).fontWeight(.semibold)
            .lineLimit(1).truncationMode(.middle)
        // `%d` needs `String(format:)`; `LText` only takes keys without arguments.
        Text(String(format: localized(L10nKeys.dashboardGroupSkillCountFormat), group.skills.count))
            .appFont(.caption2)
            .foregroundStyle(.secondary)
        Spacer()
    }
    .help(group.helpText ?? title)
}
```

> 上面这段是第一版实现；字号、可折叠、跳转按钮、tooltip 合并均已被 P2b 取代。

空状态判断改用局部 `skills`，因此「搜索结果为空 / Agent 过滤后为空 / 首屏加载中」三条分支行为完全不变。

### P2b 分组头增强（第一版开发完成后追加的需求）

用户实际看过分组视图后提了三点，均已实现：

1. **header 字号调大**：`.appFont(.caption)` → `.appFont(.subheadline)`，计数保持 `.caption`（原 `.caption2`）。
2. **点击分组名折叠/展开**：`DashboardViewModel.collapsedGroupIDs: Set<String>`（键 = `SkillGroup.id`）+ `isGroupCollapsed(_:)` / `toggleGroupCollapsed(_:)`。状态放 VM 而不是 `SkillGroup`，因为分组每次 body 都会重算；用稳定 id 作键，所以切换排序 / 刷新 / 过滤不会丢。折叠时 View 给该 `Section` 传 `[Skill]()`：header 保留（折叠按钮还在），行数为 0。
3. **跳转来源仓库**：`SourceDescriptor.webURL` + `SkillGroup.webURL`，只有 github 分支赋值，`githubWebURL(source:sourceUrl:)` 负责归一化——`sourceUrl` 是 SSH（`git@github.com:o/r.git`，真实锁文件里就有一条）时不可点，因此只在 http(s) 时采用，否则回退到 `https://github.com/<source>`，两者都去掉 `.git` 后缀，并拒绝带 userinfo 的 URL（`https://github.com@evil.example/x`）。local / ClawHub / 未知来源不出按钮。

header 结构最终形态（一个折叠按钮 + 一个可选跳转按钮）：

```swift
HStack(spacing: 6) {
    Button { viewModel.toggleGroupCollapsed(group.id) } label: {
        HStack(spacing: 6) {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
            Text(title).appFont(.subheadline).fontWeight(.semibold).lineLimit(1)
            Text(String(format: localized(L10nKeys.dashboardGroupSkillCountFormat), group.skills.count))
                .appFont(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(collapseHelp)          // 折叠/展开文案 + group.helpText 合并成一条

    if let webURL = group.webURL { /* arrow.up.right.square → NSWorkspace.shared.open */ }
}
```

两条 tooltip 合并的理由：折叠按钮用 `Spacer(minLength: 0)` 铺满 header，外层 HStack 再挂 `.help(...)` 会与之重叠，AppKit 只会显示其中一个，`local` 分组的完整路径 tooltip 会变得碰不到。

### P3 工具栏菜单

排序菜单下面加一个分组子节（同一个 `Menu` 里换 `Section`，不新增工具栏控件 —— 中间列工具栏已经接近溢出）：

```swift
Section {
    ForEach(DashboardViewModel.SortOrder.allCases, id: \.self) { order in
        Button { ... } label: {
            HStack {
                // `Label { } icon: { }` with `LText` as the title: `LText` is a View, so it can
                // only be used here, not in `Label("literal", systemImage:)`.
                Label { LText(key: order.titleKey) } icon: { Image(systemName: order.iconName) }
                if viewModel.sortOrder == order {
                    Spacer()
                    Image(systemName: viewModel.sortDirection.iconName)
                }
            }
        }
    }
} header: {
    // A `String` variable cannot be passed to `Section(_:)`'s LocalizedStringKey overload, so a
    // header view is used instead of `Section("Sort By")`.
    LText(key: L10nKeys.dashboardSortSection)
}

Section {
    ForEach(DashboardViewModel.GroupMode.allCases, id: \.self) { mode in
        Button {
            viewModel.groupMode = mode
        } label: {
            HStack {
                Label { LText(key: mode.titleKey) } icon: { Image(systemName: mode.iconName) }
                if viewModel.groupMode == mode {
                    Spacer()
                    Image(systemName: "checkmark")
                }
            }
        }
    }
} header: {
    LText(key: L10nKeys.dashboardGroupSection)
}
```

工具栏按钮 label 也必须换（`DashboardView.swift:169`，否则中文界面出现「菜单全中文、按钮上挂 `Usage Count`」）：

```swift
HStack(spacing: 2) {
    Image(systemName: "line.3.horizontal.decrease")
    LText(key: viewModel.sortOrder.titleKey)          // was Text(viewModel.sortOrder.rawValue)
    Image(systemName: viewModel.sortDirection.iconName).appFont(.caption2).imageScale(.small)
}
```

`GroupMode.allCases` 的顺序即菜单顺序，`.source` 放第一个（它是默认值）。

### P4 本地化

现有 4 个排序项（`Name` / `Scope` / `Agent Count` / `Usage Count`）和 `Section("Sort By")` 都是**硬编码英文**，中文界面下一直是英文。这次要动这个菜单，顺手补齐，否则新加的分组项是菜单中唯一随语言变化的行。

`SortOrder.rawValue` 的两个消费点（`DashboardView.swift:154` 菜单、`:169` 工具栏）改完后**没有任何消费者**（它不是 `Codable`，`DashboardTests` 只读 `.defaultDirection`），可以顺手去掉 `: String` 与 `= "Name"` 这些字面量。另外 `SortDirection.displayName`（`DashboardViewModel.swift:55`）同样无消费者，可一并删除（独立的小清理，与本次功能无关，可单独提交）。

`SortOrder` 的展示文案改成 key（与 `GroupMode.titleKey` 同一套写法）：

```swift
enum SortOrder: CaseIterable {          // 去掉 `: String` 与四个字面量
    case name, scope, agent, usage

    /// Localization key for the menu row and the toolbar label. Same rationale as
    /// `GroupMode.titleKey`: resolving happens in the View, which owns bundle + locale.
    var titleKey: String {
        switch self {
        case .name:  return L10nKeys.dashboardSortName
        case .scope: return L10nKeys.dashboardSortScope
        case .agent: return L10nKeys.dashboardSortAgentCount
        case .usage: return L10nKeys.dashboardSortUsageCount
        }
    }

    var iconName: String { ... }        // 原样保留
    var defaultDirection: SortDirection { ... }  // 原样保留，现有测试依赖
}
```

新增 key（`L10nKeys.swift` 定义 + 注册进 `allKeys`，`en` / `zh-Hans` 两个 `Localizable.strings` 各加一条，共 **13** 条）：

| key | `L10nKeys` 常量名 | en | zh-Hans | 引用处 |
|---|---|---|---|---|
| `dashboard.sort.section` | `dashboardSortSection` | `Sort By` | `排序` | P3 排序 Section header |
| `dashboard.sort.name` | `dashboardSortName` | `Name` | `名称` | `SortOrder.titleKey` |
| `dashboard.sort.scope` | `dashboardSortScope` | `Scope` | `范围` | 同上 |
| `dashboard.sort.agentCount` | `dashboardSortAgentCount` | `Agent Count` | `Agent 数量` | 同上 |
| `dashboard.sort.usageCount` | `dashboardSortUsageCount` | `Usage Count` | `使用次数` | 同上 |
| `dashboard.group.section` | `dashboardGroupSection` | `Group By` | `分组` | P3 分组 Section header |
| `dashboard.group.none` | `dashboardGroupNone` | `None` | `不分组` | `GroupMode.titleKey` |
| `dashboard.group.source` | `dashboardGroupSource` | `Source` | `来源仓库` | 同上 |
| `dashboard.group.unknownSource` | `dashboardGroupUnknownSource` | `Local / No Source` | `本地（未记录来源）` | `GroupTitle.localized`（`sourceDescriptor`） |
| `dashboard.group.skillCountFormat` | `dashboardGroupSkillCountFormat` | `%d skills` | `%d 个技能` | P2 `groupHeader` |
| `dashboard.group.collapse` | `dashboardGroupCollapse` | `Collapse this group` | `折叠该分组` | P2b `groupHeader`（折叠按钮 tooltip） |
| `dashboard.group.expand` | `dashboardGroupExpand` | `Expand this group` | `展开该分组` | 同上 |
| `dashboard.group.openSource` | `dashboardGroupOpenSource` | `Open the source repository in the browser` | `在浏览器中打开来源仓库` | P2b `groupHeader`（跳转按钮 tooltip） |

> 后 3 条来自 P2b（第一版开发完成后追加的需求），见下节。

`ClawHub` 是品牌名，用 `.literal`，不建 key。`L10nKeysCoverageTests` 会自动校验「注册的 key 在两种语言都有翻译」，漏一条就红；它**不校验**反向的孤儿 key，所以上表每一行都必须真的被引用（本版已删掉第一版里的 `dashboard.group.menuHelp`，它当初没有任何 `.help(...)` 挂载点）。

### P5 行内来源标签（`SkillRowView`）

```swift
/// Whether the third row shows `lockEntry.source`. Set to false in grouped mode: the section
/// header already states the source, and repeating it inside every row is noise.
/// Default `true` keeps the flat-list call site source-compatible.
var showsSource: Bool = true
```

**第三行整行要包进条件**（`SkillRowView.swift:130-145`）：分组模式下 `showsSource == false`，若只有 `if let lockEntry` 里加条件，而没有 author / version 的行会留下一个空的 `HStack`，仍占外层 `VStack(spacing: 6)` 的一个槽位 → 每条技能底部多出 6pt 空白，整列行高不齐：

```swift
// Third row: author + version + source.
// Skip the whole row (not just the source label) when nothing would be rendered: the outer
// VStack's 6pt spacing would otherwise leave a blank slot in every grouped row.
let hasSourceRow = skill.metadata.author != nil
    || skill.metadata.version != nil
    || (showsSource && skill.lockEntry != nil)

if hasSourceRow {
    HStack(spacing: 12) {
        if let author = skill.metadata.author { ... }
        if let version = skill.metadata.version { ... }
        if showsSource, let lockEntry = skill.lockEntry { ... }
    }
}
```

---

## 3. 被否掉的替代方案

| 方案 | 否掉原因 |
|---|---|
| **新增第 5 个 `SortOrder.source`**（仍是一维列表，只是相邻） | 满足「放在一起」但看不出边界；同一 repo 5 个技能连成一片时反而像排序乱了。用户要的是「分组」，分段才是分组。 |
| **`.none` 与 `.source` 都走 `Section`（单一 List 形状）** | 会把 `.none` 也变成 Section 渲染，`groupMode` 回滚就不再是「1 行 diff 恢复旧视图」，还平添 `Section` 空 header 的间距差异。 |
| **`Dictionary(grouping:)` + 组名排序** | 引入第二条排序规则，且与 `sortOrder` 冲突（见 P1 决策说明）。 |
| **按 `metadata.author` 分组** | author 是手写字段，缺失/拼写不一；与「从哪个仓库装」不等价。 |
| **扫描时给每个技能跑 `git config --get remote.origin.url`** | 每次刷新 N 次磁盘/子进程 I/O；npx 解包的安装没有 `.git`；锁文件已经记录了同样的信息。 |
| **在 `SkillScanner` / `SkillManager` 里预计算分组** | 分组是纯展示概念（还依赖 `groupMode`）；放进 Service 层等于把 UI 状态塞进领域层，也让 `filteredSkills` 的既有测试要跟着改。 |
| **`OutlineGroup` / 可折叠分组** | 需要递归模型 + 展开状态持久化，收益（折叠）与成本不对等；后续可选（第 7 节）。 |

---

## 4. 改动文件

```text
Sources/SkillDeck/ViewModels/DashboardViewModel.swift   # GroupMode / GroupTitle / SkillGroup / SourceDescriptor / sourceGroups / sourceDescriptor / preferredVariant / SortOrder.titleKey
Sources/SkillDeck/Views/Dashboard/DashboardView.swift   # skills 快照、分组与扁平两条分支、skillRow 抽取、groupHeader（含折叠 / 跳转） 、localized helper、两个菜单 Section、工具栏 label
Sources/SkillDeck/Views/Dashboard/SkillRowView.swift    # showsSource + 第三行整行条件渲染
Sources/SkillDeck/Utilities/Localization/L10nKeys.swift # 10 个新 key + allKeys 注册
Sources/SkillDeck/Resources/Localizations/en.lproj/Localizable.strings      # 10 条
Sources/SkillDeck/Resources/Localizations/zh-Hans.lproj/Localizable.strings # 10 条
Tests/SkillDeckTests/DashboardGroupingTests.swift       # 新增
```

### 新增测试（`DashboardGroupingTests`）

全部标 `@MainActor`（`DashboardViewModel` 是 `@MainActor`，参考 `DashboardUsageSortTests.swift:9`）。helper 注意 `LockEntry` 有 7 个无默认值字段（`LockEntry.swift:5-13`），`makeSkill(id:source:sourceType:agents:)` 需要补全 `sourceUrl` / `skillPath` / `skillFolderHash` / `installedAt` / `updatedAt`。

| 测试 | 断言 |
|---|---|
| `testCaseVariantsMergeIntoOneGroup` | `github` + `crossoverJie/skills` & `crossoverjie/skills` → 1 组、2 个技能、`title == .literal("crossoverJie/skills")` |
| `testSimilarReposDoNotMerge` | `crossoverJie/SkillDeck` 与 `crossoverJie/skills` → 2 组（钉住 `lowercased()` 不误并） |
| `testSkillsWithoutLockEntryShareFallbackGroup` | 3 个 `lockEntry == nil` → 1 组，`id == "unknown:no-entry"`，`title == .localized(dashboardGroupUnknownSource)` |
| `testClawHubSkillsShareOneGroup` | 2 个 `sourceType == "clawhub"`（不同 slug，其中一个 slug 带 `/`）→ 1 组、`id == "marketplace:clawhub"`、`title == .literal("ClawHub")` |
| `testLocalPathGroupUsesLastPathComponent` | `sourceType == "local"`, `/Users/x/repo-a/` → `id == "path:/users/x/repo-a"`（归一化去尾部斜杠 + id 小写）、`title == .literal("repo-a")`、`helpText == "/Users/x/repo-a"`（保留原大小写） |
| `testEmptySourceFallsIntoFallbackGroup` | `sourceType == "github"` + `source == "   "` → `id == "unknown:no-entry"`（钉住 catch-all 行） |
| `testUnknownSourceTypeKeepsOwnGroupAndTitle` | `sourceType == "weird"`, `source == "Some/Repo"` → `id == "unknown:some/repo"`、`title == .literal("Some/Repo")` |
| `testGroupOrderFollowsSortOrder` | 构造必然不同的数据，断言**精确的** `sourceGroups(from:).map(\.id)`：name 升序时 `["github:aaa/one", "github:zzz/two"]`，usage 降序时 `["github:zzz/two", "github:aaa/one"]` |
| `testInnerOrderRespectsSortDirection` | 同一组内 `sortDirection == .descending` 时组内 id 顺序反转 |
| `testAgentFilterDropsEmptyGroups` | `selectedAgentFilter` 过滤后不含成员的组不出现 |
| `testPreferredVariantTieBreak` | 直接调 `DashboardViewModel.preferredVariant`：次数多者胜；次数相同取大写字母更多者；再相同取字典序 |

- `.none` 分支不写测试（视图走的是扁平 `List`，`sourceGroups` 的 `guard` 只是防御性早退），由手动验收覆盖。`groupedSkills` 便捷属性已经删掉，避免留一个没有调用方的「for tests/previews」入口；测试一律直接调 `sourceGroups(from:)`。

---

## 5. 验证

| 项 | 方法 |
|---|---|
| 编译 | `swift build` |
| 全量单测 | `swift test`（当前 334 tests，实际 +18） |
| 分组正确性（真实数据） | 启动 app → Dashboard 默认分组视图。**按当时的数据现数**，核对：`anthropics/skills` 组成员数 = 行内该类技能数；`crossoverJie/skills` 只有**一个** header 且成员包含两种大小写来源；`本地（未记录来源）` 只包含无 lockEntry 的技能；`slidev` 单独一组、标题为 `slidev`、tooltip 是完整路径 |
| 分组 × 排序交叉 | 4 种排序 × 2 种方向 × 2 种 groupMode，逐一确认组内顺序与组间顺序符合第 2 节定义 |
| 与过滤/搜索交叉 | 侧栏选中某个 Agent / 输入搜索词后，空组不出现，非空组保留 |
| usage 排序 + 分组 | 首次扫描期间列表冻结（`isRelevantUsagePending`），扫描完成后组顺序随组内最高 usage 变化（预期行为） |
| 合并大小写后的组内顺序 | `crossoverJie/skills`、`crossoverjie/skills` 两组技能混排在同一 header 下，组内按当前排序 |
| 选中态 | 切换 groupMode 后 `selectedSkillID` 不丢（由 id 驱动的 `selection`） |
| 行高 | 分组模式下无 author / version 的行**底部没有多余空白**（P5 整行条件） |
| 中文/英文 | 排序与分组两个 Section 的所有行 + 工具栏按钮全部随语言切换 |
| 菜单 Section 标题渲染 | **真机确认**：本仓 `Menu` 里目前只用过字面量 `Section("Sort By")`（`DashboardView.swift:140`），自定义 header view 只在 `Form` / `List` 用过（`ProxySettingsView.swift:31`、`SidebarView.swift:147`）。macOS 菜单栏若把 `Section { } header: { LText }` 渲染成普通行而不是灰色小标题，退回字面量 `Section(L10n.string(...))`（代价：切语言需重开菜单） |
| 回归 | `DashboardUsageSortTests` 全部不经过 `sourceGroups`，必须全绿；`.none` 分支的 `List` 与改动前**功能等价**（入参从 `viewModel.filteredSkills` 换成局部 `skills` 快照，同一份数据） |

---

## 6. 风险与回滚

| 风险 | 说明 | 缓解 |
|---|---|---|
| 可见行数变少 | 每个分组多一个 ~20pt header；本机约 22 个 source 意味着约 22 个 header | header 用 subheadline 单行、不放大 padding；折叠不需要的分组；长列表可切「不分组」 |
| **`.scope` / `.agent` 排序下组顺序可能抖动** | 这两个分支没有次级排序键（`DashboardViewModel.swift:268-280`），并列时顺序来自 `filteredSkills`，而 Swift 的 `sort` 不保证稳定；`SkillManager.skills` 本身是扫描器按名排序的，所以实践中多数时候稳定 | 本次不改 `filteredSkills`（承诺不破）。若验收时观察到 header 抖动，独立提交「给 `.scope` / `.agent` 补 `isOrderedBeforeByName` 次级键」，先确认现有测试未断言并列顺序 |
| 组顺序随 usage 刷新跳动 | 组顺序 = 组内最高 usage 技能的排名 | 与现有 usage 排序的跳动行为一致；首次扫描期已冻结；不额外引入二次排序规则 |
| 单技能仓库太多时「分组」像「多加了空行」 | 本机约 22 个 source / 34 个技能 | 这正是用户视角的真实结构；「不分组」一键回旧视图 |
| 大小写合并规则不够直观 | 标题取「出现次数 → 大写字母数 → 字典序」 | 规则是 `static` 纯函数 + 单测固定；全组投票而非「第一个成员」决定标题，排序变化不会改 header |
| 同一个本地仓库因路径写法拆组 | 只用 `standardizedFileURL`（不做 I/O）时，`/private/Users/x` 与 `/Users/x` 不会被折叠 | 已知限制。若真实数据里出现，独立提交「用归一化后的路径做 key 并缓存结果」，避免在 body 里跑 `resolvingSymlinksInPath()` |
| `List` 结构变化带来动画/斑马纹变化 | 分组分支从 `List(data)` 换成 `List { Section { ForEach } }` | `.alternatesRowBackgrounds` 保持不变；`contextMenu`、`tag`、`selection` 语义不变 |

**回滚**：把 `groupMode` 默认值改回 `.none` 即恢复旧视图（1 行 diff：分组分支变为不可达，扁平分支与改动前**功能等价**）。本地化 key、`showsSource` 默认 `true`、`skillRow` 抽取都是纯增量或等价重构，可单独保留。

---

## 7. 后续可选（本次不做）

- **给 `.scope` / `.agent` 排序补次级键**（见风险表），让组顺序在所有 mode 下都确定。
- **本地路径折叠**：若 `/private/Users` 变体真的出现在用户数据里，给 `path:` key 加缓存过的 symlink 解析。
- ~~**分组可折叠**~~：**已实现**（见 P2b）。
- **持久化 `groupMode`**：现在 `sortOrder` 都不持久化，单独持久化分组模式反而不一致；若要持久化，建议与 `sortOrder` 一起放进 `@AppStorage`，并做一次「无偏好时默认 `.source`」的迁移处理。注意 `@Observable` 属性上的 `didSet` 与宏生成的存取器交互微妙，写入走 View 的 `onChange(of:)` 或显式 `setGroupMode(_:)` 更稳。
- **分组级批量操作**：某个 source 的「检查更新 / 全部更新」入口（`SkillManager.checkAllUpdates` 已内部按 `sourceUrl` 分组，复用成本低）。
- **ClawHub 组的跳转按钮**：`SkillManager` 为 clawhub 写的 `sourceUrl` 是 `https://clawhub.ai/skills/<slug>`，但该分组聚合了多个 slug，点击打开哪一个都是任意的，所以现在不给按钮；若要做，应该链到 marketplace 首页或展开成子分组。
- **分组头显示更新提示**：组内任一技能 `hasUpdate` 时在 header 加橘色箭头（`skillManager.updateStatuses` 直接可读）。
- **清理死代码**：`SortOrder: String` 与 `SortDirection.displayName` 在 P4 完成后均无消费者，可删除（`SortDirection.displayName` 现在就已经没人用）。
