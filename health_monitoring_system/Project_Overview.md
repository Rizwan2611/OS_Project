# Health Monitoring System - Project Overview

## Introduction
This project simulates a health monitoring system that processes patient vital signs. It includes scripts to analyze patient data, check for data quality issues (duplicates, missing values), and simulate various CPU scheduling algorithms (FCFS, SJF, Priority, Round Robin) using patient records as tasks.

## Project Structure
- **scripts/**: Contains the executable shell scripts.
  - `analyze_vitals.sh`: Analyzes `patient_vitals.csv`, calculates averages, and identifies high-risk patients.
  - `schedule_analysis.sh`: Uses the summary data to simulate process scheduling algorithms.
- **data/**: Contains input and output CSV files.
  - `patient_vitals.csv`: Raw input data.
  - `patient_summary.csv`: Processed summary data used for scheduling simulation.
- **reports/**: Contains generated text reports and screenshots.

## Execution
The system works by first analyzing the raw vitals to generate a summary, which is then fed into the scheduling simulator.

### Scheduling Report Output
The following report demonstrates the system's output after running the scheduling simulations on sample patient data. The algorithms simulated are:
1. **FCFS (First-Come, First-Served)**: Patients processed in order of arrival.
2. **SJF (Shortest Job First)**: Patients with fewer records processed first.
3. **Priority Scheduling**: Patients with critical conditions (WARNING status) are given higher priority.
4. **Round Robin**: Time-sliced execution for fair processing.

### Output Screenshot
![Scheduling Report Output](reports/scheduling_report.png)

## Detailed Analysis
The `analyze_vitals.sh` script generates a comprehensive daily summary, flagging patients with abnormal vitals (e.g., high blood pressure or low oxygen saturation) as "WARNING". These "WARNING" status patients effectively become high-priority tasks in the Priority Scheduling simulation.
