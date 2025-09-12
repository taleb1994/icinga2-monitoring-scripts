#!/bin/bash
export LC_ALL=C # Ensures consistent locale settings for command output parsing

# CPU Usage Monitoring Script
# This script monitors system CPU usage and alerts based on configurable thresholds.
# It provides current CPU statistics and lists the top CPU-consuming processes,
# with enhanced recognition for Java applications.

set -euo pipefail # Exit on error, undefined vars, pipe failures

# >>> Exit Codes for Monitoring Systems (e.g., Icinga/Nagios) <<< #
# These constants define the standard exit statuses as individual readonly variables.
readonly STATE_OK=0
readonly STATE_WARNING=1
readonly STATE_CRITICAL=2
readonly STATE_UNKNOWN=3


# >>> Script Metadata <<< #
# The name of the script, used for help messages.
readonly PROGRAM_NAME=$(basename "$0")

# Temporary file for storing process data (cleaned up on exit)
readonly TEMP_FILE="/tmp/icinga2data_cpu_usage_$(date +%s%N).tmp"

# Java packages to try installing if jps is not found
readonly JAVA_PACKAGE_21="openjdk-21-jdk-headless"
readonly JAVA_PACKAGE_17="openjdk-17-jdk-headless"


# >>> Global Data Structures <<< #
# Global variables for thresholds and current CPU usage.
declare -g WARNING_THRESHOLD=""
declare -g CRITICAL_THRESHOLD=""
declare -g CPU_CURRENT=0

# Bash indexed array to store details of top CPU-consuming processes.
# Each element will be a string in the format "ProcessName:CPUUsage:MemoryUsage".
declare -ga TOP_PROCESSES


# >>> Core Functions <<< #

# Function: print_help
# Displays the script's usage instructions and argument details.
# Exits with STATE_UNKNOWN after printing help.
print_help() {
    cat << EOF
===
This plugin checks the status of your System CPU and sets critical and warning thresholds.

Usage:
    ${PROGRAM_NAME} -w <warning_threshold> -c <critical_threshold>

Arguments:
    -w          CPU usage percentage to trigger a WARNING state (0-100).
    -c          CPU usage percentage to trigger a CRITICAL state (0-100).

Options:
    -h          Show this help message.

Examples:
    ${PROGRAM_NAME} -w 80 -c 90
    ${PROGRAM_NAME} -h

Notice: The critical threshold (-c) must be numerically higher than the warning threshold (-w).
This is because the script monitors the PERCENTAGE OF *USED* CPU:
A higher used percentage indicates a more severe state.
===
EOF
    exit $STATE_UNKNOWN
}

# Function: validate_threshold_inputs
# Validates the provided warning and critical thresholds.
# Parameters:
#   $1: Warning threshold percentage.
#   $2: Critical threshold percentage.
# Exits with STATE_UNKNOWN if validation fails.
validate_threshold_inputs() {
    local warning_threshold=$1
    local critical_threshold=$2

    # Check if arguments are numbers
    if ! [[ "$warning_threshold" =~ ^[0-9]+$ ]] || ! [[ "$critical_threshold" =~ ^[0-9]+$ ]]; then
        echo -e "+++\nError: Warning and critical thresholds must be positive integers." >&2
        print_help
    fi

    # Check if arguments are within a valid range (0 to 100 percent)
    if (( warning_threshold < 0 || warning_threshold > 100 )) || \
       (( critical_threshold < 0 || critical_threshold > 100 )); then
        echo -e "+++\nError: Thresholds must be numbers between 0 and 100 (inclusive)." >&2
        print_help
    fi

    # Check if the critical threshold is higher than the warning threshold.
    # This is crucial because the script checks for *used* CPU percentage.
    # A higher threshold for critical means a more severe condition (e.g., >=90% is critical)
    # compared to a lower threshold for warning (e.g., >=80% is warning).
    if (( critical_threshold <= warning_threshold )); then
        echo -e "+++\nError: Critical threshold (${critical_threshold}%) must be numerically higher than warning threshold (${warning_threshold}%)." >&2
        print_help
    fi
}

