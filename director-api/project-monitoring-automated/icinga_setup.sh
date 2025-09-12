#!/bin/bash

# =============================================================================
# Icinga Director Configuration Script - Main
# Description: Orchestrates the automated setup for Icinga monitoring.
# =============================================================================

# Script behavior configuration
set -euo pipefail # Exit on error, undefined vars, pipe failures

# --- Global Variables ---
readonly SCRIPT_DIR_ABS="$(dirname "$(readlink -f "$0")")" # Get script's absolute directory
readonly SCRIPT_NAME="$(basename "$0")"

# --- Source Configuration & Libraries ---
# source "${SCRIPT_DIR_ABS}/projects/c2vba-d_configs.sh"
source "${SCRIPT_DIR_ABS}/projects/c2vba-p_configs.sh"
source "${SCRIPT_DIR_ABS}/config/all_hosts_config.sh"

source "${SCRIPT_DIR_ABS}/lib/logging.sh"
source "${SCRIPT_DIR_ABS}/lib/utils.sh"               # Depends on logging
source "${SCRIPT_DIR_ABS}/lib/validation.sh"          # Depends on logging

# --- Source Modules ---
source "${SCRIPT_DIR_ABS}/modules/templates.sh"       # Depends on utils, logging
source "${SCRIPT_DIR_ABS}/modules/hostgroups.sh"      # Depends on utils, logging
source "${SCRIPT_DIR_ABS}/modules/users.sh"           # Depends on utils, logging
source "${SCRIPT_DIR_ABS}/modules/nodes.sh"           # Depends on utils, logging
source "${SCRIPT_DIR_ABS}/modules/zones.sh"           # Depends on utils, logging
source "${SCRIPT_DIR_ABS}/modules/services.sh"        # Depends on utils, logging
source "${SCRIPT_DIR_ABS}/modules/notifications.sh"   # Depends on utils, logging
source "${SCRIPT_DIR_ABS}/modules/deployment.sh"      # Depends on utils, logging


# --- Main Execution ---
main() {
    log_info "=== Starting Icinga Director Configuration for Project: $PROJECT_NAME ==="

    # Validate prerequisites
    validate_all_prerequisites

    # Create project zones
    log_info "--- Stage: Creating Project Zones ---"
    configure_project_icinga_zones
    kickstart_director
    deploy_icinga_configuration

    # Create generic templates
    log_info "--- Stage: Creating Generic Templates ---"
    setup_generic_timeperiod_template
    setup_generic_user_template
    setup_generic_agent_template
    setup_generic_notification_templates
    setup_generic_check_disk_template
    setup_generic_check_memory_template
    setup_generic_check_cpu_template

    # Create host groups
    log_info "--- Stage: Creating Host Groups ---"
    setup_all_hostgroups

    # Create project-specific base objects
    log_info "--- Stage: Creating Project-Specific Base Objects ---"
    setup_project_timeperiod
    setup_project_usergroup

    # Create/Update project users
    log_info "--- Stage: Processing Project Users ---"
    process_all_project_users

    # Create project agents (nodes)
    log_info "--- Stage: Creating Project Agents (Nodes) ---"
    setup_project_agents

    # Create services (e.g., disk checks)
    log_info "--- Stage: Creating Services ---"
    setup_disk_check_services
    setup_memory_check_services
    setup_cpu_check_services

    # Create project-specific notifications
    log_info "--- Stage: Creating Project Notifications ---"
    setup_project_notifications

    # Deploy configuration
    log_info "--- Stage: Finalizing and Deploying Configuration ---"
    kickstart_director

    if deploy_icinga_configuration; then
        log_success "=== Icinga Director Configuration Complete for Project: $PROJECT_NAME ==="
        log_info "Log file location: $LOG_FILE"
    else
        log_error "=== Configuration deployment failed for Project: $PROJECT_NAME ==="
        # The cleanup trap will handle the exit code
        return 1 # Explicitly return error for clarity
    fi
    return 0
}

# --- Script Entry Point ---
# Determine whether the script is being run directly or being sourced by another script.
# Ensure that this script only runs when is executed directly, not when it is sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    # Initialize logging (redirect stdout/stderr)
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)

    # Register cleanup function to be called on EXIT
    trap cleanup EXIT

    main "$@"
fi