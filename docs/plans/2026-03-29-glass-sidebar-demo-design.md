# Glass Sidebar Demo Design

## Goal

Build a completely separate macOS demo app at `/Users/levi/project/IOS/GlassSidebarDemo` that recreates the visual structure of the reference: a translucent left sidebar and a dark content-heavy right panel. The demo is presentation-focused, not a functional browser or productivity app.

## Scope

In scope:

- Create a new standalone macOS app project outside `SplitMux`
- Use SwiftUI for the full view hierarchy and interaction state
- Use limited AppKit bridging for window chrome and stronger vibrancy/material behavior
- Implement a clickable left navigation list
- Implement a content area on the right that changes based on selection
- Add a floating search surface to reinforce the composition
- Add restrained hover and selection animations

Out of scope:

- Real browser rendering
- Real app launching
- Persistence
- Networking
- Search backend
- Integrating anything into `SplitMux`

## Visual Direction

The demo should feel like a high-end macOS concept:

- Dark atmospheric background with subtle teal/blue gradients
- Left column as a layered translucent glass panel
- Right column as a matte-black content canvas with large typography
- Soft shadows, low-contrast borders, and gentle blur
- Rounded surfaces with depth separation between panels
- Minimal but deliberate animation when selection changes

The reference should be matched by composition and mood, not pixel-perfect cloning.

## Architecture

The new app will be a single-window macOS SwiftUI app. The top-level composition will be:

1. Window background layer
2. Main horizontal shell
3. Left sidebar glass panel
4. Right content presentation area
5. Floating search palette overlay

The app will keep all state local and lightweight. A single observable selection model is enough for the demo.

## Project Structure

Planned structure under `/Users/levi/project/IOS/GlassSidebarDemo`:

- `GlassSidebarDemo/App/`
- `GlassSidebarDemo/Models/`
- `GlassSidebarDemo/Views/`
- `GlassSidebarDemo/Views/Components/`
- `GlassSidebarDemo/AppKit/`
- `GlassSidebarDemo/Assets.xcassets/`

## Data Model

The demo needs only fake presentation data:

- Sidebar section groups
- Sidebar items
- Content metadata for the right pane

Each sidebar item will drive:

- Title
- Subtitle
- Accent color
- Optional badge or category text
- A few preview cards in the bottom strip

## Sidebar Behavior

The left panel will include:

- A compact toolbar zone at the top
- A search affordance row
- A small icon grid
- A sectioned text list
- A selected row highlight

Interaction behavior:

- Hover slightly brightens the row
- Click updates selected item
- Selected item updates the right content

The sidebar is intentionally fake-data driven and does not need deep interaction logic.

## Right Content Behavior

The right side will include:

- Top navigation labels
- Large editorial headline
- Supporting text
- A couple of abstract content blocks
- Bottom thumbnail rail

The content must respond to the selected sidebar row so the app feels alive. This can be done with animated text and color changes rather than heavy transitions.

## Floating Search Palette

The floating surface is decorative but interactive enough to feel credible:

- Rounded glass panel
- Search field at the top
- A few mock results below
- Blur, shadow, and border separation

It will stay visible in the first version to support the composition.

## AppKit Usage

AppKit should stay constrained to areas where SwiftUI is weaker on macOS polish:

- Configure the window for hidden title bar and full-size content view
- Apply transparent background and better blending
- Provide a reusable `NSVisualEffectView` bridge for glass materials if SwiftUI `Material` is not sufficient in key places

No business logic should live in AppKit types.

## Verification

Success criteria:

- A new app project exists at `/Users/levi/project/IOS/GlassSidebarDemo`
- It builds as a macOS app
- It launches into a single polished window
- The layout clearly shows left glass sidebar and right content area
- Clicking left items changes right content
- The result feels visually close to the provided reference in mood and composition
