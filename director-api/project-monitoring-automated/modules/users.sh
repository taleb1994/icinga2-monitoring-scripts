#!/bin/bash

# =============================================================================
# Icinga Director Configuration Script - Users and User Groups Module
# =============================================================================

# This file is meant to be sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# Dependencies:
# - lib/utils.sh (for create_icinga_object, check_object_exists, log_*)
# - projects/PROJECT_NAME_configs.sh (for PROJECT_USERGROUP, PROJECT_TIMEPERIOD, USER_NAMES, USER_DISPLAY_NAMES, USER_EMAILS arrays)

# --- Project User Group ---
setup_project_usergroup() {
    log_info "Setting up project user group: $PROJECT_USERGROUP"

    local json_data='{
        "object_name": "'"$PROJECT_USERGROUP"'",
        "object_type": "object",
        "display_name": "'"$PROJECT_USERGROUP"'"
    }'

    create_icinga_object "usergroup" "$json_data" "$PROJECT_USERGROUP" "Project user group ($PROJECT_USERGROUP)"
    return $?
}

# --- User Management ---

# Check if a user is a member of a specific usergroup using MySQL.
# _ at the beginning of the function name is a naming convention. It signals the function is intended for internal or "private" use within the script.
# Arguments:
#   $1 (username): The name of the user.
#   $2 (usergroup_name): The name of the usergroup.
# Returns:
#   0 if the user is a member, 1 if not or if an error occurred.
_check_user_in_usergroup_db() {
    local username="$1"
    local usergroup_name="$2"
    local query_output

    log_info "Database check: Is user '$username' in usergroup '$usergroup_name'?"

    # SQL query to find if a user is part of a usergroup
    local mysql_query="SELECT u.object_name FROM director.icinga_user AS u \
                       JOIN director.icinga_usergroup_user AS ugu ON u.id = ugu.user_id \
                       JOIN director.icinga_usergroup AS ug ON ugu.usergroup_id = ug.id \
                       WHERE ug.object_name = '$usergroup_name' AND u.object_name = '$username';"

    # Execute query. `mysql` output goes to stdout. Errors to stderr.
    # `|| true` on grep prevents script exit if grep finds nothing (exit code 1).
    query_output=$(mysql --batch --skip-column-names -e "$mysql_query" 2>/dev/null | grep -w "$username" || true)

    if [[ -n "$query_output" ]]; then
        log_info "User '$username' IS a member of usergroup '$usergroup_name' (DB check)."
        return 0 # True, user is in group
    else
        # This also covers cases where the query fails or returns no rows
        log_info "User '$username' is NOT a member of usergroup '$usergroup_name' (DB check)."
        return 1 # False, user is not in group or error
    fi
}

# Get current usergroups for a user from Icinga Director (via MySQL).
# Arguments:
#   $1 (username): The name of the user.
# Output:
#   Prints a comma-separated list of group names.
# Returns:
#   0 on success, 1 on error.
_get_user_groups_db() {
    local username="$1"
    local query_output

    log_info "Database fetch: Getting current groups for user '$username'..."

    local mysql_query="SELECT ug.object_name FROM director.icinga_usergroup AS ug \
                       JOIN director.icinga_usergroup_user AS ugu ON ug.id = ugu.usergroup_id \
                       JOIN director.icinga_user AS u ON ugu.user_id = u.id \
                       WHERE u.object_name = '$username';"

    # Execute query, then process output.
    # `tr '\n' ','` replaces newlines with commas.
    # `sed 's/,$//'` removes a trailing comma if it exists.
    if query_output=$(mysql --batch --skip-column-names -e "$mysql_query" 2>/dev/null); then
        if [[ -n "$query_output" ]]; then
            local groups_csv
            groups_csv=$(echo "$query_output" | tr '\n' ',' | sed 's/,$//')
            log_info "User '$username' current groups (DB): [$groups_csv]"
            echo "$groups_csv"
            return 0
        else
            log_info "User '$username' has no groups assigned (DB)."
            echo "" # No groups
            return 0
        fi
    else
        log_error "Failed to fetch groups for user '$username' from database."
        return 1
    fi
}

