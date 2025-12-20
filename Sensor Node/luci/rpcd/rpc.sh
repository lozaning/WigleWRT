#!/bin/sh
# rpc.sh - RPC handler for WigleWRT v2
# Simplified version - focused on essential operations

# Paths
WIGLEWRT_BASE="/etc/wiglewrt"
WIGLEWRT_TMP="/tmp/wiglewrt"
DATA_DIR="$WIGLEWRT_BASE/data"
NETWORKS_FILE="$DATA_DIR/networks.tsv"
GPS_FILE="$WIGLEWRT_TMP/gps.current"
STATUS_FILE="$WIGLEWRT_TMP/status.json"
BENCH_DIR="$DATA_DIR/bench"

# Helper: output JSON string
json_string() {
    echo "\"$1\""
}

# Helper: escape string for JSON
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g'
}

# Status method
method_status() {
    if [ -f "$STATUS_FILE" ]; then
        cat "$STATUS_FILE"
    else
        local running="false"
        [ -f "$WIGLEWRT_TMP/wiglewrt.pid" ] && kill -0 $(cat "$WIGLEWRT_TMP/wiglewrt.pid") 2>/dev/null && running="true"

        local networks=0
        [ -f "$NETWORKS_FILE" ] && networks=$(($(wc -l < "$NETWORKS_FILE") - 1))
        [ "$networks" -lt 0 ] && networks=0

        echo "{\"running\":$running,\"networks\":$networks,\"rate\":\"0/s\",\"strategy\":\"none\"}"
    fi
}

# GPS status
method_gps() {
    local gps_data=$(cat "$GPS_FILE" 2>/dev/null)

    if [ -n "$gps_data" ]; then
        local lat=$(echo "$gps_data" | cut -f1)
        local lon=$(echo "$gps_data" | cut -f2)
        local alt=$(echo "$gps_data" | cut -f3)
        local sats=$(echo "$gps_data" | cut -f5)

        echo "{\"fix\":true,\"lat\":$lat,\"lon\":$lon,\"alt\":$alt,\"satellites\":$sats}"
    else
        echo "{\"fix\":false,\"lat\":0,\"lon\":0,\"alt\":0,\"satellites\":0}"
    fi
}

# Networks list
method_networks() {
    local limit="${1:-50}"
    local offset="${2:-0}"

    [ ! -f "$NETWORKS_FILE" ] && echo '{"total":0,"networks":[]}' && return

    local total=$(($(wc -l < "$NETWORKS_FILE") - 1))
    [ "$total" -lt 0 ] && total=0

    echo '{"total":'$total',"networks":['

    # Skip header and offset, take limit
    tail -n +$((offset + 2)) "$NETWORKS_FILE" | head -n "$limit" | awk -F'\t' '
    BEGIN { first = 1 }
    {
        if (!first) print ","
        first = 0

        bssid = $1
        ssid = $2
        gsub(/"/, "\\\"", ssid)
        channel = $3
        signal = $4
        enc = $5
        first_seen = $6
        last_seen = $7
        times = $8
        lat = $9
        lon = $10

        printf "{\"bssid\":\"%s\",\"ssid\":\"%s\",\"channel\":%s,\"signal\":%s,\"encryption\":\"%s\",\"first_seen\":%s,\"last_seen\":%s,\"times_seen\":%s,\"lat\":%s,\"lon\":%s}",
            bssid, ssid, (channel == "" ? "0" : channel), (signal == "" ? "0" : signal), enc,
            (first_seen == "" ? "0" : first_seen), (last_seen == "" ? "0" : last_seen),
            (times == "" ? "1" : times), (lat == "" ? "0" : lat), (lon == "" ? "0" : lon)
    }'

    echo ']}'
}

# Start scanning
method_start() {
    local dwell="${1:-500}"

    /usr/bin/wiglewrt start "$dwell" >/dev/null 2>&1 &

    sleep 1
    echo '{"success":true,"message":"Started scanning with '${dwell}'ms dwell"}'
}

