#!/bin/bash

# =============================================================================
# Icinga Director Configuration Script
# Description: Automated setup for Icinga monitoring with proper error handling
# =============================================================================

# Script behavior configuration:
# -e: Exit immediately if a command exits with a non-zero status. Prevents errors from being ignored.
# -u: Treat unset variables as an error when substituting. Helps catch typos or missing variable definitions.
# -o pipefail: The return value of a pipeline is the status of the last command to exit with a non-zero status, or zero if all commands in the pipeline exit successfully. Essential for robust error handling in pipelines.
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# --- Configuration ---
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/var/log/icinga-director-setup-script.log"

# Define a read-only variable 'CONFIG_FILE'.
# It's assigned the value of the first command-line argument passed to the script ($1).
# If no argument is provided, $1 would be empty, and ":-" ensures CONFIG_FILE is set to an empty string
# instead of causing an error if 'set -u' is active and $1 is truly unset.
# Currently, this variable is defined but not used elsewhere in the script.
# Future Enhancement: This could be used to load project-specific variables or override defaults from an external file.
readonly CONFIG_FILE="${1:-}"

# Redirect the script's standard output (stdout, file descriptor 1).
# '>' redirects stdout.
# '>(tee -a "$LOG_FILE")' is process substitution. It runs 'tee -a "$LOG_FILE"' as a separate process.
# 'tee -a "$LOG_FILE"' does two things:
#   1. Appends (-a) all input it receives (which is the script's stdout) to the $LOG_FILE.
#   2. Prints the same input to its own stdout, which in this case goes to the original destination of the script's stdout (usually the terminal).
# Effect: All standard output from the script will be displayed on the terminal AND appended to the log file.
# Enable logging
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

# --- Project Configuration ---
declare -r PROJECT_NAME="c2vba-d"

# Node configuration arrays
declare -ra PROJECT_NODES_ADDRESS=(
    "master1.d.c2vba.heuboe.hbintern"
    "worker1.d.c2vba.heuboe.hbintern"
    "worker2.d.c2vba.heuboe.hbintern"
    "worker3.d.c2vba.heuboe.hbintern"
)

declare -ra PROJECT_NODES_DISPLAY_NAME=(
    "${PROJECT_NAME}-master1"
    "${PROJECT_NAME}-worker1"
    "${PROJECT_NAME}-worker2"
    "${PROJECT_NAME}-worker3"
)

# User configuration
declare -ra USER_NAMES=(
    "mohammed-taleb"
    "vera-hermanns"
    "andrzej-grala"
    "wladislaw-schmidt" 
    "andrea-haug"
)

declare -ra EMAILS=(
    "mohammed.taleb@heuboe.de"
    "vera.hermanns@heuboe.de"
    "andrzej.grala@heuboe.de"
    "wladislaw.schmidt@heuboe.de"
    "andrea.haug@heuboe.de"
)

# Declare the variable 'DISPLAY_NAMES' as a read-only array (-r for readonly, -a for array).
# This array stores the display names (e.g., initials) corresponding to the full user names in USER_NAMES
# and emails in EMAILS. The order and number of elements must match those arrays.
# Example: The first display name "M.T." corresponds to the first user_name and first email.
declare -ra DISPLAY_NAMES=(
    "M.T." 
    "V.H." 
    "A.G." 
    "W.S." 
    "A.H."
)

# --- Template Names ---
declare -r GENERIC_TIMEPERIOD_TEMPLATE="generic-24x7-template"
declare -r GENERIC_USER_TEMPLATE="generic-user-template"
declare -r GENERIC_HOST_NOTIFICATION_TEMPLATE="generic-24x7-host-notifications-template"
declare -r GENERIC_SERVICE_NOTIFICATION_TEMPLATE="generic-24x7-services-notifications-template"
declare -r GENERIC_AGENT_TEMPLATE="icinga-agent-template"
declare -r GENERIC_CHECK_DISK_TEMPLATE="check_disk-template"

# --- Project Objects ---
declare -r PROJECT_TIMEPERIOD="${PROJECT_NAME}-24x7"
declare -r PROJECT_HOSTGROUP="${PROJECT_NAME}-nodes"
declare -r PROJECT_USERGROUP="${PROJECT_NAME}-usergroup"
declare -r PROJECT_HOST_NOTIFICATION="${PROJECT_NAME}-24x7-host-notifications"
declare -r PROJECT_SERVICE_NOTIFICATION="${PROJECT_NAME}-24x7-services-notifications"

