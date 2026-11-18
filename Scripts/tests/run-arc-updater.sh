#!/bin/bash
# Arc auto-updater regression (real ArcToolchain.swift + ArcToolchainUpdater.swift).
# Pass --live <arc-source-repo> to also build and install from that repo into a temporary managed root.
set -euo pipefail
cd "$(dirname "$0")/../.."
for d in /Volumes/MAC/CodeTunerBuild /Volumes/MicroCodeBuild; do [ -d "$d" ] && export TMPDIR="$d/tmp" && break; done
mkdir -p "${TMPDIR:-/tmp}"
out_dir=$(mktemp -d "${TMPDIR:-/tmp}/microcode-arc-updater.XXXXXX")
trap 'rm -rf "$out_dir"' EXIT
cp Scripts/tests/arc-updater-regression.swift "$out_dir/main.swift"
swiftc MicroCode/Services/ArcToolchain.swift MicroCode/Services/ArcToolchainUpdater.swift "$out_dir/main.swift" -o "$out_dir/arc-updater"
"$out_dir/arc-updater"
if [ "${1:-}" = "--live" ]; then
  cp Scripts/tests/arc-updater-live.swift "$out_dir/main.swift"
  swiftc MicroCode/Services/ArcToolchain.swift MicroCode/Services/ArcToolchainUpdater.swift "$out_dir/main.swift" -o "$out_dir/arc-updater-live"
  # The real managed root is under "Application Support": test with a space in the path.
  "$out_dir/arc-updater-live" "${2:?arc source repo path}" "$out_dir/Application Support/arc"
fi