# Function: cleanup
# Removes temporary files created by the script.
# This function is registered with 'trap' to run on script exit.
cleanup() {
    # Check if the temporary file exists before attempting to remove it.
    if [[ -f "$TEMP_FILE" ]]; then
        rm -f "$TEMP_FILE"
        # echo "Temporary file $TEMP_FILE removed." # For debugging
    fi
}

# Function: get_cpu_usage
# Calculates the current system CPU usage percentage over a 1-second interval.
# Populates the global CPU_CURRENT variable.
get_cpu_usage() {
    local cpu_line prev_total prev_idle total idle
    local total_diff idle_diff

    # Read initial CPU statistics from /proc/stat.
    # $2: user, $3: nice, $4: system, $5: idle, $6: iowait, $7: irq, $8: softirq.
    # Sum of all non-idle times (user, nice, system, iowait, irq, softirq)
    # Total CPU time = user + nice + system + idle + iowait + irq + softirq + steal
    # Idle time = idle + iowait
    cpu_line=$(head -n1 /proc/stat)
    prev_total=$(echo "$cpu_line" | awk '{print $2+$3+$4+$5+$6+$7+$8+$9}') # Sum of all CPU times including steal
    prev_idle=$(echo "$cpu_line" | awk '{print $5+$6}') # idle + iowait

    # Wait for 1 second to get a meaningful difference in CPU stats.
    sleep 1

    # Read CPU statistics again.
    cpu_line=$(head -n1 /proc/stat)
    total=$(echo "$cpu_line" | awk '{print $2+$3+$4+$5+$6+$7+$8+$9}')
    idle=$(echo "$cpu_line" | awk '{print $5+$6}')

    # Calculate the difference in total and idle CPU times.
    total_diff=$((total - prev_total))
    idle_diff=$((idle - prev_idle))

    # Calculate CPU usage percentage.
    # CPU usage = (total_diff - idle_diff) / total_diff * 100
    if [[ "$total_diff" -gt 0 ]]; then
        CPU_CURRENT=$(( (total_diff - idle_diff) * 100 / total_diff ))
    else
        # If no change in total CPU time, assume 0% usage.
        CPU_CURRENT=0
    fi

    # Ensure CPU_CURRENT is within a valid 0-100% range.
    if (( CPU_CURRENT < 0 )); then
        CPU_CURRENT=0
    elif (( CPU_CURRENT > 100 )); then
        CPU_CURRENT=100
    fi
}

# Function: ensure_jps_installed
# Checks if the 'jps' command is available. If not, attempts to install
# Java Development Kit packages (OpenJDK 21 then OpenJDK 17).
# Suppresses all APT output. Requires root privileges for installation (sudo).
ensure_jps_installed() {
    if command -v jps &> /dev/null; then
        return 0 # jps is already available
    fi

    # Try OpenJDK 21
    if apt search "$JAVA_PACKAGE_21" &> /dev/null; then
        DEBIAN_FRONTEND=noninteractive apt install -y "$JAVA_PACKAGE_21" &> /dev/null
        if [ $? -eq 0 ]; then
            echo "Successfully installed $JAVA_PACKAGE_21 for jps." >&2
            return 0
        fi
    fi

    # If OpenJDK 21 failed or was not found, try OpenJDK 17
    if apt search "$JAVA_PACKAGE_17" &> /dev/null; then
        DEBIAN_FRONTEND=noninteractive apt install -y "$JAVA_PACKAGE_17" &> /dev/null
        if [ $? -eq 0 ]; then
            echo "Successfully installed $JAVA_PACKAGE_17 for jps." >&2
            return 0
        fi
    fi

    echo "Warning: Could not install jps (neither $JAVA_PACKAGE_21 nor $JAVA_PACKAGE_17 found/installed). Java process names may be generic." >&2
    return 1 # jps could not be installed
}

