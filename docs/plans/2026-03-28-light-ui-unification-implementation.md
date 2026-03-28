# SplitMux Light UI Unification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refresh SplitMux light mode so the window reads as one coherent macOS surface with brand-accented chrome, while preserving native traffic-light buttons and existing terminal behavior.

**Architecture:** Centralize the light-mode visual system in `AppTheme`, then apply it at three shell layers: app canvas, top chrome, and sidebar selection states. Keep behavior intact by limiting changes to styling and layout offsets inside the existing SwiftUI hierarchy, and verify window chrome with the current AppKit regression script plus a full build.

**Tech Stack:** SwiftUI, AppKit window configuration, Xcode build, script-based regression verification

---

### Task 1: Add unified light-mode shell tokens

**Files:**
- Modify: `/Users/levi/project/IOS/SplitMux/SplitMux/Services/SettingsManager.swift`

**Step 1: Write the failing token expectations**

Document the intended token mapping directly in code comments before implementation:

```swift
// Light mode target palette:
// appCanvasBackground: warm off-white
// chromeSurface: elevated white
// glassOverlay: low-alpha cool fog
// brandCoral: primary action accent
// brandAqua: secondary technical accent
```

**Step 2: Build to confirm there is no token support yet**

Run:

```bash
xcodebuild -project /Users/levi/project/IOS/SplitMux/SplitMux.xcodeproj -scheme SplitMux -configuration Debug build
```

Expected: PASS, but there is still no dedicated light-shell token set in `AppTheme`.

**Step 3: Implement the minimal token surface**

Add new computed properties in `AppTheme` for:

```swift
var appCanvasBackground: Color
var chromeSurfaceBackground: Color
var chromeOverlay: Color
var brandCoral: Color
var brandAqua: Color
var chromeShadow: Color
```

Use light-mode values aligned with the approved design and provide sensible mappings for non-light themes without expanding scope into a full redesign.

**Step 4: Build again**

Run:

```bash
xcodebuild -project /Users/levi/project/IOS/SplitMux/SplitMux.xcodeproj -scheme SplitMux -configuration Debug build
```

Expected: PASS

**Step 5: Commit**

```bash
git add /Users/levi/project/IOS/SplitMux/SplitMux/Services/SettingsManager.swift
git commit -m "feat: add light ui shell tokens"
```

### Task 2: Unify the window canvas and right-pane top spacing

**Files:**
- Modify: `/Users/levi/project/IOS/SplitMux/SplitMux/Views/ContentView.swift`
- Modify: `/Users/levi/project/IOS/SplitMux/SplitMux/Views/TabContent/TabContentView.swift`

**Step 1: Capture the current shell structure**

Record the current styling points that create visual fragmentation:

```swift
.background(theme.contentBackground)
.padding(.top, 28)
```

**Step 2: Build mental baseline by reading both files**

Confirm that:

- `ContentView` owns the app-wide background
- `TabContentView` owns the tab strip top offset

Expected: verified from source before editing

**Step 3: Implement the minimal shell unification**

Change `ContentView` so the full split layout sits on `theme.appCanvasBackground`, and weaken the divider visually.

Change `TabContentView` so:

- the top bar spacing is reduced and tied to the titlebar band
- the whole right pane no longer rests on a pure-white slab

Use the new theme tokens instead of ad hoc literals.

**Step 4: Build to verify layout code compiles**

Run:

```bash
xcodebuild -project /Users/levi/project/IOS/SplitMux/SplitMux.xcodeproj -scheme SplitMux -configuration Debug build
```

Expected: PASS

**Step 5: Commit**

```bash
git add /Users/levi/project/IOS/SplitMux/SplitMux/Views/ContentView.swift /Users/levi/project/IOS/SplitMux/SplitMux/Views/TabContent/TabContentView.swift
git commit -m "feat: unify splitmux light mode shell layout"
```

### Task 3: Restyle the top chrome

**Files:**
- Modify: `/Users/levi/project/IOS/SplitMux/SplitMux/Views/TabContent/TabBarView.swift`
- Modify: `/Users/levi/project/IOS/SplitMux/SplitMux/Views/Components/BreadcrumbBar.swift`

**Step 1: Identify current chrome weight**

Confirm the current heavy chrome surfaces:

```swift
.background(theme.tabBarBackground)
.background(theme.tabBarBackground.opacity(0.5))
```

**Step 2: Implement the tab strip restyle**

Update `TabBarView` so:

- active tabs use an elevated capsule tied to `chromeSurfaceBackground`
- inactive tabs rely on typography and spacing rather than block backgrounds
- the add button visually belongs to the same chrome system

Keep drag-and-drop and close button behavior unchanged.

