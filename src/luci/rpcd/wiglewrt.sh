#!/bin/sh
# WigleWRT ubus RPC handler

# Read version from VERSION file
VERSION=$(cat /usr/share/wiglewrt/VERSION 2>/dev/null || echo "2.1.0")

DATA_DIR="/etc/wiglewrt"
NETWORKS_FILE="$DATA_DIR/networks.tsv"
SESSIONS_DIR="$DATA_DIR/sessions"
PID_FILE="/var/run/wiglewrt.pid"

# Check if running
is_running() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "1"
            return 0
        fi
    fi
    echo "0"
    return 1
}

# Get current session
get_current_session() {
    if [ "$(is_running)" = "1" ]; then
        for meta in $(ls -t "$SESSIONS_DIR"/*.meta 2>/dev/null); do
            if grep -q "status=running" "$meta" 2>/dev/null; then
                basename "$meta" .meta
                return
            fi
        done
    fi
    echo ""
}

# Count networks
count_networks() {
    tail -n +2 "$NETWORKS_FILE" 2>/dev/null | wc -l | tr -d ' '
}

# Status method
status() {
    local running=$(is_running)
    local pid=""
    [ "$running" = "1" ] && pid=$(cat "$PID_FILE" 2>/dev/null)
    local current=$(get_current_session)
    local total=$(count_networks)

    local session_start=""
    local session_new=""
    if [ -n "$current" ]; then
        session_start=$(grep "start_time=" "$SESSIONS_DIR/$current.meta" 2>/dev/null | cut -d= -f2)
        session_new=$(grep "new_networks=" "$SESSIONS_DIR/$current.meta" 2>/dev/null | cut -d= -f2)
    fi

    echo "{"
    echo "  \"running\": $running,"
    echo "  \"pid\": \"$pid\","
    echo "  \"current_session\": \"$current\","
    echo "  \"total_networks\": $total,"
    echo "  \"session_start\": \"$session_start\","
    echo "  \"session_new\": \"${session_new:-0}\""
    echo "}"
}

# Networks method
networks() {
    local limit=${1:-100}
    local offset=${2:-0}

    echo "{"
    echo "  \"total\": $(count_networks),"
    echo "  \"limit\": $limit,"
    echo "  \"offset\": $offset,"
    echo "  \"networks\": ["

    # Sort by last_seen (field 7) descending and apply limit/offset
    # Filter out control characters from SSIDs and escape for JSON
    # Skip empty/null entries (from corrupted data)
    tail -n +2 "$NETWORKS_FILE" 2>/dev/null | grep -v '^[[:space:]]*$' | \
        grep -v '^\x00' | sort -t'	' -k7 -r | \
        tail -n "+$((offset + 1))" | head -n "$limit" | \
        awk -F'\t' '
        BEGIN { first = 1 }
        {
            # Skip entries with empty BSSID
            if ($1 == "" || length($1) < 10) next
            if (!first) printf ","
            first = 0
            # Clean SSID - remove control chars and escape for JSON
            ssid = $2
            gsub(/\\/, "\\\\", ssid)
            gsub(/"/, "\\\"", ssid)
            gsub(/\x00/, "", ssid)
            gsub(/[\x01-\x1f]/, "", ssid)
            if (ssid == "") ssid = "<hidden>"
            printf "\n    {\"bssid\":\"%s\",\"ssid\":\"%s\",\"channel\":\"%s\",\"signal\":\"%s\",\"encryption\":\"%s\",\"first_seen\":\"%s\",\"last_seen\":\"%s\",\"times_seen\":%s,\"lat\":\"%s\",\"lon\":\"%s\"}", \
                $1, ssid, $3, $4, $5, $6, $7, ($8 ? $8 : 1), $9, $10
        }
        END { printf "\n" }
        '

    echo "  ]"
    echo "}"
}

# Sessions method
sessions() {
    local running_now=$(is_running)
    local current_session=$(get_current_session)

    echo "{"
    echo "  \"sessions\": ["

    first=1
    for meta in $(ls -t "$SESSIONS_DIR"/*.meta 2>/dev/null); do
        session=$(basename "$meta" .meta)
        # Use head -1 to ensure single values (avoid duplicate lines in meta files)
        start=$(grep "start_time=" "$meta" | head -1 | cut -d= -f2 | tr -d '\n\r')
        end=$(grep "end_time=" "$meta" | head -1 | cut -d= -f2 | tr -d '\n\r')
        new=$(grep "new_networks=" "$meta" | head -1 | cut -d= -f2 | tr -d '\n\r')
        total=$(grep "networks_at_end=" "$meta" | head -1 | cut -d= -f2 | tr -d '\n\r')
        stat=$(grep "status=" "$meta" | head -1 | cut -d= -f2 | tr -d '\n\r')

        # If status is "running" but scanner not running, or it's not the current session, mark as abandoned
        if [ "$stat" = "running" ]; then
            if [ "$running_now" = "0" ]; then
                stat="abandoned"
            elif [ "$session" != "$current_session" ]; then
                stat="abandoned"
            fi
        fi

        if [ $first -eq 0 ]; then
            echo ","
        fi
        first=0

        echo "    {"
        echo "      \"session_id\": \"$session\","
        echo "      \"start_time\": \"$start\","
        echo "      \"end_time\": \"$end\","
        echo "      \"new_networks\": ${new:-0},"
        echo "      \"total_networks\": ${total:-0},"
        echo "      \"status\": \"$stat\""
        printf "    }"
    done

    echo ""
    echo "  ]"
    echo "}"
}

# Start method
do_start() {
    if [ "$(is_running)" = "1" ]; then
        echo '{"success": false, "message": "Already running"}'
        return
    fi

    uci set wiglewrt.settings.enabled=1
    uci commit wiglewrt

    # Start scanner using start-stop-daemon for proper daemonization
    start-stop-daemon -S -b -x /usr/bin/wiglewrt -- start
    sleep 2

    if [ "$(is_running)" = "1" ]; then
        echo '{"success": true, "message": "Scanner started"}'
    else
        echo '{"success": false, "message": "Failed to start scanner"}'
    fi
}

# Stop method
do_stop() {
    if [ "$(is_running)" = "0" ]; then
        echo '{"success": false, "message": "Not running"}'
        return
    fi

    # Close the current session before stopping
    local current=$(get_current_session)
    if [ -n "$current" ] && [ -f "$SESSIONS_DIR/$current.meta" ]; then
        sed -i 's/status=running/status=completed/' "$SESSIONS_DIR/$current.meta"
        echo "end_time=$(date '+%Y-%m-%d %H:%M:%S')" >> "$SESSIONS_DIR/$current.meta"
        # Calculate new networks for this session
        local total_now=$(count_networks)
        local total_start=$(grep "networks_at_start=" "$SESSIONS_DIR/$current.meta" | cut -d= -f2)
        local new_nets=$((total_now - total_start))
        echo "networks_at_end=$total_now" >> "$SESSIONS_DIR/$current.meta"
        echo "new_networks=$new_nets" >> "$SESSIONS_DIR/$current.meta"
    fi

    # Kill the scanner process directly
    if [ -f "$PID_FILE" ]; then
        kill $(cat "$PID_FILE") 2>/dev/null
        sleep 1
        # Force kill if still running
        [ -f "$PID_FILE" ] && kill -9 $(cat "$PID_FILE") 2>/dev/null
        rm -f "$PID_FILE"
    fi

    echo '{"success": true, "message": "Scanner stopped"}'
}

# Export method
do_export() {
    local session_id="$1"
    local output

    if [ -n "$session_id" ] && [ "$session_id" != "null" ]; then
        output=$(/usr/bin/wiglewrt-export session "$session_id" 2>/dev/null)
    else
        output=$(/usr/bin/wiglewrt-export all 2>/dev/null)
    fi

    # Get only the first filepath match and trim whitespace
    filepath=$(echo "$output" | grep -o '/[^ ]*\.csv' | head -1 | tr -d '\n\r')

    if [ -n "$filepath" ]; then
        echo "{\"success\": true, \"filepath\": \"$filepath\"}"
    else
        echo '{"success": false, "filepath": ""}'
    fi
}

# Session log method - returns sightings for a specific session
# filter: "all" (default) or "new" (only is_new=1 entries)
session_log() {
    local session_id="$1"
    local limit=${2:-100}
    local offset=${3:-0}
    local filter=${4:-all}

    local log_file="$SESSIONS_DIR/$session_id.log"

    if [ ! -f "$log_file" ]; then
        echo '{"error": "Session log not found", "entries": [], "total": 0, "unique": 0, "new_networks": 0}'
        return
    fi

    # Get base data
    local all_data=$(tail -n +2 "$log_file" 2>/dev/null)

    # Calculate totals from full dataset
    local total=$(echo "$all_data" | wc -l | tr -d ' ')
    local unique=$(echo "$all_data" | cut -f2 | sort -u | wc -l | tr -d ' ')
    local new_count=$(echo "$all_data" | awk -F'\t' '$10=="1"' | wc -l | tr -d ' ')

    # Apply filter if needed
    local filtered_data
    local filtered_total
    if [ "$filter" = "new" ]; then
        filtered_data=$(echo "$all_data" | awk -F'\t' '$10=="1"')
        filtered_total=$new_count
    else
        filtered_data="$all_data"
        filtered_total=$total
    fi

    echo "{"
    echo "  \"session_id\": \"$session_id\","
    echo "  \"total\": $total,"
    echo "  \"unique\": $unique,"
    echo "  \"new_networks\": $new_count,"
    echo "  \"filtered_total\": $filtered_total,"
    echo "  \"filter\": \"$filter\","
    echo "  \"limit\": $limit,"
    echo "  \"offset\": $offset,"
    echo "  \"entries\": ["

    echo "$filtered_data" | \
        tail -n "+$((offset + 1))" | head -n "$limit" | \
        awk -F'\t' '
        BEGIN { first = 1 }
        {
            if ($1 == "") next
            if (!first) printf ","
            first = 0
            # Clean SSID
            ssid = $3
            gsub(/\\/, "\\\\", ssid)
            gsub(/"/, "\\\"", ssid)
            # Remove control characters (simpler pattern for busybox awk)
            gsub(/[[:cntrl:]]/, "", ssid)
            if (ssid == "") ssid = "<hidden>"
            printf "\n    {\"timestamp\":\"%s\",\"bssid\":\"%s\",\"ssid\":\"%s\",\"channel\":\"%s\",\"signal\":\"%s\",\"lat\":\"%s\",\"lon\":\"%s\",\"alt\":\"%s\",\"acc\":\"%s\",\"is_new\":%s}", \
                $1, $2, ssid, $4, $5, $6, $7, $8, $9, ($10 == "1" ? "true" : "false")
        }
        END { printf "\n" }
        '

    echo "  ]"
    echo "}"
}

# GPS status method - tries gpsd first, falls back to direct device access
gps_status() {
    local gps_valid=0
    local lat=""
    local lon=""
    local alt=""
    local sats_visible=0
    local gps_device=""
    local source="none"

    # Method 1: Try gpsd via gpspipe (preferred)
    if command -v gpspipe >/dev/null 2>&1; then
        local gpsd_data=$(timeout 2 gpspipe -w -n 5 2>/dev/null | grep -m1 '"class":"TPV"')
        if [ -n "$gpsd_data" ]; then
            source="gpsd"
            gps_device="gpsd"
            # Parse JSON from gpsd - extract mode, lat, lon, alt
            local mode=$(echo "$gpsd_data" | sed 's/.*"mode":\([0-9]*\).*/\1/' 2>/dev/null)
            if [ "$mode" = "2" ] || [ "$mode" = "3" ]; then
                gps_valid=1
                lat=$(echo "$gpsd_data" | sed 's/.*"lat":\([^,}]*\).*/\1/' 2>/dev/null)
                lon=$(echo "$gpsd_data" | sed 's/.*"lon":\([^,}]*\).*/\1/' 2>/dev/null)
                alt=$(echo "$gpsd_data" | sed 's/.*"alt":\([^,}]*\).*/\1/' 2>/dev/null)
            fi
            # Get satellite count from SKY message
            local sky_data=$(timeout 1 gpspipe -w -n 10 2>/dev/null | grep -m1 '"class":"SKY"')
            if [ -n "$sky_data" ]; then
                sats_visible=$(echo "$sky_data" | sed 's/.*"nSat":\([0-9]*\).*/\1/' 2>/dev/null)
                [ -z "$sats_visible" ] && sats_visible=0
            fi

            echo "{"
            echo "  \"available\": true,"
            echo "  \"device\": \"$gps_device\","
            echo "  \"source\": \"$source\","
            echo "  \"fix\": $gps_valid,"
            echo "  \"sats\": $sats_visible,"
            echo "  \"lat\": \"$lat\","
            echo "  \"lon\": \"$lon\","
            echo "  \"alt\": \"$alt\""
            echo "}"
            return
        fi
    fi

    # Method 2: Try direct device access (fallback)
    # Check multiple common GPS device paths
    for dev in /dev/ttyACM0 /dev/ttyACM1 /dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyUSB2 /dev/gps0 /dev/gps; do
        if [ -c "$dev" ]; then
            gps_device="$dev"
            source="direct"
            break
        fi
    done

    if [ -n "$gps_device" ]; then
        # Try to read GPS data directly from device using cat with timeout
        local nmea=$(cat "$gps_device" 2>/dev/null &
            sleep 2
            kill %1 2>/dev/null
        )
        local rmc=$(echo "$nmea" | grep -E '\$G[NP]RMC' | head -1)

        # Get satellite count from GSV sentences
        local gsv_sats=$(echo "$nmea" | grep -E '\$G[PNLB]GSV' | head -1 | cut -d, -f4)
        [ -n "$gsv_sats" ] && sats_visible=$gsv_sats

        if [ -n "$rmc" ]; then
            local status=$(echo "$rmc" | cut -d, -f3)
            if [ "$status" = "A" ]; then
                gps_valid=1
                local lat_raw=$(echo "$rmc" | cut -d, -f4)
                local lat_dir=$(echo "$rmc" | cut -d, -f5)
                local lon_raw=$(echo "$rmc" | cut -d, -f6)
                local lon_dir=$(echo "$rmc" | cut -d, -f7)

                if [ -n "$lat_raw" ] && [ -n "$lon_raw" ]; then
                    lat_deg=$(echo "$lat_raw" | cut -c1-2)
                    lat_min=$(echo "$lat_raw" | cut -c3-)
                    lat=$(awk "BEGIN {printf \"%.6f\", $lat_deg + ($lat_min / 60)}" 2>/dev/null)
                    [ "$lat_dir" = "S" ] && lat="-$lat"

                    lon_deg=$(echo "$lon_raw" | cut -c1-3)
                    lon_min=$(echo "$lon_raw" | cut -c4-)
                    lon=$(awk "BEGIN {printf \"%.6f\", $lon_deg + ($lon_min / 60)}" 2>/dev/null)
                    [ "$lon_dir" = "W" ] && lon="-$lon"
                fi
            fi
        fi

        echo "{"
        echo "  \"available\": true,"
        echo "  \"device\": \"$gps_device\","
        echo "  \"source\": \"$source\","
        echo "  \"fix\": $gps_valid,"
        echo "  \"sats\": $sats_visible,"
        echo "  \"lat\": \"$lat\","
        echo "  \"lon\": \"$lon\""
        echo "}"
    else
        echo "{"
        echo "  \"available\": false,"
        echo "  \"device\": \"none\","
        echo "  \"source\": \"none\","
        echo "  \"fix\": 0,"
        echo "  \"sats\": 0,"
        echo "  \"lat\": \"\","
        echo "  \"lon\": \"\""
        echo "}"
    fi
}

# Delete sessions method - removes selected session files
do_delete_sessions() {
    local deleted=0
    local failed=0

    # Read session IDs from input (passed as JSON array string)
    # Parse each session ID and delete its files
    while read -r sid; do
        # Skip empty lines
        [ -z "$sid" ] && continue

        # Security: validate session ID format (only alphanumeric, underscore, dash)
        case "$sid" in
            *[!a-zA-Z0-9_-]*)
                failed=$((failed + 1))
                continue
                ;;
        esac

        # Delete session files if they exist
        if [ -f "$SESSIONS_DIR/$sid.meta" ] || [ -f "$SESSIONS_DIR/$sid.log" ]; then
            rm -f "$SESSIONS_DIR/$sid.meta" 2>/dev/null
            rm -f "$SESSIONS_DIR/$sid.log" 2>/dev/null
            deleted=$((deleted + 1))
        else
            failed=$((failed + 1))
        fi
    done

    echo "{\"success\": true, \"deleted\": $deleted, \"failed\": $failed}"
}

