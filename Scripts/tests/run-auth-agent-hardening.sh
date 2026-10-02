#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

# Auto-detect high-capacity external build volume if mounted
if [ -d "/Volumes/MAC/CodeTunerBuild" ]; then
  export TMPDIR="/Volumes/MAC/CodeTunerBuild/tmp"
  export CARGO_TARGET_DIR="/Volumes/MAC/CodeTunerBuild/cargo-target"
  export CARGO_HOME="/Volumes/MAC/CodeTunerBuild/cargo-home"
elif [ -d "/Volumes/MicroCodeBuild" ]; then
  export TMPDIR="/Volumes/MicroCodeBuild/tmp"
  export CARGO_TARGET_DIR="/Volumes/MicroCodeBuild/cargo-target"
  export CARGO_HOME="/Volumes/MicroCodeBuild/cargo-home"
fi
mkdir -p "${TMPDIR:-/tmp}" "${CARGO_TARGET_DIR:-}" "${CARGO_HOME:-}" 2>/dev/null || true

audit_test_dir=$(mktemp -d "${TMPDIR:-/tmp}/microcode-hardening.XXXXXX")
trap 'rm -rf "$audit_test_dir"' EXIT
swiftc MicroCode/Services/SupabaseAuthService.swift \
  MicroCode/Models/ToolApprovalModels.swift \
  MicroCode/Services/WorkspacePathPolicy.swift \
  MicroCode/Services/LocalBackendAuth.swift \
  MicroCode/Kernel/CloudGPUService.swift \
  Scripts/tests/auth-agent-hardening-regression.swift \
  -o "$audit_test_dir/regression"
"$audit_test_dir/regression"
swiftc MicroCode/Services/SupabaseAuthService.swift \
  Scripts/tests/supabase-session-regression.swift -o "$audit_test_dir/session"
"$audit_test_dir/session"
python3 Scripts/tests/shared-memory-auth-regression.py
cargo test --manifest-path Scripts/tests/rust-security/Cargo.toml -j 2
