#!/bin/bash

# =============================================================================
# Icinga Director Configuration Script - Utility Library
# =============================================================================

# This file is meant to be sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# Dependencies (ensure these are sourced before this script if calling functions directly)
# - logging.sh for log_* functions
# - all_hosts_config.sh for LOG_FILE (used in cleanup)

# Cleanup function executed on script exit
# This function is registered with 'trap cleanup EXIT' in the main script.
cleanup() {
    local exit_code=$? # Capture the exit code of the last command

    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed with exit code $exit_code."
        log_info "Check log file for details: $LOG_FILE"
    else
        log_info "Script finished with exit code $exit_code."
    fi
    # The script will exit with the captured exit_code automatically after trap handler finishes.
}

# Check if an Icinga Director object exists.
# Arguments:
#   $1 (object_type): The type of Icinga object (e.g., "host", "service", "user").
#   $2 (object_name): The name of the Icinga object.
# Output:
#   Prints "true" if the object exists, "false" otherwise.
# Returns:
#   0 if check was successful (regardless of existence), 1 on parameter error.
check_object_exists() {
    local object_type="$1"
    local object_name="$2"
    local output
    local mysql_query

    if [[ -z "$object_type" || -z "$object_name" ]]; then
        log_error "check_object_exists: Missing parameters (object_type or object_name)."
        return 1 # Indicate an error in function usage
    fi

    log_info "Checking existence of $object_type '$object_name'..."

    case "$object_type" in
        "service")
            # Services apply rules cant be directly checkable via `icingacli director service exists`.
            # This will confuse service-template checking, since it can be checked using icingacli. Thats why the double check using OR
            # Ensure your MySQL client is configured for passwordless access.
            # The query looks for service templates or apply rules by name.
            mysql_query="SELECT object_name FROM director.icinga_service WHERE object_name = '$object_name' AND (object_type = 'template' OR object_type = 'apply');"

            if output=$(mysql --batch --skip-column-names -e "$mysql_query" 2>&1); then
                if [[ -n "$output" ]]; then # If query returned object_name
                    log_info "$object_type '$object_name' found in database."
                    echo "true"
                else
                    log_info "$object_type '$object_name' not found in database."
                    echo "false"
                fi
            else
                log_warn "Failed to query database for $object_type '$object_name'. Error: $output"
                echo "false" # Assume not exists on error to prevent duplicate attempts
            fi
            ;;
        *)
            # Use the standard `icingacli director <type> exists <name>` for other object types.
            # The command output includes "exists" or "does not exist".
            output=$(icingacli director "$object_type" exists "$object_name" 2>&1 || true)
            if [[ "$output" == *"exists"* ]]; then
                log_info "$object_type '$object_name' exists."
                echo "true"
            elif [[ "$output" == *"does not exist"* ]]; then
                log_info "$object_type '$object_name' does not exist."
                echo "false"
            else
                # Unexpected output from icingacli
                log_warn "Unexpected output while checking $object_type '$object_name': $output"
                return 1
            fi
            ;;
    esac
    return 0 # Check itself was performed
}


# Generic function to create an Icinga Director object.
# Arguments:
#   $1 (object_type): The type of Icinga object (e.g., "host", "service").
#   $2 (json_data): The JSON payload for creating the object.
#   $3 (object_name): The name of the object (for logging and existence check).
#   $4 (description): A human-readable description for logging.
# Returns:
#   0 if the object was created successfully or already existed.
#   1 if creation failed or JSON was invalid.
create_icinga_object() {
    local object_type="$1"
    local json_data="$2"
    local object_name="$3"
    local description="${4:-$object_type $object_name}" # Default description

    if [[ -z "$object_type" || -z "$json_data" || -z "$object_name" ]]; then
        log_error "create_icinga_object: Missing parameters."
        return 1
    fi

    # Check if object already exists
    # The subshell $(...) captures the output of check_object_exists ("true" or "false")
    local exists_status
    exists_status=$(check_object_exists "$object_type" "$object_name")
    
    if [[ "$exists_status" == "true" ]]; then
        log_info "$description already exists. Skipping creation."
        return 0
    # If exists_status is "false" -> continues past this block (condetion will not be met)
    # If exists_status is not "false" -> logs an error about being unable to determine the existence and aborts (return 1).
    elif [[ "$exists_status" != "false" ]]; then
        log_error "Could not determine existence of $description. Aborting creation."
        return 1
    fi

    log_info "Attempting to create $description..."

    # Validate JSON syntax using jq
    # `jq empty` reads JSON and produces no output if valid, exits 0.
    # If invalid, jq prints an error to stderr and exits non-zero.
    if ! echo "$json_data" | jq empty 2>/dev/null; then
        log_error "Invalid JSON data for $description. JSON provided: $json_data"
        return 1
    fi

    # Attempt to create the object using icingacli
    if icingacli director "$object_type" create --json "$json_data"; then
        log_success "$description created successfully."
        return 0
    else
        log_error "Failed to create $description using icingacli. JSON used: $json_data"
        return 1
    fi
}