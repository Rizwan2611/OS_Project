#!/bin/bash

# Configuration
SCRIPTS_DIR="$(dirname "$0")"
DATA_DIR="$(dirname "$0")/../data"
REPORTS_DIR="$(dirname "$0")/../reports"
SUMMARY_FILE="${DATA_DIR}/patient_summary.csv"
SCHED_REPORT="${REPORTS_DIR}/scheduling_report_$(date +%Y%m%d).txt"

mkdir -p "$REPORTS_DIR"

# Ensure patient summary exists by invoking analyze_vitals.sh if needed
ensure_summary() {
    if [[ ! -f "$SUMMARY_FILE" ]]; then
        echo "Patient summary not found. Running analyze_vitals.sh to generate it..."
        bash "$SCRIPTS_DIR/analyze_vitals.sh" -a -i "$DATA_DIR/patient_vitals.csv" -o "$REPORTS_DIR/daily_summary_$(date +%Y%m%d).txt"
    fi
}

# Compute a numeric priority from vitals status and severity
# Lower number = higher priority
compute_priority() {
    local status="$1" avg_hr="$2" avg_sys="$3" avg_dia="$4" avg_spo2="$5"

    # Base on status
    if [[ "$status" == "WARNING" ]]; then
        local p=2
        # Escalate priority for very dangerous vitals
        if (( $(echo "$avg_spo2 < 92" | bc -l) )); then
            p=1
        elif (( $(echo "$avg_sys > 160 || $avg_dia > 100 || $avg_hr > 130" | bc -l) )); then
            p=1
        fi
        echo "$p"
    else
        echo 3
    fi
}

# Function to simulate First-Come-First-Serve (FCFS) scheduling on patients
fcfs_schedule() {
    echo -e "\n=== FCFS Scheduling (Patients in order of first arrival) ===" | tee -a "$SCHED_REPORT"
    echo "Patient ID | Name           | Burst (records) | Start | End | Turnaround | Waiting" | tee -a "$SCHED_REPORT"
    echo "-----------+----------------+-----------------+-------+-----+------------+--------" | tee -a "$SCHED_REPORT"

    local current_time=0

    tail -n +2 "$SUMMARY_FILE" | sort -t, -k10 | while IFS=, read -r pid name count avg_hr avg_sys avg_dia avg_temp avg_spo2 status first_ts; do
        local burst_time=$count
        local start_time=$current_time
        local end_time=$((start_time + burst_time))
        local turnaround_time=$((end_time - 0))
        local waiting_time=$((start_time - 0))

        printf "%11s | %-14s | %15s | %5s | %3s | %10s | %6s\n" \
               "$pid" "$name" "$burst_time" "$start_time" "$end_time" "$turnaround_time" "$waiting_time" | tee -a "$SCHED_REPORT"

        current_time=$end_time
    done
}

# Function to simulate Shortest Job First (SJF) scheduling on patients
sjf_schedule() {
    echo -e "\n=== SJF Scheduling (Patients with fewest records first) ===" | tee -a "$SCHED_REPORT"
    echo "Patient ID | Name           | Burst (records) | Start | End | Turnaround | Waiting" | tee -a "$SCHED_REPORT"
    echo "-----------+----------------+-----------------+-------+-----+------------+--------" | tee -a "$SCHED_REPORT"

    local current_time=0

    # Sort by entry_count (3rd field)
    tail -n +2 "$SUMMARY_FILE" | sort -t, -k3n | while IFS=, read -r pid name count avg_hr avg_sys avg_dia avg_temp avg_spo2 status first_ts; do
        local burst_time=$count
        local start_time=$current_time
        local end_time=$((start_time + burst_time))
        local turnaround_time=$((end_time - 0))
        local waiting_time=$((start_time - 0))

        printf "%11s | %-14s | %15s | %5s | %3s | %10s | %6s\n" \
               "$pid" "$name" "$burst_time" "$start_time" "$end_time" "$turnaround_time" "$waiting_time" | tee -a "$SCHED_REPORT"

        current_time=$end_time
    done
}

