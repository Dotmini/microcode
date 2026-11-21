---
name: agent-desktop
description: Operate macOS desktop applications headlessly via OS Accessibility Trees (`vercel-labs/agent-desktop` v1.3.1 In-Process FFI + OpenThai 2.0 OCR Hybrid Fallback). Use whenever reading UI state, clicking buttons, filling forms, navigating menu bars/sheets/popovers, managing notifications, or automating desktop GUI apps without screenshots or moving the user's mouse.
---

# Agent-Desktop Semantic Computer Use Skill

MicroCode embeds **`agent-desktop` v1.3.1** (`libagent_desktop_ffi.dylib` ABI v7 in-process + full 57-command native binary) combined with **OpenThai 2.0 OCR** fallback.

## Core Observe → Act → Verify Loop (Zero Screenshots Needed)

1. **Map dense apps first (`skeleton`)**:
   - Call `agent_desktop` with `{"command": "skeleton", "app": "Slack"}` (or `"command": "snapshot"` for compact apps like `"Finder"` or `"Notes"`).
   - Every interactive element carries a **snapshot-qualified ref** such as `"@s8f3k2p9:e8"`.
2. **Drill into a region (`drill`)**:
   - Call `{"command": "drill", "app": "Slack", "root": "@s8f3k2p9:e3"}` to expand only that container while saving 80–95% context tokens.
3. **Act headlessly on an exact ref (`click`, `type`, `select`, `toggle`)**:
   - Call `{"command": "click", "ref": "@s8f3k2p9:e8"}` or `{"command": "type", "ref": "@s8f3k2p9:e12", "text": "ข้อความภาษาไทย"}`.
   - Default policy is **100% Headless** (`headed: false`): uses `AXPress` / `AXShowMenu` / semantic value injection without moving the user's cursor or stealing focus.
   - If the UI changed since the snapshot, the call returns `STALE_REF` or `AMBIGUOUS_TARGET` — never guess; take a fresh `snapshot` and act on the new ref.
4. **Verify by re-reading**:
   - AX return codes alone do not prove visual effect. Re-run `snapshot` or `get` / `is` (`{"command": "get", "ref": "@s8f3k2p9:e12", "property": "value"}`) to verify.

## macOS System Surfaces & Ghost Cursor

- **Menu Bar & Open Menus**: Inspect `"surface": "menubar"` for `File`, `Edit`, `View`, click an item headlessly, then inspect `"surface": "menu"`.
- **Sheets, Alerts & Popovers**: When an action opens a modal sheet or popover, inspect `"surface": "sheet"`, `"alert"`, or `"popover"`.
- **Status Items & Dock**: Use `"surface": "menu-bar-extras"` or `"surface": "dock"`.
- **Click-Through Ghost Cursor**: Enable visual telemetry without moving the real pointer via `{"command": "cursor-overlay", "mode": "enable"}`.
- **Canvas / Custom Metal / Simulator Fallback**: When a window exposes `ref_count == 0` (e.g., WebGL/Canvas/Simulator), `agent_desktop` automatically triggers **OpenThai 2.0 OCR + Set-of-Mark** (`hybrid_openthai_ocr_fallback`) and pairs seamlessly with `computer_use` (`mark_id`).

## Security Guardrails

- Sensitive apps (`Keychain Access`, `SecurityAgent`, `Passwords`, `1Password`, `Bitwarden`, `System Settings`) and destructive quit/logout chords (`cmd+q`, `ctrl+cmd+q`) are hard-blocked by MicroCode's Security Shield.
