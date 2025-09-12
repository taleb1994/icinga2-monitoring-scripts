#!/bin/bash
export LC_ALL=C # Ensures consistent locale settings for command output parsing

# RAM Usage Monitoring Script
# This script monitors system RAM usage and alerts based on configurable thresholds.
# It provides detailed RAM statistics and lists the top memory-consuming processes.


# >>> Exit Codes for Monitoring Systems (e.g., Icinga/Nagios) <<< #
# These constants define the standard exit statuses.
readonly STATE_OK=0        # Everything is good.
readonly STATE_WARNING=1   # A condition that might require attention.
readonly STATE_CRITICAL=2  # A serious problem requiring immediate attention.
readonly STATE_UNKNOWN=3   # The state could not be determined.


# >>> Script Metadata <<< #
# The name of the script, used for help messages.
readonly PROGRAM_NAME=$(basename "$0")

# Java packages to try installing if jps is not found
readonly JAVA_PACKAGE_21="openjdk-21-jdk-headless"
readonly JAVA_PACKAGE_17="openjdk-17-jdk-headless"


# >>> Global Data Structures <<< #
# Bash associative array to store all RAM statistics.
# Using -g option to ensure it's global if declared within a function
# (though here it's globally declared for clarity).
declare -gA RAM_INFO

# Bash indexed array to store details of top memory-consuming processes.
# Each element will be a string: "Process-Name CPU% MEM% MEM-Reserved"
declare -ga TOP_PROCESSES


# >>> Core Functions <<< #

# Function: print_help
# Displays the script's usage instructions and argument details.
# Exits with STATE_UNKNOWN after printing help.
print_help() {
    cat << EOF
===
This plugin checks the status of your System RAM and sets critical and warning thresholds.

Usage:
    ${PROGRAM_NAME} -w <warning_threshold> -c <critical_threshold>

Arguments:
    -w          Percentage of RAM usage to trigger a WARNING state (e.g., 85).
    -c          Percentage of RAM usage to trigger a CRITICAL state (e.g., 90).

Options:
    -h          Show this help message.

Examples:
    ${PROGRAM_NAME} -w 85 -c 90
    ${PROGRAM_NAME} -h

Notice: The critical threshold (-c) must be numerically higher than the warning threshold (-w).
This is because the script monitors the PERCENTAGE OF *USED* RAM:
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
    # Changed range to 0-100 for usage percentage
    if (( warning_threshold < 0 || warning_threshold > 100 )) || \
       (( critical_threshold < 0 || critical_threshold > 100 )); then
        echo -e "+++\nError: Thresholds must be numbers between 0 and 100 (inclusive)." >&2
        print_help
    fi

    # Check if the critical threshold is higher than the warning threshold.
    # This is crucial because the script checks for *used* RAM percentage.
    # A higher threshold for critical means a more severe condition (e.g., >=90% is critical)
    # compared to a lower threshold for warning (e.g., >=85% is warning).
    if (( critical_threshold <= warning_threshold )); then
        echo -e "+++\nError: Critical threshold (${critical_threshold}%) must be numerically higher than warning threshold (${warning_threshold}%)." >&2
        print_help
    fi
}

# Function: format_size
# Converts a size in MiB to a more human-readable format (MiB, GiB, TiB).
# Parameter:
#   $1: Size in MiB (megabytes).
# Returns: Formatted size string (e.g., "10.5G", "512M").
format_size() {
    local size_mib=$1
    if (( size_mib >= 1048576 )); then # If size is >= 1 TiB (1024 * 1024 MiB)
        # Use awk for floating-point division and formatting
        echo "$(awk "BEGIN {printf \"%.1f\", $size_mib/1024/1024}")T"
    elif (( size_mib >= 1024 )); then # If size is >= 1 GiB (1024 MiB)
        echo "$(awk "BEGIN {printf \"%.1f\", $size_mib/1024}")G"
    else # Otherwise, display in MiB
        echo "${size_mib}M"
    fi
}

