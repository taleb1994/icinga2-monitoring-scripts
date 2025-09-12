#!/bin/bash

# =============================================================================
# Icinga Director Configuration Script - Deployment Module
# Description: This module handles Icinga Director initialization and deployment (kickstart) after editing main icinga2 configuration.
# =============================================================================

# This file is meant to be sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi


# After changing any main icinga2 configuration files (zones, scripts...), kickstart is required.
kickstart_director() {
    log_info "Starting Icinga Director initialization checks..."

    # Validate Icinga2 configuration
    log_info "Validating Icinga2 configuration (icinga2 daemon --validate)..."

    if icinga2 daemon --validate > /dev/null 2>&1; then
        log_success "Icinga2 configuration is valid."
    else
        log_error "Icinga2 configuration validation failed. Please check errors above."
        log_info "Director kickstart and deployment will be skipped due to invalid Icinga2 config."
        return 1
    fi

    # Check if Icinga Director kickstart is configured
    log_info "Checking if Icinga Director kickstart is configured (icingacli director kickstart required)..."
    
    local kickstart_status_output
    kickstart_status_output=$(icingacli director kickstart required 2>&1 || true) # Capture output and ignore errors
    local kickstart_exit_code=$?

    if echo "$kickstart_status_output" | grep -q "Kickstart configured"; then
        log_info "Icinga Director kickstart is configured."
        log_info "Attempting to run Icinga Director kickstart (icingacli director kickstart run)..."

        # Restart director otherwise it will not see the new added zones and endpoints.  
        sleep 3 && systemctl reload icinga2.service && sleep 3 && systemctl reload icinga-director.service && sleep 3

        if icingacli director kickstart run; then
            log_success "Icinga Director kickstart run successfully."
        else
            log_error "Failed to run Icinga Director kickstart."
            log_info "Review the output above for specific errors from 'icingacli director kickstart run'."
            return 1
        fi
    else
        # Handle cases where 'kickstart required' command failed or gave unexpected output
        log_error "Could not determine Icinga Director kickstart status or command failed."
        log_error "Output from 'icingacli director kickstart required': $kickstart_status_output"
        log_error "Exit code: $kickstart_exit_code"
        return 1
    fi

    log_success "Icinga Director initialization checks completed."
    return 0
}


# Deploy the pending Icinga Director configuration
deploy_icinga_configuration() {
    log_info "Attempting to deploy Icinga Director configuration (icingacli director config deploy)..."

    if icingacli director config deploy; then
        log_success "Icinga Director configuration deployed successfully."
        return 0
    else
        log_error "Failed to deploy Icinga Director configuration."
        log_info "Review the output above for specific errors from 'icingacli director config deploy'."
        log_info "You may need to check the Icinga Director deployment history in the web UI for more details."
        return 1
    fi
}
