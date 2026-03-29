#!/bin/bash
set -e

# Configuration
ALPINE_VERSION="3.19.0"
ALPINE_ARCH="aarch64" # Assuming Apple Silicon (M1/M2/M3) based on user environment
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/${ALPINE_ARCH}/alpine-minirootfs-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz"
WORK_DIR="./build_alpine"
OUTPUT_DIR="../vm_assets"
MOUNT_TAG="microcode_share"
MOUNT_POINT="/mnt/project"

echo "🚀 Starting Micro-VM Image Builder (Alpine Linux)"
echo "---------------------------------------------------"

# 1. Prepare Directories
mkdir -p "$WORK_DIR/rootfs"
mkdir -p "$OUTPUT_DIR"

# 2. Download Alpine Mini RootFS
if [ ! -f "$WORK_DIR/alpine.tar.gz" ]; then
    echo "⬇️  Downloading Alpine Mini RootFS..."
    curl -o "$WORK_DIR/alpine.tar.gz" "$ALPINE_URL"
else
    echo "✅ Alpine tarball already exists."
fi

# 3. Extract RootFS
echo "📦 Extracting RootFS..."
tar -xzf "$WORK_DIR/alpine.tar.gz" -C "$WORK_DIR/rootfs"

# 4. Configure VirtioFS Automount (Option B)
echo "🔧 Configuring /etc/fstab for VirtioFS..."
mkdir -p "$WORK_DIR/rootfs${MOUNT_POINT}"

# Append to fstab
# syntax: <file system> <mount point> <type> <options> <dump> <pass>
echo "# MicroCode Share Automount" >> "$WORK_DIR/rootfs/etc/fstab"
echo "$MOUNT_TAG $MOUNT_POINT virtiofs rw,relatime 0 0" >> "$WORK_DIR/rootfs/etc/fstab"

# 5. Network Configuration (Optional but recommended)
echo "🌐 Configuring Networking (DHCP)..."
cat <<EOF > "$WORK_DIR/rootfs/etc/network/interfaces"
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

# 6. Create Init Script (Simulated Init)
# Since we are making a simple initramfs, we need an init executable if we don't use the default OpenRC flow.
# However, standard Alpine initramfs uses /init.
# For this "Micro-VM", we will let the kernel boot into /sbin/init (OpenRC) which reads fstab.
# But we need to make sure 'virtiofs' module is loaded or built-in.
# Assuming formatting as cpio.gz for initrd.

echo "📦 Packaging initramfs.cpio.gz..."
cd "$WORK_DIR/rootfs"
find . | cpio -o -H newc | gzip > "../../$OUTPUT_DIR/initramfs-${ALPINE_VERSION}-${ALPINE_ARCH}.cpio.gz"
cd ../..

echo "---------------------------------------------------"
echo "✅ Build Complete!"
echo "📂 Initramfs: $OUTPUT_DIR/initramfs-${ALPINE_VERSION}-${ALPINE_ARCH}.cpio.gz"
echo ""
echo "👉 Usage in Rust Manager:"
echo "   MicroVM::new("
echo "       \"/path/to/vmlinuz\", "
echo "       \"path/to/$OUTPUT_DIR/initramfs-${ALPINE_VERSION}-${ALPINE_ARCH}.cpio.gz\","
echo "       Some(\"console=hvc0 root=/dev/ram0 rw init=/sbin/init\")"
echo "   );"
echo ""
echo "⚠️  Note: You still need a compatible Kernel ('vmlinuz') that has virtio-fs support enabled."
echo "   You can extract one from a standard Alpine ISO or build one."