# --- K8s Host Groups ---
declare -r K8S_MASTERS_HOSTGROUP="k8s-masters-hostgroup"
declare -r K8S_WORKERS_HOSTGROUP="k8s-workers-hostgroup"
declare -r K8S_SINGLE_NODE_HOSTGROUP="k8s-single-node-hostgroup"

# --- Node Types and Services ---
declare -r NODE_SDB_TRUE="node has sdb: true"
declare -r NODE_SDB_FALSE="node has sdb: false"
declare -r CHECK_DISK_SDA_SDB="check-disk-sda-sdb"
declare -r CHECK_DISK_SDA="check-disk-sda"


# Arguments:
#   $1 (level): The log level string (e.g., "INFO", "ERROR").
#   $@ (message): The rest of the arguments are treated as the log message.
log() {
    local level="$1"  # Store the first argument (log level) in a local variable.
    shift  # Remove the first argument ($level) from the list of positional parameters. Now, "$@" contains only the log message components.
    
    # Print the formatted log message to standard error (stderr).
    # Stderr is used so that log messages don't interfere with potential stdout data a command might produce, and it's captured by the 'exec 2> >(tee...)' redirection.
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >&2
    
}

# Convenience wrapper function for logging informational messages.
# It calls the main 'log' function with a predefined level "INFO".
# "$@" passes all arguments received by 'log_info' directly as the message to the 'log' function.0
log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_success() { log "SUCCESS" "$@"; }

# This function is executed automatically just before the script exits, due to the 'trap' command below.
cleanup() {
    # Capture the exit code of the last command that executed before cleanup was called.
    # If 'set -e' caused an exit, this will be the exit code of the failing command.
    # If the script finishes normally, this will be 0 (usually).
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed with exit code $exit_code"  # Log an error message.
        log_info "Check log file: $LOG_FILE"  # Remind user to check the log.
    fi
    exit $exit_code # Ensure the script exits with the original captured exit code.
}

# Register the 'cleanup' function to be called on the EXIT signal.
# The EXIT signal is sent when the script terminates, regardless of whether it's a normal exit or due to an error (e.g., from 'set -e').
trap cleanup EXIT

validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    if ! command -v icingacli >&/dev/null; then
        log_error "icingacli command not found. Please install Icinga CLI."
        exit 1
    fi
    
    if ! icingacli director --version >&/dev/null; then
        log_error "Icinga Director module not available."
        exit 1
    fi
    
    # Validate array lengths match
    if [[ ${#PROJECT_NODES_ADDRESS[@]} -ne ${#PROJECT_NODES_DISPLAY_NAME[@]} ]]; then
        log_error "Node address and display name arrays length mismatch"
        exit 1
    fi
    
    if [[ ${#USER_NAMES[@]} -ne ${#DISPLAY_NAMES[@]} ]] || [[ ${#USER_NAMES[@]} -ne ${#EMAILS[@]} ]]; then
        log_error "User configuration arrays length mismatch"
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

# Enhanced object existence check with error handling
check_object_exists() {
    local object_type="$1"
    local object_name="$2"
    local output

    if [[ -z "$object_type" || -z "$object_name" ]]; then
        log_error "check_object_exists: Missing parameters"
        return 1
    fi
    
    # Because service can't be chcecked using icingacli, so it will be checked through the database
    # This will confuse service-template checking, since it can be checked using icingacli. Thats why the double check using ||
    case "$object_type" in
        "service")
            if output=$(mysql --batch --skip-column-names -e "SELECT object_name, object_type FROM director.icinga_service WHERE object_name = '$object_name';" | grep -E "apply|template" 2>&1); then
                if [[ $output == *"apply"* || $output == *"template"* ]]; then
                    echo "true"
                else
                    echo "false"
                fi
            else
                log_warn "Failed to check existence of $object_type '$object_name': $output"
                echo "false"
            fi
            ;;
        *)
            # Use the standard exists command for other object types
            if output=$(icingacli director "$object_type" exists "$object_name" 2>&1); then
                if [[ $output == *"exists"* ]]; then
                    echo "true"
                else
                    echo "false"
                fi
            else
                log_warn "Failed to check existence of $object_type '$object_name': $output"
                echo "false"
            fi
            ;;
    esac
}

# Generic object creation with JSON and existence validation 
create_icinga_object() {
    local object_type="$1"
    local json_data="$2"
    local object_name="$3"
    local description="$4"
    
    # Check if object already exists before attempting to create
    if [[ $(check_object_exists "$object_type" "$object_name") == "true" ]]; then
        log_info "$description already exists. Skipping."
        return 0
    fi
    
    log_info "Creating $object_type: $object_name"
    
    # Validate JSON syntax
    # The 'empty' filter reads the JSON input and produces no output if the JSON is valid, exiting with status 0.
    # If the JSON is invalid, 'jq' prints an error message to its stderr and exits with a non-zero status.
    # If 'jq empty' exits non-zero (JSON invalid), '!' makes it 0 (condition true), so the 'then' block executes. To avoide else statments.
    if ! echo "$json_data" | jq empty 2>/dev/null; then
        log_error "Invalid JSON for $object_type '$object_name'"
        return 1
    fi
    
    if icingacli director "$object_type" create --json "$json_data"; then
        log_success "$description created successfully"
        return 0
    else
        log_error "Failed to create $description"
        return 1
    fi
}

# --- Template Creation Functions ---

create_timeperiod_template() {
    log_info "Checking generic timeperiod template..."
    
    if [[ $(check_object_exists "timeperiod" "$GENERIC_TIMEPERIOD_TEMPLATE") == "true" ]]; then
        log_info "Generic timeperiod template already exists. Skipping."
        return 0
    fi
    
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
    
    create_icinga_object "timeperiod" "$json_data" "$GENERIC_TIMEPERIOD_TEMPLATE" "Generic timeperiod template"
}

create_user_template() {
    log_info "Checking generic user template..."
    
    if [[ $(check_object_exists "user" "$GENERIC_USER_TEMPLATE") == "true" ]]; then
        log_info "Generic user template already exists. Skipping."
        return 0
    fi
    
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
}

create_agent_template() {
    log_info "Checking generic agent template..."
    
    if [[ $(check_object_exists "host" "$GENERIC_AGENT_TEMPLATE") == "true" ]]; then
        log_info "Generic agent template already exists. Skipping."
        return 0
    fi
    
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
    
    create_icinga_object "host" "$json_data" "$GENERIC_AGENT_TEMPLATE" "Generic agent template"
}

create_check_disk_template() {
    log_info "Checking check_disk service template..."
    
    if [[ $(check_object_exists "service" "$GENERIC_CHECK_DISK_TEMPLATE") == "true" ]]; then
        log_info "Check_disk service template already exists. Skipping."
        return 0
    fi
    
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
    
    create_icinga_object "service" "$json_data" "$GENERIC_CHECK_DISK_TEMPLATE" "Check_disk service template"
}

# --- Notification Template Functions ---

create_notification_templates() {
    log_info "Creating notification templates..."
    
    # Host notification template
    if [[ $(check_object_exists "notification" "$GENERIC_HOST_NOTIFICATION_TEMPLATE") != "true" ]]; then
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
                "display_name": "ICINGA-HB-INTERN"
            }
        }'
        create_icinga_object "notification" "$host_notification_json" "$GENERIC_HOST_NOTIFICATION_TEMPLATE" "Host notification template"
    fi
    
    # Service notification template
    if [[ $(check_object_exists "notification" "$GENERIC_SERVICE_NOTIFICATION_TEMPLATE") != "true" ]]; then
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
                "display_name": "ICINGA-HB-INTERN"
            }
        }'
        create_icinga_object "notification" "$service_notification_json" "$GENERIC_SERVICE_NOTIFICATION_TEMPLATE" "Service notification template"
    fi
}

# --- Host Group Creation Functions ---

