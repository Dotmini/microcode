#!/bin/bash
set -euo pipefail

# Pinned, reproducible packaging of EvanBacon/serve-sim (Apache-2.0).
# This runs at build/package time only; Preview never downloads tooling.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="0.1.46"
ARCHIVE="${ROOT}/.build-tools/serve-sim-${VERSION}.tgz"
DESTINATION="${ROOT}/Vendor/serve-sim/${VERSION}"
INTEGRITY="zdKNOv+6qbdCkhtUMEbzX0ymrb2EJK54dZvs+n3YOK15LEcpapGA9/NpSSYEphpI420kTgUWqKNmkxLoWWaVzg=="

if [[ ! -f "${DESTINATION}/dist/serve-sim.js" ]]; then
  mkdir -p "$(dirname "$ARCHIVE")" "$DESTINATION"
  curl --fail --location --silent --show-error \
    "https://registry.npmjs.org/serve-sim/-/serve-sim-${VERSION}.tgz" \
    --output "$ARCHIVE"
  ACTUAL="$(openssl dgst -sha512 -binary "$ARCHIVE" | base64)"
  if [[ "$ACTUAL" != "$INTEGRITY" ]]; then
    echo "serve-sim integrity check failed" >&2
    exit 1
  fi
  tar -xzf "$ARCHIVE" --strip-components=1 -C "$DESTINATION"
fi

# The published CLI intentionally ships without package-lock.json and keeps a
# few runtime imports (notably commander) in devDependencies. Install the
# manifest-pinned graph once while packaging and copy it into the app; Preview
# itself never touches npm or the network.
if [[ ! -d "${DESTINATION}/node_modules/ws" || ! -d "${DESTINATION}/node_modules/commander" ]]; then
  (cd "$DESTINATION" && npm install --include=dev --ignore-scripts --package-lock=false --no-audit --no-fund)
fi
