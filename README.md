# WigleWRT

WiFi wardriving scanner for OpenWRT. Scans networks, logs GPS coordinates, exports to WiGLE CSV format.

<img width="893" height="762" alt="image" src="https://github.com/user-attachments/assets/e07a4524-55b5-4dd2-8ddb-b4fa7742d6a5" />
<img width="891" height="676" alt="image" src="https://github.com/user-attachments/assets/3e4455c6-b7d7-4bf4-abc8-496a72f78d7e" />





Tested on Google OnHub running OpenWRT.

## Requirements

- OpenWRT device with LuCI web interface
- sshpass installed on your computer
- USB GPS device (optional)

## Install

```
./install.sh <router-ip> <password>
```

Example:
```
./install.sh 10.10.10.20 admin
```

## Manual Install

Copy all .ipk files to router and run:
```
opkg install wiglewrt_*.ipk
```

## Access

Web UI: http://router-ip/cgi-bin/luci/admin/services/wiglewrt

## Features

- Multi-radio scanning with channel hopping
- GPS location tracking
- WiGLE CSV export
- LED status indicators (red = no GPS, green = GPS lock, white flash = new network)
- Auto-start on boot
