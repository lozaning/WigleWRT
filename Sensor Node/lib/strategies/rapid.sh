#!/bin/sh
# rapid.sh - Continuous rapid scanning strategy
# Minimum possible dwell time, scan as fast as hardware allows

# Configuration
DWELL_MS="${DWELL_MS:-50}"

CHANNELS_2G="1 6 11"  # Only common channels for speed
CHANNELS_5G="36 44 149 157"  # Only common channels

strategy_name() {
    echo "rapid"
}

strategy_desc() {
    echo "Rapid scan ${DWELL_MS}ms dwell, common channels only"
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

strategy_scan_channel() {
    local iface="$1"
    local channel="$2"
    local parse_awk="${3:-/usr/share/wiglewrt/lib/parse_scan.awk}"

    iw dev "$iface" set channel "$channel" 2>/dev/null || return 1
    sleep_ms "$DWELL_MS"
    iw dev "$iface" scan dump 2>/dev/null | awk -f "$parse_awk"
}

strategy_scan_cycle() {
    local iface="$1"
    local parse_awk="${2:-/usr/share/wiglewrt/lib/parse_scan.awk}"
    local channels=$(strategy_channels "$iface")

    for ch in $channels; do
        strategy_scan_channel "$iface" "$ch" "$parse_awk"
    done
}
