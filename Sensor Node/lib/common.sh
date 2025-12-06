#!/bin/sh
# common.sh - Shared functions for WigleWRT v2
# Keep this small and focused

# Paths
WIGLEWRT_BASE="${WIGLEWRT_BASE:-/etc/wiglewrt}"
WIGLEWRT_TMP="${WIGLEWRT_TMP:-/tmp/wiglewrt}"
WIGLEWRT_CONFIG="${WIGLEWRT_CONFIG:-$WIGLEWRT_BASE/config}"

DATA_DIR="$WIGLEWRT_BASE/data"
NETWORKS_FILE="$DATA_DIR/networks.tsv"
GPS_FILE="$WIGLEWRT_TMP/gps.current"
STATUS_FILE="$WIGLEWRT_TMP/status.json"
EVENTS_PIPE="$WIGLEWRT_TMP/events"
LED_PIPE="$WIGLEWRT_TMP/led_cmd"

# Log levels: 0=error, 1=warn, 2=info, 3=debug
LOG_LEVEL="${LOG_LEVEL:-2}"

log() {
    local level="$1"
    shift
    local msg="$*"
    local ts=$(date '+%H:%M:%S')

    case "$level" in
        error) [ "$LOG_LEVEL" -ge 0 ] && echo "[$ts] ERROR: $msg" >&2 ;;
        warn)  [ "$LOG_LEVEL" -ge 1 ] && echo "[$ts] WARN: $msg" >&2 ;;
        info)  [ "$LOG_LEVEL" -ge 2 ] && echo "[$ts] INFO: $msg" ;;
        debug) [ "$LOG_LEVEL" -ge 3 ] && echo "[$ts] DEBUG: $msg" ;;
    esac
}

# Initialize runtime directories and pipes
init_runtime() {
    mkdir -p "$WIGLEWRT_TMP" "$DATA_DIR"

    # Create named pipes if they don't exist
    [ ! -p "$EVENTS_PIPE" ] && mkfifo "$EVENTS_PIPE"
    [ ! -p "$LED_PIPE" ] && mkfifo "$LED_PIPE"

    # Initialize GPS file
    echo "" > "$GPS_FILE"

    log info "Runtime initialized at $WIGLEWRT_TMP"
}

# Clean up runtime
cleanup_runtime() {
    rm -f "$EVENTS_PIPE" "$LED_PIPE" "$GPS_FILE" "$STATUS_FILE"
    rm -rf "$WIGLEWRT_TMP"
    log info "Runtime cleaned up"
}

# Load config file (simple key=value format)
load_config() {
    local config_file="${1:-$WIGLEWRT_CONFIG}"
    if [ -f "$config_file" ]; then
        . "$config_file"
        log debug "Loaded config from $config_file"
    else
        log warn "Config file not found: $config_file"
    fi
}

# Get current timestamp in seconds
now() {
    date +%s
}

# Get current timestamp in ISO format
now_iso() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Sleep in milliseconds (OpenWRT compatible)
sleep_ms() {
    local ms="$1"
    local sec=$(echo "scale=3; $ms / 1000" | bc 2>/dev/null || echo "0.$ms")
    sleep "$sec" 2>/dev/null || usleep "$((ms * 1000))" 2>/dev/null || sleep 1
}

# Check if process is running
is_running() {
    local pidfile="$1"
    [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null
}

# Write PID file
write_pid() {
    local pidfile="$1"
    echo $$ > "$pidfile"
}

# Read current GPS (returns: lat lon alt acc sats ts or empty)
get_gps() {
    [ -f "$GPS_FILE" ] && cat "$GPS_FILE" 2>/dev/null
}

# Write status JSON
write_status() {
    local running="$1"
    local networks="$2"
    local rate="$3"
    local strategy="$4"

    cat > "$STATUS_FILE" << EOF
{"running":$running,"networks":$networks,"rate":"$rate","strategy":"$strategy","time":"$(now_iso)"}
EOF
}

# Get interface for a phy
get_interface() {
    local phy="$1"
    ls /sys/class/ieee80211/"$phy"/device/net/ 2>/dev/null | head -1
}

# Get all wireless phys
get_phys() {
    ls /sys/class/ieee80211/ 2>/dev/null
}
