#!/usr/bin/env bash
# ==============================================================================
# MicroCode — Pre-Release Fast Verification Gate (~30s, zero disk bloat)
# Verifies:
#   1. Swift Release WMO (-O -whole-module-optimization) type-checking & <500ms expressions
#   2. Hardcoded secret & non-localhost IP scan (identical to GitHub Actions Security job)
#   3. LICENSE existence & SHA256 checksum regeneration + verification
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

echo "=========================================="
echo "🚦 MicroCode Pre-Release Verification Gate"
echo "=========================================="

# 1. Secret & Hardcoded IP Scan
echo "🔍 [1/4] Scanning for hardcoded secrets & non-localhost IPs..."
FOUND=0
if git grep --untracked -nE "AIza[a-zA-Z0-9_-]{30,}" -- '*.swift' '*.rs' 2>/dev/null; then
    echo "❌ Found Google API key"; FOUND=1
fi
if git grep --untracked -nE "sk-[a-zA-Z0-9]{20,}" -- '*.swift' '*.rs' 2>/dev/null | grep -v 'placeholder\|"sk-..."'; then
    echo "❌ Found OpenAI key"; FOUND=1
fi
if git grep --untracked -nE "AKIA[0-9A-Z]{16}" -- '*.swift' '*.rs' 2>/dev/null; then
    echo "❌ Found AWS key"; FOUND=1
fi
if git grep --untracked -nE "BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY" -- '*.swift' '*.rs' '*.pem' 2>/dev/null; then
    echo "❌ Found private key"; FOUND=1
fi
if git grep --untracked -nE "http://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" -- '*.swift' '*.rs' 2>/dev/null | grep -v "127.0.0.1\|0.0.0.0"; then
    echo "❌ Found hardcoded non-localhost IP"; FOUND=1
fi
if [ ! -f "LICENSE" ]; then
    echo "❌ LICENSE file missing!"; FOUND=1
fi
if [ "$FOUND" -ne 0 ]; then
    echo "🚨 Security pre-flight FAILED"
    exit 1
fi
echo "✅ Security & LICENSE scan passed."

# 2. Zero-disk Swift Release WMO Typecheck (if local SwiftPM module cache is present)
DBG_DIR="$ROOT_DIR/.codetuner-build/swiftpm/codetunner-native/arm64-apple-macosx/debug"
if [ -d "$DBG_DIR/Modules" ] && [ -f "$DBG_DIR/MicroCodeSupport.build/module.modulemap" ]; then
    echo "⚡ [2/4] Running zero-disk Swift Release WMO (-O) type-check..."
    python3 - "$ROOT_DIR" "$DBG_DIR" <<'PY'
import pathlib, re, subprocess, sys

root = sys.argv[1]
dbg = sys.argv[2]
pkg = pathlib.Path(root, "Package.swift").read_text()
m = re.search(r'\.executableTarget\(\s*name:\s*"MicroCode".*?sources:\s*\[(.*?)\]\s*\)', pkg, re.S)
if not m:
    sys.exit("Could not parse MicroCode sources from Package.swift")
# Extract only active (uncommented) Swift files from the sources block
src_block = pkg.split('name: "MicroCode"', 1)[1].split("sources:", 1)[1].split("]", 1)[0]
uncommented_lines = [line.split("//", 1)[0] for line in src_block.splitlines()]
sources = [f"{root}/MicroCode/{s}" for s in re.findall(r'"([^"]+\.swift)"', "\n".join(uncommented_lines))]
accessor = f"{dbg}/MicroCode.build/DerivedSources/resource_bundle_accessor.swift"
if pathlib.Path(accessor).exists():
    sources.append(accessor)

def build_cmd(swiftc_bin, sdk_path):
    return [
        swiftc_bin,
        "-typecheck",
        "-O",
        "-whole-module-optimization",
        "-module-name", "MicroCode",
        "-I", f"{dbg}/Modules",
        "-target", "arm64-apple-macosx13.0",
        "-DSWIFT_PACKAGE",
        "-DSWIFT_MODULE_RESOURCE_BUNDLE_AVAILABLE",
        "-Xcc", f"-fmodule-map-file={dbg}/MicroCodeSupport.build/module.modulemap",
        "-Xcc", "-I", "-Xcc", f"{root}/MicroCodeSupport/include",
        "-Xcc", f"-fmodule-map-file={dbg}/MicroCodeKernel.build/module.modulemap",
        "-Xcc", "-I", "-Xcc", f"{root}/MicroCodeKernel/include",
        "-Xcc", f"-fmodule-map-file={root}/MicrocodeCoreSupport/include/module.modulemap",
        "-Xcc", "-I", "-Xcc", f"{root}/MicrocodeCoreSupport/include",
        "-module-cache-path", f"{dbg}/ModuleCache",
        "-Xfrontend", "-entry-point-function-name", "-Xfrontend", "MicroCode_main",
        "-swift-version", "5",
        "-strict-concurrency=minimal",
        "-Xfrontend", "-solver-expression-time-threshold=300",
        "-Xfrontend", "-warn-long-expression-type-checking=500",
        "-sdk", sdk_path,
        "-Xcc", "-isysroot", "-Xcc", sdk_path,
    ] + sources

