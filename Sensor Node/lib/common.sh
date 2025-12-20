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

# Sensor mode paths
SENSOR_CONF="${SENSOR_CONF:-$WIGLEWRT_BASE/sensor.conf}"
SENSOR_BUFFER="$WIGLEWRT_TMP/sensor_buffer.ndjson"

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

# Buffer a network for reporting to control node (sensor mode)
# Usage: buffer_for_control bssid ssid channel signal encryption
buffer_for_control() {
    local bssid="$1" ssid="$2" channel="$3" signal="$4" enc="$5"

    # Skip if sensor mode not configured
    [ ! -f "$SENSOR_CONF" ] && return 0

    # Escape special chars in SSID for JSON
    local safe_ssid=$(echo "$ssid" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g')

    # Append as newline-delimited JSON (one object per line)
    echo "{\"bssid\":\"$bssid\",\"ssid\":\"$safe_ssid\",\"channel\":\"$channel\",\"signal\":\"$signal\",\"encryption\":\"$enc\"}" >> "$SENSOR_BUFFER"

    # Enforce buffer max size (drop oldest entries if exceeded)
    if [ -f "$SENSOR_CONF" ]; then
        . "$SENSOR_CONF"
        BUFFER_MAX="${BUFFER_MAX:-500}"
        local count=$(wc -l < "$SENSOR_BUFFER" 2>/dev/null | tr -d ' ')
        if [ "$count" -gt "$BUFFER_MAX" ]; then
            local excess=$((count - BUFFER_MAX))
            tail -n +"$((excess + 1))" "$SENSOR_BUFFER" > "${SENSOR_BUFFER}.tmp" && \
                mv "${SENSOR_BUFFER}.tmp" "$SENSOR_BUFFER"
            log debug "Buffer overflow: dropped $excess oldest entries"
        fi
    fi
}

# Trigger sensor report (called after scan cycle)
# Throttled to only send every REPORT_INTERVAL seconds (default 10)
trigger_sensor_report() {
    # Only if sensor mode is configured
    [ ! -f "$SENSOR_CONF" ] && return 0
    [ ! -s "$SENSOR_BUFFER" ] && return 0

    # Load config for interval
    . "$SENSOR_CONF" 2>/dev/null
    local interval="${REPORT_INTERVAL:-10}"
    local last_report_file="$WIGLEWRT_TMP/last_report"
    local now=$(date +%s)

    # Check if enough time has passed since last report
    if [ -f "$last_report_file" ]; then
        local last_report=$(cat "$last_report_file" 2>/dev/null)
        local elapsed=$((now - last_report))
        if [ "$elapsed" -lt "$interval" ]; then
            # Not enough time passed, skip this report
            return 0
        fi
    fi

    # Update last report timestamp
    echo "$now" > "$last_report_file"

    # Run reporter in background to not block scanning
    if [ -x "/usr/bin/sensor-report.sh" ]; then
        /usr/bin/sensor-report.sh &
    elif [ -x "$(dirname "$0")/sensor-report.sh" ]; then
        "$(dirname "$0")/sensor-report.sh" &
    fi
}
