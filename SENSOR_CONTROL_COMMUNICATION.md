# WigleWRT Sensor-Control Node Communication

## Architecture Overview

WigleWRT uses a distributed architecture with two types of nodes:

- **Control Node** (10.10.10.20): Central hub that collects data from all sources, runs the LuCI web interface, and manages session data
- **Sensor Node** (10.10.10.11): Remote scanner that buffers WiFi sightings locally and periodically reports to the control node

```
┌─────────────────┐                    ┌─────────────────┐
│   Sensor Node   │                    │  Control Node   │
│  (10.10.10.11)  │                    │  (10.10.10.20)  │
│                 │                    │                 │
│ ┌─────────────┐ │   HTTP POST        │ ┌─────────────┐ │
│ │wiglewrt-scan│ │   (ndjson)         │ │sensor-receive│ │
│ └──────┬──────┘ │ ──────────────────>│ │   (CGI)     │ │
│        │        │                    │ └──────┬──────┘ │
│        v        │                    │        │        │
│ ┌─────────────┐ │                    │        v        │
│ │sensor_buffer│ │                    │ ┌─────────────┐ │
│ │  .ndjson    │ │                    │ │sensor_queue/│ │
│ └──────┬──────┘ │                    │ └──────┬──────┘ │
│        │        │                    │        │        │
│        v        │                    │        v        │
│ ┌─────────────┐ │                    │ ┌─────────────┐ │
│ │sensor-report│ │                    │ │sensor-worker│ │
│ │    .sh      │ │                    │ └──────┬──────┘ │
│ └─────────────┘ │                    │        │        │
│                 │                    │        v        │
│                 │                    │ ┌─────────────┐ │
│                 │                    │ │ current.csv │ │
│                 │                    │ │(WiGLE format)│
│                 │                    │ └─────────────┘ │
└─────────────────┘                    └─────────────────┘
```

## Data Flow

### 1. Sensor Node Scanning

**File:** `/usr/bin/wiglewrt-scan`

The scanner runs continuously on each wireless interface, detecting WiFi networks. For each network found, it:
1. Logs to the local networks database
2. Buffers the sighting for the control node via `buffer_for_control()`

### 2. Buffering for Control Node

**File:** `/usr/share/wiglewrt/lib/common.sh` (function `buffer_for_control`)

Networks are appended to a buffer file as NDJSON (newline-delimited JSON):
- **Buffer location:** `/tmp/wiglewrt/sensor_buffer.ndjson`
- **Format:** One JSON object per line

```json
{"bssid":"aa:bb:cc:dd:ee:ff","ssid":"NetworkName","channel":"6","signal":"-50","encryption":"WPA2"}
{"bssid":"11:22:33:44:55:66","ssid":"AnotherNet","channel":"36","signal":"-65","encryption":"WPA3"}
```

### 3. Triggering Report to Control Node

**File:** `/usr/share/wiglewrt/lib/common.sh` (function `trigger_sensor_report`)

After each scan cycle, if sensor mode is enabled (CONTROL_NODE is set in config), the scanner calls `trigger_sensor_report()` which:
1. Checks if enough time has passed since last report (REPORT_INTERVAL)
2. Spawns `/usr/bin/sensor-report.sh` in background

### 4. Sending Data to Control Node

**File:** `/usr/bin/sensor-report.sh`

This script:
1. Reads the buffer file
2. Prepends a `NODE:<node_id>` header line
3. Creates payload file at `/tmp/wiglewrt/sensor_payload.ndjson`
4. Sends via HTTP POST to control node

**Payload format:**
```
NODE:sensor1
{"bssid":"aa:bb:cc:dd:ee:ff","ssid":"NetworkName","channel":"6","signal":"-50","encryption":"WPA2"}
{"bssid":"11:22:33:44:55:66","ssid":"AnotherNet","channel":"36","signal":"-65","encryption":"WPA3"}
```

**HTTP Request:**
```bash
curl -s \
    -H "Content-Type: text/plain" \
    --data-binary @"$PAYLOAD_FILE" \
    --connect-timeout 10 \
    "http://10.10.10.20/cgi-bin/sensor-receive"
```

**Important:** Must use `--data-binary` (not `-d`) to preserve newlines in the NDJSON format.

### 5. Receiving Data on Control Node

**File:** `/www/cgi-bin/sensor-receive`

