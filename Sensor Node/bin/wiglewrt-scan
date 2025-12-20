#!/bin/sh
# scan.sh - Per-radio scanner for WigleWRT v2
# Runs one instance per wireless interface, writes directly to database
# Usage: scan.sh <interface> <strategy> <dwell_ms>

SCRIPT_DIR="$(dirname "$0")"
# Try multiple locations for common.sh
if [ -f "$SCRIPT_DIR/../lib/common.sh" ]; then
    . "$SCRIPT_DIR/../lib/common.sh"
elif [ -f "/usr/share/wiglewrt/lib/common.sh" ]; then
    . "/usr/share/wiglewrt/lib/common.sh"
else
    echo "ERROR: common.sh not found" >&2
    exit 1
fi

IFACE="$1"
STRATEGY="${2:-fixed}"
DWELL_MS="${3:-500}"

# Validate
if [ -z "$IFACE" ]; then
    echo "Usage: $0 <interface> [strategy] [dwell_ms]"
    echo "Strategies: fixed, adaptive, rapid, monitor"
    exit 1
fi

# Export dwell for strategies
export DWELL_MS

# Load strategy - try multiple locations
if [ -f "$SCRIPT_DIR/../lib/strategies/${STRATEGY}.sh" ]; then
    STRATEGY_FILE="$SCRIPT_DIR/../lib/strategies/${STRATEGY}.sh"
elif [ -f "/usr/share/wiglewrt/lib/strategies/${STRATEGY}.sh" ]; then
    STRATEGY_FILE="/usr/share/wiglewrt/lib/strategies/${STRATEGY}.sh"
else
    log error "Unknown strategy: $STRATEGY"
    exit 1
fi
. "$STRATEGY_FILE"

# Find parse_scan.awk - try multiple locations
if [ -f "$SCRIPT_DIR/../lib/parse_scan.awk" ]; then
    PARSE_AWK="$SCRIPT_DIR/../lib/parse_scan.awk"
elif [ -f "/usr/share/wiglewrt/lib/parse_scan.awk" ]; then
    PARSE_AWK="/usr/share/wiglewrt/lib/parse_scan.awk"
else
    log error "parse_scan.awk not found"
    exit 1
fi
LOCK_FILE="$WIGLEWRT_TMP/db.lock"

log info "Starting scanner on $IFACE with strategy $(strategy_name)"

# Setup interface
setup_interface() {
    ip link set "$IFACE" down 2>/dev/null
    iw dev "$IFACE" set type managed 2>/dev/null
    ip link set "$IFACE" up 2>/dev/null
    log info "Interface $IFACE ready"
}

# Acquire lock (simple flock-like using mkdir)
acquire_lock() {
    local attempts=0
    while ! mkdir "$LOCK_FILE" 2>/dev/null; do
        attempts=$((attempts + 1))
        if [ $attempts -gt 50 ]; then
            # Stale lock - force remove
            rm -rf "$LOCK_FILE"
        fi
        sleep 0.1 2>/dev/null || usleep 100000 2>/dev/null || sleep 1
    done
}

release_lock() {
    rmdir "$LOCK_FILE" 2>/dev/null
}

# Initialize database if needed
init_db() {
    if [ ! -f "$NETWORKS_FILE" ] || [ ! -s "$NETWORKS_FILE" ]; then
        mkdir -p "$(dirname "$NETWORKS_FILE")"
        echo "bssid	ssid	channel	signal	encryption	first_seen	last_seen	times_seen	lat	lon	alt	acc" > "$NETWORKS_FILE"
        log info "Initialized networks database"
    fi
}

# Update network in database
update_network() {
    local bssid="$1" ssid="$2" channel="$3" signal="$4" enc="$5"
    local lat="$6" lon="$7" alt="$8" acc="$9"
    local ts=$(now)

    acquire_lock

    # Check if exists
    if grep -q "^$bssid	" "$NETWORKS_FILE" 2>/dev/null; then
        # Update existing
        awk -F'\t' -v OFS='\t' -v b="$bssid" -v ts="$ts" -v sig="$signal" '
            $1 == b {
                $7 = ts
                $8 = $8 + 1
            }
            { print }
        ' "$NETWORKS_FILE" > "$NETWORKS_FILE.tmp" && mv "$NETWORKS_FILE.tmp" "$NETWORKS_FILE"
    else
        # New network
        echo "$bssid	$ssid	$channel	$signal	$enc	$ts	$ts	1	$lat	$lon	$alt	$acc" >> "$NETWORKS_FILE"
        log info "NEW: $ssid ($bssid) ch$channel ${signal}dBm"
    fi

    release_lock
}

# Scan loop - runs forever
scan_loop() {
    local cycle=0

    init_db

    while true; do
        cycle=$((cycle + 1))

        # Read GPS (non-blocking from file)
        local gps_data=$(cat "$GPS_FILE" 2>/dev/null)
        local lat="" lon="" alt="" acc=""
        if [ -n "$gps_data" ]; then
            lat=$(echo "$gps_data" | cut -f1)
            lon=$(echo "$gps_data" | cut -f2)
            alt=$(echo "$gps_data" | cut -f3)
            acc=$(echo "$gps_data" | cut -f4)
        fi

        # Run scan cycle, process each network
        strategy_scan_cycle "$IFACE" "$PARSE_AWK" | while IFS='	' read -r bssid ssid channel signal enc; do
            [ -z "$bssid" ] && continue
            update_network "$bssid" "$ssid" "$channel" "$signal" "$enc" "$lat" "$lon" "$alt" "$acc"

            # Buffer for control node (if sensor mode enabled)
            buffer_for_control "$bssid" "$ssid" "$channel" "$signal" "$enc"
        done

        log debug "Cycle $cycle complete on $IFACE"

        # Trigger sensor report to control node (runs in background)
        trigger_sensor_report
    done
}

# Main
case "${4:-run}" in
    run)
        setup_interface
        scan_loop
        ;;
    setup)
        setup_interface
        ;;
    test)
        setup_interface
        init_db
        log info "Running single scan cycle..."
        strategy_scan_cycle "$IFACE" "$PARSE_AWK"
        ;;
    *)
        echo "Usage: $0 <interface> <strategy> <dwell_ms> [run|setup|test]"
        exit 1
        ;;
esac
