#!/bin/sh
# db.sh - Database writer daemon for WigleWRT v2
# Reads events from pipe, deduplicates, writes to networks.tsv
# Single-writer pattern - no locks needed

SCRIPT_DIR="$(dirname "$0")"
. "$SCRIPT_DIR/../lib/common.sh"

# Metrics
TOTAL_EVENTS=0
NEW_NETWORKS=0
START_TIME=$(now)

log info "Starting database writer"

# Initialize networks file with header if empty
init_db() {
    if [ ! -f "$NETWORKS_FILE" ] || [ ! -s "$NETWORKS_FILE" ]; then
        mkdir -p "$(dirname "$NETWORKS_FILE")"
        echo "bssid	ssid	channel	signal	encryption	first_seen	last_seen	times_seen	lat	lon	alt	acc" > "$NETWORKS_FILE"
        log info "Initialized networks database"
    fi
}

# Process events from pipe
process_events() {
    # Load existing BSSIDs into memory (awk associative array)
    while read -r line; do
        [ -z "$line" ] && continue

        TOTAL_EVENTS=$((TOTAL_EVENTS + 1))

        # Parse event: TS BSSID SSID CH SIG ENC LAT LON ALT ACC IFACE
        ts=$(echo "$line" | cut -f1)
        bssid=$(echo "$line" | cut -f2)
        ssid=$(echo "$line" | cut -f3)
        channel=$(echo "$line" | cut -f4)
        signal=$(echo "$line" | cut -f5)
        enc=$(echo "$line" | cut -f6)
        lat=$(echo "$line" | cut -f7)
        lon=$(echo "$line" | cut -f8)
        alt=$(echo "$line" | cut -f9)
        acc=$(echo "$line" | cut -f10)

        # Skip invalid
        [ -z "$bssid" ] && continue

        # Check if network exists
        if grep -q "^$bssid	" "$NETWORKS_FILE" 2>/dev/null; then
            # Update existing: increment times_seen, update last_seen
            awk -F'\t' -v OFS='\t' -v b="$bssid" -v ts="$ts" -v sig="$signal" '
                $1 == b {
                    $7 = ts
                    $8 = $8 + 1
                    if (sig != "" && sig < $4) $4 = sig  # Keep strongest signal
                }
                { print }
            ' "$NETWORKS_FILE" > "$NETWORKS_FILE.tmp" && mv "$NETWORKS_FILE.tmp" "$NETWORKS_FILE"
        else
            # New network - append
            echo "$bssid	$ssid	$channel	$signal	$enc	$ts	$ts	1	$lat	$lon	$alt	$acc" >> "$NETWORKS_FILE"
            NEW_NETWORKS=$((NEW_NETWORKS + 1))

            # Signal LED for new network
            echo "new" > "$LED_PIPE" 2>/dev/null &

            log info "NEW: $ssid ($bssid) ch$channel ${signal}dBm"
        fi

        # Update status every 10 events
        if [ $((TOTAL_EVENTS % 10)) -eq 0 ]; then
            update_status
        fi

    done < "$EVENTS_PIPE"
}

# Alternative: more efficient awk-based processing
process_events_awk() {
    awk -F'\t' -v nf="$NETWORKS_FILE" -v lp="$LED_PIPE" '
    BEGIN {
        OFS = "\t"
        # Load existing networks
        while ((getline < nf) > 0) {
            if (NR == 1) continue  # Skip header
            seen[$1] = 1
            data[$1] = $0
        }
        close(nf)
        new_count = 0
    }
    {
        ts = $1; bssid = $2; ssid = $3; ch = $4; sig = $5; enc = $6
        lat = $7; lon = $8; alt = $9; acc = $10

        if (bssid == "") next

        if (seen[bssid]) {
            # Update existing
            split(data[bssid], f)
            f[7] = ts           # last_seen
            f[8] = f[8] + 1     # times_seen
            if (sig != "" && sig + 0 > f[4] + 0) f[4] = sig
            data[bssid] = f[1] OFS f[2] OFS f[3] OFS f[4] OFS f[5] OFS f[6] OFS f[7] OFS f[8] OFS f[9] OFS f[10] OFS f[11] OFS f[12]
        } else {
            # New network
            seen[bssid] = 1
            data[bssid] = bssid OFS ssid OFS ch OFS sig OFS enc OFS ts OFS ts OFS 1 OFS lat OFS lon OFS alt OFS acc
            new_count++
            print "NEW: " ssid " (" bssid ") ch" ch " " sig "dBm" > "/dev/stderr"
            # Signal LED (background)
            system("echo new > " lp " 2>/dev/null &")
        }
    }
    END {
        # Write all networks back
        print "bssid\tssid\tchannel\tsignal\tencryption\tfirst_seen\tlast_seen\ttimes_seen\tlat\tlon\talt\tacc" > nf
        for (b in data) {
            print data[b] > nf
        }
        close(nf)
        print "Processed " NR " events, " new_count " new networks" > "/dev/stderr"
    }
    ' < "$EVENTS_PIPE"
}

update_status() {
    local total=$(wc -l < "$NETWORKS_FILE" 2>/dev/null | tr -d ' ')
    total=$((total - 1))  # Subtract header
    [ "$total" -lt 0 ] && total=0

    local elapsed=$(($(now) - START_TIME))
    local rate="0"
    if [ "$elapsed" -gt 0 ]; then
        rate=$(echo "scale=1; $TOTAL_EVENTS / $elapsed" | bc 2>/dev/null || echo "0")
    fi

    write_status "true" "$total" "$rate/s" "$(cat /tmp/wiglewrt_strategy 2>/dev/null || echo unknown)"
}

# Main
case "$1" in
    start)
        init_db
        write_pid "$WIGLEWRT_TMP/db.pid"
        # Use simple processing for now, can switch to awk version if needed
        process_events
        ;;
    stop)
        if [ -f "$WIGLEWRT_TMP/db.pid" ]; then
            kill $(cat "$WIGLEWRT_TMP/db.pid") 2>/dev/null
            rm -f "$WIGLEWRT_TMP/db.pid"
        fi
        ;;
    status)
        if is_running "$WIGLEWRT_TMP/db.pid"; then
            echo "Database writer running"
            echo "Networks: $(wc -l < "$NETWORKS_FILE" 2>/dev/null)"
        else
            echo "Database writer not running"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|status}"
        exit 1
        ;;
esac
