---
name: microcode-anti-slop
description: Quality bar that keeps agent output from reading as generic AI filler - in prose, code and UI. Use whenever you write user-facing text, code, commit messages, docs or interface designs, and before finalising a reply. Pairs with the slop_check tool and the frontend-design skill.
license: MIT
metadata:
  owner: MicroCode
  always_on: "true"
  tool: slop_check
  lint: "slop:ignore-file"
---

# MicroCode Anti-Slop

Slop is output that could have been written for anyone about anything. It has no specific subject, no decision behind it, and no cost to produce. The fix is never a longer prompt; it is a specific choice made for this task.

## Prose
Every sentence must tell the reader something they did not already know. Cut it otherwise.
- No openers or closers: "Certainly!", "Great question", "I'd be happy to", "I hope this helps", "Let me know if", "In conclusion", "Overall,".
- No filler verbs or adjectives: delve, leverage, unlock, elevate, empower, seamless, robust, powerful, cutting-edge, game-changer, tapestry, landscape, "it's worth noting that".
- No "not just X but Y", no automatic three-item lists, no em-dash rhythm, no emoji headings.
- Do not restate the question or summarise what you just did. State the result, the evidence, the open risk.
- Use the concrete noun, the number, the file name. Replace "improved performance" with "cold start 1.8 s to 0.6 s".

## Code
Write what a maintainer would be glad to inherit.
- Comments explain why, never what. Delete comments that restate the line below them.
- Never ship placeholders: `TODO: implement`, `...rest of code`, `pass`, `fatalError("not implemented")`, commented-out blocks.
- No swallowed errors: no empty `catch {}`, no `except: pass`. Handle at the layer that can act, or let it propagate.
- No speculative abstraction: an interface with one implementation, a config flag nobody sets, a `Manager`, `Helper` or `Utils` bucket.
- Names say intent. `data`, `result`, `temp`, `handleStuff` do not.
- Reuse the helper the codebase already has before writing a second one. Do not invent APIs; open the definition.
- Tests assert behaviour. A test that mocks everything and asserts nothing is noise.

## UI
Start from the subject, not a template; the frontend-design skill carries the full method.
- Tells to avoid by default: purple-to-blue gradients, gradient text, glass cards everywhere, identical rounded cards with one soft grey shadow, emoji as icons, the icon-title-blurb three-column grid, a big number with a gradient accent as the hero, tracked ALL-CAPS eyebrows, one accented word in every headline, `->` on every button, fade-up on every section, invented testimonials, logos or statistics, lorem ipsum.
- Decide tokens first: 4 to 6 named colours, one or two type families with a real scale, a spacing scale. Spend boldness in one place.
- Ship every state: empty, loading, error, disabled, focus. Keyboard focus must be visible; reduced motion must be respected.
- Real copy only. Name an action the same way through the whole flow: "Save changes" then "Saved".

## Process
Before you finalise: run `slop_check` on the text and files you produced, fix every finding or say why it is intentional, then re-read your reply once and delete anything that carries no information.
