#!/bin/bash
# =============================================================================
# MicroCode - SHA256 Checksum Generator v2.0
# สร้าง Checksum สำหรับ Source Files ทั้งหมด
# ใช้สำหรับตรวจสอบความถูกต้องและป้องกัน Malware
#
# Usage: ./generate_checksums.sh [--verify] [--quiet]
# =============================================================================

set -e

CHECKSUM_FILE="CHECKSUMS.sha256"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUIET=false
VERIFY_AFTER=false

# Parse args
for arg in "$@"; do
    case $arg in
        --quiet|-q) QUIET=true ;;
        --verify|-v) VERIFY_AFTER=true ;;
    esac
done

[ "$QUIET" = false ] && echo "🔐 MicroCode SHA256 Checksum Generator v2.0"
[ "$QUIET" = false ] && echo "============================================"

# Backup existing checksums
if [ -f "$CHECKSUM_FILE" ]; then
    cp "$CHECKSUM_FILE" "${CHECKSUM_FILE}.bak"
fi

# ลบไฟล์เก่า
rm -f "$CHECKSUM_FILE"

# Function to hash files in a directory
hash_files() {
    local dir="$1"
    local pattern="$2"
    local label="$3"
    
    if [ -d "$dir" ]; then
        local count=0
        while IFS= read -r -d '' file; do
            shasum -a 256 "$file" >> "$CHECKSUM_FILE"
            ((count++))
        done < <(find "$dir" -name "$pattern" -type f -print0 | sort -z)
        [ "$QUIET" = false ] && [ "$count" -gt 0 ] && echo "  📁 $label: $count files"
    fi
}

[ "$QUIET" = false ] && echo "📁 Generating checksums for source files..."

# Swift Sources
hash_files "CodeTunner" "*.swift" "Swift sources"

# ObjC++ Sources (CodeTunnerSupport) - multiple patterns
if [ -d "CodeTunnerSupport" ]; then
    count=0
    while IFS= read -r -d '' file; do
        shasum -a 256 "$file" >> "$CHECKSUM_FILE"
        ((count++))
    done < <(find CodeTunnerSupport \( -name "*.mm" -o -name "*.m" -o -name "*.h" \) -type f -print0 | sort -z)
    [ "$QUIET" = false ] && [ "$count" -gt 0 ] && echo "  📁 ObjC++ sources: $count files"
fi

# Rust Backend Sources
hash_files "backend/src" "*.rs" "Rust backend"

# Extension Host (Rust)
hash_files "extension-host/src" "*.rs" "Extension host"

# VSCode Compat Host (TypeScript/JS)
if [ -d "vscode-compat-host/src" ]; then
    count=0
    while IFS= read -r -d '' file; do
        shasum -a 256 "$file" >> "$CHECKSUM_FILE"
        ((count++))
    done < <(find vscode-compat-host/src \( -name "*.ts" -o -name "*.js" \) -type f -print0 | sort -z)
    [ "$QUIET" = false ] && [ "$count" -gt 0 ] && echo "  📁 VSCode compat: $count files"
fi

# Critical Config Files
for config in Package.swift backend/Cargo.toml build.sh; do
    if [ -f "$config" ]; then
        shasum -a 256 "$config" >> "$CHECKSUM_FILE"
    fi
done

# Count entries
COUNT=$(wc -l < "$CHECKSUM_FILE" | tr -d ' ')

[ "$QUIET" = false ] && echo ""
[ "$QUIET" = false ] && echo "✅ Generated $COUNT checksums"
[ "$QUIET" = false ] && echo "📄 Saved to: $CHECKSUM_FILE"

# Show diff if backup existed
if [ -f "${CHECKSUM_FILE}.bak" ]; then
    DIFF=$(diff "$CHECKSUM_FILE" "${CHECKSUM_FILE}.bak" 2>/dev/null || true)
    if [ -n "$DIFF" ]; then
        CHANGED=$(diff "$CHECKSUM_FILE" "${CHECKSUM_FILE}.bak" | grep "^[<>]" | wc -l | tr -d ' ')
        [ "$QUIET" = false ] && echo "   📝 $CHANGED lines changed since last generation"
    else
        [ "$QUIET" = false ] && echo "   ✅ No changes from previous checksums"
    fi
    rm -f "${CHECKSUM_FILE}.bak"
fi

[ "$QUIET" = false ] && echo ""
[ "$QUIET" = false ] && echo "🔐 To verify: ./verify_checksums.sh"

# Optionally verify after generating
if [ "$VERIFY_AFTER" = true ]; then
    echo ""
    echo "🔍 Verifying generated checksums..."
    chmod +x verify_checksums.sh
    ./verify_checksums.sh
fi
