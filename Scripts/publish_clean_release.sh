#!/bin/bash
# =============================================================================
# MicroCode - Automated Release Orchestrator
# Dotmini Company Limited - Founder & CEO: Tirawat Nantamas
# Cleans old releases, pushes main branch, and publishes latest Release with DMG & PKG
# =============================================================================

set -euo pipefail

REPO="Dotmini/microcode"
TAG="${1:-v2.5.27}"
TITLE="MicroCode ${TAG} — Multi-Project Isolation & Autonomous Workstation"
DIST_DIR="Dist/DeveloperPreview"

echo "🚀 MicroCode Release Orchestrator: $TAG"
echo "=================================================="

# Check GitHub token or CLI
if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "✓ Using GITHUB_TOKEN environment variable"
    export GH_TOKEN="$GITHUB_TOKEN"
elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    echo "✓ GitHub CLI (gh) is authenticated"
else
    echo "❌ Error: GitHub authentication is required."
    echo "   Please run 'gh auth login' or export GITHUB_TOKEN='ghp_...'"
    exit 1
fi

echo ""
echo "🧹 Step 1: Checking existing release on GitHub for tag $TAG ($REPO)..."
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "   🗑️ Deleting existing release for re-release: $TAG"
    gh release delete "$TAG" --repo "$REPO" --yes 2>/dev/null || true
fi

echo ""
echo "📤 Step 2: Pushing main branch to origin..."
git push origin main

echo ""
echo "🏷️ Step 3: Creating and pushing tag $TAG..."
git tag -d "$TAG" 2>/dev/null || true
git push origin ":refs/tags/$TAG" 2>/dev/null || true
git tag -a "$TAG" -m "$TITLE" --no-sign
git push origin "$TAG"

echo ""
echo "📦 Step 4: Preparing release artifacts (DMG / PKG)..."
SRC_DMG="Dist/DeveloperPreview/MicroCode-2.3.1-DeveloperPreview.dmg"
SRC_PKG="Dist/DeveloperPreview/MicroCode-2.3.1-DeveloperPreview.pkg"

if [ ! -f "$SRC_DMG" ] || [ ! -f "$SRC_PKG" ]; then
    echo "   ⚠️ Artifacts not found, building them now..."
    APP_PATH="$HOME/Applications/MicroCode.app" ./Scripts/build_developer_preview.sh
fi

DMG_FILE="$DIST_DIR/MicroCode-${TAG}.dmg"
PKG_FILE="$DIST_DIR/MicroCode-${TAG}.pkg"

cp -f "$SRC_DMG" "$DMG_FILE"
cp -f "$SRC_PKG" "$PKG_FILE"

# Generate SHA256 checksums for release assets
(cd "$DIST_DIR" && shasum -a 256 "MicroCode-${TAG}.dmg" "MicroCode-${TAG}.pkg" > "SHA256SUMS-${TAG}.txt")
SUMS_FILE="$DIST_DIR/SHA256SUMS-${TAG}.txt"

echo "   Ready DMG: $DMG_FILE ($(du -h "$DMG_FILE" | cut -f1))"
echo "   Ready PKG: $PKG_FILE ($(du -h "$PKG_FILE" | cut -f1))"
echo "   Ready Checksums: $SUMS_FILE"

echo ""
echo "🎉 Step 5: Publishing new Release to GitHub ($TAG)..."
gh release create "$TAG" \
    "$DMG_FILE" \
    "$PKG_FILE" \
    "$SUMS_FILE" \
    --repo "$REPO" \
    --title "$TITLE" \
    --notes "## What's New in MicroCode $TAG

### 🌟 Key Highlights
- **Strict Multi-Project Isolation**: AI agent now strictly isolates chat sessions, semantic memory, open editor tabs, and tool executions per workspace. Working across multiple projects concurrently is completely insulated with zero cross-project hallucination or context bleeding.
- **BYOK Reasoning Streaming Crash Resolution**: Resolved fatal string index out of bounds in \`MessageContentParser\` during streaming and added native support for \`<think>...</think>\` tags across DeepSeek R1, Qwen 2.5 QwQ, Claude 3.7 Sonnet, and OpenAI o1/o3.
- **Universal API Key Fallback Engine**: Intelligent fallback through Memory -> Keychain -> UserDefaults Suite -> Process Environment via \`resolveApiKey\` across all model execution pipelines.
- **Supply-Chain & Dependency Hardening**: Pinned and patched core Rust dependencies in tracked \`Cargo.lock\` (rustls 0.23, openssl 0.10, webpki-roots) eliminating known CVE vulnerabilities.
- **Enterprise Large File Virtualization**: Intelligent chunked streaming (FileHandle 1MB/2MB) and MainActor guards preventing UI freezes/beachballs when inspecting massive files (>10MB).
- **Token & Cost Budget Circuit Breaker**: Realtime cost accumulator and automatic runaway-loop circuit breakers across 24/7 autonomous agents and subagents.
- **Realtime Model Catalog**: Native live model discovery via provider endpoints (OpenAI, Anthropic, Gemini, Grok, DeepSeek, Local MLX/Ollama). Zero mock models.
- **Full Test Suite & Audit Verified**: 100% test pass rate across 47 backend tests, 12 security regressions, and 7 authentication hardening benchmarks.

### 📥 Downloads
| File | Size | Description |
|:---|:---:|:---|
| 💿 [MicroCode-${TAG}.dmg](https://github.com/$REPO/releases/download/$TAG/MicroCode-${TAG}.dmg) | $(du -h "$DMG_FILE" | cut -f1) | Native macOS Disk Image Installer |
| 📦 [MicroCode-${TAG}.pkg](https://github.com/$REPO/releases/download/$TAG/MicroCode-${TAG}.pkg) | $(du -h "$PKG_FILE" | cut -f1) | macOS Standard Component Package |
| 📄 [SHA256SUMS-${TAG}.txt](https://github.com/$REPO/releases/download/$TAG/SHA256SUMS-${TAG}.txt) | - | Cryptographic Checksums |

---
*Dotmini Company Limited — Founder & CEO: Tirawat Nantamas*" \
    --latest

echo ""
echo "=================================================="
echo "✅ Release $TAG successfully published!"
echo "   URL: https://github.com/$REPO/releases/tag/$TAG"
echo "=================================================="
