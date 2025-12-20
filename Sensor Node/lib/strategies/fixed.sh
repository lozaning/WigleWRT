#!/bin/sh
# fixed.sh - Fixed dwell time scanning strategy
# Spends exactly DWELL_MS on each channel before moving

# Configuration (can be overridden)
DWELL_MS="${DWELL_MS:-500}"

# Channels by band
CHANNELS_2G="1 2 3 4 5 6 7 8 9 10 11"
CHANNELS_5G="36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140 144 149 153 157 161 165"

strategy_name() {
    echo "fixed_${DWELL_MS}"
}

strategy_desc() {
    echo "Fixed ${DWELL_MS}ms dwell per channel"
}

# Get channels for interface based on phy capabilities
strategy_channels() {
    local iface="$1"
    local phy=$(cat /sys/class/net/"$iface"/phy80211/name 2>/dev/null)

    # Check if 5GHz capable
    if iw phy "$phy" info 2>/dev/null | grep -q "5180 MHz"; then
        # 5GHz capable - check if also 2.4GHz
        if iw phy "$phy" info 2>/dev/null | grep -q "2412 MHz"; then
            echo "$CHANNELS_2G $CHANNELS_5G"
        else
            echo "$CHANNELS_5G"
        fi
    else
        echo "$CHANNELS_2G"
    fi
}

# Scan one channel, output networks found
# Output: BSSID<tab>SSID<tab>CHANNEL<tab>SIGNAL<tab>ENC
strategy_scan_channel() {
    local iface="$1"
    local channel="$2"
    local parse_awk="${3:-/usr/share/wiglewrt/lib/parse_scan.awk}"

    # Do active scan on this frequency
    # freq = channel * 5 + 2407 for 2.4GHz, different for 5GHz
    local freq
    if [ "$channel" -le 14 ]; then
        freq=$((channel * 5 + 2407))
        [ "$channel" -eq 14 ] && freq=2484
    else
        freq=$((channel * 5 + 5000))
    fi

    # Trigger active scan on specific frequency
    iw dev "$iface" scan freq "$freq" 2>/dev/null | awk -f "$parse_awk"
}

# Full scan cycle across all channels
# Output: one line per network found
strategy_scan_cycle() {
    local iface="$1"
    local parse_awk="${2:-/usr/share/wiglewrt/lib/parse_scan.awk}"
    local channels=$(strategy_channels "$iface")

    for ch in $channels; do
        strategy_scan_channel "$iface" "$ch" "$parse_awk"
    done
}
