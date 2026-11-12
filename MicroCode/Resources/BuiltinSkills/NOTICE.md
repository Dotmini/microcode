# Built-in Skills — provenance and licences

MicroCode ships these skills inside the app so a fresh install has a quality baseline.
Skills are plain folders; the user can disable any of them in Settings → Agent Skills or override one by placing a skill with the same id in `~/.microcode/skills`.

## Original (MIT, © Dotmini Company Limited)
| id | purpose |
|---|---|
| microcode-harness-core | Agent operating protocol: orient, plan, act, verify, report. Always active. |
| microcode-anti-slop | Quality bar for prose, code and UI. Paired with the `slop_check` tool. Always active. |
| microcode-swift-macos-ui | Native macOS / SwiftUI interface rules. |
| microcode-thai-ui-typography | Thai typography, copy and formatting rules. |
| microcode-security-baseline | Minimum security rules for agent-written code. |
| microcode-skill-authoring | How to write a skill that triggers and helps. |

## Third-party, Apache License 2.0, unmodified
Source: https://github.com/anthropics/skills at commit `2c5958ecac7cee2b583967a2c4981d0f4a75c579`
Each folder keeps its own `LICENSE.txt`. Files are copied verbatim; no changes were made.

| id | upstream path |
|---|---|
| frontend-design | skills/frontend-design |
| webapp-testing | skills/webapp-testing |
| mcp-builder | skills/mcp-builder |
| theme-factory | skills/theme-factory |

## Design references used for the original skills
- Anthropic Engineering: Building effective agents; Effective harnesses for long-running agents; Effective context engineering for AI agents; Writing effective tools for agents.
- OpenAI: A practical guide to building agents; Codex `AGENTS.md` conventions.
- Agent Skills open specification: https://agentskills.io
- Apple Human Interface Guidelines (macOS): https://developer.apple.com/design/human-interface-guidelines/macos
- W3C Thai Layout Requirements: https://www.w3.org/TR/thai-lreq/
- OWASP Top 10, ASVS and LLM Top 10: https://owasp.org
