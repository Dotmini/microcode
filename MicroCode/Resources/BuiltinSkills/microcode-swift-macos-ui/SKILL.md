---
name: microcode-swift-macos-ui
description: Rules for building native macOS interfaces in SwiftUI and AppKit that look and behave like the platform - type, spacing, colour, controls, keyboard, accessibility, motion and rendering performance. Use when creating or changing any SwiftUI view, window, toolbar, sidebar, settings pane or menu in a Mac app.
license: MIT
metadata:
  owner: MicroCode
  source: "Apple Human Interface Guidelines - macOS (developer.apple.com/design/human-interface-guidelines/macos)"
---

# Native macOS UI (SwiftUI + AppKit)

A Mac app earns trust by behaving like the Mac. Custom chrome that fights the platform reads as a port.

## Type
- Use system text styles, not fixed sizes: `.largeTitle`, `.title`, `.title2`, `.title3`, `.headline`, `.body`, `.callout`, `.subheadline`, `.footnote`, `.caption`. Default body is 13 pt on macOS.
- Hierarchy comes from weight and colour (`.primary`, `.secondary`, `.tertiary`), not from five different sizes in one view.
- Monospace (`.monospaced()`) only for code, paths, hashes and numbers that must align.

## Space and layout
- 8 pt grid. Window content margin 20 pt; 8 pt between related controls; 12 to 20 pt between groups.
- Never hard-code frame sizes for content. Use `minWidth`/`minHeight`, `Grid`, `ViewThatFits`, and let the window resize.
- Structure: `NavigationSplitView` for sidebar apps; `Form` with `.formStyle(.grouped)` for settings; inspector panes on the trailing edge.
- Toolbars: SF Symbol plus `.help("...")` text for every item; group related items; no more than one prominent action.

## Colour and material
- Semantic colours only: `.primary`, `.secondary`, `Color(nsColor: .windowBackgroundColor)`, `.controlBackgroundColor`, `.separatorColor`, `.accentColor`. Never literal black or white for chrome.
- Respect the user's accent colour and both appearances. Check Increase Contrast and Reduce Transparency; text on materials must stay readable.
- Reserve saturated colour for state (error, success, selection) and one brand accent.

## Controls
- Native styles: `.bordered`, `.borderedProminent` for exactly one primary action per view, `.plain` for inline links. `.controlSize(.small)` inside dense inspectors.
- `Toggle` as a switch for immediate settings; checkbox for form selections; `Picker` for 2 to 5 choices; menus beyond that.
- Destructive buttons use `role: .destructive` and a confirmation unless undoable.

## Keyboard, pointer, accessibility
- Every command exists in the menu bar with its standard shortcut: Command-N, W, comma (Settings), F, Z, Shift-Command-Z. Add new shortcuts only when no standard one applies.
- Full keyboard navigation; focus ring visible; sensible `focusable` order; Escape dismisses sheets, Return confirms.
- Icon-only controls need `.accessibilityLabel`. Group composite rows with `.accessibilityElement(children: .combine)`.
- Hover and right-click context menus are shortcuts, never the only path.

## Motion
- Under 0.25 s, ease-in-out or a default spring. Animate state change, not decoration. Honour `@Environment(\.accessibilityReduceMotion)`.

## States
Every list and panel has empty, loading, error and populated states. An empty state says what to do next; an error says what failed and how to fix it. No spinner without a label if it can last over a second.

## Performance
- Keep `body` cheap: no I/O, sorting or formatting inside it. Precompute in the model.
- `@StateObject` for objects the view owns, `@ObservedObject` for injected ones. Stable `id`s. `LazyVStack` for long content. Avoid `AnyView`.
- Streaming text (chat, logs): batch updates to roughly one render per frame instead of one per token.
- Measure with Instruments before optimising; do not guess.

## Check before you finish
Run the app. Look at: small and large window, light and dark, Increase Contrast, Reduce Motion, keyboard-only pass, and a Thai or long-string sample to catch clipping.
