#!/bin/sh
# bench.sh - Benchmark controller for WigleWRT v2
# Runs automated trials comparing scanning strategies

# Use absolute paths for device deployment
SCRIPT_DIR="/usr/share/wiglewrt"
. /usr/share/wiglewrt/lib/common.sh

# Default trial duration: 30 minutes
TRIAL_DURATION="${TRIAL_DURATION:-1800}"
METRICS_INTERVAL=10  # Collect metrics every 10 seconds

# All available strategies
ALL_STRATEGIES="fixed_100 fixed_500 fixed_1000 adaptive rapid monitor"

BENCH_DIR="$DATA_DIR/bench"
RESULTS_DIR=""
TRIAL_NETWORKS=""
TRIAL_TIMELINE=""
TRIAL_METRICS=""

usage() {
    cat << EOF
WigleWRT Benchmark Tool

Usage: $0 <command> [options]

Commands:
    run <strategy|all>    Run benchmark trial(s)
    status                Show current trial status
    report [trial_dir]    Generate comparison report
    list                  List completed trials
    compare <s1> <s2>     Compare two strategies

Strategies:
    fixed_100     Fixed 100ms dwell
    fixed_500     Fixed 500ms dwell
    fixed_1000    Fixed 1000ms dwell
    adaptive      Adaptive dwell (100-500ms)
    rapid         Rapid scan (50ms, common channels only)
    monitor       Passive monitor mode

Options:
    TRIAL_DURATION=<sec>  Trial duration (default: 1800 = 30min)

Examples:
    $0 run fixed_500                        # Run single 30-min trial
    TRIAL_DURATION=300 $0 run adaptive      # Run 5-min trial
    $0 run all                              # Run all strategies (~3 hours)
    $0 report                               # Show latest results
EOF
}

# Initialize trial directory
init_trial() {
    local strategy="$1"
    local ts=$(date +%Y%m%d_%H%M%S)

    RESULTS_DIR="$BENCH_DIR/${ts}_${strategy}"
    mkdir -p "$RESULTS_DIR"

    TRIAL_NETWORKS="$RESULTS_DIR/networks.tsv"
    TRIAL_TIMELINE="$RESULTS_DIR/timeline.tsv"
    TRIAL_METRICS="$RESULTS_DIR/metrics.tsv"

    # Initialize files with headers
    echo "bssid	ssid	channel	signal	encryption	first_seen	last_seen	times_seen	lat	lon	alt	acc" > "$TRIAL_NETWORKS"
    echo "timestamp	event	bssid	ssid	channel	signal" > "$TRIAL_TIMELINE"
    echo "timestamp	networks	new_networks	cpu_pct	mem_kb" > "$TRIAL_METRICS"

    # Save trial config
    cat > "$RESULTS_DIR/config.json" << EOF
{
    "strategy": "$strategy",
    "duration": $TRIAL_DURATION,
    "start_time": "$(date -Iseconds)",
    "interfaces": "$(find_interfaces | tr '\n' ' ')"
}
EOF

    log info "Trial initialized: $RESULTS_DIR"
}

# Find wireless interfaces
find_interfaces() {
    for phy in $(get_phys); do
        iface=$(get_interface "$phy")
        [ -n "$iface" ] && echo "$iface"
    done
}

# Collect system metrics
collect_metrics() {
    local ts=$(now)
    local networks=$(wc -l < "$TRIAL_NETWORKS" 2>/dev/null | tr -d ' ')
    networks=$((networks - 1))  # Subtract header
    [ "$networks" -lt 0 ] && networks=0

    # Get new networks count (from timeline)
    local new=$(grep -c "^" "$TRIAL_TIMELINE" 2>/dev/null || echo 1)
    new=$((new - 1))  # Subtract header

    # CPU usage (from /proc/stat)
    local cpu=$(awk '/^cpu / {print int(($2+$4)*100/($2+$4+$5))}' /proc/stat 2>/dev/null || echo 0)

    # Memory usage
    local mem=$(awk '/MemFree/ {print int($2)}' /proc/meminfo 2>/dev/null || echo 0)

    echo "$ts	$networks	$new	$cpu	$mem" >> "$TRIAL_METRICS"
}