create_hostgroups() {
    log_info "Creating host groups..."
    
    local hostgroups=(
        "$PROJECT_HOSTGROUP:Project host group"
        "$K8S_MASTERS_HOSTGROUP:K8s masters host group"
        "$K8S_WORKERS_HOSTGROUP:K8s workers host group"
        "$K8S_SINGLE_NODE_HOSTGROUP:K8s single-node host group"
    )
    
    for hostgroup_info in "${hostgroups[@]}"; do
        local hostgroup_name="${hostgroup_info%:*}"
        local description="${hostgroup_info#*:}"
        
        if [[ $(check_object_exists "hostgroup" "$hostgroup_name") != "true" ]]; then
            local json_data='{
                "object_name": "'"$hostgroup_name"'",
                "object_type": "object",
                "display_name": "'"$hostgroup_name"'"
            }'
            create_icinga_object "hostgroup" "$json_data" "$hostgroup_name" "$description"
        else
            log_info "$description already exists. Skipping."
        fi
    done
}

# --- Project Object Creation Functions ---

create_project_timeperiod() {
    log_info "Creating project timeperiod..."
    
    local json_data='{
        "object_name": "'"$PROJECT_TIMEPERIOD"'",
        "object_type": "object",
        "imports": ["'"$GENERIC_TIMEPERIOD_TEMPLATE"'"],
        "display_name": "'"$PROJECT_TIMEPERIOD"'"
    }'
    
    create_icinga_object "timeperiod" "$json_data" "$PROJECT_TIMEPERIOD" "Project timeperiod" || log_warn "Failed to create project timeperiod"
}

create_project_usergroup() {
    log_info "Creating project user group..."
    
    if [[ $(check_object_exists "usergroup" "$PROJECT_USERGROUP") == "true" ]]; then
        log_info "Project user group already exists. Skipping."
        return 0
    fi
    
    local json_data='{
        "object_name": "'"$PROJECT_USERGROUP"'",
        "object_type": "object",
        "display_name": "'"$PROJECT_USERGROUP"'"
    }'
    
    create_icinga_object "usergroup" "$json_data" "$PROJECT_USERGROUP" "Project user group" || log_warn "Failed to create project user group"
}

# Check if user is member of a specific usergroup
check_user_in_usergroup() {
    local username="$1"
    local usergroup="$2"
    
    log_info "Checking if user '$username' is member of usergroup '$usergroup'..."
    
    local query="SELECT u.object_name AS user_member_name 
                 FROM director.icinga_user AS u 
                 JOIN director.icinga_usergroup_user AS ugu ON u.id = ugu.user_id 
                 JOIN director.icinga_usergroup AS ug ON ugu.usergroup_id = ug.id 
                 WHERE ug.object_name = '$usergroup';"
    
    # Prevent the script to exit with "|| true'" if the sql query is wrong 
    local result=$(mysql -e "$query" | grep -w "$username" || true)
    
    if [[ -n "$result" ]]; then
        log_info "User '$username' is already member of usergroup '$usergroup'"
        return 0
    else
        log_info "User '$username' is not member of usergroup '$usergroup'"
        return 1
    fi
}

# Get current usergroups for a user
get_user_groups() {
    local username="$1"
    
    log_info "Getting current usergroups for user '$username'..."
    
    local query="SELECT ug.object_name 
                 FROM director.icinga_usergroup AS ug
                 JOIN director.icinga_usergroup_user AS ugu ON ug.id = ugu.usergroup_id
                 JOIN director.icinga_user AS u ON ugu.user_id = u.id
                 WHERE u.object_name = '$username';"
    
    local groups=$(mysql -e "$query" --skip-column-names | tr '\n' ',' | sed 's/,$//')
    echo "$groups"
}

# Add user to usergroup (preserving existing usergroups of this user)
add_user_to_usergroup() {
    local username="$1"
    local new_usergroup="$2"
    
    log_info "Adding user '$username' to usergroup '$new_usergroup'..."
    
    # Get current groups
    local current_groups=$(get_user_groups "$username")
    
    if [[ -z "$current_groups" ]]; then
        log_info "User has no current groups, adding only '$new_usergroup'"
        local groups_array="[\"$new_usergroup\"]"
    else
        log_info "Current groups: [ $current_groups ]"
        
        # Convert comma-separated groups to JSON array format
        local groups_array="["
        IFS=',' read -ra GROUP_ARRAY <<< "$current_groups"
        for i in "${!GROUP_ARRAY[@]}"; do
            if [[ $i -gt 0 ]]; then
                groups_array+=", "
            fi
            groups_array+="\"${GROUP_ARRAY[$i]}\""
        done
        groups_array+=", \"$new_usergroup\"]"
    fi
    
    log_info "Setting groups for user '$username': $groups_array"
    
    local json_data="{\"groups\": $groups_array}"
    
    if icingacli director user set "$username" --json "$json_data"; then
        log_success "Successfully added user '$username' to usergroup '$new_usergroup'"
        return 0
    else
        log_error "Failed to add user '$username' to usergroup '$new_usergroup'"
        return 1
    fi
}

