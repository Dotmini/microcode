#!/bin/bash
# =============================================================================
# MicroCode - SHA256 Checksum Verifier
# ตรวจสอบ Checksum เพื่อป้องกัน Malware และการแก้ไขไฟล์โดยไม่ได้รับอนุญาต
# =============================================================================

set -e

CHECKSUM_FILE="CHECKSUMS.sha256"

echo "🔍 MicroCode SHA256 Checksum Verifier"
echo "======================================"

if [ ! -f "$CHECKSUM_FILE" ]; then
    echo "❌ Error: $CHECKSUM_FILE not found!"
    echo "   Run ./generate_checksums.sh first"
    exit 1
fi

echo "📄 Verifying checksums from: $CHECKSUM_FILE"
echo ""

# Verify all checksums
FAILED=0
PASSED=0
MISSING=0

while IFS= read -r line; do
    HASH=$(echo "$line" | awk '{print $1}')
    FILE=$(echo "$line" | awk '{print $2}')
    
    if [ ! -f "$FILE" ]; then
        echo "⚠️  MISSING: $FILE"
        MISSING=$((MISSING + 1))
        continue
    fi
    
    CURRENT_HASH=$(shasum -a 256 "$FILE" | awk '{print $1}')
    
    if [ "$HASH" == "$CURRENT_HASH" ]; then
        PASSED=$((PASSED + 1))
    else
        echo "❌ FAILED:  $FILE"
        echo "   Expected: $HASH"
        echo "   Got:      $CURRENT_HASH"
        FAILED=$((FAILED + 1))
    fi
done < "$CHECKSUM_FILE"

echo ""
echo "======================================"
echo "📊 Results:"
echo "   ✅ Passed:  $PASSED"
echo "   ❌ Failed:  $FAILED"
echo "   ⚠️  Missing: $MISSING"
echo ""

if [ $FAILED -gt 0 ]; then
    echo "🚨 SECURITY ALERT: Some files have been modified!"
    echo "   This could indicate:"
    echo "   - Unauthorized changes"
    echo "   - Malware injection"
    echo "   - Merge conflicts not resolved properly"
    echo ""
    echo "   Please review the failed files before proceeding."
    exit 1
elif [ $MISSING -gt 0 ]; then
    echo "⚠️  Warning: Some files are missing."
    echo "   Run ./generate_checksums.sh to update if files were intentionally removed."
    exit 0
else
    echo "✅ All checksums verified successfully!"
    echo "🔐 Project integrity confirmed."
    exit 0
fi
