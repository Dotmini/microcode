#!/bin/bash
# =============================================================================
# MicroCode - SHA256 Checksum Generator v2.0
# สร้าง Checksum สำหรับ Source Files ทั้งหมด
# =============================================================================

CHECKSUM_FILE="CHECKSUMS.sha256"

echo "🔐 MicroCode SHA256 Checksum Generator"
echo "======================================="

rm -f "$CHECKSUM_FILE"
echo "📁 Generating checksums..."

find MicroCode -name "*.swift" -type f | sort | while read f; do shasum -a 256 "$f" >> "$CHECKSUM_FILE"; done
find MicroCodeSupport \( -name "*.mm" -o -name "*.m" -o -name "*.h" \) -type f 2>/dev/null | sort | while read f; do shasum -a 256 "$f" >> "$CHECKSUM_FILE"; done
find backend/src -name "*.rs" -type f 2>/dev/null | sort | while read f; do shasum -a 256 "$f" >> "$CHECKSUM_FILE"; done
find extension-host/src -name "*.rs" -type f 2>/dev/null | sort | while read f; do shasum -a 256 "$f" >> "$CHECKSUM_FILE"; done
find vscode-compat-host/src \( -name "*.ts" -o -name "*.js" \) -type f 2>/dev/null | sort | while read f; do shasum -a 256 "$f" >> "$CHECKSUM_FILE"; done

for config in Package.swift backend/Cargo.toml build.sh; do
    [ -f "$config" ] && shasum -a 256 "$config" >> "$CHECKSUM_FILE"
done

COUNT=$(wc -l < "$CHECKSUM_FILE" | tr -d ' ')
echo "✅ Generated $COUNT checksums"
echo "📄 Saved to: $CHECKSUM_FILE"
echo "🔐 To verify: ./verify_checksums.sh"
