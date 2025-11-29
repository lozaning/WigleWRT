#!/bin/sh
# WigleWRT Installer
# Usage: ./install.sh <router-ip> [password]

ROUTER_IP="${1:-10.10.10.20}"
ROUTER_PASS="${2:-admin}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing WigleWRT to $ROUTER_IP..."

# Copy all packages
for pkg in "$SCRIPT_DIR"/*.ipk; do
    sshpass -p "$ROUTER_PASS" scp -o StrictHostKeyChecking=no "$pkg" root@"$ROUTER_IP":/tmp/
done

# Install packages in order
sshpass -p "$ROUTER_PASS" ssh -o StrictHostKeyChecking=no root@"$ROUTER_IP" << 'EOF'
cd /tmp
opkg install libusb-1.0-0*.ipk 2>/dev/null
opkg install kmod-usb-serial_*.ipk 2>/dev/null
opkg install kmod-usb-serial-ch341*.ipk 2>/dev/null
opkg install kmod-usb-serial-cp210x*.ipk 2>/dev/null
opkg install kmod-usb-serial-pl2303*.ipk 2>/dev/null
opkg install kmod-usb-acm*.ipk 2>/dev/null
opkg install libgps*.ipk 2>/dev/null
opkg install gpsd_*.ipk 2>/dev/null
opkg install gpsd-clients*.ipk 2>/dev/null
opkg install wiglewrt_*.ipk
rm -f /tmp/*.ipk
EOF

echo "Done. Access web UI at: http://$ROUTER_IP/cgi-bin/luci/admin/services/wiglewrt"