# Run single trial
run_trial() {
    local strategy="$1"
    local dwell="500"

    # Parse strategy name for dwell time
    case "$strategy" in
        fixed_100) dwell=100; strategy_name="fixed" ;;
        fixed_500) dwell=500; strategy_name="fixed" ;;
        fixed_1000) dwell=1000; strategy_name="fixed" ;;
        adaptive) strategy_name="adaptive" ;;
        rapid) dwell=50; strategy_name="rapid" ;;
        monitor) strategy_name="monitor" ;;
        *)
            log error "Unknown strategy: $strategy"
            return 1
            ;;
    esac

    log info "Starting trial: $strategy for ${TRIAL_DURATION}s"

    init_trial "$strategy"

    # Clear main networks file for this trial
    # We'll use a separate copy for benchmarking
    local orig_networks="$NETWORKS_FILE"
    export NETWORKS_FILE="$TRIAL_NETWORKS"

    # Start scanning
    init_runtime
    echo "$strategy" > /tmp/wiglewrt_strategy

    # Start GPS
    /usr/bin/wiglewrt-gps start &
    GPS_PID=$!
    sleep 2

    # Start scanners (db.sh not needed - scanners write directly)
    local scanner_pids=""
    for iface in $(find_interfaces); do
        log info "Starting scanner on $iface with $strategy_name dwell=$dwell"
        DWELL_MS=$dwell /usr/bin/wiglewrt-scan "$iface" "$strategy_name" "$dwell" run &
        scanner_pids="$scanner_pids $!"
    done

    # Save PIDs
    echo "$GPS_PID $scanner_pids" > "$WIGLEWRT_TMP/bench_pids"

    # Run for duration, collecting metrics
    local start_time=$(now)
    local end_time=$((start_time + TRIAL_DURATION))
    local last_metrics=0

    log info "Trial running until $(date -d @$end_time '+%H:%M:%S' 2>/dev/null || date -r $end_time '+%H:%M:%S' 2>/dev/null || echo $end_time)"

    while [ $(now) -lt $end_time ]; do
        local current=$(now)

        # Collect metrics every METRICS_INTERVAL seconds
        if [ $((current - last_metrics)) -ge $METRICS_INTERVAL ]; then
            collect_metrics
            last_metrics=$current

            # Progress update
            local elapsed=$((current - start_time))
            local remaining=$((end_time - current))
            local networks=$(wc -l < "$TRIAL_NETWORKS" 2>/dev/null | tr -d ' ')
            networks=$((networks - 1))
            log info "Progress: ${elapsed}s elapsed, ${remaining}s remaining, $networks networks"
        fi

        sleep 1
    done

    # Stop all processes
    log info "Trial complete, stopping processes..."
    for pid in $(cat "$WIGLEWRT_TMP/bench_pids" 2>/dev/null); do
        kill "$pid" 2>/dev/null
    done
    /usr/bin/wiglewrt-gps stop 2>/dev/null

    # Final metrics collection
    collect_metrics

    # Generate summary
    generate_summary "$strategy"

    # Restore original networks file
    export NETWORKS_FILE="$orig_networks"

    log info "Trial $strategy complete. Results in $RESULTS_DIR"
}

# Generate trial summary
generate_summary() {
    local strategy="$1"

    local total_networks=$(wc -l < "$TRIAL_NETWORKS" 2>/dev/null | tr -d ' ')
    total_networks=$((total_networks - 1))

    local total_events=$(wc -l < "$TRIAL_TIMELINE" 2>/dev/null | tr -d ' ')
    total_events=$((total_events - 1))

    # Calculate rates
    local rate=$(echo "scale=2; $total_networks * 60 / $TRIAL_DURATION" | bc 2>/dev/null || echo "0")

    # Get CPU/memory stats
    local avg_cpu=$(awk -F'\t' 'NR>1 {sum+=$4; n++} END {print int(sum/n)}' "$TRIAL_METRICS" 2>/dev/null || echo "0")
    local avg_mem=$(awk -F'\t' 'NR>1 {sum+=$5; n++} END {print int(sum/n)}' "$TRIAL_METRICS" 2>/dev/null || echo "0")

    cat > "$RESULTS_DIR/summary.json" << EOF
{
    "strategy": "$strategy",
    "duration_sec": $TRIAL_DURATION,
    "total_networks": $total_networks,
    "total_events": $total_events,
    "networks_per_minute": $rate,
    "avg_cpu_pct": $avg_cpu,
    "avg_mem_kb": $avg_mem,
    "end_time": "$(date -Iseconds)"
}
EOF

    log info "Summary: $total_networks networks, ${rate}/min, CPU: ${avg_cpu}%"
}

