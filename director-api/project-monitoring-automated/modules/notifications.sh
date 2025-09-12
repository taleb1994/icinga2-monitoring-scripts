#!/bin/bash

# =============================================================================
# Icinga Director Configuration Script - Project Notifications Module
# =============================================================================

# This file is meant to be sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# Dependencies:
# - lib/utils.sh (for create_icinga_object, log_*)
# - config/all_hosts_config.sh

# Create project-specific project-specific timeperiod
setup_project_timeperiod() {
    log_info "Setting up project timeperiod: $PROJECT_TIMEPERIOD"

    local json_data='{
        "object_name": "'"$PROJECT_TIMEPERIOD"'",
        "object_type": "object",
        "imports": ["'"$GENERIC_TIMEPERIOD_TEMPLATE"'"],
        "display_name": "'"$PROJECT_TIMEPERIOD"'"
    }'
    
    create_icinga_object "timeperiod" "$json_data" "$PROJECT_TIMEPERIOD" "Project-specific timeperiod ($PROJECT_TIMEPERIOD)"
    if [[ $? -ne 0 ]]; then
        log_warn "Failed to ensure project timeperiod '$PROJECT_TIMEPERIOD' was created."
        return 1
    fi
    return 0
}

# Create project-specific notification apply rules.
setup_project_notifications() {
    log_info "Setting up project-specific notifications..."
    local overall_status=0

    # Host Notification Apply Rule
    log_info "Setting up project host notification: $PROJECT_HOST_NOTIFICATION"
    
    local host_notification_json='{
        "object_name": "'"$PROJECT_HOST_NOTIFICATION"'",
        "object_type": "apply",
        "apply_to": "Host",
        "user_groups": ["'"$PROJECT_USERGROUP"'"],
        "period": "'"$PROJECT_TIMEPERIOD"'",
        "imports": ["'"$GENERIC_HOST_NOTIFICATION_TEMPLATE"'"],
        "assign_filter": "host.enable_notifications != \"false\" && host.groups = \"'"$PROJECT_HOSTGROUP"'\"",
        "states": ["Down"],
        "types": ["Acknowledgement", "Custom", "DowntimeEnd", "DowntimeRemoved", "DowntimeStart", "Problem", "Recovery"]
    }'

    create_icinga_object "notification" "$host_notification_json" "$PROJECT_HOST_NOTIFICATION" "Project host notification rule"
    if [[ $? -ne 0 ]]; then
        log_warn "Failed to set up project host notification rule."
        overall_status=1
    fi

    # Service Notification Apply Rule
    log_info "Setting up project service notification: $PROJECT_SERVICE_NOTIFICATION"
    
    local service_notification_json='{
        "object_name": "'"$PROJECT_SERVICE_NOTIFICATION"'",
        "object_type": "apply",
        "apply_to": "Service",
        "user_groups": ["'"$PROJECT_USERGROUP"'"],
        "period": "'"$PROJECT_TIMEPERIOD"'",
        "imports": ["'"$GENERIC_SERVICE_NOTIFICATION_TEMPLATE"'"],
        "assign_filter": "service.enable_notifications != \"false\" && host.groups = \"'"$PROJECT_HOSTGROUP"'\"",
        "states": ["Unknown", "Warning", "Critical"],
        "types": ["Acknowledgement", "Custom", "DowntimeEnd", "DowntimeRemoved", "DowntimeStart", "Problem", "Recovery"]
    }'

    create_icinga_object "notification" "$service_notification_json" "$PROJECT_SERVICE_NOTIFICATION" "Project service notification rule"
    if [[ $? -ne 0 ]]; then
        log_warn "Failed to set up project service notification rule."
        overall_status=1
    fi

    if [[ $overall_status -eq 0 ]]; then
        log_success "Project notifications processed successfully."
    else
        log_warn "Some project notifications may not have been processed correctly."
    fi
    return $overall_status
}