clt_swiftc = "/Library/Developer/CommandLineTools/usr/bin/swiftc"
clt_sdk = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
swiftterm_mod = pathlib.Path(dbg, "Modules/SwiftTerm.swiftmodule")
use_clt = False
if swiftterm_mod.exists() and pathlib.Path(clt_swiftc).exists() and pathlib.Path(clt_sdk).exists():
    # Prefer CLT swiftc directly if cached SwiftTerm.swiftmodule was built with 6.2.x while Xcode is 6.4+
    xc_ver = subprocess.check_output(["xcrun", "swiftc", "--version"], text=True, stderr=subprocess.STDOUT)
    if "Swift version 6.4" in xc_ver:
        use_clt = True

if use_clt:
    p = subprocess.run(build_cmd(clt_swiftc, clt_sdk), capture_output=True, text=True)
    combined = p.stdout + "\n" + p.stderr
else:
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    p = subprocess.run(["xcrun"] + build_cmd("swiftc", sdk), capture_output=True, text=True)
    combined = p.stdout + "\n" + p.stderr
    if "module compiled with Swift" in combined and pathlib.Path(clt_swiftc).exists() and pathlib.Path(clt_sdk).exists():
        p = subprocess.run(build_cmd(clt_swiftc, clt_sdk), capture_output=True, text=True)
        combined = p.stdout + "\n" + p.stderr

slow = []
errors = []
for line in combined.splitlines():
    if ": error:" in line:
        errors.append(line)
    elif "expression took" in line:
        slow.append(line)
for s in slow:
    print("  ⚠️ ", s)
if errors:
    for e in errors:
        print("  ❌", e)
    sys.exit(1)
print(f"✅ WMO Release type-check passed across {len(sources)} Swift files ({len(slow)} slow-expression warnings).")
PY
else
    echo "⏩ [2/4] Local SwiftPM debug module cache not initialized; skipping fast WMO type-check."
fi

# 2.5 Verify UniFFI ABI Checksums + microcode_core/Cargo.lock tracking
echo "🧬 [2.5/4] Verifying UniFFI ABI checksums & Cargo.lock determinism..."
if [ ! -f "microcode_core/Cargo.lock" ]; then
    echo "❌ microcode_core/Cargo.lock is missing! CI will pull unpinned uniffi and cause ABI checksum crash."
    exit 1
fi
if [ -f "MicrocodeCoreSupport/libmicrocode_core.dylib" ]; then
    python3 - "MicrocodeCoreSupport/libmicrocode_core.dylib" "MicroCode/Services/MicroCore/microcode_core.swift" <<'PY'
import ctypes, pathlib, re, sys
dylib_path, swift_path = sys.argv[1], sys.argv[2]
swift_src = pathlib.Path(swift_path).read_text()
lib = ctypes.CDLL(dylib_path)
pairs = re.findall(r"(uniffi_microcode_core_checksum_[a-zA-Z0-9_]+)\(\)\s*!=\s*(\d+)", swift_src)
for sym, exp_str in pairs:
    fn = getattr(lib, sym)
    fn.restype = ctypes.c_uint16
    got = fn()
    if got != int(exp_str):
        sys.exit(f"❌ UniFFI checksum mismatch on {sym}: dylib={got} != swift={exp_str}")
print(f"✅ All {len(pairs)} UniFFI ABI checksums match local libmicrocode_core.dylib.")
PY
fi

# 3. Regenerate & Verify SHA256 Checksums
echo "🔐 [3/4] Regenerating SHA256 checksums..."
./generate_checksums.sh | tail -4

echo "🔐 [4/4] Verifying SHA256 checksums..."
./verify_checksums.sh | tail -7

echo "=========================================="
echo "🎉 Release Pre-Flight Ready!"
echo "=========================================="
