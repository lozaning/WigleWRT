#!/bin/bash
# Build OpenWRT .ipk package for WigleWRT

set -e

PKG_DIR="$(cd "$(dirname "$0")" && pwd)/wiglewrt"
BUILD_DIR="$(cd "$(dirname "$0")" && pwd)/build"
OUTPUT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Get version from control file
VERSION=$(grep "^Version:" "$PKG_DIR/CONTROL/control" | cut -d' ' -f2)
PKG_NAME="wiglewrt_${VERSION}_all.ipk"

echo "Building $PKG_NAME..."

# Clean and create build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Create debian-binary
echo "2.0" > "$BUILD_DIR/debian-binary"

# Create control.tar.gz
echo "Creating control archive..."
cd "$PKG_DIR/CONTROL"
chmod +x postinst prerm 2>/dev/null || true

# Calculate installed size
INSTALLED_SIZE=$(du -sk "$PKG_DIR/data" | cut -f1)
sed -i.bak "s/^Installed-Size:.*/Installed-Size: $INSTALLED_SIZE/" control
rm -f control.bak

tar czf "$BUILD_DIR/control.tar.gz" ./control ./postinst ./prerm ./conffiles

# Create data.tar.gz
echo "Creating data archive..."
cd "$PKG_DIR/data"

# Ensure proper permissions
find . -type f -name "*.sh" -exec chmod +x {} \;
find . -type f -path "*/bin/*" -exec chmod +x {} \;
find . -type f -path "*/init.d/*" -exec chmod +x {} \;
find . -type f -path "*/cgi-bin/*" -exec chmod +x {} \;
find . -type f -path "*/rpcd/*" -exec chmod +x {} \;

tar czf "$BUILD_DIR/data.tar.gz" .

# Build the .ipk (ar archive)
echo "Creating .ipk archive..."
cd "$BUILD_DIR"

# Use ar to create the archive (ipk format)
ar -r "$OUTPUT_DIR/$PKG_NAME" debian-binary control.tar.gz data.tar.gz

# Cleanup
rm -rf "$BUILD_DIR"

echo ""
echo "Package built successfully: $OUTPUT_DIR/$PKG_NAME"
echo ""
echo "Install on OpenWRT with:"
echo "  opkg install $PKG_NAME"
echo ""
echo "Or copy to router and install:"
echo "  scp $PKG_NAME root@router:/tmp/"
echo "  ssh root@router 'opkg install /tmp/$PKG_NAME'"