# Process a single user (create or update usergroup membership)
process_user() {
    local name="$1"
    local display="$2"
    local email="$3"
    local project_usergroup="$4"
    local generic_template="$5"
    local project_timeperiod="$6"
    
    log_info "Processing user: $name ($display, $email)"
    
    # Check if user exists
    if [[ $(check_object_exists "user" "$name") == "true" ]]; then
        log_info "User '$name' already exists."
        
        # Check if user is already in the project usergroup
        if check_user_in_usergroup "$name" "$project_usergroup"; then
            log_info "Skipping to next user"
            return 0
        else
            add_user_to_usergroup "$name" "$project_usergroup"
            return $?
        fi
    else
        log_info "User '$name' does not exist. Creating new user..."
        
        local json_data='{
            "object_name": "'"$name"'",
            "object_type": "object",
            "groups": ["'"$project_usergroup"'"],
            "imports": ["'"$generic_template"'"],
            "display_name": "'"$display"'",
            "email": "'"$email"'",
            "enable_notifications": true,
            "period": "'"$project_timeperiod"'",
            "states": ["Critical", "Down", "Up", "Unknown", "Warning", "OK"],
            "types": ["Acknowledgement", "Custom", "DowntimeEnd", "DowntimeRemoved", "DowntimeStart", "Problem", "Recovery"]
        }'
        
        if create_icinga_object "user" "$json_data" "$name" "User $name"; then
            log_success "User '$name' created and configured for project notifications"
            return 0
        else
            log_error "Failed to create user '$name'"
            return 1
        fi
    fi
}

# Create project users with all its needed checks
create_project_users() {
    log_info "Creating/updating project users..."
    
    local success_count=0
    local total_count=${#USER_NAMES[@]}
    
    for i in "${!USER_NAMES[@]}"; do
        local name="${USER_NAMES[$i]}"
        local display="${DISPLAY_NAMES[$i]}"
        local email="${EMAILS[$i]}"
        
        if process_user "$name" "$display" "$email" "$PROJECT_USERGROUP" "$GENERIC_USER_TEMPLATE" "$PROJECT_TIMEPERIOD"; then
            success_count=$((success_count + 1))
        fi
    done
    
    log_info "User processing completed: $success_count/$total_count users processed successfully"
    
    if [[ $success_count -eq $total_count ]]; then
        log_success "All users processed successfully"
        return 0
    else
        log_warn "Some users failed to process correctly"
        return 1
    fi
}

# --- Node Management Functions ---

get_node_hostgroups() {
    local address="$1"
    local hostgroups=("$PROJECT_HOSTGROUP")
    
    case "$address" in
        *master*) hostgroups+=("$K8S_MASTERS_HOSTGROUP") ;;
        *worker*) hostgroups+=("$K8S_WORKERS_HOSTGROUP") ;;
        *k3s*)    hostgroups+=("$K8S_SINGLE_NODE_HOSTGROUP") ;;
        *)        return 1 ;;  # Unknown node type
    esac
    
    printf '%s\n' "${hostgroups[@]}"
}

# This is going to be used inside host.notes to tell check_disk if a node has an sdb or not 
get_node_sdb_status() {
    local address="$1"
    
    case "$address" in
        *master*) echo "$NODE_SDB_FALSE" ;;
        *worker*|*k3s*) echo "$NODE_SDB_TRUE" ;;
        *) return 1 ;;
    esac
}

