#!/usr/bin/env bash

echo "🧹 MicroCode Project Cleaner"
echo "Cleaning up Rust target directories and Xcode DerivedData..."

echo "--------------------------------------------------------"
echo "Cleaning Backend (usually takes 1-12GB)..."
cd "$(dirname "$0")/backend" && cargo clean

echo "--------------------------------------------------------"
echo "Cleaning Microcode Core (usually takes 1GB)..."
cd "$(dirname "$0")/microcode_core" && cargo clean

echo "--------------------------------------------------------"
echo "Cleaning Preview Agent (usually takes ~300MB)..."
cd "$(dirname "$0")/PreviewAgent" && cargo clean

echo "--------------------------------------------------------"
echo "Cleaning Xcode DerivedData..."
rm -rf ~/Library/Developer/Xcode/DerivedData/MicroCode*

echo "--------------------------------------------------------"
echo "✅ Cleanup Complete! You have recovered gigabytes of free space."
echo "Note: The next time you build the project in Xcode, it will take longer because it has to rebuild from scratch."