**Step 3: Implement the breadcrumb restyle**

Update `BreadcrumbBar` so:

- height and contrast are reduced
- the bar reads as metadata, not a second toolbar
- branch accent can use a restrained brand color

**Step 4: Build and inspect**

Run:

```bash
xcodebuild -project /Users/levi/project/IOS/SplitMux/SplitMux.xcodeproj -scheme SplitMux -configuration Debug build
```

Expected: PASS

**Step 5: Commit**

```bash
git add /Users/levi/project/IOS/SplitMux/SplitMux/Views/TabContent/TabBarView.swift /Users/levi/project/IOS/SplitMux/SplitMux/Views/Components/BreadcrumbBar.swift
git commit -m "feat: restyle splitmux top chrome"
```

### Task 4: Restyle the sidebar and empty state with restrained brand accents

**Files:**
- Modify: `/Users/levi/project/IOS/SplitMux/SplitMux/Views/Sidebar/SidebarView.swift`
- Modify: `/Users/levi/project/IOS/SplitMux/SplitMux/Views/Components/EmptyStateView.swift`

**Step 1: Confirm current oversaturated states**

Review the current selected session and CTA styling:

```swift
theme.accentColor.opacity(0.18)
Color(red: 0.4, green: 0.45, blue: 0.95)
Color(red: 0.55, green: 0.4, blue: 0.85)
```

**Step 2: Implement sidebar refinements**

Adjust `SidebarView` so:

- selected cards use lower saturation and less glow
- utility buttons and metadata text are quieter
- the sidebar surface feels layered over the shared canvas

Do not change row information density or interaction model.

**Step 3: Implement empty-state brand alignment**

Adjust `EmptyStateView` so:

- the CTA gradient uses `brandCoral` and `brandAqua`
- supporting text stays calm and neutral
- the illustration remains the focal brand moment

**Step 4: Build to verify**

Run:

```bash
xcodebuild -project /Users/levi/project/IOS/SplitMux/SplitMux.xcodeproj -scheme SplitMux -configuration Debug build
```

Expected: PASS

**Step 5: Commit**

```bash
git add /Users/levi/project/IOS/SplitMux/SplitMux/Views/Sidebar/SidebarView.swift /Users/levi/project/IOS/SplitMux/SplitMux/Views/Components/EmptyStateView.swift
git commit -m "feat: align splitmux light mode branding"
```

### Task 5: Verify chrome integrity and manual visual acceptance

**Files:**
- Verify: `/Users/levi/project/IOS/SplitMux/SplitMux/App/WindowChromeConfigurator.swift`
- Verify: `/Users/levi/project/IOS/SplitMux/scripts/window_chrome_regression.swift`

**Step 1: Run the existing window chrome regression**

Run:

```bash
swiftc -parse-as-library /Users/levi/project/IOS/SplitMux/SplitMux/App/WindowChromeConfigurator.swift /Users/levi/project/IOS/SplitMux/scripts/window_chrome_regression.swift -o /tmp/window_chrome_regression && /tmp/window_chrome_regression
```

Expected: PASS

**Step 2: Run a full debug build**

Run:

```bash
xcodebuild -project /Users/levi/project/IOS/SplitMux/SplitMux.xcodeproj -scheme SplitMux -configuration Debug build
```

Expected: PASS

**Step 3: Launch and manually inspect**

Manual checklist:

- traffic-light buttons remain visible
- no reintroduced window toolbar title strip
- tab strip sits higher and feels integrated
- sidebar and content read as one composition
- empty state CTA matches the brand palette
- one-session and multi-tab states both look balanced

**Step 4: Record any final token adjustments**

If visual balance still feels off, only tweak theme tokens and spacing constants. Do not introduce new component patterns in this pass.

**Step 5: Commit**

```bash
git add /Users/levi/project/IOS/SplitMux/SplitMux/Services/SettingsManager.swift /Users/levi/project/IOS/SplitMux/SplitMux/Views/ContentView.swift /Users/levi/project/IOS/SplitMux/SplitMux/Views/TabContent/TabContentView.swift /Users/levi/project/IOS/SplitMux/SplitMux/Views/TabContent/TabBarView.swift /Users/levi/project/IOS/SplitMux/SplitMux/Views/Components/BreadcrumbBar.swift /Users/levi/project/IOS/SplitMux/SplitMux/Views/Sidebar/SidebarView.swift /Users/levi/project/IOS/SplitMux/SplitMux/Views/Components/EmptyStateView.swift /Users/levi/project/IOS/SplitMux/scripts/window_chrome_regression.swift
git commit -m "feat: polish splitmux light mode shell"
```
