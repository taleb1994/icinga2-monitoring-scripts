#!/bin/bash

# =============================================================================
# Icinga Director Configuration Script - Zones Module
# Description: This module configures Icinga2 zones for a given project.
# =============================================================================

# This file is meant to be sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# Configure Icinga2 zones for a project
configure_project_icinga_zones() {
    log_info "Starting Icinga2 zone configuration for project: $PROJECT_NAME..."

    local ZONES_CONF="/etc/icinga2/zones.conf"
    local PROJECT_ZONES_DIR="/etc/icinga2/zones.d/$PROJECT_NAME"

    # Configure global zone for the project in zones.conf
    log_info "Checking/Configuring global zone '$PROJECT_NAME' in $ZONES_CONF..."
    
    if ! grep -qE "^\s*object\s+Zone\s+\"$PROJECT_NAME\"\s*\{" "$ZONES_CONF"; then
        log_info "Adding Zone object for '$PROJECT_NAME' to $ZONES_CONF."
        
        local temp_zones_update
        temp_zones_update=$(mktemp)
        printf "\n//-- Zone for project %s - Added by script on %s --//\nobject Zone \"%s\" {\n    global = true\n}\n" \
            "$PROJECT_NAME" "$(date)" "$PROJECT_NAME" > "$temp_zones_update"

        if tee -a "$ZONES_CONF" < "$temp_zones_update" > /dev/null; then
            log_success "Successfully added Zone object for '$PROJECT_NAME' to $ZONES_CONF."
        else
            log_error "Failed to add Zone object for '$PROJECT_NAME' to $ZONES_CONF. Check permissions and file."
            rm "$temp_zones_update"
            return 1
        fi
        rm "$temp_zones_update"
    else
        log_info "Zone object for '$PROJECT_NAME' already exists in $ZONES_CONF."
    fi
    
    # Check if include_recursive line for this project exists at end of file
    log_info "Ensuring project '$PROJECT_NAME' has include_recursive at end of $ZONES_CONF..."
    
    local project_name_quoted="\"$PROJECT_NAME\""  # e.g., "c2vba-d" formatted for inclusion
    
    if ! tail -n 20 "$ZONES_CONF" | grep -qE "include_recursive\s+\"zones.d\"[^;]*$project_name_quoted"; then
        log_info "Adding include_recursive line for '$PROJECT_NAME' to end of file."
        
        # Add new include_recursive line at the end
        printf "\n//-- Include zones.d for project %s - Added by script on %s --//\ninclude_recursive \"zones.d\", %s\n" \
            "$PROJECT_NAME" "$(date)" "$project_name_quoted" >> "$ZONES_CONF"
    else
        log_info "include_recursive line for '$PROJECT_NAME' already exists in $ZONES_CONF."
    fi

    # Node-specific configurations
    if [[ ${#PROJECT_NODES_ADDRESS[@]} -eq ${#PROJECT_NODES_IPS[@]} ]]; then
        log_info "Creating project zone directory: $PROJECT_ZONES_DIR..."
        if mkdir -p "$PROJECT_ZONES_DIR"; then
            log_success "Directory $PROJECT_ZONES_DIR created/ensured."
        else
            log_error "Failed to create directory $PROJECT_ZONES_DIR. Check permissions." 
            return 1
        fi

        log_info "Creating/Updating node configuration files in $PROJECT_ZONES_DIR..."
        local i
        for i in "${!PROJECT_NODES_ADDRESS[@]}"; do
            local node_addr="${PROJECT_NODES_ADDRESS[i]}"
            local node_ip="${PROJECT_NODES_IPS[i]}"
            local node_conf_file="$PROJECT_ZONES_DIR/${node_addr}.conf"

            log_info "Processing config for node $node_addr (IP: $node_ip) -> $node_conf_file"
            
            local temp_node_conf
            temp_node_conf=$(mktemp)
            cat << EOF > "$temp_node_conf"
//-- Node: ${node_addr} --//
//-- IP: ${node_ip} --//
//-- Configured by script for project ${PROJECT_NAME} on $(date) --//

object Endpoint "${node_addr}" {
    host = "${node_ip}"
    port = 5665
    log_duration = 0s
}

object Zone "${node_addr}" {
    parent = "master" // Assumes nodes are direct satellites/agents of 'master'.
    endpoints = [ "${node_addr}" ]
}
EOF
            if cp "$temp_node_conf" "$node_conf_file"; then
                log_success "Successfully created/updated $node_conf_file."
            else
                log_error "Failed to create/update $node_conf_file. Check permissions."
                rm "$temp_node_conf" # Still remove temp file on error
                return 1
            fi
            rm "$temp_node_conf"
        done

        log_info "Setting ownership for $PROJECT_ZONES_DIR and its contents to nagios:nagios..."
        
        if chown -R nagios:nagios "$PROJECT_ZONES_DIR"; then
            log_success "Ownership set for $PROJECT_ZONES_DIR."
        else
            log_error "Failed to set ownership for $PROJECT_ZONES_DIR. Check user 'nagios' exists and permissions."
            return 1
        fi
    else
        log_warn "Skipping node-specific zone directory creation and file generation due to missing/invalid node addresses/IPs."
    fi

    log_info "Icinga2 zone configuration for project $PROJECT_NAME processing completed."
    log_success "Review $ZONES_CONF and files in $PROJECT_ZONES_DIR. Validate Icinga2 config (icinga2 daemon -C) and reload/restart service if changes were made."
    return 0
}