#!/bin/bash

# =============================================================================
# Icinga Director Configuration Script - Validation Library
# =============================================================================

# This file is meant to be sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# Dependencies
# - logging.sh for log_* functions
# - projects/PROJECT_NAME_configs.sh for PROJECT_NODES_* arrays and  USER_* arrays

# Validate that essential commands are available.
validate_commands_exist() {
    log_info "Validating required commands..."
    local command_missing=0

    if ! command -v icingacli >&/dev/null; then
        log_error "'icingacli' command not found. Please install Icinga CLI."
        command_missing=1
    fi

    if ! command -v mysql >&/dev/null; then
        log_warn "'mysql' command not found. Database operations (like checking service existence) might fail."
        # Not exiting here as some operations might still work, but it's a strong warning.
    fi

    if ! command -v jq >&/dev/null; then
        log_error "'jq' command not found. JSON validation will not be possible. Please install jq."
        command_missing=1
    fi

    if [[ $command_missing -ne 0 ]]; then
        log_error "One or more critical commands are missing. Please install them and retry."
        exit 1
    fi

    # Check if Icinga Director module is available via icingacli
    if ! icingacli director --version >&/dev/null; then
        log_error "Icinga Director module not available or 'icingacli director' command failed."
        log_info "Ensure the Icinga Director is installed and accessible via 'icingacli'."
        exit 1
    fi

    log_success "Required commands validated."
    return 0
}

# Validate that configuration arrays (nodes, users) have matching lengths.
validate_config_array_lengths() {
    log_info "Validating configuration array lengths..."
    local validation_failed=0

    # Validate node configuration arrays
    if [[ ${#PROJECT_NODES_ADDRESS[@]} -ne ${#PROJECT_NODES_DISPLAY_NAME[@]} ]]; then
        log_error "Node configuration array length mismatch: PROJECT_NODES_ADDRESS (${#PROJECT_NODES_ADDRESS[@]}) vs PROJECT_NODES_DISPLAY_NAME (${#PROJECT_NODES_DISPLAY_NAME[@]})."
        validation_failed=1
    else
        log_info "Node configuration array lengths match."
    fi

    # Validate user configuration arrays
    if [[ ${#USER_NAMES[@]} -ne ${#USER_DISPLAY_NAMES[@]} ]] || \
       [[ ${#USER_NAMES[@]} -ne ${#USER_EMAILS[@]} ]]; then
        log_error "User configuration array length mismatch: USER_NAMES (${#USER_NAMES[@]}), USER_DISPLAY_NAMES (${#USER_DISPLAY_NAMES[@]}), USER_EMAILS (${#USER_EMAILS[@]})."
        validation_failed=1
    else
        log_info "User configuration array lengths match."
    fi

    if [[ $validation_failed -ne 0 ]]; then
        log_error "Configuration array length validation failed. Please check your settings in config/node_config.sh and config/user_config.sh."
        exit 1
    fi

    log_success "Configuration array lengths validated."
    return 0
}

# Main prerequisite validation function to be called from the main script.
validate_all_prerequisites() {
    log_info "--- Starting Prerequisite Validation ---"
    validate_commands_exist
    validate_config_array_lengths
    log_success "All prerequisites validated successfully."
}
