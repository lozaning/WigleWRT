# WigleWRT OpenWRT Package

WiFi wardriving scanner for OpenWRT with LuCI web interface and BLE mobile app support.

## Features

- **WiFi Scanning**: Scans all 2.4GHz and 5GHz channels for WiFi networks
- **WiGLE Export**: Exports data in WiGLE-compatible CSV format for upload
- **GPS Integration**: Records GPS coordinates with each network sighting
- **LuCI Web Interface**: Control and monitor scanning from the router's web UI
- **BLE Mobile App**: Android companion app for monitoring via Bluetooth
- **LED Status**: Visual feedback on Google OnHub ring LEDs (red=no GPS, green=GPS fix)

## Installation

### From Package File

```bash
# Copy package to router
scp wiglewrt_2.9.1-1_all.ipk root@<router-ip>:/tmp/

# SSH to router and install
ssh root@<router-ip>
opkg update
opkg install /tmp/wiglewrt_2.9.1-1_all.ipk
```

### Dependencies

The package depends on:
- `iw` - Wireless tools
- `rpcd` - OpenWRT RPC daemon
- `luci-base` - LuCI web interface
- `python3` - Python 3 runtime (for BLE service)
- `python3-dbus` - D-Bus bindings for BLE

For BLE support on OnHub, you may also need:
```bash
opkg install bluez-daemon python3-pip
pip3 install dbus-fast
```

## Usage

### Web Interface

Navigate to **Services → WigleWRT** in LuCI to:
- Start/stop scanning
- View live network sightings
- Monitor GPS status
- Export and download scan data
- Manage previous scan sessions

### Command Line

```bash
# Start scanning (default 500ms dwell)
wiglewrt start

# Start with custom dwell time
wiglewrt start 100    # Fast scanning
wiglewrt start 1000   # Thorough scanning

# Check status
wiglewrt status

# Stop scanning
wiglewrt stop
```

### Android App

The WigleWRT Monitor Android app connects via BLE to:
- Monitor scanner status
- View GPS position
- See recent network discoveries
- Start/stop scanning remotely

## File Locations

- `/etc/config/wiglewrt` - Configuration file
- `/etc/wiglewrt/sessions/` - Scan session CSV files
- `/usr/bin/wiglewrt*` - Scanner executables
- `/usr/share/wiglewrt/` - Support libraries

## Building the Package

```bash
# Rebuild from source files
./build-ipk.sh
```

## License

GPL-3.0-or-later
