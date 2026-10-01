#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
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