# Radios method - simplified static response based on device capabilities
radios() {
    cat << 'RADIOJSON'
{
  "radios": {
    "phy0": {
      "band": "2g",
      "channels": [1,2,3,4,5,6,7,8,9,10,11]
    },
    "phy1": {
      "band": "5g",
      "channels": [36,40,44,48,52,56,60,64,100,104,108,112,116,120,124,128,132,136,140,144,149,153,157,161,165]
    },
    "phy2": {
      "band": "dual",
      "channels_2g": [1,2,3,4,5,6,7,8,9,10,11],
      "channels_5g": [36,40,44,48,52,56,60,64,100,104,108,112,116,120,124,128,132,136,140,144,149,153,157,161,165]
    }
  }
}
RADIOJSON
}

# Main dispatch
case "$1" in
    list)
        echo '{"status":{},"networks":{"limit":"int","offset":"int"},"sessions":{},"session_log":{"session_id":"str","limit":"int","offset":"int","filter":"str"},"gps_status":{},"start":{},"stop":{},"export":{"session_id":"str"},"delete_sessions":{"session_ids":"array"},"radios":{},"version":{}}'
        ;;
    call)
        # Read JSON parameters from stdin
        read input
        case "$2" in
            status)
                status
                ;;
            networks)
                # Parse JSON args from stdin
                limit=$(echo "$input" | jsonfilter -e '@.limit' 2>/dev/null || echo 100)
                offset=$(echo "$input" | jsonfilter -e '@.offset' 2>/dev/null || echo 0)
                networks "$limit" "$offset"
                ;;
            sessions)
                sessions
                ;;
            session_log)
                session_id=$(echo "$input" | jsonfilter -e '@.session_id' 2>/dev/null)
                limit=$(echo "$input" | jsonfilter -e '@.limit' 2>/dev/null || echo 100)
                offset=$(echo "$input" | jsonfilter -e '@.offset' 2>/dev/null || echo 0)
                filter=$(echo "$input" | jsonfilter -e '@.filter' 2>/dev/null || echo all)
                session_log "$session_id" "$limit" "$offset" "$filter"
                ;;
            gps_status)
                gps_status
                ;;
            start)
                do_start
                ;;
            stop)
                do_stop
                ;;
            export)
                session_id=$(echo "$input" | jsonfilter -e '@.session_id' 2>/dev/null)
                do_export "$session_id"
                ;;
            radios)
                radios
                ;;
            version)
                echo "{\"version\": \"$VERSION\"}"
                ;;
            delete_sessions)
                # Parse session_ids array from JSON input
                echo "$input" | jsonfilter -e '@.session_ids[*]' 2>/dev/null | do_delete_sessions
                ;;
            *)
                echo '{"error": "Unknown method"}'
                ;;
        esac
        ;;
    *)
        echo '{"error": "Unknown command"}'
        ;;
esac