# Add a user to a usergroup, preserving existing group memberships.
# Uses `icingacli director user set <username> --json '{"groups": ["group1", "new_group"]}'`
# Arguments:
#   $1 (username): The name of the user.
#   $2 (new_usergroup_to_add): The usergroup to add the user to.
# Returns:
#   0 on success, 1 on failure.
_add_user_to_usergroup_cli() {
    local username="$1"
    local new_usergroup_to_add="$2"
    local current_groups_csv
    local current_groups_array=()
    local final_groups_json_array="[]" # Default to empty JSON array

    log_info "CLI Update: Adding user '$username' to usergroup '$new_usergroup_to_add'..."

    # Get current groups using the DB function
    if ! current_groups_csv=$(_get_user_groups_db "$username"); then
        log_error "Failed to get current groups for '$username'. Cannot update groups."
        return 1
    fi

    # Convert CSV to bash array
    if [[ -n "$current_groups_csv" ]]; then
        IFS=',' read -r -a current_groups_array <<< "$current_groups_csv"
    fi

    # Add the new group if not already present
    local group_found=0
    for group in "${current_groups_array[@]}"; do
        if [[ "$group" == "$new_usergroup_to_add" ]]; then
            group_found=1
            break
        fi
    done

    if [[ $group_found -eq 0 ]]; then
        current_groups_array+=("$new_usergroup_to_add")
        log_info "Usergroup '$new_usergroup_to_add' will be added to '$username'."
    else
        log_info "User '$username' is already in '$new_usergroup_to_add'. No change to group list needed for this group."
        # We still proceed to set the groups to ensure consistency if other logic relies on `user set`
    fi
    
    # Build JSON array string for the API call
    if [[ ${#current_groups_array[@]} -gt 0 ]]; then
        local temp_json_array
        temp_json_array=$(printf '"%s",' "${current_groups_array[@]}") # "group1","group2",
        final_groups_json_array="[${temp_json_array%,}]" # Remove trailing comma and wrap
    fi

    log_info "Setting groups for user '$username' to: $final_groups_json_array"
    local json_payload="{\"groups\": $final_groups_json_array}"

    if icingacli director user set "$username" --json "$json_payload"; then
        log_success "Successfully updated user '$username' groups to include '$new_usergroup_to_add'."
        return 0
    else
        log_error "Failed to update groups for user '$username' using icingacli. Payload: $json_payload"
        return 1
    fi
}


# Process a single user: create if not exists, or update usergroup membership.
# Arguments:
#   $1 (name): Username.
#   $2 (display_name): User's display name.
#   $3 (email): User's email address.
# Returns:
#   0 if user processed successfully, 1 on failure.
_process_single_user() {
    local name="$1"
    local display_name="$2"
    local email="$3"

    log_info "Processing user: $name (Display: $display_name, Email: $email)"

    local user_exists_status
    user_exists_status=$(check_object_exists "user" "$name")

    if [[ "$user_exists_status" == "true" ]]; then
        log_info "User '$name' already exists. Checking group membership for '$PROJECT_USERGROUP'."
        
        # Check if user is already in the project usergroup using the DB check
        if _check_user_in_usergroup_db "$name" "$PROJECT_USERGROUP"; then
            log_info "User '$name' is already in '$PROJECT_USERGROUP'. No action needed for this user."
            return 0
        else
            log_info "User '$name' exists but is not in '$PROJECT_USERGROUP'. Adding now."
            _add_user_to_usergroup_cli "$name" "$PROJECT_USERGROUP"
            return $?
        fi
    elif [[ "$user_exists_status" == "false" ]]; then
        log_info "User '$name' does not exist. Creating new user and adding to '$PROJECT_USERGROUP'..."

        local json_data='{
            "object_name": "'"$name"'",
            "object_type": "object",
            "groups": ["'"$PROJECT_USERGROUP"'"],
            "imports": ["'"$GENERIC_USER_TEMPLATE"'"],
            "display_name": "'"$display_name"'",
            "email": "'"$email"'",
            "enable_notifications": true,
            "period": "'"$PROJECT_TIMEPERIOD"'",
            "states": ["Critical", "Down", "Up", "Unknown", "Warning", "OK"],
            "types": ["Acknowledgement", "Custom", "DowntimeEnd", "DowntimeRemoved", "DowntimeStart", "Problem", "Recovery"]
        }'

        if create_icinga_object "user" "$json_data" "$name" "User $name"; then
            log_success "User '$name' created and assigned to '$PROJECT_USERGROUP'."
            return 0
        else
            log_error "Failed to create user '$name'."
            return 1
        fi
    else
        log_error "Could not determine existence of user '$name'. Skipping."
        return 1
    fi
}

# Create/update all project users based on configuration arrays.
process_all_project_users() {
    log_info "Creating/updating project users..."
    local success_count=0
    local total_count=${#USER_NAMES[@]}
    local overall_status=0

    if [[ $total_count -eq 0 ]]; then
        log_info "No users defined for this project. Skipping user processing."
        return 0
    fi

    for i in "${!USER_NAMES[@]}"; do
        local name="${USER_NAMES[$i]}"
        local display_name="${USER_DISPLAY_NAMES[$i]}"
        local email="${USER_EMAILS[$i]}"

        if _process_single_user "$name" "$display_name" "$email"; then
            success_count=$((success_count + 1))
        else
            overall_status=1 # Mark that at least one user failed
            log_warn "Processing failed for user: $name"
        fi
    done

    log_info "User processing completed: $success_count/$total_count users processed successfully."

    if [[ $overall_status -eq 0 ]]; then
        log_success "All users processed successfully."
    else
        log_warn "Some users may not have been processed correctly. Please review logs."
    fi
    return $overall_status
}