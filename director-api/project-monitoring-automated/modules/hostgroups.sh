#!/bin/bash

# =============================================================================
# Icinga Director Configuration Script - Host Groups Module
# =============================================================================

# This file is meant to be sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# Dependencies:
# - lib/utils.sh (for create_icinga_object, log_*)
# - projects/PROJECT_NAME_configs.sh (for PROJECT_HOSTGROUP, K8S_*_HOSTGROUP variables)

# Create all project-defined and k8s-related host groups.
setup_all_hostgroups() {
    log_info "Setting up host groups..."
    local overall_status=0

    # Define hostgroups as an array of "name:description"
    local hostgroups_to_create=(
        "$PROJECT_HOSTGROUP:Project host group ($PROJECT_HOSTGROUP)"
        "$K8S_MASTERS_HOSTGROUP:K8s masters host group ($K8S_MASTERS_HOSTGROUP)"
        "$K8S_WORKERS_HOSTGROUP:K8s workers host group ($K8S_WORKERS_HOSTGROUP)"
        "$K8S_SINGLE_NODE_HOSTGROUP:K8s single-node host group ($K8S_SINGLE_NODE_HOSTGROUP)"
    )

    for hostgroup_entry in "${hostgroups_to_create[@]}"; do
        local hostgroup_name="${hostgroup_entry%:*}" # Use the part till ':' as name
        local description="${hostgroup_entry#*:}" # Use the part after ':' as description

        log_info "Processing host group: $hostgroup_name"
        local json_data='{
            "object_name": "'"$hostgroup_name"'",
            "object_type": "object",
            "display_name": "'"$hostgroup_name"'"
        }'

        create_icinga_object "hostgroup" "$json_data" "$hostgroup_name" "$description"
        if [[ $? -ne 0 ]]; then
            log_warn "Failed to ensure host group '$hostgroup_name' was created."
            overall_status=1
        fi
    done
    
    if [[ $overall_status -eq 0 ]]; then
        log_success "All host groups processed successfully."
    else
        log_warn "Some host groups may not have been processed successfully."
    fi
    return $overall_status
}