# Function: get_top_processes
# Extracts the top 3 CPU-consuming processes using the 'ps' command.
# Populates the global TOP_PROCESSES array with formatted strings.
# For Java processes, attempts to provide more specific names (Kafka, JPS-based).
get_top_processes() {
    # Use 'ps aux' to get detailed process information, sort by CPU usage, and take the top 3.
    # '--no-headers' removes the header line.
    # The output format is critical: PID, %CPU, %MEM, Command
    if ! ps aux --no-headers --sort=-%cpu | head -3 | awk '
        {
            # Print PID, %CPU, %MEM, and then the rest of the command string
            printf "%s %s %s ", $2, $3, $4;
            for (i=11; i<=NF; i++) printf "%s%s", $i, (i==NF?"":" ");
            printf "\n";
        }
    ' > "$TEMP_FILE"; then
        echo "Error: Failed to retrieve process information with 'ps' command." >&2
        exit "${STATE_UNKNOWN}"
    fi

    # Clear any previous content in the global TOP_PROCESSES array.
    TOP_PROCESSES=()

    local jps_available=false
    if ensure_jps_installed; then
        jps_available=true
    fi

    # Read each line from the temporary file and parse into desired components.
    while IFS=' ' read -r pid cpu_usage memory_usage process_command_raw; do
        # Remove leading/trailing whitespace from raw command and ensure the command is without arguments.
        process_command_raw=$(echo "$process_command_raw" | awk '{print $1}' | xargs)
        local display_name=$(basename "$process_command_raw" 2>/dev/null || echo "$process_command_raw") # Default to original command name

        # Check if it's a Java process (case-insensitive check for "java" in command line)
        if [[ "$process_command_raw" =~ [Jj]ava ]]; then
            local proc_uid=$(ps -o uid= -p "$pid" | xargs 2>/dev/null)

            # Check for Kafka specific user and config file
            if [[ "$proc_uid" == "1001" ]]; then
                # Search the full command line for Kafka server properties
                if ps -p "$pid" -o command= | grep -q "kafka/config/server.properties"; then
                    display_name="kafka"
                fi
            fi

            # If not identified as Kafka, or for other users, try jps if available
            if [[ "$display_name" == "$(basename "$process_command_raw" 2>/dev/null || echo "$process_command_raw")" && "$jps_available" == true ]]; then
                # Use jps -l to get the full class name or JAR path
                local jps_output=$(jps -l | grep "^${pid} " | sed -E 's/^[0-9]+ //; s/^(de\.heuboe\.|de\.)//; s/\.Main$//' 2>/dev/null)
                if [[ -n "$jps_output" ]]; then
                    display_name="$jps_output"
                fi
            fi
        fi

        # Only add to array if we have valid data.
        if [[ -n "$display_name" && -n "$cpu_usage" && -n "$memory_usage" ]]; then
            # Store as "name:cpu:mem" string for easier handling later.
            TOP_PROCESSES+=("$display_name:$cpu_usage:$memory_usage")
        fi
    done < "$TEMP_FILE"

    # Ensure we have exactly 3 entries for consistent output (pad with "N/A" if less).
    while [[ ${#TOP_PROCESSES[@]} -lt 3 ]]; do
        TOP_PROCESSES+=("N/A:0.0:0.0")
    done

    # If by any chance more than 3 processes are read (e.g., if head -3 failed and more lines appeared),
    # trim the array to exactly 3.
    if [[ ${#TOP_PROCESSES[@]} -gt 3 ]]; then
        TOP_PROCESSES=("${TOP_PROCESSES[@]:0:3}")
    fi
}

# Function: display_process_table
# Formats and displays the top 3 CPU-consuming processes in a table.
display_process_table() {
    echo "" # Add an empty line for better readability
    echo "Top 3 CPU demanding workloads:"
    echo "================================================="
    printf "%-25s %8s %8s\n" "Process" "CPU%" "Memory%" # Added % symbols to header
    echo "================================================="

    for process_info in "${TOP_PROCESSES[@]}"; do
        # Split the "name:cpu:mem" string into individual variables.
        IFS=':' read -r name cpu mem <<< "$process_info"
        # Truncate long process names for consistent display.
        if [[ ${#name} -gt 24 ]]; then
            name="${name:0:21}..."
        fi
        printf "%-25s %7s%% %7s%%\n" "$name" "$cpu" "$mem" # Added % symbols to values
    done

    echo "================================================="
}

# Function: generate_status_report
# Generates and prints the final monitoring report.
# Parameters:
#   $1: The status level (e.g., "OK", "WARNING", "CRITICAL").
#   $2: The message prefix (e.g., "Current", "!WARNING! -->").
# Exits the script with the corresponding exit code.
generate_status_report() {
    local status_level="$1"
    local message_prefix="$2"

    echo "" # Add an empty line for better readability
    echo "${message_prefix} CPU-Usage: ${CPU_CURRENT}%"
    display_process_table
    echo "" # Add an empty line at the end of the report

    # Use a case statement to exit with the correct predefined constant.
    case "$status_level" in
        "OK")       exit "$STATE_OK" ;;
        "WARNING")  exit "$STATE_WARNING" ;;
        "CRITICAL") exit "$STATE_CRITICAL" ;;
        "UNKNOWN")  exit "$STATE_UNKNOWN" ;; # Fallback for unexpected status_level
        *)          exit "$STATE_UNKNOWN" ;; # Default if status_level is entirely unhandled
    esac
}

# Function: evaluate_cpu_status
# Compares current CPU usage against defined thresholds and calls
# generate_status_report with the appropriate status and message.
evaluate_cpu_status() {
    if (( CPU_CURRENT >= CRITICAL_THRESHOLD )); then
        generate_status_report "CRITICAL" "!CRITICAL! -->"
    elif (( CPU_CURRENT >= WARNING_THRESHOLD )); then
        generate_status_report "WARNING" "!WARNING! -->"
    else
        generate_status_report "OK" "Current"
    fi
}


# >>> Main Execution Block <<< #
# This function encapsulates the primary logic flow of the script.
main() {
    # Set up cleanup trap to remove temporary files on script exit.
    trap cleanup EXIT

    # Initialize threshold variables.
    local warning_threshold_arg=""
    local critical_threshold_arg=""

    # Parse command line arguments using getopts.
    # The leading colon in ":w:c:h" enables silent error handling for unknown options
    # and missing arguments, allowing custom error messages.
    while getopts ":w:c:h" opt; do
        case $opt in
            w) # Warning threshold option
                warning_threshold_arg=$OPTARG
                ;;
            c) # Critical threshold option
                critical_threshold_arg=$OPTARG
                ;;
            h) # Help option
                print_help
                ;;
            \?) # Handle invalid options (e.g., -x)
                echo -e "+++\nERROR: Invalid option -- '${OPTARG}'" >&2
                print_help
                ;;
            :) # Handle missing arguments for an option (e.g., -w without a value)
                echo -e "+++\nERROR: Missing argument for option -- '${OPTARG}'" >&2
                print_help
                ;;
            *) # Catch-all for any other unexpected options
                echo -e "+++\nERROR: Unimplemented option: -'${OPTARG}'" >&2
                print_help
                ;;
        esac
    done
    # Shift positional parameters so that "$@" now refers to remaining arguments (if any).
    shift $((OPTIND-1))

    # Ensure both warning and critical thresholds have been provided.
    if [[ -z "$warning_threshold_arg" || -z "$critical_threshold_arg" ]]; then
        echo -e "+++\nERROR: Both warning (-w) and critical (-c) thresholds must be provided." >&2
        print_help
    fi

    # Assign parsed arguments to global configuration variables.
    WARNING_THRESHOLD="$warning_threshold_arg"
    CRITICAL_THRESHOLD="$critical_threshold_arg"

    # Validate the input thresholds (numbers, range, and relationship).
    validate_threshold_inputs "$WARNING_THRESHOLD" "$CRITICAL_THRESHOLD"

    # Gather system information.
    get_cpu_usage
    get_top_processes

    # Evaluate and report status based on CPU usage and thresholds.
    evaluate_cpu_status
}

# Execute main function only if the script is run directly (not sourced).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
