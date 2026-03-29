# Glass Sidebar Demo Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a standalone macOS SwiftUI demo at `/Users/levi/project/IOS/GlassSidebarDemo` with a translucent left sidebar and a dynamic right content panel inspired by the provided reference.

**Architecture:** The demo will be a separate macOS app project. SwiftUI handles layout, state, animation, and most rendering. Small AppKit bridges handle window chrome and, if needed, stronger material/vibrancy surfaces.

**Tech Stack:** SwiftUI, AppKit bridge types, Xcode project generation via `xcodegen` if available or Xcode default project format, macOS app target

---

### Task 1: Create the standalone project skeleton

**Files:**
- Create: `/Users/levi/project/IOS/GlassSidebarDemo/project.yml`
- Create: `/Users/levi/project/IOS/GlassSidebarDemo/README.md`
- Create: `/Users/levi/project/IOS/GlassSidebarDemo/GlassSidebarDemo/App/GlassSidebarDemoApp.swift`
- Create: `/Users/levi/project/IOS/GlassSidebarDemo/GlassSidebarDemo/Info.plist`

**Step 1: Create the directory structure**

Run:

```bash
mkdir -p /Users/levi/project/IOS/GlassSidebarDemo/GlassSidebarDemo/{App,Models,Views/Components,AppKit,Assets.xcassets}
```

Expected: folders exist for app, models, views, and AppKit helpers.

**Step 2: Write the project definition**

Create `project.yml` with:

- macOS application target
- deployment target aligned to current local toolchain
- source root at `GlassSidebarDemo`

**Step 3: Write the app entry point**

Create `GlassSidebarDemoApp.swift` with a single window scene that mounts the demo root view.

**Step 4: Generate the Xcode project**

Run:

```bash
cd /Users/levi/project/IOS/GlassSidebarDemo && xcodegen generate
```

Expected: `GlassSidebarDemo.xcodeproj` is created.

**Step 5: Commit**

```bash
git -C /Users/levi/project/IOS/GlassSidebarDemo init
git -C /Users/levi/project/IOS/GlassSidebarDemo add .
git -C /Users/levi/project/IOS/GlassSidebarDemo commit -m "chore: scaffold glass sidebar demo"
```

### Task 2: Define the fake data model

**Files:**
- Create: `/Users/levi/project/IOS/GlassSidebarDemo/GlassSidebarDemo/Models/DemoItem.swift`
- Create: `/Users/levi/project/IOS/GlassSidebarDemo/GlassSidebarDemo/Models/DemoSection.swift`
- Create: `/Users/levi/project/IOS/GlassSidebarDemo/GlassSidebarDemo/Models/DemoStore.swift`

**Step 1: Write the model types**

Create lightweight models for:

- a sidebar item
- a sidebar section
- the store holding sections and selected item

**Step 2: Seed the fake data**

Populate the store with a few app-like cards and list items that can drive content changes.

**Step 3: Keep selection logic local**

Expose `selectedItem` and a `select(_:)` function.

**Step 4: Verify models compile**

Run:

```bash
xcodebuild -project /Users/levi/project/IOS/GlassSidebarDemo/GlassSidebarDemo.xcodeproj -scheme GlassSidebarDemo -configuration Debug build
```

Expected: build succeeds or only fails on missing view files from later tasks.

**Step 5: Commit**

```bash
git -C /Users/levi/project/IOS/GlassSidebarDemo add .
git -C /Users/levi/project/IOS/GlassSidebarDemo commit -m "feat: add demo selection models"
```

### Task 3: Build the visual shell and background

**Files:**
- Create: `/Users/levi/project/IOS/GlassSidebarDemo/GlassSidebarDemo/Views/DemoRootView.swift`
- Create: `/Users/levi/project/IOS/GlassSidebarDemo/GlassSidebarDemo/Views/Components/AtmosphericBackgroundView.swift`
- Create: `/Users/levi/project/IOS/GlassSidebarDemo/GlassSidebarDemo/Views/Components/GlassCard.swift`

**Step 1: Create the root composition**

Build a top-level `ZStack` with:

- atmospheric background
- main content shell
- floating search overlay

**Step 2: Add reusable surface styling**

Create a reusable glass-style card/container with:

- rounded corners
- subtle stroke
- layered opacity
- shadow

**Step 3: Add the full-window background**

Implement a dark gradient background with a soft teal glow and low-noise feel using gradients and blurred shapes.

**Step 4: Verify the composition renders**

Run:

```bash
xcodebuild -project /Users/levi/project/IOS/GlassSidebarDemo/GlassSidebarDemo.xcodeproj -scheme GlassSidebarDemo -configuration Debug build
```

Expected: project builds with the root view wired in.

**Step 5: Commit**