create_project_agents() {
    log_info "Creating project agents..."
    
    for i in "${!PROJECT_NODES_ADDRESS[@]}"; do
        local address="${PROJECT_NODES_ADDRESS[$i]}"
        local display="${PROJECT_NODES_DISPLAY_NAME[$i]}"
        
        log_info "Processing Node: $address ($display)"
        
        local hostgroups_array
        if ! hostgroups_array=($(get_node_hostgroups "$address")); then
            log_warn "Unknown node type for '$address'. Skipping."
            continue
        fi
        
        local sdb_status
        if ! sdb_status=$(get_node_sdb_status "$address"); then
            log_warn "Cannot determine SDB status for '$address'. Skipping."
            continue
        fi
        
        # Build hostgroups JSON array
        local hostgroups_json=""
        for group in "${hostgroups_array[@]}"; do
            hostgroups_json+="\"$group\","
        done
        hostgroups_json="[${hostgroups_json%,}]"  # Remove trailing comma and wrap
        
        local json_data='{
            "object_name": "'"$address"'",
            "object_type": "object",
            "address": "'"$address"'",
            "groups": '"$hostgroups_json"',
            "zone": '"$address"',
            "notes": "'"$sdb_status"'",
            "imports": ["'"$GENERIC_AGENT_TEMPLATE"'"],
            "display_name": "'"$display"'"
        }'
        
        if create_icinga_object "host" "$json_data" "$address" "Node $address"; then
            log_info "Node '$address' belongs to hostgroups: $hostgroups_json"
        else
            log_warn "Failed to create node '$address'"
        fi
    done
}

# --- Service Creation Functions ---

create_disk_check_services() {
    log_info "Creating disk check services..."
    
    # Service for nodes with SDB
    local sda_sdb_json='{
        "object_name": "'"$CHECK_DISK_SDA_SDB"'",
        "object_type": "apply",
        "imports": ["'"$GENERIC_CHECK_DISK_TEMPLATE"'"],
        "assign_filter": "host.notes = \"'"$NODE_SDB_TRUE"'\"",
        "vars": {
            "disk_partition": "/",
            "disk_partitions": "/dev/sdb1"
        }
    }'
    
    create_icinga_object "service" "$sda_sdb_json" "$CHECK_DISK_SDA_SDB" "Disk check service (SDA+SDB)" || log_warn "Failed to create SDA+SDB disk check service"
    
    # Service for nodes without SDB
    local sda_json='{
        "object_name": "'"$CHECK_DISK_SDA"'",
        "object_type": "apply",
        "imports": ["'"$GENERIC_CHECK_DISK_TEMPLATE"'"],
        "assign_filter": "host.notes = \"'"$NODE_SDB_FALSE"'\"",
        "vars": {
            "disk_partition": "/"
        }
    }'
    
    create_icinga_object "service" "$sda_json" "$CHECK_DISK_SDA" "Disk check service (SDA only)" || log_warn "Failed to create SDA disk check service"
}

create_project_notifications() {
    log_info "Creating project notifications..."
    
    # Host notification
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
    
    create_icinga_object "notification" "$host_notification_json" "$PROJECT_HOST_NOTIFICATION" "Project host notification" || log_warn "Failed to create host notification"
    
    # Service notification
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
    
    create_icinga_object "notification" "$service_notification_json" "$PROJECT_SERVICE_NOTIFICATION" "Project service notification" || log_warn "Failed to create service notification"
}

# --- Deployment Function ---

deploy_configuration() {
    log_info "Deploying configuration..."
    
    if icingacli director config deploy; then
        log_success "Configuration deployed successfully"
        return 0
    else
        log_error "Failed to deploy Icinga Director configuration"
        return 1
    fi
}

# --- Main Execution ---

main() {
    log_info "=== Starting Icinga Director Configuration for Project: $PROJECT_NAME ==="
    
    # Validate prerequisites
    validate_prerequisites
    
    # Create generic templates
    log_info "Creating generic templates..."
    create_timeperiod_template
    create_user_template
    create_agent_template
    create_check_disk_template
    create_notification_templates
    
    # Create host groups
    create_hostgroups
    
    # Create project objects
    log_info "Creating project-specific objects..."
    create_project_timeperiod
    create_project_usergroup
    create_project_users
    create_project_notifications
    
    # Create agents and services
    log_info "Creating agents and services..."
    create_project_agents
    create_disk_check_services
    
    # Deploy configuration
    log_info "Finalizing configuration..."
    sleep 3  # Brief pause before deployment
    
    if deploy_configuration; then
        log_success "=== Icinga Director Configuration Complete for Project: $PROJECT_NAME ==="
        log_info "Log file location: $LOG_FILE"
    else
        log_error "=== Configuration deployment failed ==="
        exit 1
    fi
}

# Run main function
main "$@"