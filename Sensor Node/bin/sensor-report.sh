#!/bin/sh
# sensor-report.sh - Send buffered scan data to control node
# Called after each scan cycle to report discovered networks
# FIXED: Use --data-binary and case pattern for success check

SCRIPT_DIR="$(dirname "$0")"
# Try multiple locations for common.sh
if [ -f "$SCRIPT_DIR/../lib/common.sh" ]; then
    . "$SCRIPT_DIR/../lib/common.sh"
elif [ -f "/usr/share/wiglewrt/lib/common.sh" ]; then
    . "/usr/share/wiglewrt/lib/common.sh"
else
    # Minimal fallback definitions
    WIGLEWRT_TMP="${WIGLEWRT_TMP:-/tmp/wiglewrt}"
    SENSOR_BUFFER="$WIGLEWRT_TMP/sensor_buffer.ndjson"
    log() { echo "[$(date +%H:%M:%S)] $1: $2" >&2; }
fi

# Load sensor config
SENSOR_CONF="${SENSOR_CONF:-/etc/wiglewrt/sensor.conf}"
if [ -f "$SENSOR_CONF" ]; then
    . "$SENSOR_CONF"
fi

# Configuration with defaults
CONTROL_NODE="${CONTROL_NODE:-10.10.10.20}"
NODE_ID="${NODE_ID:-sensor1}"
BUFFER_FILE="${SENSOR_BUFFER:-$WIGLEWRT_TMP/sensor_buffer.ndjson}"
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY="${RETRY_DELAY:-2}"

# Check if buffer exists and has content
if [ ! -f "$BUFFER_FILE" ] || [ ! -s "$BUFFER_FILE" ]; then
    log debug "No buffered data to send"
    exit 0
fi

# Count networks in buffer
NETWORK_COUNT=$(wc -l < "$BUFFER_FILE" | tr -d " ")
if [ "$NETWORK_COUNT" -eq 0 ]; then
    log debug "Buffer empty"
    exit 0
fi

log info "Sending $NETWORK_COUNT networks to control node $CONTROL_NODE"

# Send buffer directly as ndjson (one JSON object per line)
# Prepend node_id header line
PAYLOAD_FILE="$WIGLEWRT_TMP/sensor_payload.ndjson"

{
    echo "NODE:$NODE_ID"
    cat "$BUFFER_FILE"
} > "$PAYLOAD_FILE"

# Send to control node with retries
send_data() {
    local retry=0
    local response=""

    while [ $retry -lt $MAX_RETRIES ]; do
        # Use curl with --data-binary to preserve newlines in ndjson
        if command -v curl >/dev/null 2>&1; then
            response=$(curl -s \
                -H "Content-Type: text/plain" \
                --data-binary @"$PAYLOAD_FILE" \
                --connect-timeout 10 \
                "http://${CONTROL_NODE}/cgi-bin/sensor-receive" 2>/dev/null)
        elif command -v wget >/dev/null 2>&1; then
            # wget as fallback - but may not work with all uhttpd configs
            response=$(wget -q -O - \
                --post-file="$PAYLOAD_FILE" \
                --timeout=10 \
                "http://${CONTROL_NODE}/cgi-bin/sensor-receive" 2>/dev/null)
        else
            log error "No curl or wget available"
            return 1
        fi

        # Check for success using case pattern (works with busybox ash)
        case "$response" in
            *success*true*)
                log info "Successfully sent $NETWORK_COUNT networks to control node"
                return 0
                ;;
        esac

        retry=$((retry + 1))
        if [ $retry -lt $MAX_RETRIES ]; then
            log warn "Failed to send (attempt $retry/$MAX_RETRIES), retrying in ${RETRY_DELAY}s..."
            sleep "$RETRY_DELAY"
        fi
    done

    log error "Failed to send data after $MAX_RETRIES attempts. Response: $response"
    return 1
}

# Send data
if send_data; then
    # Success - clear buffer
    > "$BUFFER_FILE"
    log debug "Buffer cleared"
    rm -f "$PAYLOAD_FILE"
    exit 0
else
    # Failed - keep buffer for retry
    log warn "Keeping buffer for retry"
    rm -f "$PAYLOAD_FILE"
    exit 1
fi