# Function to simulate Priority Scheduling on patients
priority_schedule() {
    echo -e "\n=== Priority Scheduling (Urgent patients first) ===" | tee -a "$SCHED_REPORT"
    echo "Patient ID | Name           | Priority | Burst (records) | Start | End | Turnaround | Waiting" | tee -a "$SCHED_REPORT"
    echo "-----------+----------------+----------+-----------------+-------+-----+------------+--------" | tee -a "$SCHED_REPORT"

    local current_time=0

    # Build a temporary file with computed priorities
    local tmp="${DATA_DIR}/priority_patients.tmp"
    tail -n +2 "$SUMMARY_FILE" | while IFS=, read -r pid name count avg_hr avg_sys avg_dia avg_temp avg_spo2 status first_ts; do
        prio=$(compute_priority "$status" "$avg_hr" "$avg_sys" "$avg_dia" "$avg_spo2")
        echo "$prio,$pid,$name,$count,$avg_hr,$avg_sys,$avg_dia,$avg_temp,$avg_spo2,$status,$first_ts" >> "$tmp"
    done

    sort -t, -k1n,1 -k4n "$tmp" | while IFS=, read -r prio pid name count avg_hr avg_sys avg_dia avg_temp avg_spo2 status first_ts; do
        local burst_time=$count
        local start_time=$current_time
        local end_time=$((start_time + burst_time))
        local turnaround_time=$((end_time - 0))
        local waiting_time=$((start_time - 0))

        printf "%11s | %-14s | %8s | %15s | %5s | %3s | %10s | %6s\n" \
               "$pid" "$name" "$prio" "$burst_time" "$start_time" "$end_time" "$turnaround_time" "$waiting_time" | tee -a "$SCHED_REPORT"

        current_time=$end_time
    done

    rm -f "$tmp"
}

# Function to simulate Round Robin scheduling on patients
round_robin_schedule() {
    echo -e "\n=== Round Robin Scheduling (Time Quantum = 2 records) ===" | tee -a "$SCHED_REPORT"
    echo "Patient ID | Name           | Remaining | Time Executed | Completion | Turnaround | Waiting" | tee -a "$SCHED_REPORT"
    echo "-----------+----------------+-----------+--------------+-----------+-----------+--------" | tee -a "$SCHED_REPORT"

    local time_quantum=2
    local current_time=0

    # Load patients into arrays (avoid subshell so arrays persist)
    declare -a P_IDS P_NAMES P_REMAINING
    local idx=0

    # Skip header manually, then read remaining lines
    local first_line=1
    while IFS=, read -r pid name count avg_hr avg_sys avg_dia avg_temp avg_spo2 status first_ts; do
        if (( first_line )); then
            first_line=0
            continue
        fi
        P_IDS[$idx]="$pid"
        P_NAMES[$idx]="$name"
        P_REMAINING[$idx]=$count
        idx=$((idx + 1))
    done < "$SUMMARY_FILE"

    local total=${#P_IDS[@]}
    local completed=0
    declare -a completion_time turnaround waiting

    while (( completed < total )); do
        for ((i=0; i<total; i++)); do
            local rem=${P_REMAINING[$i]:-0}
            if (( rem <= 0 )); then
                continue
            fi

            local exec=$time_quantum
            if (( rem < time_quantum )); then
                exec=$rem
            fi

            # All other active patients wait during this slice
            for ((j=0; j<total; j++)); do
                if (( j == i )); then
                    continue
                fi
                if (( ${P_REMAINING[$j]:-0} > 0 )); then
                    waiting[$j]=$(( ${waiting[$j]:-0} + exec ))
                fi
            done

            current_time=$((current_time + exec))
            rem=$((rem - exec))
            P_REMAINING[$i]=$rem

            if (( rem == 0 )); then
                completion_time[$i]=$current_time
                turnaround[$i]=$current_time
                completed=$((completed + 1))

                printf "%11s | %-14s | %9s | %12s | %9s | %9s | %6s\n" \
                       "${P_IDS[$i]}" "${P_NAMES[$i]}" "0" "$exec" "${completion_time[$i]}" "${turnaround[$i]}" "${waiting[$i]:-0}" | tee -a "$SCHED_REPORT"
            fi
        done
    done
}

# Main execution
main() {
    chmod +x "${SCRIPTS_DIR}/analyze_vitals.sh"

    ensure_summary

    echo "HEALTH MONITORING SCHEDULING REPORT - $(date +%Y-%m-%d)" > "$SCHED_REPORT"
    echo "====================================================" >> "$SCHED_REPORT"

    fcfs_schedule
    sjf_schedule
    priority_schedule
    round_robin_schedule

    echo -e "\nAll scheduling simulations completed. See: $SCHED_REPORT"
}

main
