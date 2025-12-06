#!/bin/sh
# install.sh - Install WigleWRT v2 on OpenWRT device
# Usage: ./install.sh [device_ip] [username]

DEVICE_IP="${1:-10.10.10.20}"
USERNAME="${2:-root}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "WigleWRT v2 Installer"
echo "====================="
echo "Target: $USERNAME@$DEVICE_IP"
echo ""

# Check SSH connectivity
echo "Checking connectivity..."
if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$USERNAME@$DEVICE_IP" "echo OK" >/dev/null 2>&1; then
    echo "ERROR: Cannot connect to $DEVICE_IP"
    echo "Make sure:"
    echo "  1. Device is powered on and connected"
    echo "  2. SSH is enabled"
    echo "  3. IP address is correct"
    exit 1
fi

echo "Connected!"
echo ""

# Create directories on device
echo "Creating directories..."
ssh "$USERNAME@$DEVICE_IP" "mkdir -p /usr/bin /usr/share/wiglewrt/lib/strategies /etc/wiglewrt/data /usr/share/rpcd/acl.d /www/luci-static/resources/view /www/cgi-bin"

# Copy binaries
echo "Installing binaries..."
scp -q "$SCRIPT_DIR/bin/wiglewrt" "$USERNAME@$DEVICE_IP:/usr/bin/"
scp -q "$SCRIPT_DIR/bin/scan.sh" "$USERNAME@$DEVICE_IP:/usr/bin/wiglewrt-scan"
scp -q "$SCRIPT_DIR/bin/gps.sh" "$USERNAME@$DEVICE_IP:/usr/bin/wiglewrt-gps"
scp -q "$SCRIPT_DIR/bin/db.sh" "$USERNAME@$DEVICE_IP:/usr/bin/wiglewrt-db"
scp -q "$SCRIPT_DIR/bin/bench.sh" "$USERNAME@$DEVICE_IP:/usr/bin/wiglewrt-bench"
scp -q "$SCRIPT_DIR/bin/export.sh" "$USERNAME@$DEVICE_IP:/usr/bin/wiglewrt-export"

# Copy libraries
echo "Installing libraries..."
scp -q "$SCRIPT_DIR/lib/common.sh" "$USERNAME@$DEVICE_IP:/usr/share/wiglewrt/lib/"
scp -q "$SCRIPT_DIR/lib/parse_scan.awk" "$USERNAME@$DEVICE_IP:/usr/share/wiglewrt/lib/"

# Copy strategies
echo "Installing strategies..."
scp -q "$SCRIPT_DIR/lib/strategies/"*.sh "$USERNAME@$DEVICE_IP:/usr/share/wiglewrt/lib/strategies/"

# Copy RPC handler
echo "Installing RPC handler..."
scp -q "$SCRIPT_DIR/luci/rpcd/rpc.sh" "$USERNAME@$DEVICE_IP:/usr/share/rpcd/scripts/wiglewrt"

# Copy web UI
echo "Installing web UI..."
scp -q "$SCRIPT_DIR/luci/view/wiglewrt.js" "$USERNAME@$DEVICE_IP:/www/luci-static/resources/view/"

# Create ACL file
echo "Installing ACL..."
ssh "$USERNAME@$DEVICE_IP" 'cat > /usr/share/rpcd/acl.d/luci-app-wiglewrt.json << EOF
{
    "luci-app-wiglewrt": {
        "description": "WigleWRT WiFi Scanner",
        "read": {
            "ubus": {
                "wiglewrt": ["status", "gps", "networks", "bench_status", "bench_list"]
            }
        },
        "write": {
            "ubus": {
                "wiglewrt": ["start", "stop", "export"]
            }
        }
    }
}
EOF'

# Create CGI download script
echo "Installing CGI handler..."
ssh "$USERNAME@$DEVICE_IP" 'cat > /www/cgi-bin/wiglewrt-download << EOF
#!/bin/sh
echo "Content-Type: application/octet-stream"
FILE=\$(echo "\$QUERY_STRING" | sed "s/.*file=//; s/&.*//")
FILE=\$(printf "%b" "\${FILE//%/\\x}")
FILEPATH="/tmp/wiglewrt_exports/\$FILE"
if [ -f "\$FILEPATH" ]; then
    echo "Content-Disposition: attachment; filename=\"\$FILE\""
    echo ""
    cat "\$FILEPATH"
else
    echo "Status: 404 Not Found"
    echo ""
    echo "File not found"
fi
EOF
chmod 755 /www/cgi-bin/wiglewrt-download'

# Create LuCI menu entry
echo "Installing LuCI menu..."
ssh "$USERNAME@$DEVICE_IP" 'cat > /usr/share/luci/menu.d/luci-app-wiglewrt.json << EOF
{
    "admin/services/wiglewrt": {
        "title": "WigleWRT",
        "order": 90,
        "action": {
            "type": "view",
            "path": "wiglewrt"
        },
        "depends": {
            "acl": ["luci-app-wiglewrt"]
        }
    }
}
EOF'

# Set permissions
echo "Setting permissions..."
ssh "$USERNAME@$DEVICE_IP" "chmod +x /usr/bin/wiglewrt /usr/bin/wiglewrt-* /usr/share/rpcd/scripts/wiglewrt"

# Fix script paths (update SCRIPT_DIR to absolute paths)
echo "Fixing script paths..."
ssh "$USERNAME@$DEVICE_IP" '
for script in /usr/bin/wiglewrt /usr/bin/wiglewrt-scan /usr/bin/wiglewrt-gps /usr/bin/wiglewrt-db /usr/bin/wiglewrt-bench /usr/bin/wiglewrt-export; do
    sed -i "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"/usr/share/wiglewrt\"|g" "$script" 2>/dev/null
done
'

# Restart rpcd to load new handler
echo "Restarting rpcd..."
ssh "$USERNAME@$DEVICE_IP" "/etc/init.d/rpcd restart"

# Restart uhttpd to load CGI
echo "Restarting uhttpd..."
ssh "$USERNAME@$DEVICE_IP" "/etc/init.d/uhttpd restart"

echo ""
echo "Installation complete!"
echo ""
echo "Usage:"
echo "  SSH:  wiglewrt start              # Start scanning"
echo "        wiglewrt start adaptive     # Start with adaptive strategy"
echo "        wiglewrt status             # Check status"
echo "        wiglewrt stop               # Stop scanning"
echo "        wiglewrt-bench run fixed_500  # Run benchmark"
echo ""
echo "  Web:  http://$DEVICE_IP/cgi-bin/luci/admin/services/wiglewrt"
echo ""
echo "Quick test:"
echo "  ssh $USERNAME@$DEVICE_IP 'wiglewrt status'"
