#!/bin/sh
# adaptive.sh - Adaptive dwell time scanning strategy
# Stays longer on channels where networks are found

# Configuration
MIN_DWELL_MS="${MIN_DWELL_MS:-100}"
MAX_DWELL_MS="${MAX_DWELL_MS:-500}"
BUSY_THRESHOLD="${BUSY_THRESHOLD:-3}"

CHANNELS_2G="1 2 3 4 5 6 7 8 9 10 11"
CHANNELS_5G="36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140 144 149 153 157 161 165"

strategy_name() {
    echo "adaptive"
}

strategy_desc() {
    echo "Adaptive dwell ${MIN_DWELL_MS}-${MAX_DWELL_MS}ms based on activity"
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

    # Initial short dwell
    sleep_ms "$MIN_DWELL_MS"

    # Quick check how many networks
    local quick_count=$(iw dev "$iface" scan dump 2>/dev/null | grep -c "^BSS ")

    # If busy channel, wait longer
    if [ "$quick_count" -ge "$BUSY_THRESHOLD" ]; then
        local extra=$((MAX_DWELL_MS - MIN_DWELL_MS))
        sleep_ms "$extra"
    fi

    # Full scan and parse
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
