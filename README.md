# WigleWRT

WiFi wardriving software for OpenWRT routers with distributed sensor support and LuCI web interface.

## Overview

WigleWRT turns OpenWRT routers into WiFi scanning stations that log networks in WiGLE-compatible CSV format. It supports a distributed architecture where multiple sensor nodes can report to a central control node.

### Key Features

- **Multi-radio scanning**: Scans on all available WiFi radios simultaneously
- **GPS integration**: Records location data for each sighting
- **WiGLE-compatible export**: CSV files can be uploaded directly to WiGLE.net
- **Distributed sensing**: Multiple sensor nodes report to a central control node
- **LuCI web interface**: Real-time monitoring with dark mode UI
- **Band-colored display**: 2.4GHz (blue), 5GHz (green), 6GHz (purple) row coloring
- **Source tracking**: Shows which device (control/sensor) captured each network

## Architecture

```
                    ┌─────────────────────┐
                    │    Control Node     │
                    │   (10.10.10.20)     │
                    │                     │
┌─────────────┐     │  ┌───────────────┐  │     ┌─────────────┐
│ Sensor Node │────>│  │ sensor-receive│  │<────│ Sensor Node │
│  (sensor1)  │     │  │    (CGI)      │  │     │  (sensor2)  │
└─────────────┘     │  └───────┬───────┘  │     └─────────────┘
                    │          │          │
                    │          v          │
                    │  ┌───────────────┐  │
                    │  │ sensor-worker │  │
                    │  └───────┬───────┘  │
                    │          │          │
                    │          v          │
                    │  ┌───────────────┐  │
                    │  │  LuCI Web UI  │  │
                    │  │ (wiglewrt.js) │  │
                    │  └───────────────┘  │
                    └─────────────────────┘
```

## Directory Structure

```
WigleWRT/
├── Control Node/
│   ├── openwrt-package/
│   │   └── wiglewrt/
│   │       └── data/
│   │           ├── usr/bin/
│   │           │   ├── wiglewrt           # Main controller
│   │           │   ├── wiglewrt-scan      # Per-radio scanner
│   │           │   ├── wiglewrt-gps       # GPS daemon
│   │           │   ├── wiglewrt-leds      # LED status indicator
│   │           │   ├── wiglewrt-export    # CSV export utility
│   │           │   └── sensor-worker      # Processes sensor data queue
│   │           ├── usr/libexec/rpcd/
│   │           │   └── wiglewrt           # RPC backend for LuCI
│   │           ├── usr/share/wiglewrt/lib/
│   │           │   ├── common.sh          # Shared functions
│   │           │   ├── parse_scan.awk     # iw scan output parser
│   │           │   └── strategies/        # Scan timing strategies
│   │           ├── www/luci-static/resources/view/
│   │           │   └── wiglewrt.js        # LuCI frontend
│   │           └── www/cgi-bin/
│   │               └── sensor-receive     # HTTP endpoint for sensors
│   └── usr/share/wiglewrt/lib/            # Development copies
│
├── Sensor Node/
│   ├── bin/
│   │   ├── wiglewrt                       # Main controller (sensor mode)
│   │   ├── wiglewrt-scan                  # Scanner with buffering
│   │   └── sensor-report.sh               # Sends data to control node
│   ├── lib/
│   │   ├── common.sh                      # Shared functions + sensor helpers
│   │   └── parse_scan.awk                 # iw scan output parser
│   └── etc/
│       └── sensor.conf.example            # Sensor configuration template
│
├── android-simple/                        # Android companion app
├── SENSOR_CONTROL_COMMUNICATION.md        # Technical docs on sensor protocol
└── README.md                              # This file
```

## Installation

### Control Node

1. Copy files to your OpenWRT router:
```bash
scp -r "Control Node/openwrt-package/wiglewrt/data/"* root@10.10.10.20:/
```

2. Set permissions:
```bash
ssh root@10.10.10.20 'chmod +x /usr/bin/wiglewrt* /usr/bin/sensor-worker /usr/libexec/rpcd/wiglewrt /www/cgi-bin/sensor-receive'
```

3. Restart services:
```bash
ssh root@10.10.10.20 '/etc/init.d/rpcd restart && /etc/init.d/uhttpd restart'
```

### Sensor Node

1. Copy files:
```bash
scp -r "Sensor Node/bin/"* root@10.10.10.11:/usr/bin/
scp -r "Sensor Node/lib/"* root@10.10.10.11:/usr/share/wiglewrt/lib/
```

2. Create config:
```bash
ssh root@10.10.10.11 'cat > /etc/wiglewrt/sensor.conf << EOF
CONTROL_NODE="10.10.10.20"
NODE_ID="sensor1"
REPORT_INTERVAL=2
MAX_BUFFER_SIZE=500
EOF'
```