# Run all strategies
run_all() {
    log info "Running all strategies (this will take ~3 hours)"

    for strategy in $ALL_STRATEGIES; do
        log info "=== Starting trial: $strategy ==="
        run_trial "$strategy"

        # Cool down between trials
        log info "Cooling down for 30 seconds..."
        sleep 30
    done

    log info "All trials complete"
    generate_comparison_report
}

# Generate comparison report
generate_comparison_report() {
    local report_file="$BENCH_DIR/comparison_$(date +%Y%m%d_%H%M%S).txt"

    echo "WigleWRT Benchmark Comparison Report" > "$report_file"
    echo "Generated: $(date)" >> "$report_file"
    echo "" >> "$report_file"
    echo "Strategy          Networks  Rate/min  CPU%  Mem(KB)" >> "$report_file"
    echo "-------------------------------------------------------" >> "$report_file"

    # Find all trial directories and extract summaries
    for dir in "$BENCH_DIR"/*/; do
        if [ -f "$dir/summary.json" ]; then
            awk '
            /strategy/ { gsub(/[",]/, ""); strategy = $2 }
            /total_networks/ { gsub(/[,]/, ""); networks = $2 }
            /networks_per_minute/ { gsub(/[,]/, ""); rate = $2 }
            /avg_cpu_pct/ { gsub(/[,]/, ""); cpu = $2 }
            /avg_mem_kb/ { gsub(/[,]/, ""); mem = $2 }
            END {
                printf "%-16s  %8s  %8s  %4s  %7s\n", strategy, networks, rate, cpu, mem
            }' "$dir/summary.json" >> "$report_file"
        fi
    done

    echo "" >> "$report_file"
    echo "Recommendation: Strategy with highest networks/min and acceptable CPU usage" >> "$report_file"

    cat "$report_file"
    log info "Report saved to $report_file"
}

# List completed trials
list_trials() {
    echo "Completed trials:"
    echo ""

    for dir in "$BENCH_DIR"/*/; do
        if [ -f "$dir/summary.json" ]; then
            local name=$(basename "$dir")
            local networks=$(grep "total_networks" "$dir/summary.json" | grep -o '[0-9]*')
            local rate=$(grep "networks_per_minute" "$dir/summary.json" | grep -o '[0-9.]*')
            echo "$name: $networks networks (${rate}/min)"
        fi
    done
}

# Show trial status
show_status() {
    if [ -f "$WIGLEWRT_TMP/bench_pids" ]; then
        echo "Benchmark trial in progress"
        echo "Strategy: $(cat /tmp/wiglewrt_strategy 2>/dev/null)"

        local networks=0
        if [ -f "$TRIAL_NETWORKS" ]; then
            networks=$(wc -l < "$TRIAL_NETWORKS" 2>/dev/null | tr -d ' ')
            networks=$((networks - 1))
        fi
        echo "Networks found: $networks"
    else
        echo "No benchmark running"
        list_trials
    fi
}

# Main
case "$1" in
    run)
        if [ "$2" = "all" ]; then
            run_all
        elif [ -n "$2" ]; then
            run_trial "$2"
        else
            echo "Usage: $0 run <strategy|all>"
            echo "Strategies: $ALL_STRATEGIES"
            exit 1
        fi
        ;;
    status)
        show_status
        ;;
    report)
        if [ -n "$2" ] && [ -d "$2" ]; then
            cat "$2/summary.json"
        else
            generate_comparison_report
        fi
        ;;
    list)
        list_trials
        ;;
    compare)
        if [ -n "$2" ] && [ -n "$3" ]; then
            echo "Comparing $2 vs $3..."
            # Find latest trials for each strategy
            for strategy in "$2" "$3"; do
                trial=$(ls -d "$BENCH_DIR"/*_${strategy}/ 2>/dev/null | tail -1)
                if [ -d "$trial" ]; then
                    echo ""
                    echo "=== $strategy ==="
                    cat "$trial/summary.json"
                else
                    echo "No trial found for $strategy"
                fi
            done
        else
            echo "Usage: $0 compare <strategy1> <strategy2>"
            exit 1
        fi
        ;;
    --help|-h|"")
        usage
        ;;
    *)
        echo "Unknown command: $1"
        usage
        exit 1
        ;;
esac
