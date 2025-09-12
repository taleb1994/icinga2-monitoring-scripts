#!/bin/bash
#
# Kubernetes Cluster Monitoring Script
#

export LC_ALL=C # Consistent locale settings for command output parsing

set -euo pipefail # Exit on error, undefined vars, pipe failures

# >>> Exit Codes for Icinga/Nagios <<< #
readonly STATE_OK=0
readonly STATE_WARNING=1
readonly STATE_CRITICAL=2
readonly STATE_UNKNOWN=3

# >>> Script Metadata <<< #
readonly PROGRAM_NAME=$(basename "$0")

# Converts Kubernetes memory units (Ki, Mi, Gi) to GiB for consistent reporting.
to_gib() {
    local mem_val=$1
    local num_val=${mem_val//[!0-9]/}
    local unit=${mem_val//[0-9]/}

    case "$unit" in
        Ki) awk "BEGIN {printf \"%.2f\", $num_val / 1024 / 1024}" ;;
        Mi) awk "BEGIN {printf \"%.2f\", $num_val / 1024}" ;;
        Gi) awk "BEGIN {printf \"%.2f\", $num_val}" ;;
        *) echo "0.00" ;; # Default case for unexpected units
    esac
}

# Displays the script's usage instructions.
print_help() {
    cat << EOF
===
Kubernetes Cluster Health Check Plugin

This plugin performs a comprehensive health check of a Kubernetes cluster.
It checks node health, pod statuses, and resource utilization.

Usage:
    ${PROGRAM_NAME}

This script takes no arguments. It automatically discovers and checks the cluster
it is run against, provided kubectl is configured correctly.

Options:
    -h, --help      Show this help message.
===
EOF
    exit $STATE_UNKNOWN
}

# Finds and deletes all pods in the "Completed" state across all namespaces.
delete_completed_pods() {
    echo -e "\nINFO: Cleaning up 'Completed' status pods..."
    # Get namespace and name of completed pods using jsonpath
    completed_pods=$(kubectl get pods --all-namespaces -o jsonpath='{range .items[?(@.status.phase=="Succeeded")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}')

    if [[ -n "$completed_pods" ]]; then
        echo "$completed_pods" | while read -r namespace name; do
            if ! kubectl delete pod -n "$namespace" "$name" --ignore-not-found=true; then
                echo "WARNING: Failed to delete completed pod '$name' in namespace '$namespace'."
            else
                echo "INFO: Deleted completed pod '$name' in namespace '$namespace'."
            fi
        done
    else
        echo -e "\nINFO: No 'Completed' status pods found to delete."
    fi
    echo "-------------------------------------------------"
}

