# Changelog

All notable changes to WigleWRT will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.8.0] - 2025-11-29

### Added
- **BLE Monitor Service**: New Bluetooth Low Energy GATT server for remote monitoring
  - Exposes scanner status, GPS, networks, session info, radio config, and activity
  - Uses dbus-fast (async) for OpenWRT compatibility
  - Android companion app support via custom service UUID
  - D-Bus policy file for proper system bus permissions
- New `wiglewrt-ble` daemon with 6 GATT characteristics:
  - Status (running, session, total networks)
  - GPS (fix, satellites, coordinates)
  - Networks (total count)
  - Session (ID, start time, new networks)
  - Radios (configuration and channels)
  - Activity (recent network sightings)

### Prompt Reference
- `prompt-019`: "BLE monitor service for Android app integration"

---

## [2.7.0] - 2025-11-29

### Changed
- **MAJOR PERFORMANCE IMPROVEMENT**: Parallel radio scanning (3-4x faster)
  - All radios now scan simultaneously using background processes
  - Removed 2-second sleep between scan cycles
  - Scan cycle reduced from ~17 seconds to ~5 seconds
- Reconfigured radio2 (dual-band) for 5GHz DFS channels (52-144)
  - Now covers UNII-2A (52-64) and UNII-2C (100-144) bands
  - Provides 16 additional 5GHz channels for better coverage
- Set default scan_interval to 0 (no delay between cycles)

### Fixed
- Sequential radio scanning bottleneck (was blocking 4-5 sec per radio)
- Radio2 underutilization (was only using 3x 2.4GHz channels)

### Prompt Reference
- `prompt-018`: "scanning performance overhaul - parallel scanning, remove delays"

---

## [2.6.2] - 2025-11-29

