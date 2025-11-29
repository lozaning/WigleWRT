# WigleWRT Bluetooth Monitor

Monitor your WigleWRT WiFi scanner status via Bluetooth Low Energy (BLE) when WiFi radios are dedicated to scanning.

## Components

### 1. OpenWRT BLE Service (`openwrt/`)

A Python-based GATT server that exposes WigleWRT scanner status over BLE.

#### Requirements

- OpenWRT with BlueZ support
- Python 3 with the following packages:
  - `dbus-python`
  - `PyGObject`

#### Installation

```bash
# Install dependencies
opkg update
opkg install python3 python3-dbus bluez-daemon

# Copy the BLE service
cp openwrt/wiglewrt-ble /usr/bin/
chmod +x /usr/bin/wiglewrt-ble

# Copy init script
cp openwrt/wiglewrt-ble.init /etc/init.d/wiglewrt-ble
chmod +x /etc/init.d/wiglewrt-ble

# Enable and start the service
/etc/init.d/wiglewrt-ble enable
/etc/init.d/wiglewrt-ble start
```

#### BLE Service Details

- **Service UUID**: `12345678-1234-5678-1234-56789abcdef0`
- **Device Name**: `WigleWRT`

##### Characteristics

| Characteristic | UUID | Description |
|----------------|------|-------------|
| Status | `...def1` | Scanner running state, total networks |
| GPS | `...def2` | GPS fix status, coordinates, satellites |
| Networks | `...def3` | Total network count |
| Session | `...def4` | Current session ID, start time, new networks |
| Radios | `...def5` | Radio configuration (bands, channels) |
| Activity | `...def6` | Recent network sightings (last 10) |

### 2. Android App (`android-app/`)

A simple Android app that connects to the WigleWRT BLE service and displays real-time status.

#### Features

- BLE scanning for WigleWRT devices
- Auto-connect to WigleWRT service
- Real-time status updates (5-second refresh)
- Pull-to-refresh support
- Dark theme UI matching web interface

#### Building the APK

##### Option A: Using Android Studio

1. Open `android-app/` in Android Studio
2. Click Build > Build Bundle(s) / APK(s) > Build APK(s)
3. APK will be in `app/build/outputs/apk/debug/`

##### Option B: Using Command Line

```bash
cd android-app
./gradlew assembleDebug
# APK will be at app/build/outputs/apk/debug/app-debug.apk
```

#### Requirements

- Android 8.0 (API 26) or higher
- Bluetooth LE support
- Location permission (required for BLE scanning)

#### Usage

1. Install the APK on your Android device
2. Ensure Bluetooth is enabled
3. Open the app and tap "Connect"
4. The app will scan for and connect to the WigleWRT device
5. Status will auto-refresh every 5 seconds

## Displayed Information

The app shows all the same information as the web GUI:

- **Scanner Status**: Running/Stopped indicator
- **GPS Status**: Fix status, satellite count, coordinates
- **Total Networks**: Count of all discovered networks
- **Current Session**: Session ID, start time, new networks found
- **Radio Configuration**: Per-radio status, bands, and hopping channels
- **Recent Activity**: Last 10 network sightings with:
  - New network indicator
  - SSID and BSSID
  - Channel and signal strength
  - Timestamp

## Troubleshooting

### BLE Service Won't Start

1. Check if Bluetooth adapter is present: `hciconfig`
2. Bring up adapter: `hciconfig hci0 up`
3. Check BlueZ is running: `pidof bluetoothd`

### Android App Can't Find Device

1. Ensure BLE service is running on router
2. Check Bluetooth and Location are enabled on phone
3. Grant all requested permissions to the app
4. Make sure you're within BLE range (~10m)

### Connection Drops

- BLE connections can be affected by interference
- Try moving closer to the router
- Restart the BLE service on the router

## License

Same license as WigleWRT main project.
