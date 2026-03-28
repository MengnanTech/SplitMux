# SplitMux Light UI Unification Design

**Date:** 2026-03-28

**Context**

SplitMux currently renders as three visually separate layers in light mode:

- the sidebar uses a frosted gradient surface
- the tab area presents as an independent white strip
- the terminal content area is a large pure-white canvas

That split makes the app feel stitched together instead of intentional. Recent titlebar fixes also exposed extra vertical whitespace at the top of the right pane, which made the composition looser and less premium.

This design defines a light-mode refresh that preserves the native macOS traffic-light buttons and titlebar behavior while giving the app a more integrated, branded appearance.

## Goals

- Make the window feel like one coherent surface instead of three disconnected panels.
- Keep the left-top traffic lights visible and native.
- Pull the tab strip visually into the titlebar band without breaking hit targets or layout.
- Use SplitMux brand colors as restrained accents rather than full-surface fills.
- Keep the design aligned with macOS conventions instead of looking like a custom web app.

## Non-Goals

- No dark-mode redesign in this pass.
- No information architecture changes.
- No terminal rendering changes beyond surrounding shell styling.
- No new animation system or large interaction redesign.

## Visual Direction

The chosen direction is **Apple base + brand accent**.

The UI should read as a clean macOS utility first, with SplitMux branding introduced only where it improves recognition:

- base surfaces use warm off-white and foggy gray instead of pure white
- material is used sparingly and softly, mainly in the sidebar shell and active elements
- SplitMux coral and aqua are used for active accents, primary CTA states, and empty-state illustration
- separators are softened or removed where spacing and tonal contrast already define structure

The result should feel calmer, tighter, and more intentional than the current layout.

## Layout Decisions

### Window shell

- Keep the native traffic-light buttons visible in the titlebar region.
- Preserve the hidden textual title and toolbar cleanup work already done for window chrome.
- Treat the full app as one background canvas, not separate left/right slabs.

### Sidebar

- Sidebar remains visually distinct, but as a translucent layer on top of the shared window canvas.
- The selection card becomes more restrained:
  - less saturated blue fill
  - softer border
  - less glow
- Header, footer, and utility buttons keep the current structure but reduce contrast so they support the content instead of competing with it.

### Right pane

- The right pane content should move upward visually by integrating the tab strip into the titlebar band.
- The terminal content itself should not be hard-pinned to the top edge; only the chrome should compress.
- Breadcrumbs become a lightweight contextual row, not a second toolbar.

### Empty state

- Keep the logo-inspired illustration because it already communicates brand identity.
- Replace the current purple CTA with a SplitMux brand gradient based on coral and aqua.
- Keep the typography calm and centered; avoid over-styling.

## Color System

### Base colors

- Window canvas: warm off-white / misty gray, never pure white.
- Sidebar layer: faint material over the same base canvas.
- Elevated active surfaces: slightly brighter white with subtle shadow.
- Borders: very low contrast gray-beige.

### Accent colors

- **Coral** is the action accent.
- **Aqua** is the technical accent.
- Blue/purple should not remain the primary visual accent in light mode.

### Accent usage rules

Accent colors are limited to:

- active tab emphasis
- selected session emphasis
- primary button fills
- branch/highlight indicators where appropriate
- empty-state illustration

They should not be used for broad backgrounds across the whole shell.

## Component-Level Changes

### `ContentView`

- Introduce a unified app canvas behind both sidebar and content.
- Reduce the visual strength of the vertical divider.
- Keep the layout split, but change the perceived background from “two panels” to “one surface with a layered sidebar”.

### `TabContentView`

- Replace the hard `28pt` top spacing with a titlebar-aware spacing model.
- Allow the tab strip to live higher in the chrome band.
- Keep the terminal content, split panes, search, and history behavior unchanged.

### `TabBarView`

- Active tab becomes a lighter, cleaner capsule card.
- Inactive tabs lose unnecessary background weight.
- The add button should visually belong to the tab row rather than floating as a detached symbol.
- The whole bar should feel embedded in the top chrome instead of sitting on a separate slab.

### `BreadcrumbBar`

- Reduce weight and height.
- Tone it down so it acts as metadata, not a toolbar.
- Keep clickable path segments and git branch visibility.

### `SidebarView`

- Keep the existing information density.
- Lower chroma in the selected session state.
- Tune button fills, header text, footer text, and section dividers for a quieter hierarchy.

### `EmptyStateView`

- Update CTA colors to match the SplitMux logo palette.
- Keep the illustration concept.
- Ensure the empty state still feels consistent with the surrounding shell.

### `SettingsManager` / `AppTheme`

- Add light-theme tokens for:
  - app canvas
  - layered glass overlay
  - softened shell border
  - coral accent
  - aqua accent
  - active chrome surface
  - subtle shadow tint
- Avoid scattering raw color literals across view files.

## Interaction Constraints

- No regression in drag behavior for the sidebar divider.
- No regression in tab dragging, tab closing, or session switching.
- No regression in titlebar button visibility.
- No regression in `isMovableByWindowBackground` behavior.

## Validation

Success is:

- the app launches with native traffic lights visible
- the right side no longer reads as a big empty white document
- the tab strip feels integrated into the top of the window
- the sidebar and right pane feel like one coordinated composition
- the brand accents are visible but restrained

Validation should include:

- rebuilding the macOS app
- rerunning the window chrome regression script
- manually checking the light theme with zero sessions, one session, and multiple tabs