This CGI script:
1. Reads the entire POST body from stdin
2. Writes it to a queue file: `/tmp/wiglewrt/sensor_queue/<timestamp>_<pid>.json`
3. Returns immediately with `{"success":true,"queued":true}`

**Key point:** The CGI does NOT parse the data - it just queues it for background processing. This keeps HTTP response times fast.

### 6. Processing Queued Data

**File:** `/usr/bin/sensor-worker`

A background daemon that continuously:
1. Watches `/tmp/wiglewrt/sensor_queue/` for new files
2. Parses each file:
   - First line: `NODE:<node_id>` - extracts the source identifier
   - Subsequent lines: JSON objects with network data
3. Writes to WiGLE-format CSV: `/etc/wiglewrt/sessions/current.csv`
4. Writes source tracking: `/tmp/wiglewrt/source_tracking.txt`
5. Deletes processed queue file

**Source tracking format:**
```
bssid|timestamp|source
aa:bb:cc:dd:ee:ff|2025-12-05 08:12:40|sensor1
11:22:33:44:55:66|2025-12-05 08:12:40|control
```

## Configuration

### Sensor Node Configuration

**File:** `/etc/wiglewrt/sensor.conf`

```sh
# Control node IP address
CONTROL_NODE="10.10.10.20"

# This sensor's identifier (appears in Source column)
NODE_ID="sensor1"

# How often to report (seconds)
REPORT_INTERVAL=2

# Max networks to buffer before forced report
MAX_BUFFER_SIZE=500
```

### Control Node Configuration

No special configuration needed - the control node automatically:
- Accepts incoming sensor data via CGI
- Runs sensor-worker daemon to process queue
- Tags local scans with source "control"

## File Locations Summary

### Sensor Node
| Purpose | Path |
|---------|------|
| Main scanner | `/usr/bin/wiglewrt-scan` |
| Report script | `/usr/bin/sensor-report.sh` |
| Common functions | `/usr/share/wiglewrt/lib/common.sh` |
| Configuration | `/etc/wiglewrt/sensor.conf` |
| Buffer file | `/tmp/wiglewrt/sensor_buffer.ndjson` |
| Payload file | `/tmp/wiglewrt/sensor_payload.ndjson` |

### Control Node
| Purpose | Path |
|---------|------|
| CGI endpoint | `/www/cgi-bin/sensor-receive` |
| Queue processor | `/usr/bin/sensor-worker` |
| Queue directory | `/tmp/wiglewrt/sensor_queue/` |
| Session CSV | `/etc/wiglewrt/sessions/current.csv` |
| Source tracking | `/tmp/wiglewrt/source_tracking.txt` |
| RPC backend | `/usr/libexec/rpcd/wiglewrt` |
| LuCI frontend | `/www/luci-static/resources/view/wiglewrt.js` |

## WiGLE CSV Compatibility

The session CSV maintains 100% WiGLE.net compatibility with 11 fields:
```
MAC,SSID,AuthMode,FirstSeen,Channel,RSSI,CurrentLatitude,CurrentLongitude,AltitudeMeters,AccuracyMeters,Type
```

**Source information is NOT stored in the CSV** - it's kept separately in `/tmp/wiglewrt/source_tracking.txt` for UI display only. This ensures exported CSVs can be uploaded directly to WiGLE.net without modification.

## Troubleshooting

### Sensor data not appearing on control node

1. Check sensor config: `cat /etc/wiglewrt/sensor.conf`
2. Verify buffer has data: `wc -l /tmp/wiglewrt/sensor_buffer.ndjson`
3. Test manual report: `/usr/bin/sensor-report.sh` (watch for errors)
4. Check control node queue: `ls /tmp/wiglewrt/sensor_queue/`
5. Check sensor-worker status: `/usr/bin/sensor-worker status`
6. Check sensor-worker log: `tail /tmp/wiglewrt/sensor_worker.log`

### Common issues

- **"no data" error from CGI:** Usually means wget was used instead of curl. Busybox wget doesn't send Content-Length header, which confuses uhttpd.
- **Success but data not appearing:** Check sensor-worker is running and processing queue files.
- **Source shows "unknown":** The NODE: header line is missing or malformed in the payload.

## Network Requirements

- Sensor must be able to reach control node on port 80 (HTTP)
- No authentication is currently implemented (assumes trusted network)
- Recommended: Both nodes on same subnet or with routing configured
