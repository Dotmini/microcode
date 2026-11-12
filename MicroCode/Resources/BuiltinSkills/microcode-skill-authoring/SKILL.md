---
name: microcode-skill-authoring
description: How to write a good Agent Skill (SKILL.md) - frontmatter limits, a description that triggers reliably, progressive disclosure, bundled scripts and references, and how to test it. Use when creating, crystallising, reviewing or improving a skill, or when a skill never triggers or triggers wrongly.
license: MIT
metadata:
  owner: MicroCode
  sources: "Agent Skills open specification (agentskills.io); Anthropic Agent Skills best practices; anthropics/skills repository"
---

# Writing a Skill

A skill is a folder with a `SKILL.md`. The agent sees only `name` and `description` until the task matches; then it loads the body; then it opens bundled files only when needed. Write for that order.

## Frontmatter
- `name`: lowercase letters, digits and hyphens, at most 64 characters, equal to the folder name.
- `description`: at most 1024 characters. Say what the skill does and when to use it, in the third person. The description is the trigger; the body is never read if it does not match.
- Optional: `license`, `compatibility`, `metadata`, `allowed-tools`.

## A description that triggers
- Front-load concrete triggers: file types, tools, tasks, error strings, the words a user would actually type.
- Bad: "Helps with documents." Good: "Extracts text and tables from PDF files, fills PDF forms, merges and splits PDFs. Use when the user mentions a .pdf, forms, or document extraction."
- Describe one job. If the description needs "and also", split the skill.

## Body
- Keep it under about 500 lines and a few thousand tokens. Lead with the rules the agent must follow, then the procedure, then pointers.
- Give the default and an escape hatch, not a menu of equal options. Say what to do first.
- Use one term per concept throughout. Avoid dates and version-sensitive claims; link to the source instead.
- Explain why a rule exists when it is not obvious; an agent applies a reason to new cases and a bare rule only to the case it was written for.
- Use a checklist for fragile multi-step work, and say how to verify each step.

## Progressive disclosure
- `references/`: long documentation, schemas, API notes. Link them from `SKILL.md` one level deep; do not chain references through other references.
- `scripts/`: deterministic work (parsing, conversion, validation). Say whether the agent should run the script or read it. A script is cheaper and more reliable than regenerating the same code each time.
- `assets/`: templates and static files the output uses.

## Test it
1. Write three real prompts the skill should handle and two it should ignore.
2. Run them with and without the skill and compare. If the result is no better, the skill is noise; delete it.
3. If it did not trigger, rewrite the description with the user's own wording. If it triggered but failed, fix the body.
4. Re-test after every edit.

## What not to put in
Marketing language, praise, restated common knowledge, secrets, absolute local paths, and instructions that only work on one machine.