```bash
git -C /Users/levi/project/IOS/GlassSidebarDemo add .
git -C /Users/levi/project/IOS/GlassSidebarDemo commit -m "feat: add demo visual shell"
```

### Task 4: Implement the left sidebar

**Files:**
- Create: `/Users/levi/project/IOS/GlassSidebarDemo/GlassSidebarDemo/Views/Components/SidebarPanelView.swift`
- Create: `/Users/levi/project/IOS/GlassSidebarDemo/GlassSidebarDemo/Views/Components/SidebarIconGridView.swift`
- Create: `/Users/levi/project/IOS/GlassSidebarDemo/GlassSidebarDemo/Views/Components/SidebarRowView.swift`

**Step 1: Build the sidebar layout**

Add:

- top controls/search affordance
- icon grid
- grouped list items

**Step 2: Add hover and selected states**

Use SwiftUI hover tracking and animations for:

- row hover lift/brightness
- selected row highlight

**Step 3: Connect selection to the store**

Clicking a row updates the selected item in `DemoStore`.

**Step 4: Verify the sidebar behavior**

Run:

```bash
xcodebuild -project /Users/levi/project/IOS/GlassSidebarDemo/GlassSidebarDemo.xcodeproj -scheme GlassSidebarDemo -configuration Debug build
```

Expected: build succeeds with interactive sidebar code in place.

**Step 5: Commit**

```bash
git -C /Users/levi/project/IOS/GlassSidebarDemo add .
git -C /Users/levi/project/IOS/GlassSidebarDemo commit -m "feat: add glass sidebar navigation"
```

### Task 5: Implement the right content panel and floating search surface

**Files:**
- Create: `/Users/levi/project/IOS/GlassSidebarDemo/GlassSidebarDemo/Views/Components/ContentPanelView.swift`
- Create: `/Users/levi/project/IOS/GlassSidebarDemo/GlassSidebarDemo/Views/Components/FloatingSearchPanelView.swift`
- Create: `/Users/levi/project/IOS/GlassSidebarDemo/GlassSidebarDemo/Views/Components/PreviewRailView.swift`

**Step 1: Build the right-side content structure**

Implement:

- top nav labels
- editorial headline
- subtitle/caption
- abstract lower content rail

**Step 2: Bind content to selected item**

Selected sidebar item updates:

- main title
- subtitle
- accent usage
- bottom preview cards

**Step 3: Add the floating search panel**

Place a centered-lower overlay panel with:

- search field
- a few fake results
- blur and shadow

**Step 4: Add restrained transitions**

Use opacity, offset, and spring timing to make content updates feel intentional.

**Step 5: Verify the end-to-end UI**

Run:

```bash
xcodebuild -project /Users/levi/project/IOS/GlassSidebarDemo/GlassSidebarDemo.xcodeproj -scheme GlassSidebarDemo -configuration Debug build
```

Expected: build succeeds with the full composition.

**Step 6: Commit**

```bash
git -C /Users/levi/project/IOS/GlassSidebarDemo add .
git -C /Users/levi/project/IOS/GlassSidebarDemo commit -m "feat: add dynamic content panel"
```

### Task 6: Add AppKit window polish and run verification

**Files:**
- Create: `/Users/levi/project/IOS/GlassSidebarDemo/GlassSidebarDemo/AppKit/WindowChromeView.swift`
- Create: `/Users/levi/project/IOS/GlassSidebarDemo/GlassSidebarDemo/AppKit/VisualEffectBlur.swift`
- Modify: `/Users/levi/project/IOS/GlassSidebarDemo/GlassSidebarDemo/App/GlassSidebarDemoApp.swift`

**Step 1: Add window chrome configuration**

Configure:

- hidden title bar
- full-size content view
- transparent background behavior where appropriate

**Step 2: Add visual effect bridge if SwiftUI materials are insufficient**

Wrap `NSVisualEffectView` so key panels can opt into stronger macOS vibrancy.

**Step 3: Build the release-quality demo**

Run:

```bash
xcodebuild -project /Users/levi/project/IOS/GlassSidebarDemo/GlassSidebarDemo.xcodeproj -scheme GlassSidebarDemo -configuration Debug build
```

Expected: `** BUILD SUCCEEDED **`

**Step 4: Launch the app**

Run:

```bash
open /Users/levi/Library/Developer/Xcode/DerivedData/GlassSidebarDemo-*/Build/Products/Debug/GlassSidebarDemo.app
```

Expected: the demo opens as a standalone macOS window.

**Step 5: Commit**

```bash
git -C /Users/levi/project/IOS/GlassSidebarDemo add .
git -C /Users/levi/project/IOS/GlassSidebarDemo commit -m "feat: polish mac demo window"
```