# Checks the status of all pods in the cluster.
check_pods() {
    echo -e "\nINFO: Checking status of all pods..."
    local final_exit_code=$STATE_OK
    local problem_pods=""

    # <namespace> <pod_name> <phase> <ready_status>
    all_pods_status=$(kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}{.status.phase}{" "}{range .status.conditions[?(@.type=="Ready")]}{.status}{end}{"\n"}{end}')

    while read -r namespace pod_name phase ready_status; do
        # A pod is problematic if its phase is not Running or Succeeded, OR if it's not Ready.
        if [[ "$phase" != "Running" && "$phase" != "Succeeded" ]] || [[ "$ready_status" != "True" ]]; then
            problem_pods+="${namespace} ${pod_name}\n"
        fi
    done <<< "$all_pods_status"

    problem_pods=$(echo -e "$problem_pods" | sed '/^$/d') # Clean up blank lines

    if [[ -z "$problem_pods" ]]; then
        echo "OK: All pods are running and ready."
        echo -e "\n--- Top 6 Pods by Memory Usage ---"
        kubectl top pods --all-namespaces --sort-by=memory | head -n 7
        echo "------------------------------------"
    else
        echo -e "\nCRITICAL: Found one or more pods with issues."
        final_exit_code=$STATE_CRITICAL
        while read -r namespace pod_name; do
            echo -e "\n=== PROBLEM POD: ${namespace}/${pod_name} ==="
            
            # Get detailed info
            pod_info=$(kubectl get pod -n "$namespace" "$pod_name" -o jsonpath='{.status.phase}|{.status.reason}|{.status.message}|{.spec.nodeName}|{.status.startTime}')
            IFS='|' read -r p_phase p_reason p_message p_node p_start_time <<< "$pod_info"

            # Get container statuses
            container_statuses=$(kubectl get pod -n "$namespace" "$pod_name" -o jsonpath='{range .status.containerStatuses[*]}Container: {.name}, Ready: {.ready}, Restarts: {.restartCount}, State: {.state.*.reason}{"\n"}{end}')

            printf "%-15s %s\n" "STATUS:" "${p_phase}"
            if [[ -n "$p_reason" ]]; then printf "%-15s %s\n" "REASON:" "${p_reason}"; fi
            if [[ -n "$p_message" ]]; then printf "%-15s %s\n" "MESSAGE:" "${p_message}"; fi
            printf "%-15s %s\n" "NODE:" "${p_node:-N/A}"
            printf "%-15s %s\n" "STARTED:" "${p_start_time:-N/A}"

            echo -e "\n--- Container Statuses ---"
            echo -e "${container_statuses:-No container statuses available.}"

            echo -e "\n--- Recent Events ---"
            events=$(kubectl get events -n "$namespace" --field-selector "involvedObject.name=$pod_name" --sort-by=.lastTimestamp | tail -n 5)
            if [[ -n "$events" ]]; then
                echo "$events"
            else
                echo "No recent events found for this pod."
            fi
            echo "================================================"
        done <<< "$problem_pods"
    fi

    # Check for high restart counts on running pods (without jq)
    echo -e "\nINFO: Checking for high restart counts on running pods..."
    # Get all running pods and their container restart counts
    # <namespace> <pod_name> <container_name> <restart_count> <last_restart_time>
    restarting_pods_data=$(kubectl get pods --all-namespaces -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{range .status.containerStatuses[?(@.restartCount > 10)]}{.name}{" "}{.restartCount}{" "}{.lastState.terminated.finishedAt}{"\n"}{end}{"---\n"}{end}')
    
    echo "$restarting_pods_data" | awk -v warn_code="$STATE_WARNING" -v final_code="$final_exit_code" '
    BEGIN { pod_ns=""; pod_name=""; problem_found=0 }
    /---/ { next }
    NF == 2 { pod_ns=$1; pod_name=$2; next }
    NF > 2 {
        container_name=$1;
        restart_count=$2;
        last_restart_time=$3;

        if (last_restart_time == "<no value>" || last_restart_time == "") {
            printf "WARNING: Pod '\''%s/%s'\'' (container: %s) has a high restart count (%d), but last restart time is unavailable.\n", pod_ns, pod_name, container_name, restart_count;
            if (final_code < warn_code) { final_code = warn_code; }
            problem_found=1;
            next;
        }

        # Convert timestamp to seconds for comparison
        cmd = "date -d \"" last_restart_time "\" +%s";
        cmd | getline last_restart_sec;
        close(cmd);

        cmd = "date +%s";
        cmd | getline current_time_sec;
        close(cmd);
        
        age_in_seconds = current_time_sec - last_restart_sec;
        two_days_in_seconds = 2 * 24 * 60 * 60;

        if (age_in_seconds < two_days_in_seconds) {
            printf "WARNING: Pod '\''%s/%s'\'' (container: %s) has a high restart count (%d) and the last restart was less than 2 days ago.\n", pod_ns, pod_name, container_name, restart_count;
            if (final_code < warn_code) { final_code = warn_code; }
            problem_found=1;
        }
    }
    END { if(problem_found==0){ print "INFO: No running pods with recent high restart counts found." } exit final_code }'
    
    local awk_exit_code=$?
    if (( awk_exit_code > final_exit_code )); then
        final_exit_code=$awk_exit_code
    fi

    return $final_exit_code
}

# Checks the status of all nodes in the cluster and displays a consolidated report.
check_nodes() {
    echo -e "\nINFO: Checking status of all cluster nodes..."
    local final_exit_code=$STATE_OK
    local problem_nodes=""

    # <name>|<ready_status>|<unschedulable>|<pressure_conditions>
    all_nodes_data=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.spec.unschedulable}{"|"}{range .status.conditions[?(@.type=="Ready")]}{.status}{end}{"|"}{range .status.conditions[?(@.status=="True")]}{.type}{" "}{end}{"\n"}{end}')

    while IFS='|' read -r node_name unschedulable ready_status pressure_conditions; do
        local has_problem=false
        if [[ "$unschedulable" == "true" ]] || [[ "$ready_status" != "True" ]] || [[ "$pressure_conditions" =~ (MemoryPressure|DiskPressure|PIDPressure) ]]; then
            problem_nodes+="${node_name}\n"
        fi
    done <<< "$all_nodes_data"

    problem_nodes=$(echo -e "$problem_nodes" | sed '/^$/d') # Clean up blank lines

    if [[ -z "$problem_nodes" ]]; then
        echo "OK: All nodes are ready and healthy."
        echo -e "\n--- Node Information & Resource Usage ---"
        
        # FIX: Adjusted printf widths to accommodate headers and prevent wrapping.
        printf "%-35s %-10s %-10s %-20s %-18s %-10s %-15s %-15s\n" "NODE" "STATUS" "TAINTS" "CPU ALLOC (Cores)" "MEM ALLOC (GiB)" "PODS" "CPU USE" "MEM USE (GiB)"
        
        # Get node data
        node_info_list=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.spec.taints}{"|"}{.status.capacity.pods}{"|"}{.status.allocatable.cpu}{"|"}{.status.allocatable.memory}{"|"}{range .status.conditions[?(@.type=="Ready")]}{.status}{end}{"\n"}{end}')
        node_metrics=$(kubectl top nodes --no-headers 2>/dev/null || echo "")

        echo "$node_info_list" | while IFS='|' read -r name taints pods cpu_alloc mem_alloc status; do
            taint_count=$(echo "$taints" | grep -c "key" || true)
            
            # Convert memory to GiB
            mem_alloc_gib=$(to_gib "$mem_alloc")

            # Get metrics for this node
            metrics_line=$(echo "$node_metrics" | grep "^$name\s" || echo "")
            cpu_use="N/A"
            mem_use_gib="N/A"
            if [[ -n "$metrics_line" ]]; then
                cpu_use=$(echo "$metrics_line" | awk '{print $2}')
                mem_use_val=$(echo "$metrics_line" | awk '{print $4}')
                mem_use_gib=$(to_gib "$mem_use_val")
            fi

            printf "%-35s %-10s %-10s %-20s %-18s %-10s %-15s %-15s\n" "$name" "$status" "$taint_count" "$cpu_alloc" "$mem_alloc_gib" "$pods" "$cpu_use" "$mem_use_gib"
        done
        if [[ -z "$node_metrics" ]]; then
            echo -e "\nINFO: Node metrics not available (metrics-server may not be installed)."
        fi
        echo "-----------------------------------------"
    else
        echo -e "\nCRITICAL: Found one or more nodes with issues."
        final_exit_code=$STATE_CRITICAL
        
        while read -r node_name; do
            [[ -z "$node_name" ]] && continue
            
            echo -e "\n=== Investigating Problem Node: $node_name ==="
            
            # Get node conditions and taints
            conditions=$(kubectl get node "$node_name" -o jsonpath='{range .status.conditions[*]}{.type}{": "}{.status}{" ("}{.reason}{") - "}{.message}{"\n"}{end}')
            taints=$(kubectl get node "$node_name" -o jsonpath='{"Taints: "}{.spec.taints}{"\n"}')
            unschedulable=$(kubectl get node "$node_name" -o jsonpath='{"Unschedulable: "}{.spec.unschedulable}{"\n"}')
            
            echo -e "\n--- Node Status & Conditions ---"
            kubectl get node "$node_name" -o wide
            echo ""
            echo -e "$conditions"
            echo -e "$unschedulable"
            echo -e "$taints"
            
            echo -e "\n--- Recent Node Events ---"
            events=$(kubectl get events --field-selector "involvedObject.kind=Node,involvedObject.name=$node_name" --sort-by=.lastTimestamp 2>/dev/null | tail -n 5)
            if [[ -n "$events" ]]; then
                echo "$events"
            else
                echo "Could not retrieve recent events for node $node_name"
            fi
            echo "=============================================="
        done <<< "$problem_nodes"
    fi
    
    return $final_exit_code
}

