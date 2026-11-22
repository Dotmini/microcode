#!/bin/bash
# ot1 web portal client regression: executes the OT object embedded in CollaborationService.swift under Node.
set -euo pipefail
cd "$(dirname "$0")/../.."
node Scripts/tests/collab-ot-web-regression.js MicroCode/Services/CollaborationService.swift
