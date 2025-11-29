#!/bin/bash
# WigleWRT IPK Package Builder
# Creates an OpenWRT-compatible .ipk package for easy installation

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Package metadata
PKG_NAME="wiglewrt"
PKG_VERSION=$(cat VERSION)
PKG_RELEASE="1"
PKG_ARCH="all"
PKG_MAINTAINER="WigleWRT Team"
PKG_LICENSE="GPL-3.0-or-later"
PKG_SECTION="net"
PKG_DESCRIPTION="WigleWRT WiFi scanner for wardriving with LuCI web interface"

# Build directories
BUILD_DIR="./build"
IPK_DIR="${BUILD_DIR}/ipk"
CONTROL_DIR="${IPK_DIR}/control"
DATA_DIR="${IPK_DIR}/data"
OUTPUT_DIR="./dist"

echo "=== WigleWRT IPK Builder ==="
echo "Building ${PKG_NAME} v${PKG_VERSION}-${PKG_RELEASE}"
echo ""

# Clean and create directories
echo "[1/7] Creating build directories..."
rm -rf "$BUILD_DIR"
mkdir -p "$CONTROL_DIR" "$DATA_DIR" "$OUTPUT_DIR"

# Create data directory structure
echo "[2/7] Creating directory structure..."
mkdir -p "$DATA_DIR/usr/bin"
mkdir -p "$DATA_DIR/usr/share/wiglewrt"
mkdir -p "$DATA_DIR/usr/share/luci/menu.d"
mkdir -p "$DATA_DIR/usr/share/rpcd/acl.d"
mkdir -p "$DATA_DIR/usr/libexec/rpcd"
mkdir -p "$DATA_DIR/etc/init.d"
mkdir -p "$DATA_DIR/etc/config"
mkdir -p "$DATA_DIR/etc/wiglewrt/sessions"
mkdir -p "$DATA_DIR/etc/wiglewrt/exports"
mkdir -p "$DATA_DIR/www/luci-static/resources/view"
mkdir -p "$DATA_DIR/www/cgi-bin"

# Copy files
echo "[3/7] Copying application files..."

# Main scripts
cp wiglewrt "$DATA_DIR/usr/bin/"
cp wiglewrt-export "$DATA_DIR/usr/bin/"
cp wiglewrt-leds "$DATA_DIR/usr/bin/"

# Version file
cp VERSION "$DATA_DIR/usr/share/wiglewrt/"

# Init and config
cp wiglewrt.init "$DATA_DIR/etc/init.d/wiglewrt"
cp wiglewrt.config "$DATA_DIR/etc/config/wiglewrt"

# LuCI components
cp luci/menu.d/luci-app-wiglewrt.json "$DATA_DIR/usr/share/luci/menu.d/"
cp luci/acl.d/luci-app-wiglewrt.json "$DATA_DIR/usr/share/rpcd/acl.d/"
cp luci/view/wiglewrt.js "$DATA_DIR/www/luci-static/resources/view/"
cp luci/rpcd/wiglewrt.sh "$DATA_DIR/usr/libexec/rpcd/wiglewrt"
cp luci/cgi/wiglewrt-download "$DATA_DIR/www/cgi-bin/wiglewrt-download"

# Set permissions
echo "[4/7] Setting file permissions..."
chmod 755 "$DATA_DIR/usr/bin/wiglewrt"
chmod 755 "$DATA_DIR/usr/bin/wiglewrt-export"
chmod 755 "$DATA_DIR/usr/bin/wiglewrt-leds"
chmod 755 "$DATA_DIR/etc/init.d/wiglewrt"
chmod 755 "$DATA_DIR/usr/libexec/rpcd/wiglewrt"
chmod 755 "$DATA_DIR/www/cgi-bin/wiglewrt-download"
chmod 644 "$DATA_DIR/etc/config/wiglewrt"
chmod 644 "$DATA_DIR/usr/share/wiglewrt/VERSION"
chmod 644 "$DATA_DIR/usr/share/luci/menu.d/luci-app-wiglewrt.json"
chmod 644 "$DATA_DIR/usr/share/rpcd/acl.d/luci-app-wiglewrt.json"
chmod 644 "$DATA_DIR/www/luci-static/resources/view/wiglewrt.js"

# Calculate installed size
INSTALLED_SIZE=$(du -sb "$DATA_DIR" | cut -f1)

# Create control file
echo "[5/7] Creating package metadata..."
cat > "$CONTROL_DIR/control" << EOF
Package: ${PKG_NAME}
Version: ${PKG_VERSION}-${PKG_RELEASE}
Depends: libc, iw, rpcd, luci-base
Source: https://github.com/lozaning/wiglewrt
SourceName: ${PKG_NAME}
License: ${PKG_LICENSE}
Section: ${PKG_SECTION}
SourceDateEpoch: $(date +%s)
Maintainer: ${PKG_MAINTAINER}
Architecture: ${PKG_ARCH}
Installed-Size: ${INSTALLED_SIZE}
Description: ${PKG_DESCRIPTION}
EOF

# Create conffiles (preserved on upgrade)
cat > "$CONTROL_DIR/conffiles" << EOF
/etc/config/wiglewrt
EOF

