#!/bin/bash

# =============================================================================
# Icinga Director Configuration Script - Nodes (Agents) Module
# =============================================================================

# This file is meant to be sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# Dependencies:
# - lib/utils.sh (for create_icinga_object, log_*)
# - projects/PROJECT_NAME_configs.sh (for PROJECT_HOSTGROUP, PROJECT_NODES_ADDRESS, PROJECT_NODES_DISPLAY_NAME arrays)
# - config/all_hosts_config.sh (for K8S_*_HOSTGROUP, GENERIC_AGENT_TEMPLATE, NODE_SDB_* arrays)

# Determine the hostgroups for a given node address.
# Arguments:
#   $1 (address): The FQDN or IP address of the node.
# Output:
#   Prints a space-separated list of hostgroup names.
# Returns:
#   0 if hostgroups determined, 1 if node type is unknown.
_get_node_hostgroups_by_address() {
    local address="$1"
    local hostgroups_list=() # Use an array to build the list

    # Always add the main project hostgroup
    hostgroups_list+=("$PROJECT_HOSTGROUP")

    # Determine additional hostgroups based on address patterns
    case "$address" in
        *master*)
            hostgroups_list+=("$K8S_MASTERS_HOSTGROUP")
            ;;
        *worker*)
            hostgroups_list+=("$K8S_WORKERS_HOSTGROUP")
            ;;
        *k3s*|*single-node*)
            hostgroups_list+=("$K8S_SINGLE_NODE_HOSTGROUP")
            ;;
        *)
            log_warn "Node address '$address' does not match known patterns for k8s type. Assigning only to project hostgroup."
            ;;
    esac

    if [[ ${#hostgroups_list[@]} -gt 0 ]]; then
        echo "${hostgroups_list[@]}" # Output space-separated list
        return 0
    else
        # This case should ideally not be reached if PROJECT_HOSTGROUP is always added.
        log_error "No hostgroups determined for node '$address'."
        return 1
    fi
}

# Determine the SDB status note for a given node address.
# Arguments:
#   $1 (address): The FQDN or IP address of the node.
# Output:
#   Prints the SDB status string (e.g., "node has sdb: true").
# Returns:
#   0 if status determined, 1 if node type is unknown for SDB status.
_get_node_sdb_status_note() {
    local address="$1"

    case "$address" in
        *master*)
            echo "$NODE_SDB_FALSE_NOTES"
            ;;
        *worker*|*k3s*|*single-node*) # Workers and single-nodes are assumed to have sdb for this project
            echo "$NODE_SDB_TRUE_NOTES"
            ;;
        *)
            log_warn "Cannot determine SDB status for node '$address' based on its name. Defaulting to no SDB note."
            echo "$NODE_SDB_FALSE_NOTES"
            return 1 # Indicate that a specific status was not determined
            ;;
    esac
    return 0
}

# Create/update all project agents (nodes) based on configuration.
setup_project_agents() {
    log_info "Setting up project agents (nodes)..."
    local overall_status=0
    local total_nodes=${#PROJECT_NODES_ADDRESS[@]}

    if [[ $total_nodes -eq 0 ]]; then
        log_info "No project nodes are defined. Skipping agent creation."
        return 0
    fi

    for i in "${!PROJECT_NODES_ADDRESS[@]}"; do
        local address="${PROJECT_NODES_ADDRESS[$i]}"
        local display_name="${PROJECT_NODES_DISPLAY_NAME[$i]}"

        log_info "Processing Node: $address (Display: $display_name)"

        local hostgroups_string
        if ! hostgroups_string=$(_get_node_hostgroups_by_address "$address"); then
            log_warn "Could not determine k8s-specific hostgroups for '$address'. It will only be in '$PROJECT_HOSTGROUP'."
            # Continue with at least the project hostgroup
            hostgroups_string="$PROJECT_HOSTGROUP"
        fi

        local sdb_status_note
        sdb_status_note=$(_get_node_sdb_status_note "$address")
        # If _get_node_sdb_status_note returned 1, sdb_status_note might be empty or a default.

        # Build hostgroups JSON array string from the space-separated string
        local hostgroups_json_array="[]"
        if [[ -n "$hostgroups_string" ]]; then
            local temp_json_array
            # Read space-separated string into an array
            local -a hostgroups_array
            read -r -a hostgroups_array <<< "$hostgroups_string"
            # Create comma-separated quoted list
            temp_json_array=$(printf '"%s",' "${hostgroups_array[@]}")
            hostgroups_json_array="[${temp_json_array%,}]" # Remove trailing comma and wrap
        fi
        
        log_info "Node '$address' will be assigned to hostgroups: $hostgroups_json_array"
        if [[ -n "$sdb_status_note" ]]; then
            log_info "Node '$address' SDB status note: '$sdb_status_note'"
        fi

        local json_data='{
            "object_name": "'"$address"'",
            "object_type": "object",
            "address": "'"$address"'",
            "groups": '"$hostgroups_json_array"',
            "zone": "'"$address"'",
            "notes": "'"$sdb_status_note"'",
            "imports": ["'"$GENERIC_AGENT_TEMPLATE"'"],
            "display_name": "'"$display_name"'"
        }'

        if create_icinga_object "host" "$json_data" "$address" "Node $address"; then
            log_info "Node '$address' processed successfully."
        else
            log_warn "Failed to process node '$address'."
            overall_status=1
        fi
    done

    if [[ $overall_status -eq 0 ]]; then
        log_success "All project agents processed successfully."
    else
        log_warn "Some project agents may not have been processed correctly."
    fi
    return $overall_status
}