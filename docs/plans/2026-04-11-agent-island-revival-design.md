# Agent Island Revival Design

**Goal**

Reintroduce a top-centered floating agent capsule for the macOS app using a stable `NSPanel` child-window pattern, without depending on iPhone Dynamic Island APIs.

**Findings From Git History**

- The current repository history does not contain committed `AgentIslandPanelController` or `AgentIslandView` files.
- The closest committed floating-window implementation is [`FloatingZoomButton`](../../SplitMux/Views/Components/FloatingZoomButton.swift), which uses a child `NSPanel` above terminal-backed views.
- The current `dev`/`main` codebase already has agent state in `ClaudeHookService` and a detailed `Agent Dashboard`, but no top floating capsule.

**Chosen Approach**

1. Add a pure `AgentIslandSnapshot` model that derives the visible capsule state from `ClaudeHookService.agentInfos` plus session/tab metadata.
2. Add unit tests for snapshot prioritization and metadata resolution.
3. Implement a dedicated `AgentIslandOverlay` using an `NSPanel` child window anchored to the main app window.
4. Show the capsule only when there are tracked agents.
5. Keep the capsule interaction simple and stable: click opens the Agent Dashboard.

**Non-Goals**

- Recreating an unverified historical UI pixel-for-pixel.
- Building a system-wide floating island outside the app window.
- Adding drag, resize, or complex expand/collapse choreography in this pass.