### Added
- Privacy mode now masks GPS coordinates (shows integer, replaces decimal digits with x's)
- Coordinate masking applies to GPS status display and all network lists

### Prompt Reference
- `prompt-017`: "privacy mode coordinate masking"

---

## [2.6.1] - 2025-11-29

### Fixed
- Fixed GPS data reading in main scanner causing LED color to stay red even with GPS lock
- Changed from unreliable `timeout + dd` method to `cat` with background process
- LEDs now correctly change from red (no GPS) to green (GPS lock)

### Prompt Reference
- `prompt-016`: "fix GPS LED color not changing to green on GPS lock"

---

## [2.6.0] - 2025-11-29

### Added
- IPK package builder (`build_ipk.sh`) for easy OpenWRT installation
- Complete IPK package with proper control metadata, postinst/prerm scripts
- GPS dependency packages bundled in `dist/` directory
- Helper script `install_all.sh` for one-command installation of all packages
- Package includes conffiles support to preserve user configuration on upgrades

### Changed
- CGI download script moved to `/www/cgi-bin/wiglewrt-download` for proper installation

### Prompt Reference
- `prompt-015`: "create OpenWRT IPK package for easy installation"

---

## [2.5.1] - 2025-11-29

### Fixed
- Fixed init script crash loop caused by procd respawn conflicts
- Disabled procd respawn (set to 0 0 0) since wiglewrt manages its own lifecycle
- Added cleanup of stale PID file before starting service
- Added 5-second delay in boot() to ensure wireless interfaces are ready

### Prompt Reference
- `prompt-014`: "fix autostart crash loop on boot"

---

## [2.5.0] - 2025-11-29

### Changed
- Enabled autostart by default in configuration
- Scanning and LED functionality now start automatically on device boot
- Updated `wiglewrt.config` with `enabled='1'` and `autostart='1'`

### Prompt Reference
- `prompt-013`: "enable scanning and LED autostart on boot"

---

## [2.4.0] - 2025-11-29

### Added
- Session selection and bulk deletion feature
- Checkboxes on session rows for multi-select
- "Select All" checkbox to toggle all session checkboxes
- "Delete Selected" button with confirmation modal
- `delete_sessions` RPC method for backend deletion

### Changed
- Session table now includes checkbox column
- ACL updated to include delete_sessions permission

### Fixed
- Radio Configuration and Session control bar now use dark-theme compatible colors
- Changed from hardcoded light colors (#f8fafc) to semi-transparent rgba values

### Prompt Reference
- `prompt-011`: "session selection and deletion feature"
- `prompt-012`: "fix UI color scheme for dark theme"

---

## [2.3.0] - 2025-11-29

### Added
- gpsd integration for GPS abstraction (supports any GPS device via gpsd daemon)
- Auto-detection of multiple GPS device paths (/dev/ttyACM*, /dev/ttyUSB*, /dev/gps*)
- GPS source reporting in status (shows "gpsd", "direct", or "none")

### Changed
- GPS initialization now tries gpsd first, falls back to direct device access
- RPC gps_status method updated for gpsd support
- Main scanner uses gpsd when available for more reliable GPS handling

### Prompt Reference
- `prompt-010`: "gpsd integration for universal GPS support"

---

## [2.2.0] - 2025-11-29

### Fixed
- Export download now works correctly in browsers (fixed URL decoding in CGI script)
- Export files now have correct permissions (644) for web server access
- Export RPC no longer returns duplicate/malformed filepath
- Session export buttons now trigger actual file download (not just notification)
- E2E test selectors updated to match actual UI button text

### Changed
- All 46 tests passing (22 E2E browser tests + 24 RPC tests)
- Fully functional web UI with working Start/Stop/Export buttons
- WiGLE CSV export downloads correctly in Firefox/Chrome

### Prompt Reference
- `prompt-009`: "fix export and download functionality bugs"

---

## [2.1.0] - 2025-11-29

### Added
- Comprehensive test suite using bats-core for shell scripts and pytest for RPC/E2E
- VERSION file as single source of truth for version number
- `--version` flag on all CLI tools (wiglewrt, wiglewrt-export, wiglewrt-leds)
- Version display in web UI header
- Git repository initialization
- CHANGELOG.md with prompt registry for tracking changes

### Prompt Reference
- `prompt-008`: "implement test suite and versioning system"

---

## [2.0.0] - 2025-11-23

### Added
- Multi-radio scanning support (phy0: 2.4GHz, phy1: 5GHz, phy2: dual-band)
- GPS integration via /dev/ttyACM0 with NMEA parsing (GNRMC/GNGGA)
- Session management with start/stop/export functionality
- LuCI web interface with real-time updates (3-second polling)
- Privacy mode for safe screenshot sharing (masks SSIDs and BSSIDs)
- Radio configuration display with channel hopping info
- Tabbed session activity view (New Networks / All Sightings)
- WiGLE CSV export format
- Per-session export functionality
- LED status indication (orange chase=no GPS, green chase=GPS lock, blue pulse=new network)

### Prompt Reference
- `prompt-001`: Core scanner daemon with channel hopping
- `prompt-002`: GPS NMEA parsing (parse_rmc, parse_gga functions)
- `prompt-003`: LuCI web interface
- `prompt-004`: RPC handler implementation (8 methods)
- `prompt-005`: Session logging and export
- `prompt-006`: Privacy mode (SSID/BSSID masking)
- `prompt-007`: Radio config display and LED integration

---

## [1.0.0] - 2025-11-20

### Added
- Initial WiFi scanning functionality
- Basic network logging to TSV format
- Single radio support

---

# Prompt Registry

This section maps prompts to specific changes for traceability.

| Prompt ID | Date | Summary | Files Changed |
|-----------|------|---------|---------------|
| prompt-001 | 2025-11-20 | Core scanner daemon | wiglewrt |
| prompt-002 | 2025-11-21 | GPS NMEA parsing | wiglewrt (lines 100-166) |
| prompt-003 | 2025-11-22 | Web UI | luci/view/wiglewrt.js |
| prompt-004 | 2025-11-22 | RPC backend | luci/rpcd/wiglewrt.sh |
| prompt-005 | 2025-11-23 | Sessions | wiglewrt, wiglewrt-export |
| prompt-006 | 2025-11-23 | Privacy mode | luci/view/wiglewrt.js |
| prompt-007 | 2025-11-23 | Radio config & LEDs | luci/view/wiglewrt.js, wiglewrt-leds |
| prompt-008 | 2025-11-29 | Test suite & versioning | tests/*, VERSION, CHANGELOG.md, wiglewrt, install.sh |
| prompt-009 | 2025-11-29 | Fix export/download bugs | luci/cgi/wiglewrt-download, luci/rpcd/wiglewrt.sh, luci/view/wiglewrt.js, wiglewrt-export |
| prompt-010 | 2025-11-29 | gpsd integration | wiglewrt, luci/rpcd/wiglewrt.sh |
| prompt-011 | 2025-11-29 | Session deletion feature | luci/rpcd/wiglewrt.sh, luci/view/wiglewrt.js, luci/acl.d/luci-app-wiglewrt.json |
| prompt-012 | 2025-11-29 | Dark theme color fix | luci/view/wiglewrt.js |
| prompt-013 | 2025-11-29 | Enable autostart on boot | wiglewrt.config |
| prompt-014 | 2025-11-29 | Fix autostart crash loop | wiglewrt.init |
| prompt-015 | 2025-11-29 | Create IPK package builder | build_ipk.sh |
| prompt-016 | 2025-11-29 | Fix GPS LED color change | wiglewrt |
| prompt-017 | 2025-11-29 | Privacy mode coordinate masking | luci/view/wiglewrt.js |
| prompt-018 | 2025-11-29 | Scanning performance overhaul | wiglewrt, wiglewrt.config |
| prompt-019 | 2025-11-29 | BLE monitor service | wiglewrt-ble |