# >>> Main Execution Block <<< #
main() {
    if [[ $# -gt 0 ]]; then
        case $1 in
            -h|--help)
                print_help
                ;;
            *)
                echo "ERROR: Unknown argument: $1" >&2
                print_help
                ;;
        esac
    fi

    # Dependency checks
    if ! command -v kubectl &> /dev/null; then
        echo "CRITICAL: kubectl command not found. Please ensure it's installed and in your PATH."
        exit $STATE_CRITICAL
    fi
    if ! command -v awk &> /dev/null; then
        echo "CRITICAL: awk command not found. This script requires awk for data processing."
        exit $STATE_CRITICAL
    fi

    # Create a temporary file to store the detailed output
    local SCRIPT_OUTPUT
    SCRIPT_OUTPUT=$(mktemp)
    # Ensure the temp file is removed on script exit
    trap 'rm -f "$SCRIPT_OUTPUT"' EXIT

    local pod_status=0
    local node_status=0

    # '||' to catch the non-zero exit codes from check functions without letting 'set -e' terminate the script prematurely
    {
        echo "================================================="
        echo "Starting Kubernetes Cluster Health Check"
        echo "Timestamp: $(date)"
        echo "================================================="
        delete_completed_pods
        check_pods || pod_status=$?
        check_nodes || node_status=$?
    } > "$SCRIPT_OUTPUT" 2>&1

    # Determine the final exit code. Critical status takes precedence.
    local final_status=$STATE_OK
    if (( pod_status > final_status )); then final_status=$pod_status; fi
    if (( node_status > final_status )); then final_status=$node_status; fi

    # Print the final status message FIRST.
    echo -n "Final Status: "
    case "$final_status" in
        0) echo "OK - Cluster is healthy." ;;
        1) echo "WARNING - Cluster has warnings." ;;
        2) echo "CRITICAL - Cluster has critical issues." ;;
        *) echo "UNKNOWN" ;;
    esac
    echo -e "=================================================\n"
    
    # 2. Print the detailed output from the temp file.
    cat "$SCRIPT_OUTPUT"
    
    exit $final_status
}

# Execute main function only if the script is run directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi