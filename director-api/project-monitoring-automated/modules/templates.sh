#!/bin/bash

# =============================================================================
# Icinga Director Configuration Script - Generic Templates Module
# =============================================================================

# This file is meant to be sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# Dependencies (ensure these are sourced before this script):
# - lib/utils.sh (for create_icinga_object, check_object_exists, log_*)
# - config/all_hosts_config.sh (for GENERIC_*_TEMPLATE variables)

# --- TimePeriod Template ---
setup_generic_timeperiod_template() {
    log_info "Setting up generic timeperiod template: $GENERIC_TIMEPERIOD_TEMPLATE"

    local json_data='{
        "object_name": "'"$GENERIC_TIMEPERIOD_TEMPLATE"'",
        "object_type": "template",
        "display_name": "generic-24/7-template",
        "ranges": {
            "friday": "00:00-24:00",
            "monday": "00:00-24:00",
            "saturday": "00:00-24:00",
            "sunday": "00:00-24:00",
            "thursday": "00:00-24:00",
            "tuesday": "00:00-24:00",
            "wednesday": "00:00-24:00"
        }
    }'
     
    create_icinga_object "timeperiod" "$json_data" "$GENERIC_TIMEPERIOD_TEMPLATE" "Generic 24x7 timeperiod template"
    return $?
}

# --- User Template ---
setup_generic_user_template() {
    log_info "Setting up generic user template: $GENERIC_USER_TEMPLATE"

    local json_data='{
        "object_name": "'"$GENERIC_USER_TEMPLATE"'",
        "object_type": "template",
        "enable_notifications": true,
        "states": ["Critical", "Down", "Unknown", "Up", "Warning", "OK"],
        "types": [
            "Acknowledgement", "Custom", "DowntimeEnd", "DowntimeRemoved",
            "DowntimeStart", "Problem", "Recovery"
        ]
    }'

    create_icinga_object "user" "$json_data" "$GENERIC_USER_TEMPLATE" "Generic user template"
    return $?
}

# --- Agent (Host) Template ---
setup_generic_agent_template() {
    log_info "Setting up generic agent (host) template: $GENERIC_AGENT_TEMPLATE"

    local json_data='{
        "object_name": "'"$GENERIC_AGENT_TEMPLATE"'",
        "object_type": "template",
        "check_command": "hostalive",
        "max_check_attempts": "3",
        "check_interval": "5m",
        "retry_interval": "45s",
        "check_timeout": "10s",
        "enable_notifications": true,
        "enable_active_checks": true,
        "enable_passive_checks": true,
        "enable_event_handler": true,
        "enable_perfdata": true
    }'

    create_icinga_object "host" "$json_data" "$GENERIC_AGENT_TEMPLATE" "Generic agent (host) template"
    return $?
}

# --- Check Disk Service Template ---
setup_generic_check_disk_template() {
    log_info "Setting up generic check_disk service template: $GENERIC_CHECK_DISK_TEMPLATE"

    local json_data='{
        "object_name": "'"$GENERIC_CHECK_DISK_TEMPLATE"'",
        "object_type": "template",
        "check_command": "disk",
        "max_check_attempts": "3",
        "check_interval": "6h",
        "retry_interval": "1m",
        "check_timeout": "30s",
        "enable_notifications": true,
        "enable_active_checks": true,
        "enable_passive_checks": true,
        "enable_event_handler": true,
        "enable_perfdata": true,
        "vars": {
            "disk_wfree": "15%",
            "disk_cfree": "10%",
            "disk_units": "GB"
        }
    }'

    create_icinga_object "service" "$json_data" "$GENERIC_CHECK_DISK_TEMPLATE" "Generic check_disk service template"
    return $?
}

# --- Notification Templates (Host and Service) ---
setup_generic_notification_templates() {
    log_info "Setting up generic notification templates..."
    local overall_status=0

    # Host notification template
    log_info "Setting up generic host notification template: $GENERIC_HOST_NOTIFICATION_TEMPLATE"
    local host_notification_json='{
        "object_name": "'"$GENERIC_HOST_NOTIFICATION_TEMPLATE"'",
        "object_type": "template",
        "imports": [],
        "times_begin": "10m",
        "command": "mail-host-notification",
        "notification_interval": "6h",
        "states": ["Down"],
        "types": ["Acknowledgement", "Custom", "DowntimeEnd", "DowntimeRemoved", "DowntimeStart", "Problem", "Recovery"],
        "vars": {
            "notification_from": "icinga-intern@heuboe.de",
            "display_name": "icinga-host-mail-intern"
        }
    }'

    create_icinga_object "notification" "$host_notification_json" "$GENERIC_HOST_NOTIFICATION_TEMPLATE" "Generic host notification template"
    if [[ $? -ne 0 ]]; then overall_status=1; fi

    # Service notification template
    log_info "Setting up generic service notification template: $GENERIC_SERVICE_NOTIFICATION_TEMPLATE"
    local service_notification_json='{
        "object_name": "'"$GENERIC_SERVICE_NOTIFICATION_TEMPLATE"'",
        "object_type": "template",
        "imports": [],
        "times_begin": "10m",
        "command": "mail-service-notification",
        "notification_interval": "6h",
        "states": ["Unknown", "Warning", "Critical"],
        "types": ["Acknowledgement", "Custom", "DowntimeEnd", "DowntimeRemoved", "DowntimeStart", "Problem", "Recovery"],
        "vars": {
            "notification_from": "icinga-intern@heuboe.de",
            "display_name": "icinga-service-mail-intern"
        }
    }'
    create_icinga_object "notification" "$service_notification_json" "$GENERIC_SERVICE_NOTIFICATION_TEMPLATE" "Generic service notification template"
    if [[ $? -ne 0 ]]; then overall_status=1; fi
    
    return $overall_status
}

# --- Check Memory Service Template ---
setup_generic_check_memory_template() {
    log_info "Setting up generic check_memory service template: $GENERIC_CHECK_MEMORY_TEMPLATE"

    local json_data='{
        "object_name": "'"$GENERIC_CHECK_MEMORY_TEMPLATE"'",
        "object_type": "template",
        "check_command": "check_memory",
        "max_check_attempts": "3",
        "check_interval": "30m",
        "retry_interval": "1m",
        "check_timeout": "30s",
        "enable_notifications": true,
        "enable_active_checks": true,
        "enable_passive_checks": true,
        "enable_event_handler": true,
        "enable_perfdata": true,
		"enable_flapping": true,
        "vars": {
            "ram_wused": "85",
            "ram_cused": "90"
        }
    }'

    create_icinga_object "service" "$json_data" "$GENERIC_CHECK_MEMORY_TEMPLATE" "Generic check_memory service template"
    return $?
}

# --- Check CPU Service Template ---
setup_generic_check_cpu_template() {
    log_info "Setting up generic check_cpu service template: $GENERIC_CHECK_CPU_TEMPLATE"

    local json_data='{
        "object_name": "'"$GENERIC_CHECK_CPU_TEMPLATE"'",
        "object_type": "template",
        "check_command": "check_cpu",
        "max_check_attempts": "3",
        "check_interval": "5m",
        "retry_interval": "1m",
        "check_timeout": "30s",
        "enable_notifications": true,
        "enable_active_checks": true,
        "enable_passive_checks": true,
        "enable_event_handler": true,
        "enable_perfdata": true,
		"enable_flapping": true,
        "vars": {
            "cpu_wused": "85",
            "cpu_cused": "90"
        }
    }'

    create_icinga_object "service" "$json_data" "$GENERIC_CHECK_CPU_TEMPLATE" "Generic check_cpu service template"
    return $?
}