#!/bin/sh
# monitor.sh - Passive monitor mode strategy
# Put interface in monitor mode and listen for beacons
# No active probing - completely passive

# Configuration
DWELL_MS="${DWELL_MS:-200}"

CHANNELS_2G="1 2 3 4 5 6 7 8 9 10 11"
CHANNELS_5G="36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140 144 149 153 157 161 165"

strategy_name() {
    echo "monitor"
}

strategy_desc() {
    echo "Passive monitor mode, beacon sniffing only"
}

strategy_channels() {
    local iface="$1"
    local phy=$(cat /sys/class/net/"$iface"/phy80211/name 2>/dev/null)

    if iw phy "$phy" info 2>/dev/null | grep -q "5180 MHz"; then
        if iw phy "$phy" info 2>/dev/null | grep -q "2412 MHz"; then
            echo "$CHANNELS_2G $CHANNELS_5G"
        else
            echo "$CHANNELS_5G"
        fi
    else
        echo "$CHANNELS_2G"
    fi
}

# Setup monitor mode on interface
strategy_setup() {
    local iface="$1"

    ip link set "$iface" down 2>/dev/null
    iw dev "$iface" set type monitor 2>/dev/null
    ip link set "$iface" up 2>/dev/null

    log info "Set $iface to monitor mode"
}

# Restore managed mode
strategy_teardown() {
    local iface="$1"

    ip link set "$iface" down 2>/dev/null
    iw dev "$iface" set type managed 2>/dev/null
    ip link set "$iface" up 2>/dev/null

    log info "Restored $iface to managed mode"
}

# Parse tcpdump beacon output for networks
# tcpdump output format varies, we look for Beacon frames
parse_beacons() {
    awk '
    /Beacon/ {
        # Extract BSSID from line like: ... SA:aa:bb:cc:dd:ee:ff ...
        if (match($0, /SA:([0-9a-f:]+)/)) {
            bssid = substr($0, RSTART+3, 17)
        }
        # Extract SSID - usually in parentheses after ESSID
        if (match($0, /\(([^)]*)\)/)) {
            ssid = substr($0, RSTART+1, RLENGTH-2)
        }
        if (bssid != "" && ssid != "") {
            print bssid "\t" ssid "\t0\t-50\tUnknown"
            bssid = ""
            ssid = ""
        }
    }'
}

strategy_scan_channel() {
    local iface="$1"
    local channel="$2"
    local parse_awk="${3:-/usr/share/wiglewrt/lib/parse_scan.awk}"

    iw dev "$iface" set channel "$channel" 2>/dev/null || return 1

    # Capture beacons for DWELL_MS
    local tmp_file="/tmp/monitor_$$.pcap"

    # Use tcpdump to capture beacon frames
    timeout_ms=$((DWELL_MS))
    tcpdump -i "$iface" -c 50 -w "$tmp_file" type mgt subtype beacon 2>/dev/null &
    local tcpdump_pid=$!
    sleep_ms "$DWELL_MS"
    kill $tcpdump_pid 2>/dev/null
    wait $tcpdump_pid 2>/dev/null

    # Parse captured beacons
    if [ -f "$tmp_file" ]; then
        tcpdump -r "$tmp_file" -e 2>/dev/null | parse_beacons
        rm -f "$tmp_file"
    fi
}

# Alternative: use iw scan even in monitor mode (some drivers support this)
strategy_scan_channel_iw() {
    local iface="$1"
    local channel="$2"
    local parse_awk="${3:-/usr/share/wiglewrt/lib/parse_scan.awk}"

    iw dev "$iface" set channel "$channel" 2>/dev/null || return 1
    sleep_ms "$DWELL_MS"

    # Try passive scan
    iw dev "$iface" scan passive 2>/dev/null | awk -f "$parse_awk"
}

strategy_scan_cycle() {
    local iface="$1"
    local parse_awk="${2:-/usr/share/wiglewrt/lib/parse_scan.awk}"
    local channels=$(strategy_channels "$iface")

    for ch in $channels; do
        # Use iw passive scan (more reliable than tcpdump parsing)
        strategy_scan_channel_iw "$iface" "$ch" "$parse_awk"
    done
}
