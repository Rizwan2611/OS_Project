#!/bin/bash

# Configuration
DATA_DIR="$(dirname "$0")/../data"
REPORTS_DIR="$(dirname "$0")/../reports"
INPUT_FILE="${DATA_DIR}/patient_vitals.csv"
OUTPUT_FILE="${REPORTS_DIR}/daily_summary_$(date +%Y%m%d).txt"
SUMMARY_FILE="${DATA_DIR}/patient_summary.csv"

# Create reports directory if it doesn't exist
mkdir -p "$REPORTS_DIR"

# Function to display help
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -i, --input    Specify input CSV file (default: $INPUT_FILE)"
    echo "  -o, --output   Specify output file (default: $OUTPUT_FILE)"
    echo "  -a, --analyze  Run analysis on the data"
    echo "  -c, --check    Check for duplicates and missing data"
}

# Function to check for duplicates and missing data
check_data_quality() {
    echo "Checking data quality..."
    echo "======================="
    
    # Check for missing values
    echo -e "\nMissing values per column:"
    awk -F, 'NR==1 {split($0, headers, ","); next} 
    {
        for(i=1; i<=NF; i++) {
            if ($i == "") {
                missing[headers[i]]++
            }
        }
    } 
    END {
        for (h in headers) {
            printf "%s: %d missing\n", headers[h], missing[headers[h]]
        }
    }' "$INPUT_FILE"
    
    # Check for duplicate entries
    echo -e "\nDuplicate entries (by patient_id and timestamp):"
    awk -F, 'NR>1 {print $1 "," $7}' "$INPUT_FILE" | sort | uniq -d | while read -r dup; do
        echo "Duplicate found: $dup"
    done
}

# Function to analyze vitals and generate report
analyze_vitals() {
    echo "Analyzing patient vitals..."
    echo "=========================="

    # Create header for the human-readable report
    echo "DAILY PATIENT VITALS SUMMARY - $(date +%Y-%m-%d)" > "$OUTPUT_FILE"
    echo "==========================================" >> "$OUTPUT_FILE"

    echo -e "\nAVERAGE VITALS BY PATIENT" >> "$OUTPUT_FILE"
    echo "-----------------------" >> "$OUTPUT_FILE"

    # Generate both the text report and a machine-readable patient summary CSV
    awk -F, -v summary_file="$SUMMARY_FILE" '
    NR==1 {
        # Input CSV header row
        next;
    }
    {
        if (NF < 2) next;

        patient_id = $1;
        name       = $2;
        hr         = $3;
        sys        = $4;
        dia        = $5;
        t          = $6;
        oxy        = $7;
        ts         = $8;

        heart_rate[patient_id] += hr;
        systolic[patient_id]   += sys;
        diastolic[patient_id]  += dia;
        temp[patient_id]       += t;
        oxygen[patient_id]     += oxy;
        count[patient_id]++;

        if (!(patient_id in names)) {
            names[patient_id] = name;
        }

        # Track first arrival timestamp per patient (ISO timestamps compare lexicographically)
        if (!(patient_id in first_ts) || ts < first_ts[patient_id]) {
            first_ts[patient_id] = ts;
        }
    }
    END {
        # Header for human-readable table
        printf("%-10s %-20s %-12s %-12s %-10s %-10s %-10s\n",
               "Patient ID", "Name", "Avg HR", "Avg BP", "Avg Temp", "Avg SpO2", "Status");
        print "--------------------------------------------------------------------------------";

        # Header for machine-readable summary (used by schedulers)
        print "patient_id,patient_name,entry_count,avg_hr,avg_sys,avg_dia,avg_temp,avg_spo2,status,first_timestamp" > summary_file;

        for (id in count) {
            avg_hr  = heart_rate[id] / count[id];
            avg_sys = systolic[id]   / count[id];
            avg_dia = diastolic[id]  / count[id];
            avg_t   = temp[id]       / count[id];
            avg_oxy = oxygen[id]     / count[id];

            status = "NORMAL";
            if (avg_hr > 100 || avg_hr < 60 || avg_sys > 140 || avg_sys < 90 ||
                avg_dia > 90 || avg_dia < 60 || avg_oxy < 95) {
                status = "WARNING";
            }

            bp = sprintf("%d/%d", avg_sys, avg_dia);

            # Print row in human-readable report
            printf("%-10s %-20s %-12.1f %-12s %-10.1f %-10.1f %-10s\n",
                   id, names[id], avg_hr, bp, avg_t, avg_oxy, status);

            # Print row to summary CSV
            printf("%s,%s,%d,%.2f,%.2f,%.2f,%.2f,%.2f,%s,%s\n",
                   id, names[id], count[id], avg_hr, avg_sys, avg_dia, avg_t, avg_oxy, status, first_ts[id]) >> summary_file;
        }
    }' "$INPUT_FILE" >> "$OUTPUT_FILE"

    # Add high-risk patient section based on WARNING status in the summary
    echo -e "\nHIGH-RISK PATIENTS" >> "$OUTPUT_FILE"
    echo "------------------" >> "$OUTPUT_FILE"
    if grep -q "WARNING" "$SUMMARY_FILE" 2>/dev/null; then
        awk -F, 'NR>1 && $9 == "WARNING" {
            printf "Patient ID: %s, Name: %s, Avg HR: %s, Avg BP: %s/%s, Avg Temp: %s, Avg SpO2: %s (Status: %s)\n",
                   $1, $2, $4, $5, $6, $7, $8, $9;
        }' "$SUMMARY_FILE" >> "$OUTPUT_FILE"
    else
        echo "No high-risk patients detected." >> "$OUTPUT_FILE"
    fi

    echo -e "\nAnalysis complete. Report generated at: $OUTPUT_FILE"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -i|--input)
            INPUT_FILE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -a|--analyze)
            analyze_vitals
            exit 0
            ;;
        -c|--check)
            check_data_quality
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# If no arguments provided, show help
if [[ $# -eq 0 ]]; then
    show_help
fi
