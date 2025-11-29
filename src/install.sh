#!/bin/bash
# WigleWRT Installer
# Deploys WigleWRT to an OpenWRT device

set -e

DEVICE_IP="${1:-10.10.10.20}"
DEVICE_USER="${2:-root}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== WigleWRT Installer ==="
echo "Target device: $DEVICE_USER@$DEVICE_IP"
echo ""

# Check SSH connectivity
echo "[1/8] Testing SSH connection..."
if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
    "$DEVICE_USER@$DEVICE_IP" "echo 'Connection OK'" 2>/dev/null; then
    echo "ERROR: Cannot connect to device"
    exit 1
fi

echo "[2/9] Creating directories on device..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$DEVICE_USER@$DEVICE_IP" 2>/dev/null << 'EOF'
mkdir -p /etc/wiglewrt/sessions
mkdir -p /etc/wiglewrt/exports
mkdir -p /usr/share/luci/menu.d
mkdir -p /usr/share/rpcd/acl.d
mkdir -p /usr/libexec/rpcd
mkdir -p /www/luci-static/resources/view
mkdir -p /www/cgi-bin/luci/admin/services/wiglewrt
mkdir -p /usr/share/wiglewrt
EOF

echo "[3/9] Deploying main scripts..."
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$SCRIPT_DIR/wiglewrt" "$DEVICE_USER@$DEVICE_IP:/usr/bin/wiglewrt" 2>/dev/null

scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$SCRIPT_DIR/wiglewrt-export" "$DEVICE_USER@$DEVICE_IP:/usr/bin/wiglewrt-export" 2>/dev/null

scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$SCRIPT_DIR/wiglewrt-leds" "$DEVICE_USER@$DEVICE_IP:/usr/bin/wiglewrt-leds" 2>/dev/null

scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$SCRIPT_DIR/VERSION" "$DEVICE_USER@$DEVICE_IP:/usr/share/wiglewrt/VERSION" 2>/dev/null

echo "[4/9] Deploying init script..."
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$SCRIPT_DIR/wiglewrt.init" "$DEVICE_USER@$DEVICE_IP:/etc/init.d/wiglewrt" 2>/dev/null

echo "[5/9] Deploying UCI configuration..."
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$SCRIPT_DIR/wiglewrt.config" "$DEVICE_USER@$DEVICE_IP:/etc/config/wiglewrt" 2>/dev/null

echo "[6/9] Deploying LuCI components..."
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$SCRIPT_DIR/luci/menu.d/luci-app-wiglewrt.json" \
    "$DEVICE_USER@$DEVICE_IP:/usr/share/luci/menu.d/luci-app-wiglewrt.json" 2>/dev/null

scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$SCRIPT_DIR/luci/acl.d/luci-app-wiglewrt.json" \
    "$DEVICE_USER@$DEVICE_IP:/usr/share/rpcd/acl.d/luci-app-wiglewrt.json" 2>/dev/null

scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$SCRIPT_DIR/luci/view/wiglewrt.js" \
    "$DEVICE_USER@$DEVICE_IP:/www/luci-static/resources/view/wiglewrt.js" 2>/dev/null

scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$SCRIPT_DIR/luci/rpcd/wiglewrt.sh" \
    "$DEVICE_USER@$DEVICE_IP:/usr/libexec/rpcd/wiglewrt" 2>/dev/null

scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$SCRIPT_DIR/luci/cgi/wiglewrt-download" \
    "$DEVICE_USER@$DEVICE_IP:/www/cgi-bin/luci/admin/services/wiglewrt/download" 2>/dev/null

echo "[7/9] Setting permissions..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$DEVICE_USER@$DEVICE_IP" 2>/dev/null << 'EOF'
chmod +x /usr/bin/wiglewrt
chmod +x /usr/bin/wiglewrt-export
chmod +x /usr/bin/wiglewrt-leds
chmod +x /etc/init.d/wiglewrt
chmod +x /usr/libexec/rpcd/wiglewrt
chmod +x /www/cgi-bin/luci/admin/services/wiglewrt/download

# Enable the init script
/etc/init.d/wiglewrt enable 2>/dev/null || true

# Restart rpcd to load new handler
/etc/init.d/rpcd restart

# Clear LuCI cache
rm -rf /tmp/luci-modulecache
rm -rf /tmp/luci-indexcache
EOF

echo "[8/9] Verifying installation..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$DEVICE_USER@$DEVICE_IP" 2>/dev/null << 'EOF'
echo "Checking files..."
ls -la /usr/bin/wiglewrt
ls -la /usr/bin/wiglewrt-leds
ls -la /etc/init.d/wiglewrt
ls -la /etc/config/wiglewrt
ls -la /www/luci-static/resources/view/wiglewrt.js
ls -la /usr/libexec/rpcd/wiglewrt
ls -la /usr/share/wiglewrt/VERSION

echo ""
echo "Version check..."
/usr/bin/wiglewrt --version

echo ""
echo "Testing ubus..."
ubus list | grep wiglewrt || echo "ubus not yet available (may need rpcd restart)"
EOF

echo "[9/9] Deployment summary..."
echo "VERSION: $(cat "$SCRIPT_DIR/VERSION")"

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Access the web interface at: http://$DEVICE_IP/cgi-bin/luci/admin/services/wiglewrt"
echo ""
echo "Command line usage:"
echo "  ssh $DEVICE_USER@$DEVICE_IP"
echo "  /etc/init.d/wiglewrt start   # Start scanning"
echo "  /etc/init.d/wiglewrt stop    # Stop scanning"
echo "  wiglewrt status              # Check status"
echo "  wiglewrt stats               # Show statistics"
echo "  wiglewrt-export all          # Export all networks"
echo ""