3. Set permissions and start:
```bash
ssh root@10.10.10.11 'chmod +x /usr/bin/wiglewrt* /usr/bin/sensor-report.sh && wiglewrt start'
```

## Usage

### Starting the Scanner

```bash
# Start with default settings (500ms dwell time)
wiglewrt start

# Start with custom dwell time
wiglewrt start 100    # Faster scanning
wiglewrt start 1000   # More thorough scanning

# Check status
wiglewrt status

# Stop scanning
wiglewrt stop
```

### Web Interface

Access the LuCI interface at: `http://10.10.10.20/cgi-bin/luci/admin/services/wiglewrt`

Features:
- Start/Stop/Export controls
- Real-time GPS coordinates
- Network count and scan rate
- Current scan table with band coloring
- Source column showing control vs sensor
- Previous scans list with download links

### Exporting Data

```bash
# Export current session
wiglewrt-export

# Files are saved to /etc/wiglewrt/sessions/
# Format: WiGLE-compatible CSV
```

## Configuration

### Control Node Settings

Edit via LuCI or `/etc/config/wiglewrt`:
- **Dwell Time**: Time spent on each channel (100-1000ms)
- **Channel Mode**: All channels or specific band
- **Channel Offset**: Skip channels for multi-radio setups

### Sensor Node Settings

Edit `/etc/wiglewrt/sensor.conf`:
```bash
# IP address of the control node
CONTROL_NODE="10.10.10.20"

# Unique identifier for this sensor (shown in UI)
NODE_ID="sensor1"

# How often to send buffered data (seconds)
REPORT_INTERVAL=2

# Max networks to buffer before forced send
MAX_BUFFER_SIZE=500
```

## Data Format

### WiGLE CSV (Export Format)
```csv
WigleWifi-1.4,appRelease=2.0,model=OpenWRT,release=v2,device=WigleWRT,display=LuCI,board=Router,brand=WigleWRT
MAC,SSID,AuthMode,FirstSeen,Channel,RSSI,CurrentLatitude,CurrentLongitude,AltitudeMeters,AccuracyMeters,Type
aa:bb:cc:dd:ee:ff,NetworkName,[WPA2],2025-12-05 08:00:00,6,-50,45.123456,-93.123456,250,10,WIFI
```

### Sensor Protocol (NDJSON)
```
NODE:sensor1
{"bssid":"aa:bb:cc:dd:ee:ff","ssid":"NetworkName","channel":"6","signal":"-50","encryption":"WPA2"}
{"bssid":"11:22:33:44:55:66","ssid":"AnotherNet","channel":"36","signal":"-65","encryption":"WPA3"}
```

## Network Credentials

| Device | IP | Password |
|--------|-----|----------|
| Control Node | 10.10.10.20 | admin |
| Sensor Node | 10.10.10.11 | oneill |

**Note:** Sensor node requires legacy SSH options:
```bash
ssh -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa root@10.10.10.11
```

## Troubleshooting

### Scanner not starting
```bash
# Check for stale locks
rm -f /tmp/wiglewrt/*.pid /tmp/wiglewrt/*.lock

# Restart
wiglewrt stop && sleep 2 && wiglewrt start
```

### Sensor data not appearing
```bash
# On sensor: check buffer
wc -l /tmp/wiglewrt/sensor_buffer.ndjson

# On sensor: test manual send
/usr/bin/sensor-report.sh

# On control: check queue
ls /tmp/wiglewrt/sensor_queue/

# On control: check worker
/usr/bin/sensor-worker status
tail /tmp/wiglewrt/sensor_worker.log
```

### GPS not working
```bash
# Check GPS daemon
ps | grep gps

# Check GPS file
cat /tmp/wiglewrt/gps.current

# Restart GPS
wiglewrt-gps stop && wiglewrt-gps start
```

## Technical Notes

### Why curl --data-binary?
The sensor protocol uses NDJSON (newline-delimited JSON). Standard `curl -d` or busybox `wget` can strip newlines. Always use `curl --data-binary @file` to preserve the format.

### Why separate source tracking?
WiGLE.net expects a specific 11-field CSV format. Adding a "Source" field would break compatibility. Source information is stored in `/tmp/wiglewrt/source_tracking.txt` and joined at display time in the RPC layer.

### Band Detection
Channel numbers determine WiFi band:
- 1-14: 2.4 GHz
- 32-177: 5 GHz
- 191+: 6 GHz

## Version History

- **v2.5.0**: Added distributed sensor support, source tracking, band coloring
- **v2.0.0**: LuCI web interface, multi-radio scanning
- **v1.0.0**: Basic scanning and CSV export

## License

MIT License - See LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Test on actual OpenWRT hardware
4. Submit a pull request

## Related Projects

- [WiGLE.net](https://wigle.net) - WiFi network database
- [OpenWRT](https://openwrt.org) - Linux distribution for routers
- [LuCI](https://github.com/openwrt/luci) - OpenWRT web interface