# Create postinst script
cat > "$CONTROL_DIR/postinst" << 'POSTINST'
#!/bin/sh
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0

# Enable init script
/etc/init.d/wiglewrt enable 2>/dev/null || true

# Restart rpcd to load new RPC handler
/etc/init.d/rpcd restart 2>/dev/null || true

# Clear LuCI cache
rm -rf /tmp/luci-modulecache
rm -rf /tmp/luci-indexcache

echo "WigleWRT installed successfully!"
echo "Access the web interface at: http://<device-ip>/cgi-bin/luci/admin/services/wiglewrt"

exit 0
POSTINST
chmod 755 "$CONTROL_DIR/postinst"

# Create prerm script
cat > "$CONTROL_DIR/prerm" << 'PRERM'
#!/bin/sh
# Stop service before removal
/etc/init.d/wiglewrt stop 2>/dev/null || true
/etc/init.d/wiglewrt disable 2>/dev/null || true
exit 0
PRERM
chmod 755 "$CONTROL_DIR/prerm"

# Create debian-binary
echo "2.0" > "$IPK_DIR/debian-binary"

# Create tar archives
echo "[6/7] Creating package archives..."
(cd "$CONTROL_DIR" && tar --numeric-owner --group=0 --owner=0 -czf ../control.tar.gz ./*)
(cd "$DATA_DIR" && tar --numeric-owner --group=0 --owner=0 -czf ../data.tar.gz ./)

# Create final IPK
IPK_FILE="${PKG_NAME}_${PKG_VERSION}-${PKG_RELEASE}_${PKG_ARCH}.ipk"
(cd "$IPK_DIR" && tar --numeric-owner --group=0 --owner=0 -czf "../${IPK_FILE}" ./debian-binary ./control.tar.gz ./data.tar.gz)

# Move to output directory
mv "${BUILD_DIR}/${IPK_FILE}" "$OUTPUT_DIR/"

# Copy GPS dependency packages
echo "[7/7] Copying GPS dependency packages..."
if [ -d "packages" ]; then
    cp packages/*.ipk "$OUTPUT_DIR/" 2>/dev/null || true
fi

# Create install helper script
cat > "$OUTPUT_DIR/install_all.sh" << 'INSTALL_SCRIPT'
#!/bin/bash
# WigleWRT Complete Installer
# Installs WigleWRT and all GPS dependencies

set -e

DEVICE_IP="${1:-10.10.10.20}"
DEVICE_USER="${2:-root}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== WigleWRT Complete Installer ==="
echo "Target: ${DEVICE_USER}@${DEVICE_IP}"
echo ""

# Check for sshpass
if ! command -v sshpass &> /dev/null; then
    echo "Note: sshpass not found. You may be prompted for password multiple times."
    SSH_CMD="ssh -o StrictHostKeyChecking=no"
    SCP_CMD="scp -o StrictHostKeyChecking=no"
else
    read -s -p "Enter device password: " DEVICE_PASS
    echo ""
    SSH_CMD="sshpass -p '$DEVICE_PASS' ssh -o StrictHostKeyChecking=no"
    SCP_CMD="sshpass -p '$DEVICE_PASS' scp -o StrictHostKeyChecking=no"
fi

echo "[1/3] Copying packages to device..."
eval $SCP_CMD "$SCRIPT_DIR"/*.ipk "${DEVICE_USER}@${DEVICE_IP}:/tmp/"

echo "[2/3] Installing GPS dependencies..."
eval $SSH_CMD "${DEVICE_USER}@${DEVICE_IP}" << 'EOF'
cd /tmp
# Install in dependency order
opkg install libusb-1.0-0*.ipk 2>/dev/null || true
opkg install kmod-usb-serial_*.ipk 2>/dev/null || true
opkg install kmod-usb-serial-ch341*.ipk 2>/dev/null || true
opkg install kmod-usb-serial-cp210x*.ipk 2>/dev/null || true
opkg install kmod-usb-serial-pl2303*.ipk 2>/dev/null || true
opkg install kmod-usb-acm*.ipk 2>/dev/null || true
opkg install libgps*.ipk 2>/dev/null || true
opkg install gpsd_*.ipk 2>/dev/null || true
opkg install gpsd-clients*.ipk 2>/dev/null || true
EOF

echo "[3/3] Installing WigleWRT..."
eval $SSH_CMD "${DEVICE_USER}@${DEVICE_IP}" "opkg install /tmp/wiglewrt_*.ipk"

echo ""
echo "=== Installation Complete ==="
echo "Access the web interface at: http://${DEVICE_IP}/cgi-bin/luci/admin/services/wiglewrt"
INSTALL_SCRIPT
chmod +x "$OUTPUT_DIR/install_all.sh"

# Clean up build directory
rm -rf "$BUILD_DIR"

echo ""
echo "=== Build Complete ==="
echo ""
echo "Output files in ${OUTPUT_DIR}/:"
ls -la "$OUTPUT_DIR/"
echo ""
echo "To install on device:"
echo "  Option 1 (all packages): ./dist/install_all.sh <device-ip> [user]"
echo "  Option 2 (main only):    scp dist/${IPK_FILE} root@<device-ip>:/tmp/"
echo "                           ssh root@<device-ip> 'opkg install /tmp/${IPK_FILE}'"
