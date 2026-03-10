# Settings 字体放大时窗口自适应尺寸 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 根据用户设置的字体大小动态扩展 Settings 窗口最小尺寸，避免横向换行与纵向滚动条。

**Architecture:** 抽出纯函数计算最小窗口尺寸（根据字号得到 width/height），在 SettingsView 中读取 AppStorage 的字号并应用 `.frame(minWidth:minHeight:)`。这样可测试、可复用，并保证字号变大时窗口相应变大。

**Tech Stack:** SwiftUI, AppStorage, XCTest

---

### Task 1: 定义窗口尺寸计算规则（纯函数 + 测试）

**Files:**
- Create: `Sources/SkillDeck/Utilities/SettingsWindowSizing.swift`
- Test: `Tests/SkillDeckTests/SettingsWindowSizingTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import SkillDeck

final class SettingsWindowSizingTests: XCTestCase {
    func testMinWindowSizeScalesWithFontSize() {
        let base = SettingsWindowSizing.minSize(forFontSize: 13)
        let larger = SettingsWindowSizing.minSize(forFontSize: 20)

        XCTAssertGreaterThan(larger.width, base.width)
        XCTAssertGreaterThan(larger.height, base.height)
    }

    func testMinWindowSizeClampsToMinimums() {
        let tiny = SettingsWindowSizing.minSize(forFontSize: 8)
        XCTAssertEqual(tiny.width, SettingsWindowSizing.baseWidth)
        XCTAssertEqual(tiny.height, SettingsWindowSizing.baseHeight)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter SettingsWindowSizingTests`
Expected: FAIL (type not found / method not found)

**Step 3: Write minimal implementation**

```swift
import Foundation

enum SettingsWindowSizing {
    static let baseWidth: CGFloat = 450
    static let baseHeight: CGFloat = 350
    static let baseFontSize: CGFloat = 13

    static func minSize(forFontSize fontSize: Double) -> CGSize {
        let size = max(CGFloat(fontSize), baseFontSize)
        let scale = size / baseFontSize
        return CGSize(width: baseWidth * scale, height: baseHeight * scale)
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter SettingsWindowSizingTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/SkillDeck/Utilities/SettingsWindowSizing.swift Tests/SkillDeckTests/SettingsWindowSizingTests.swift
git commit -m "feat: add settings window sizing helper"
```

---

### Task 2: SettingsView 使用动态最小尺寸

**Files:**
- Modify: `Sources/SkillDeck/Views/SettingsView.swift`

**Step 1: Update view to read font size**

Add at `SettingsView` level:

```swift
@AppStorage(FontSettings.sizeKey) private var uiFontSize = FontSettings.defaultFontSize
```

**Step 2: Apply dynamic min size**

Replace fixed `.frame(width:height:)` with:

```swift
let minSize = SettingsWindowSizing.minSize(forFontSize: uiFontSize)
TabView { ... }
    .frame(minWidth: minSize.width, minHeight: minSize.height)
```

**Step 3: Run tests**

Run: `swift test --filter SettingsWindowSizingTests`
Expected: PASS

**Step 4: Commit**

```bash
git add Sources/SkillDeck/Views/SettingsView.swift
git commit -m "feat: scale settings window size with font"
```

---

### Task 3: Full verification

**Step 1: Build**

Run: `swift build`
Expected: Success

**Step 2: Test**

Run: `swift test`
Expected: All tests pass

**Step 3: Manual check**

1. 打开设置窗口（Cmd+,）
2. 将字体调大到 20+，确认：
   - “Overview/Agents/General” 等内容无明显横向换行
   - 不出现垂直滚动条

---

## Notes

- 动态尺寸只扩不缩，避免用户感知窗口在缩小（体验更稳定）。
- 如果需要更强适配，可在后续加入最大尺寸上限或更细粒度的缩放曲线。