# Stop scanning
method_stop() {
    /usr/bin/wiglewrt stop >/dev/null 2>&1

    echo '{"success":true,"message":"Scanning stopped"}'
}

# Export to WiGLE CSV
method_export() {
    local export_dir="/tmp/wiglewrt_exports"
    mkdir -p "$export_dir"

    local filename="wiglewrt_$(date +%Y%m%d_%H%M%S).csv"
    local filepath="$export_dir/$filename"

    # WiGLE CSV header
    echo "WigleWifi-1.4,appRelease=2.0,model=OpenWRT,release=v2,device=WigleWRT,display=LuCI,board=OnHub,brand=Google" > "$filepath"
    echo "MAC,SSID,AuthMode,FirstSeen,Channel,RSSI,CurrentLatitude,CurrentLongitude,AltitudeMeters,AccuracyMeters,Type" >> "$filepath"

    # Convert networks to WiGLE format
    tail -n +2 "$NETWORKS_FILE" 2>/dev/null | awk -F'\t' '
    {
        bssid = $1
        ssid = $2
        gsub(/"/, "\"\"", ssid)  # Escape quotes for CSV
        enc = $5
        first_seen = $6
        channel = $3
        signal = $4
        lat = $9
        lon = $10
        alt = $11
        acc = $12

        # Convert timestamp to date
        if (first_seen != "" && first_seen > 0) {
            cmd = "date -d @" first_seen " \"+%Y-%m-%d %H:%M:%S\" 2>/dev/null || date -r " first_seen " \"+%Y-%m-%d %H:%M:%S\" 2>/dev/null"
            cmd | getline date_str
            close(cmd)
        } else {
            date_str = ""
        }

        # Map encryption to WiGLE format
        auth = "[" enc "]"

        printf "%s,\"%s\",%s,%s,%s,%s,%s,%s,%s,%s,WIFI\n",
            bssid, ssid, auth, date_str, channel, signal, lat, lon, alt, acc
    }' >> "$filepath"

    chmod 644 "$filepath"

    echo '{"success":true,"filename":"'$filename'","path":"'$filepath'"}'
}

# Benchmark status
method_bench_status() {
    if [ -f "$WIGLEWRT_TMP/bench_pids" ]; then
        local strategy=$(cat /tmp/wiglewrt_strategy 2>/dev/null)
        echo '{"running":true,"strategy":"'$strategy'"}'
    else
        echo '{"running":false}'
    fi
}

# Benchmark results list
method_bench_list() {
    echo '{"trials":['

    local first=1
    for dir in "$BENCH_DIR"/*/; do
        [ ! -d "$dir" ] && continue
        [ ! -f "$dir/summary.json" ] && continue

        [ "$first" -eq 0 ] && echo ","
        first=0

        cat "$dir/summary.json"
    done

    echo ']}'
}

# Main dispatcher
case "$1" in
    list)
        echo '{"status":{},"gps":{},"networks":{"limit":"number","offset":"number"},"start":{"dwell":"number"},"stop":{},"export":{},"bench_status":{},"bench_list":{}}'
        ;;
    call)
        case "$2" in
            status)
                method_status
                ;;
            gps)
                method_gps
                ;;
            networks)
                # Parse JSON params
                limit=$(echo "$3" | jsonfilter -e '@.limit' 2>/dev/null || echo 50)
                offset=$(echo "$3" | jsonfilter -e '@.offset' 2>/dev/null || echo 0)
                method_networks "$limit" "$offset"
                ;;
            start)
                dwell=$(echo "$3" | jsonfilter -e '@.dwell' 2>/dev/null || echo 500)
                method_start "$dwell"
                ;;
            stop)
                method_stop
                ;;
            export)
                method_export
                ;;
            bench_status)
                method_bench_status
                ;;
            bench_list)
                method_bench_list
                ;;
            *)
                echo '{"error":"Unknown method: '$2'"}'
                ;;
        esac
        ;;
    *)
        echo '{"error":"Unknown command"}'
        ;;
esac
