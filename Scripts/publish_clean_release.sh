#!/bin/bash
# =============================================================================
# MicroCode - Automated Release Orchestrator
# Dotmini Company Limited - Founder & CEO: Tirawat Nantamas
# Cleans old releases, pushes main branch, and publishes latest Release with DMG & PKG
# =============================================================================

set -euo pipefail

REPO="Dotmini/microcode"
TAG="${1:-v2.5.25}"
TITLE="MicroCode ${TAG} — Autonomous Workstation & Realtime Model Engine"
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
echo "🧹 Step 1: Deleting ALL old releases on GitHub ($REPO)..."
OLD_RELEASES=$(gh release list --repo "$REPO" --limit 100 --json tagName -q '.[].tagName' 2>/dev/null || true)

if [ -n "$OLD_RELEASES" ]; then
    for old_tag in $OLD_RELEASES; do
        echo "   🗑️ Deleting release: $old_tag"
        gh release delete "$old_tag" --repo "$REPO" --yes 2>/dev/null || true
    done
    echo "✓ All old releases cleared from GitHub!"
else
    echo "✓ No existing releases found on GitHub"
fi

echo ""
echo "📤 Step 2: Pushing main branch to origin..."
git push origin main

echo ""
echo "🏷️ Step 3: Creating and pushing tag $TAG..."
git tag -d "$TAG" 2>/dev/null || true
git push origin ":refs/tags/$TAG" 2>/dev/null || true
git tag -a "$TAG" -m "$TITLE"
git push origin "$TAG"

echo ""
echo "📦 Step 4: Verifying release artifacts (DMG / PKG)..."
DMG_FILE=$(find "$DIST_DIR" -maxdepth 1 -name "*.dmg" -type f | sort -r | head -n 1)
PKG_FILE=$(find "$DIST_DIR" -maxdepth 1 -name "*.pkg" -type f | sort -r | head -n 1)

if [ -z "$DMG_FILE" ] || [ -z "$PKG_FILE" ]; then
    echo "   ⚠️ Artifacts not found in $DIST_DIR, building them now..."
    APP_PATH="/Volumes/MAC/CodeTunerBuild/apps/MicroCode.app" ./Scripts/build_developer_preview.sh
    DMG_FILE=$(find "$DIST_DIR" -maxdepth 1 -name "*.dmg" -type f | sort -r | head -n 1)
    PKG_FILE=$(find "$DIST_DIR" -maxdepth 1 -name "*.pkg" -type f | sort -r | head -n 1)
fi

echo "   Found DMG: $DMG_FILE"
echo "   Found PKG: $PKG_FILE"

echo ""
echo "🎉 Step 5: Publishing new Release to GitHub ($TAG)..."
gh release create "$TAG" \
    "$DMG_FILE" \
    "$PKG_FILE" \
    --repo "$REPO" \
    --title "$TITLE" \
    --notes "## What's New in MicroCode $TAG

### 🌟 Key Highlights
- **Realtime Model Catalog**: Native live model discovery via provider endpoints (OpenAI, Anthropic, Gemini, Grok, DeepSeek, Local MLX/Ollama). Zero mock models.
- **Autonomous Agent Workstation**: Uncapped 24/7 autonomous loop, multi-agent consensus, interactive tool approval, and live device bezels.
- **Security & Integrity Hardening**: 100-step secret audit passed. All local secrets, plists, and sensitive credentials strictly decoupled and ignored.
- **Hardware Integration**: Metal-accelerated UI, Apple Silicon SIMD rendering, and responsive multi-window dock.

### 📥 Downloads
- **macOS Installer (PKG)**: $(basename "$PKG_FILE")
- **Disk Image (DMG)**: $(basename "$DMG_FILE")

---
*Dotmini Company Limited — Founder & CEO: Tirawat Nantamas*" \
    --latest

echo ""
echo "=================================================="
echo "✅ Release $TAG successfully published!"
echo "   URL: https://github.com/$REPO/releases/tag/$TAG"
echo "=================================================="
