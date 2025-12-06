#!/bin/sh
# fixed.sh - Fixed dwell time scanning strategy
# Supports common/all channel modes and channel offset for multi-radio coordination

# Configuration (can be overridden by environment)
DWELL_MS="${DWELL_MS:-500}"
CHANNEL_MODE="${CHANNEL_MODE:-common}"
CHANNEL_OFFSET="${CHANNEL_OFFSET:-0}"
RADIO_INDEX="${RADIO_INDEX:-0}"
RADIO_BAND="${RADIO_BAND:-auto}"

# Channel definitions
# Common channels (most APs use these)
CHANNELS_2G_COMMON="1 6 11"
CHANNELS_5G_COMMON="36 40 44 48 149 153 157 161 165"

# All channels
CHANNELS_2G_ALL="1 2 3 4 5 6 7 8 9 10 11"
CHANNELS_5G_ALL="36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140 144 149 153 157 161 165"

# Offset channel orders (for dual-band radio to avoid overlap)
# These start at different points in the sequence
CHANNELS_2G_COMMON_OFFSET="6 11 1"
CHANNELS_5G_COMMON_OFFSET="149 153 157 161 165 36 40 44 48"
CHANNELS_2G_ALL_OFFSET="6 7 8 9 10 11 1 2 3 4 5"
CHANNELS_5G_ALL_OFFSET="100 104 108 112 116 120 124 128 132 136 140 144 149 153 157 161 165 36 40 44 48 52 56 60 64"

strategy_name() {
    local offset_str=""
    [ "$CHANNEL_OFFSET" = "1" ] && offset_str="_offset"
    echo "fixed_${DWELL_MS}_${CHANNEL_MODE}${offset_str}"
}

strategy_desc() {
    echo "Fixed ${DWELL_MS}ms dwell, ${CHANNEL_MODE} channels"
}

# Get channels based on mode, band, and offset
get_channels() {
    local band="$1"
    local use_offset="$2"

    case "$band" in
        2g)
            if [ "$CHANNEL_MODE" = "common" ]; then
                if [ "$use_offset" = "1" ]; then
                    echo "$CHANNELS_2G_COMMON_OFFSET"
                else
                    echo "$CHANNELS_2G_COMMON"
                fi
            else
                if [ "$use_offset" = "1" ]; then
                    echo "$CHANNELS_2G_ALL_OFFSET"
                else
                    echo "$CHANNELS_2G_ALL"
                fi
            fi
            ;;
        5g)
            if [ "$CHANNEL_MODE" = "common" ]; then
                if [ "$use_offset" = "1" ]; then
                    echo "$CHANNELS_5G_COMMON_OFFSET"
                else
                    echo "$CHANNELS_5G_COMMON"
                fi
            else
                if [ "$use_offset" = "1" ]; then
                    echo "$CHANNELS_5G_ALL_OFFSET"
                else
                    echo "$CHANNELS_5G_ALL"
                fi
            fi
            ;;
        dual)
            # Dual-band: interleave 2.4 and 5GHz channels
            # Always use offset for dual-band when offset mode is enabled
            local ch_2g ch_5g
            if [ "$CHANNEL_MODE" = "common" ]; then
                if [ "$use_offset" = "1" ]; then
                    ch_2g="$CHANNELS_2G_COMMON_OFFSET"
                    ch_5g="$CHANNELS_5G_COMMON_OFFSET"
                else
                    ch_2g="$CHANNELS_2G_COMMON"
                    ch_5g="$CHANNELS_5G_COMMON"
                fi
            else
                if [ "$use_offset" = "1" ]; then
                    ch_2g="$CHANNELS_2G_ALL_OFFSET"
                    ch_5g="$CHANNELS_5G_ALL_OFFSET"
                else
                    ch_2g="$CHANNELS_2G_ALL"
                    ch_5g="$CHANNELS_5G_ALL"
                fi
            fi
            # Interleave: 5G, 2G, 5G, 2G... (more 5G channels so extras at end)
            local result=""
            local arr_2g="" arr_5g=""
            set -- $ch_2g; arr_2g="$*"
            set -- $ch_5g; arr_5g="$*"

            local i=1
            while true; do
                local c2=$(echo "$arr_2g" | cut -d' ' -f$i)
                local c5=$(echo "$arr_5g" | cut -d' ' -f$i)
                [ -z "$c2" ] && [ -z "$c5" ] && break
                [ -n "$c5" ] && result="$result $c5"
                [ -n "$c2" ] && result="$result $c2"
                i=$((i + 1))
            done
            echo "$result"
            ;;
    esac
}

# Get channels for interface based on config
strategy_channels() {
    local iface="$1"
    local use_offset=0

    # Use offset for dual-band radio (index 2) when offset is enabled
    if [ "$CHANNEL_OFFSET" = "1" ] && [ "$RADIO_BAND" = "dual" ]; then
        use_offset=1
    fi

    # If band is set via RADIO_BAND, use that
    if [ -n "$RADIO_BAND" ] && [ "$RADIO_BAND" != "auto" ]; then
        get_channels "$RADIO_BAND" "$use_offset"
        return
    fi

    # Auto-detect band from phy capabilities
    local phy=$(cat /sys/class/net/"$iface"/phy80211/name 2>/dev/null)
    local has_5g=0 has_2g=0

    iw phy "$phy" info 2>/dev/null | grep -q "5180 MHz" && has_5g=1
    iw phy "$phy" info 2>/dev/null | grep -q "2412 MHz" && has_2g=1

    if [ "$has_5g" = "1" ] && [ "$has_2g" = "1" ]; then
        get_channels "dual" "$use_offset"
    elif [ "$has_5g" = "1" ]; then
        get_channels "5g" "$use_offset"
    else
        get_channels "2g" "$use_offset"
    fi
}

# Scan one channel, output networks found
# Output: BSSID<tab>SSID<tab>CHANNEL<tab>SIGNAL<tab>ENC
strategy_scan_channel() {
    local iface="$1"
    local channel="$2"
    local parse_awk="${3:-/usr/share/wiglewrt/lib/parse_scan.awk}"

    # Calculate frequency from channel
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
