#!/bin/bash

# =============================================================================
# Icinga Director Configuration Script - Services Module
# =============================================================================

# This file is meant to be sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# Dependencies:
# - lib/utils.sh (for create_icinga_object, log_*)
# - config/all_hosts_config.sh (for GENERIC_CHECK_DISK_TEMPLATE, NODE_SDB_*, CHECK_DISK_*)

# Create disk check services (apply rules).
# One for nodes with /dev/sdb (checks / and /dev/sdb1)
# One for nodes without /dev/sdb (checks only /)
setup_disk_check_services() {
    log_info "Setting up disk check services..."
    local overall_status=0

    # --- Service for nodes WITH SDB (e.g., workers) ---
    log_info "Setting up disk check service for nodes with SDB: $CHECK_DISK_SDA_SDB_SERVICE_NAME"
    
    local sda_sdb_json='{
        "object_name": "'"$CHECK_DISK_SDA_SDB_SERVICE_NAME"'",
        "object_type": "apply",
        "imports": ["'"$GENERIC_CHECK_DISK_TEMPLATE"'"],
        "assign_filter": "host.notes = \"'"$NODE_SDB_TRUE_NOTES"'\"",
        "vars": {
            "disk_partition": "/",
            "disk_partitions": "/dev/sdb1"
        }
    }'
    # If `check_disk` command expects an array for `disk_partitions`, then e.g. `["/dev/sdb1", "/dev/sdb2"]` is more robust.

    create_icinga_object "service" "$sda_sdb_json" "$CHECK_DISK_SDA_SDB_SERVICE_NAME" "Disk check service (Root & SDB)"

    if [[ $? -ne 0 ]]; then
        log_warn "Failed to set up disk check service for nodes with SDB."
        overall_status=1
    fi

    # --- Service for nodes WITHOUT SDB (e.g., masters) ---
    log_info "Setting up disk check service for nodes without SDB: $CHECK_DISK_SDA_SERVICE_NAME"
    
    local sda_only_json='{
        "object_name": "'"$CHECK_DISK_SDA_SERVICE_NAME"'",
        "object_type": "apply",
        "imports": ["'"$GENERIC_CHECK_DISK_TEMPLATE"'"],
        "assign_filter": "host.notes = \"'"$NODE_SDB_FALSE_NOTES"'\"",
        "vars": {
            "disk_partition": "/"
        }
    }'

    create_icinga_object "service" "$sda_only_json" "$CHECK_DISK_SDA_SERVICE_NAME" "Disk check service (Root only)"

    if [[ $? -ne 0 ]]; then
        log_warn "Failed to set up disk check service for nodes without SDB."
        overall_status=1
    fi

    if [[ $overall_status -eq 0 ]]; then
        log_success "Disk check services processed successfully."
    else
        log_warn "Some disk check services may not have been processed correctly."
    fi
    return $overall_status
}

# Dependencies:
# - lib/utils.sh (for create_icinga_object, log_*)
# - config/all_hosts_config.sh (for GENERIC_CHECK_MEMORY_TEMPLATE)

# Create memory check services (apply rules).
setup_memory_check_services() {
    log_info "Setting up memory check services..."
    
    local json_data='{
        "object_name": "'"$CHECK_MEMORY_SERVICE_NAME"'",
        "object_type": "apply",
        "imports": ["'"$GENERIC_CHECK_MEMORY_TEMPLATE"'"],
        "assign_filter": "host.groups = \"'"$K8S_MASTERS_HOSTGROUP"'\" || host.groups = \"'"$K8S_WORKERS_HOSTGROUP"'\" || host.groups = \"'"$K8S_SINGLE_NODE_HOSTGROUP"'\""
    }'

    create_icinga_object "service" "$json_data" "$CHECK_MEMORY_SERVICE_NAME" "Memory check service (RAM & SWAP)"

    if [[ $? -ne 0 ]]; then
        log_warn "Failed to set up memory check service for all hosts."
        return 1
    fi
}

# Dependencies:
# - lib/utils.sh (for create_icinga_object, log_*)
# - config/all_hosts_config.sh (for GENERIC_CHECK_CPU_TEMPLATE)

# Create cpu check services (apply rules).
setup_cpu_check_services() {
    log_info "Setting up cpu check services..."
    
    local json_data='{
        "object_name": "'"$CHECK_CPU_SERVICE_NAME"'",
        "object_type": "apply",
        "imports": ["'"$GENERIC_CHECK_CPU_TEMPLATE"'"],
        "assign_filter": "host.groups = \"'"$K8S_MASTERS_HOSTGROUP"'\" || host.groups = \"'"$K8S_WORKERS_HOSTGROUP"'\" || host.groups = \"'"$K8S_SINGLE_NODE_HOSTGROUP"'\""
    }'

    create_icinga_object "service" "$json_data" "$CHECK_CPU_SERVICE_NAME" "CPU check service (ps & jps -l)"

    if [[ $? -ne 0 ]]; then
        log_warn "Failed to set up cpu check service for all hosts."
        return 1
    fi
}