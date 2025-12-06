#!/bin/sh
# export.sh - WiGLE CSV exporter for WigleWRT v2

SCRIPT_DIR="$(dirname "$0")"
. "$SCRIPT_DIR/../lib/common.sh"

EXPORT_DIR="/tmp/wiglewrt_exports"

usage() {
    cat << EOF
WigleWRT Export Tool

Usage: $0 [options]

Options:
    -o <file>    Output file path (default: auto-generated)
    -f <format>  Output format: wigle, csv, json (default: wigle)
    -h           Show this help

Examples:
    $0                           # Export to WiGLE CSV
    $0 -o /tmp/export.csv        # Export to specific file
    $0 -f json -o networks.json  # Export as JSON
EOF
}

# Export to WiGLE CSV format
export_wigle() {
    local output="$1"

    # WiGLE header
    echo "WigleWifi-1.4,appRelease=2.0,model=OpenWRT,release=v2,device=WigleWRT,display=LuCI,board=OnHub,brand=Google"
    echo "MAC,SSID,AuthMode,FirstSeen,Channel,RSSI,CurrentLatitude,CurrentLongitude,AltitudeMeters,AccuracyMeters,Type"

    # Convert each network
    tail -n +2 "$NETWORKS_FILE" 2>/dev/null | while IFS='	' read -r bssid ssid channel signal enc first_seen last_seen times lat lon alt acc; do
        # Skip empty
        [ -z "$bssid" ] && continue

        # Escape SSID for CSV
        ssid_escaped=$(echo "$ssid" | sed 's/"/""/g')

        # Convert timestamp
        if [ -n "$first_seen" ] && [ "$first_seen" -gt 0 ] 2>/dev/null; then
            date_str=$(date -d "@$first_seen" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || \
                       date -r "$first_seen" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || \
                       echo "")
        else
            date_str=""
        fi

        # Format auth mode
        auth="[$enc]"

        echo "$bssid,\"$ssid_escaped\",$auth,$date_str,$channel,$signal,$lat,$lon,$alt,$acc,WIFI"
    done
}

# Export to simple CSV
export_csv() {
    echo "bssid,ssid,channel,signal,encryption,first_seen,last_seen,times_seen,lat,lon,alt,acc"

    tail -n +2 "$NETWORKS_FILE" 2>/dev/null | while IFS='	' read -r bssid ssid channel signal enc first_seen last_seen times lat lon alt acc; do
        [ -z "$bssid" ] && continue
        ssid_escaped=$(echo "$ssid" | sed 's/"/""/g')
        echo "$bssid,\"$ssid_escaped\",$channel,$signal,$enc,$first_seen,$last_seen,$times,$lat,$lon,$alt,$acc"
    done
}

# Export to JSON
export_json() {
    echo '{"networks":['

    local first=1
    tail -n +2 "$NETWORKS_FILE" 2>/dev/null | while IFS='	' read -r bssid ssid channel signal enc first_seen last_seen times lat lon alt acc; do
        [ -z "$bssid" ] && continue

        [ "$first" -eq 0 ] && echo ","
        first=0

        ssid_escaped=$(echo "$ssid" | sed 's/\\/\\\\/g; s/"/\\"/g')

        cat << EOF
{"bssid":"$bssid","ssid":"$ssid_escaped","channel":$channel,"signal":$signal,"encryption":"$enc","first_seen":$first_seen,"last_seen":$last_seen,"times_seen":$times,"lat":$lat,"lon":$lon,"alt":$alt,"acc":$acc}
EOF
    done

    echo ']}'
}

# Main
OUTPUT=""
FORMAT="wigle"

while getopts "o:f:h" opt; do
    case "$opt" in
        o) OUTPUT="$OPTARG" ;;
        f) FORMAT="$OPTARG" ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

# Check networks file exists
if [ ! -f "$NETWORKS_FILE" ]; then
    log error "No networks database found: $NETWORKS_FILE"
    exit 1
fi

# Generate output filename if not specified
if [ -z "$OUTPUT" ]; then
    mkdir -p "$EXPORT_DIR"
    case "$FORMAT" in
        wigle|csv) OUTPUT="$EXPORT_DIR/wiglewrt_$(date +%Y%m%d_%H%M%S).csv" ;;
        json) OUTPUT="$EXPORT_DIR/wiglewrt_$(date +%Y%m%d_%H%M%S).json" ;;
    esac
fi

# Export based on format
case "$FORMAT" in
    wigle)
        export_wigle > "$OUTPUT"
        ;;
    csv)
        export_csv > "$OUTPUT"
        ;;
    json)
        export_json > "$OUTPUT"
        ;;
    *)
        log error "Unknown format: $FORMAT"
        exit 1
        ;;
esac

chmod 644 "$OUTPUT"

count=$(($(wc -l < "$NETWORKS_FILE") - 1))
log info "Exported $count networks to $OUTPUT"
echo "$OUTPUT"