# Function: get_ram_usage_stats
# Gathers system RAM and swap usage statistics using 'free -m'.
# Populates the global RAM_INFO associative array with raw and formatted values.
get_ram_usage_stats() {
    local mem_info_output
    # Get memory information in megabytes
    mem_info_output=$(free -m)

    # Use awk to parse the 'free -m' output.
    # Extract total, used, free, shared, buffer/cache, and available RAM for 'Mem' line (NR==2)
    # Extract total, used, and free for 'Swap' line (NR==3)
    read -r \
        RAM_INFO[total_mb] RAM_INFO[used_mb] RAM_INFO[free_mb] \
        RAM_INFO[shared_mb] RAM_INFO[buffers_cache_mb] RAM_INFO[available_mb] \
        RAM_INFO[swap_total_mb] RAM_INFO[swap_used_mb] RAM_INFO[swap_free_mb] \
        <<< $(echo "$mem_info_output" | awk '
            NR==2 {
                # Memory line: total, used, free, shared, buff/cache, available
                printf "%d %d %d %d %d %d ", $2, $3, $4, $5, $6, $7;
            }
            NR==3 {
                # Swap line: total, used, free
                printf "%d %d %d", $2, $3, $4;
            }
        ')

    # Calculate percentages for RAM usage (based on total memory).
    # Using awk for precise floating-point arithmetic and rounding to nearest whole number.
    RAM_INFO[used_perc]=$(awk "BEGIN {printf \"%.0f\", (${RAM_INFO[used_mb]} * 100.0) / ${RAM_INFO[total_mb]}}")
    RAM_INFO[available_perc]=$(awk "BEGIN {printf \"%.0f\", (${RAM_INFO[available_mb]} * 100.0) / ${RAM_INFO[total_mb]}}")
    RAM_INFO[buffers_cache_perc]=$(awk "BEGIN {printf \"%.0f\", (${RAM_INFO[buffers_cache_mb]} * 100.0) / ${RAM_INFO[total_mb]}}")

    # Calculate swap used percentage, handling cases with no swap memory.
    if (( ${RAM_INFO[swap_total_mb]} > 0 )); then
        RAM_INFO[swap_used_perc]=$(awk "BEGIN {printf \"%.0f\", (${RAM_INFO[swap_used_mb]} * 100.0) / ${RAM_INFO[swap_total_mb]}}")
    else
        RAM_INFO[swap_used_perc]=0
    fi

    # Format raw MiB values into human-readable strings for display.
    RAM_INFO[total_display]=$(format_size "${RAM_INFO[total_mb]}")
    RAM_INFO[used_display]=$(format_size "${RAM_INFO[used_mb]}")
    RAM_INFO[free_display]=$(format_size "${RAM_INFO[free_mb]}")
    RAM_INFO[available_display]=$(format_size "${RAM_INFO[available_mb]}")
    RAM_INFO[buffers_cache_display]=$(format_size "${RAM_INFO[buffers_cache_mb]}")
    RAM_INFO[swap_total_display]=$(format_size "${RAM_INFO[swap_total_mb]}")
    RAM_INFO[swap_used_display]=$(format_size "${RAM_INFO[swap_used_mb]}")
    RAM_INFO[swap_free_display]=$(format_size "${RAM_INFO[swap_free_mb]}")
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


# Function: get_top_memory_processes
# Identifies the top 3 processes consuming the most RAM.
# Populates the global TOP_PROCESSES array with formatted strings.
# For Java processes, attempts to provide more specific names (Kafka, JPS-based).
get_top_memory_processes() {
    local temp_file # Declare a local variable for the temporary file path.
    # Create a temporary file to store the 'top' command output.
    temp_file=$(mktemp)
    # Ensure the temporary file is removed automatically when the script exits,
    # even if an error occurs.
    trap 'rm -f "$temp_file"' EXIT

    local jps_available=false
    if ensure_jps_installed; then
        jps_available=true
    fi

    # Execute 'top' in batch mode (-b), one iteration (-n1), sorted by memory usage (-o %MEM).
    # Use LC_ALL=C for consistent output parsing.
    # Pipe the output to awk to process and format relevant lines.
    LC_ALL=C top -b -n1 -o %MEM | awk '
        NR>7 {  # Skip header lines (usually first 7 lines) from 'top' output.
            # $1 is PID, $12 is the command.
            pid = $1;
            cmd_raw = $12;
            for (i=13; i<=NF; i++) cmd_raw = cmd_raw " " $i;

            # Extract Resident Size (RES) from $6 and convert it to MiB.
            mem_raw = $6;
            mem_mb; # Implicitly local to this block in awk.
            if (mem_raw ~ /g$/) { # If unit is Gigabytes
                mem_mb = substr(mem_raw, 1, length(mem_raw)-1) * 1024;
            } else if (mem_raw ~ /m$/) { # If unit is Megabytes
                mem_mb = substr(mem_raw, 1, length(mem_raw)-1);
            } else if (mem_raw ~ /t$/) { # If unit is Terabytes
                mem_mb = substr(mem_raw, 1, length(mem_raw)-1) * 1024 * 1024;
            } else { # Assume Kilobytes if no unit specified
                mem_mb = mem_raw / 1024;
            }

            # Print raw data to a temporary file, including PID, for further processing in Bash
            printf "%s|%s|%s|%s|%.2f\n", pid, cmd_raw, $9, $10, mem_mb;
        }
    ' | head -3 > "$temp_file" # Take only the top 3 lines (processes).

    # Clear any previous content in the global TOP_PROCESSES array.
    TOP_PROCESSES=()

    # Read each line from the temporary file into the TOP_PROCESSES array and enhance names.
    while IFS='|' read -r pid cmd_name cpu_perc mem_perc mem_reserved_mib; do
        # Initialize display_name with the full raw command initially
        local display_name="$cmd_name"

        # Check if it's a Java process (case-insensitive check for "java" in command line)
        if [[ "$cmd_name" =~ [Jj]ava ]]; then
            local proc_uid=$(ps -o uid= -p "$pid" | xargs 2>/dev/null)

            # Check for Kafka based on the specific path in ps -aux output
            if [[ "$proc_uid" == "1001" ]]; then
                # Search the captured full command line for Kafka server properties
                if ps -aux | grep "$pid" | grep -q "kafka/config/server.properties"; then
                    display_name="kafka"
                fi
            fi

            # If not identified as Kafka or specific for user 1001, try jps if available
            # Only attempt jps if display_name is still the original raw command,
            # meaning no specific identification has been made yet.
            if [[ "$display_name" == "$cmd_name" && "$jps_available" == true ]]; then
                # Use jps -l to get the full class name or JAR path
                local jps_output=$(jps -l | grep "^${pid} " | sed -E 's/^[0-9]+ //; s/^(de\.heuboe\.|de\.)//; s/\.Main$//' 2>/dev/null)
                if [[ -n "$jps_output" ]]; then
                    display_name="$jps_output"
                fi
            fi
        fi

        # Final step: If display_name is still the full command (no specific identification),
        # then apply basename to get the executable name.
        if [[ "$display_name" == "$cmd_name" ]]; then
            display_name=$(basename "$display_name" 2>/dev/null || echo "$display_name")
        fi

        # Add the processed process line to the global array.
        TOP_PROCESSES+=("$(printf "%-30s %10s %10s %15.2f" "$display_name" "$cpu_perc" "$mem_perc" "$mem_reserved_mib")")
    done < "$temp_file"

    # Ensure we have exactly 3 entries for consistent output (pad with empty if needed)
    while [[ ${#TOP_PROCESSES[@]} -lt 3 ]]; do
        TOP_PROCESSES+=("N/A:0.0:0.0") # Use N/A for empty processes
    done

    # Limit to exactly 3 entries
    if [[ ${#TOP_PROCESSES[@]} -gt 3 ]]; then
        TOP_PROCESSES=("${TOP_PROCESSES[@]:0:3}")
    fi
}

# Function: print_monitoring_report
# Displays the final RAM usage report and process list.
# Parameters:
#   $1: The exit status (STATE_OK, STATE_WARNING, STATE_CRITICAL).
#   $2: The primary status message to display.
# Exits with the provided status code.
print_monitoring_report() {
    local status_level="$1" # Renamed status to status_level for consistency with CPU script
    local message_prefix="$2" # Renamed message to message_prefix

    echo -e "${message_prefix}\n----"
    echo -e "RAM Total:\t\t${RAM_INFO[total_display]}"
    echo -e "RAM Used:\t\t${RAM_INFO[used_display]} (${RAM_INFO[used_perc]}%)"
    echo -e "Buffer/Cache:\t\t${RAM_INFO[buffers_cache_display]} (${RAM_INFO[buffers_cache_perc]}%)"
    echo -e "RAM Available:\t\t${RAM_INFO[available_display]} (${RAM_INFO[available_perc]}%)"
    echo -e "RAM Free:\t\t${RAM_INFO[free_display]}"
    echo -e "----"
    echo -e "Swap Total:\t\t${RAM_INFO[swap_total_display]}"
    echo -e "Swap Used:\t\t${RAM_INFO[swap_used_display]} (${RAM_INFO[swap_used_perc]}%)"
    echo -e "Swap Free:\t\t${RAM_INFO[swap_free_display]}"
    echo -e "----"

    echo -e "\nTop 3 RAM consuming processes:"
    echo -e "--------------------------------------------------------------------------"
    # Print table header for processes - PID is NOT shown here as requested
    printf "%-30s %10s %10s %20s\n\n" "Process-Name" "CPU%" "MEM%" "MEM-Reserved"

    # Iterate through the TOP_PROCESSES array and print each process's details.
    for process_line in "${TOP_PROCESSES[@]}"; do
        # The line is already formatted without PID, so just print it.
        echo "$process_line MiB" # Add "MiB" suffix here as it's not in the formatted string
    done

    echo -e "--------------------------------------------------------------------------"

    # Use a case statement to exit with the correct predefined constant.
    case "$status_level" in
        "OK")       exit "$STATE_OK" ;;
        "WARNING")  exit "$STATE_WARNING" ;;
        "CRITICAL") exit "$STATE_CRITICAL" ;;
        "UNKNOWN")  exit "$STATE_UNKNOWN" ;; # Fallback for unexpected status_level
        *)          exit "$STATE_UNKNOWN" ;; # Default if status_level is entirely unhandled
    esac
}


# >>> Main Execution Block <<< #
# This function encapsulates the primary logic flow of the script.
main() {
    # Set up cleanup trap to remove temporary files on script exit.
    trap 'rm -f "$TEMP_FILE"' EXIT # Ensure temp file cleanup for this script

    # Initialize threshold variables.
    local warning_threshold=""
    local critical_threshold=""

    # Parse command line arguments using getopts.
    # The colon before 'c' and 'w' indicates that they require an argument.
    # The leading colon in ":c:w:h" suppresses default error messages for better custom handling.
    while getopts ":c:w:h" opt; do
        case $opt in
            c) # Critical threshold option
                critical_threshold=$OPTARG
                ;;
            w) # Warning threshold option
                warning_threshold=$OPTARG
                ;;
            h) # Help option
                print_help
                ;;
            \?) # Handle invalid options (e.g., -x)
                echo -e "+++\nERROR: Invalid option -- '${OPTARG}'" >&2
                print_help
                ;;
            :) # Handle missing arguments for an option (e.g., -c without a value)
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
    if [[ -z "$warning_threshold" || -z "$critical_threshold" ]]; then
        echo -e "+++\nERROR: Both warning (-w) and critical (-c) thresholds must be provided." >&2
        print_help
    fi

    # Validate the input thresholds (numbers, range, and relationship).
    validate_threshold_inputs "$warning_threshold" "$critical_threshold"

    # Gather system RAM and swap usage statistics.
    get_ram_usage_stats

    # Identify and list the top 3 memory-consuming processes.
    get_top_memory_processes

    # Determine the system status based on RAM USAGE and defined thresholds.
    # Changed from available_perc to used_perc and reversed comparison operators.
    if (( ${RAM_INFO[used_perc]} >= critical_threshold )); then
        print_monitoring_report "CRITICAL" "CRITICAL: Used Memory is ${RAM_INFO[used_perc]}% (>=${critical_threshold}%)."
    elif (( ${RAM_INFO[used_perc]} >= warning_threshold )); then
        print_monitoring_report "WARNING" "WARNING: Used Memory is ${RAM_INFO[used_perc]}% (>=${warning_threshold}%)."
    else
        print_monitoring_report "OK" "OK: Current RAM Usage: ${RAM_INFO[used_perc]}%."
    fi
}

# Call the main function to start script execution.
main "$@"