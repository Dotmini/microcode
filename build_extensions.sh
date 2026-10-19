#!/bin/bash
set -e

echo "🚀 Building MicroCode Extension System..."

if [ -n "${CODETUNER_BUILD_ROOT:-}" ]; then
    BUILD_ROOT="$CODETUNER_BUILD_ROOT"
elif [ -d "/Volumes/MicroCodeBuild" ]; then
    BUILD_ROOT="/Volumes/MicroCodeBuild"
elif [ -d "/Volumes/XcodeWork" ]; then
    BUILD_ROOT="/Volumes/XcodeWork/MicroCodeBuild"
elif [ -d "/Volumes/MAC" ]; then
    BUILD_ROOT="/Volumes/MAC/CodeTunerBuild"
else
    BUILD_ROOT="$(pwd)/.build"
fi

export CARGO_HOME="$BUILD_ROOT/cargo-home"
export CARGO_TARGET_DIR="$BUILD_ROOT/cargo-target"

# 1. Build VSCode Compat Host (Node)
echo "🟢 Building vscode-compat-host..."
cd vscode-compat-host
if [ ! -d "node_modules" ]; then
    npm install
fi
./node_modules/.bin/tsc
cp -f dist/index.js dist/api.js src/ 2>/dev/null || true
cd ..

# 2. Build & Package Official MicroCode VS Code Extension (.vsix)
echo "⚡ Building & Packaging vscode-extension (dotmini.microcode-vscode)..."
cd vscode-extension
../vscode-compat-host/node_modules/.bin/tsc -p ./
node ./scripts/package_vsix.js
cd ..

if [[ "${1:-}" == "--with-rust-host" ]]; then
    echo "📦 Building extension-host & microcode-ext (Rust)..."
    (cd extension-host && cargo build)
    (cd microcode-ext && cargo build)
fi

echo "📲 Installing VSIX into local VS Code-based IDEs (Antigravity, Cursor, VS Code, MicroCode)..."
if [ -x "/Applications/Antigravity IDE.app/Contents/Resources/app/bin/antigravity-ide" ]; then
    "/Applications/Antigravity IDE.app/Contents/Resources/app/bin/antigravity-ide" --install-extension vscode-extension/dotmini.microcode-vscode-2.5.27.vsix >/dev/null 2>&1 || true
fi

node -e '
const fs = require("fs");
const path = require("path");
const os = require("os");
const extDir = path.resolve("vscode-extension");
const targets = [
  path.join(os.homedir(), ".antigravity-ide/extensions"),
  path.join(os.homedir(), ".antigravity/extensions"),
  path.join(os.homedir(), ".cursor/extensions"),
  path.join(os.homedir(), ".vscode/extensions")
];
const itemsToCopy = ["package.json", "README.md", "language-configuration.json", "media", "syntaxes", "snippets", "dist"];
for (const dir of targets) {
  fs.mkdirSync(dir, { recursive: true });
  const dest = path.join(dir, "dotmini.microcode-vscode-2.5.27");
  fs.rmSync(dest, { recursive: true, force: true });
  fs.mkdirSync(dest, { recursive: true });
  for (const item of itemsToCopy) {
    const src = path.join(extDir, item);
    if (fs.existsSync(src)) fs.cpSync(src, path.join(dest, item), { recursive: true });
  }
  const regFile = path.join(dir, "extensions.json");
  let list = [];
  if (fs.existsSync(regFile)) {
    try { list = JSON.parse(fs.readFileSync(regFile, "utf8")); } catch { list = []; }
  }
  list = list.filter(item => item?.identifier?.id !== "dotmini.microcode-vscode");
  list.push({
    identifier: { id: "dotmini.microcode-vscode" },
    version: "2.5.27",
    location: { $mid: 1, fsPath: dest, external: "file://" + dest, path: dest, scheme: "file" },
    relativeLocation: "dotmini.microcode-vscode-2.5.27",
    metadata: { installedTimestamp: Date.now(), pinned: true, source: "vsix" }
  });
  fs.writeFileSync(regFile, JSON.stringify(list));
}
const mcDest = path.join(os.homedir(), "Library/Application Support/MicroCode/Extensions/dotmini.microcode-vscode");
fs.mkdirSync(path.dirname(mcDest), { recursive: true });
fs.rmSync(mcDest, { recursive: true, force: true });
fs.mkdirSync(mcDest, { recursive: true });
for (const item of itemsToCopy) {
  const src = path.join(extDir, item);
  if (fs.existsSync(src)) fs.cpSync(src, path.join(mcDest, item), { recursive: true });
}
fs.writeFileSync(path.join(mcDest, "manifest.json"), JSON.stringify({
  id: "dotmini.microcode-vscode",
  name: "MicroCode — AI Agent, Ardium v2.3 & Polyglot Workstation",
  version: "2.5.27",
  author: "Dotmini Software",
  description: "Official MicroCode Extension for VS Code, Cursor, Windsurf & Antigravity.",
  type: "tool",
  runtime: "javascript",
  main: "./dist/extension.js",
  license: "Elastic-2.0",
  keywords: ["microcode", "ardium", "ai-agent", "mcp", "polyglot"]
}, null, 2));
'

echo "✅ Extension System Build & Local IDE Deployment Complete!"
echo "   - Node Compat Host: vscode-compat-host/dist/index.js"
echo "   - Official VSIX:    vscode-extension/dotmini.microcode-vscode-2.5.27.vsix"
echo "   - Installed in:     Antigravity, Antigravity IDE, Cursor, VS Code, MicroCode.app"
