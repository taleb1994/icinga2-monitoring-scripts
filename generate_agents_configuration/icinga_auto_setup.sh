#!/bin/bash

# ==============================================================================
# Icinga2 Master/Agent Automated Setup Script
#
# This script automates the setup process for an Icinga2 monitoring environment.
# It can be run in two modes:
# 1. Master Mode: Discovers agents, creates configurations and tickets,
#    and pushes them to a Git repository.
# 2. Agent Mode: Pulls configuration from Git, installs Icinga2,
#    and configures itself to connect to the master.
#
# ==============================================================================

# --- Configuration ---
# Directory for project-specific host discovery configurations
CONF_DIR="conf"
# Directory where generated agent configurations will be stored
PROJECTS_CONF_DIR="project-agents-conf"
# Local directory for the Git repository clone
# GIT_REPO_DIR="icinga-config-repo"


# --- Helper Functions ---
# Print a formatted header message
print_header() {
    echo "=============================================================================="
    echo "  $1"
    echo "=============================================================================="
}

# Print a success message
print_success() {
    echo -e "\e[32m[SUCCESS]\e[0m $1"
}

# Print an error message and exit
print_error() {
    echo -e "\e[31m[ERROR]\e[0m $1" >&2
    exit 1
}

# Print an informational message
print_info() {
    echo -e "\e[34m[INFO]\e[0m $1"
}

# --- Master Functions ---

# 1. DISCOVER HOSTS
# Runs the host discovery process based on a selected configuration file.
discover_hosts() {
    print_header "Host Discovery"

    # Check if conf directory exists
    if [ ! -d "$CONF_DIR" ]; then
        print_info "Configuration directory '$CONF_DIR' not found. Creating it."
        mkdir -p "$CONF_DIR"
        print_error "Please add project configuration files to $CONF_DIR/ and run again."
    fi

    # Get list of configuration files
    local config_files=("$CONF_DIR"/*.conf)
    if [ ${#config_files[@]} -eq 0 ] || [ ! -f "${config_files[0]}" ]; then
        print_error "No .conf files found in $CONF_DIR/. Please create one."
    fi

    # Present numbered list of configuration files
    echo "Available project configuration files:"
    for i in "${!config_files[@]}"; do
        local filename
        filename=$(basename "${config_files[$i]}")
        echo "$((i+1)). $filename"
    done
    echo "0. Exit"

    # Get user selection
    read -p "Select a configuration file (number): " selection
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 0 ] || [ "$selection" -gt "${#config_files[@]}" ]; then
        print_error "Invalid selection. Exiting."
    fi
    [ "$selection" -eq 0 ] && { echo "Exiting."; exit 0; }

    # Get selected config file and load it
    CONFIG_FILE="${config_files[$((selection-1))]}"
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    PROJECT_CONF_DIR="${PROJECTS_CONF_DIR}/${PROJECT}"
    AGENT_LIST_FILE="${PROJECT_CONF_DIR}/${PROJECT}_agents.txt"

    # Validate required variables
    if [ -z "${DOMAIN_S[*]}" ] || [ -z "${NODES[*]}" ] || [ -z "$TLD" ]; then
        print_error "Config file missing required variables (DOMAIN_S, NODES, or TLD)."
    fi

    print_info "Creating project directory: $PROJECT_CONF_DIR"
    mkdir -p "$PROJECT_CONF_DIR"

    print_info "Starting host discovery with configuration from $(basename "$CONFIG_FILE")"
    echo "Output file: $AGENT_LIST_FILE"
    echo "------------------------------------------"

    > "$AGENT_LIST_FILE"
    local reachable_count=0
    local unreachable_count=0

    for domain in "${DOMAIN_S[@]}"; do
        print_info "Checking domain: $domain"
        for node_pattern in "${NODES[@]}"; do
            # Expand brace patterns (e.g., kafka{1..3})
            for node in $(eval echo "$node_pattern"); do
                local host="${node}.${domain}.${TLD}"
                printf "  Testing %-60s" "$host"
                if ping -c 1 -W 1 "$host" &>/dev/null; then
                    echo -e "\e[32m✓ REACHABLE\e[0m"
                    echo "$host" >> "$AGENT_LIST_FILE"
                    ((reachable_count++))
                else
                    echo -e "\e[31m✗ UNREACHABLE\e[0m"
                    ((unreachable_count++))
                fi
            done
        done
    done

    echo "------------------------------------------"
    print_success "Discovery complete. Found $reachable_count reachable hosts."
    echo "Results saved to $AGENT_LIST_FILE"
}

# 2. GENERATE AGENT CONFIGURATIONS
# Creates a setup script for each agent discovered.
generate_agent_configs() {
    print_header "Generate Agent Configurations"

    local icinga_master_fqdn
    local icinga_master_ip
    icinga_master_fqdn=$(cat /etc/hostname)
    icinga_master_ip=$(hostname -I | awk '{print $1}')

    if [ -z "$icinga_master_fqdn" ] || [ -z "$icinga_master_ip" ]; then
        print_error "Could not determine master FQDN or IP address."
    fi
    print_info "Master FQDN: $icinga_master_fqdn"
    print_info "Master IP: $icinga_master_ip"

    # Generate trusted certificate for agents
    local TRUSTED_CERT_PATH="${PROJECT_CONF_DIR}/trusted-parent.crt"
    local MASTER_TRUSTED_CERT="/var/lib/icinga2/certs/trusted-parent.crt"

    print_info "Checking for existing trusted parent certificate on master..."

    # Check if the trusted certificate exists on the master
    if [ -f "$MASTER_TRUSTED_CERT" ]; then
        print_info "Found existing trusted certificate on master, copying to project directory..."
        if cp "$MASTER_TRUSTED_CERT" "$TRUSTED_CERT_PATH"; then
            print_success "Certificate copied to $TRUSTED_CERT_PATH"
        else
            print_error "Failed to copy trusted certificate from $MASTER_TRUSTED_CERT"
        fi
    else
        print_info "No existing trusted certificate found, generating new one..."
        # Generate and save the trusted certificate
        if icinga2 pki save-cert --trustedcert "$MASTER_TRUSTED_CERT" --host "$icinga_master_fqdn"; then
            # Copy the newly created certificate to project directory
            if cp "$MASTER_TRUSTED_CERT" "$TRUSTED_CERT_PATH"; then
                print_success "Certificate generated and saved to $TRUSTED_CERT_PATH"
            else
                print_error "Failed to copy newly generated certificate to $TRUSTED_CERT_PATH"
            fi
        else
            print_error "Failed to generate trusted certificate."
        fi
    fi

    # Loop through each reachable agent and create its config
    while IFS= read -r node_fqdn; do
        if [ -n "$node_fqdn" ]; then
            print_info "Generating config for agent: $node_fqdn"
            local node_conf_script="${PROJECT_CONF_DIR}/${node_fqdn}_conf.sh"
            
            # Generate a new ticket for the node
            local ticket
            ticket=$(icinga2 pki ticket --cn "$node_fqdn" 2>/dev/null)
            if [ -z "$ticket" ]; then
                print_error "Failed to generate ticket for $node_fqdn. Check Icinga2 logs."
                continue
            fi
            
            # Create the agent setup script using a heredoc
            cat > "$node_conf_script" <<EOF
#!/bin/bash
echo "--- Running Icinga Agent Setup for ${node_fqdn} ---"

# Stop Icinga2 if running to prevent issues
systemctl stop icinga2

# Run the node setup command
icinga2 node setup \\
--ticket ${ticket} \\
--listen 0.0.0.0,5665 \\
--cn ${node_fqdn} \\
--zone ${node_fqdn} \\
--endpoint ${icinga_master_fqdn},${icinga_master_ip} \\
--parent_zone master \\
--parent_host ${icinga_master_fqdn} \\
--trustedcert /var/lib/icinga2/certs/trusted-parent.crt \\
--accept-config \\
--accept-commands \\
--disable-confd

if [ \$? -eq 0 ]; then
    echo "Node setup command completed successfully."
else
    echo "Node setup command failed. Please check the output above."
    exit 1
fi
EOF
            chmod +x "$node_conf_script"
            print_success "Configuration script created: $node_conf_script"
        fi
    done < "$AGENT_LIST_FILE"
}

# 3. PUSH CONFIGURATIONS TO GIT
# Commits and pushes the generated configurations to a remote repository.
push_to_git() {
    print_header "Push Configurations to Git"
    # read -p "Enter the Git repository URL (e.g., git@github.com:user/repo.git): " GIT_REPO_URL
    
    # Hardcoded Repo. Uncomment above line to make it dynamic.
    GIT_REPO_URL="git@github.com:taleb1994/icinga2-monitoring-scripts.git"

    if [ -z "$GIT_REPO_URL" ]; then
        print_error "Git repository URL cannot be empty."
    fi

    # Commit and push
    print_info "Adding, committing, and pushing changes..."
    git add .
    git commit -m "Automated configuration update for project ${PROJECT} at $(date)"
    git push || print_error "Failed to push to Git repository. Check credentials and permissions."

    print_success "All configurations successfully pushed to the remote repository."
    cd ..
}


# --- Agent Functions ---

# 4. INSTALL ICINGA2 ON AGENT
# Detects OS and installs the Icinga2 package.
install_icinga_agent() {
    print_header "Install Icinga2 Agent"
    if command -v icinga2 &> /dev/null; then
        print_success "Icinga2 is already installed."
        return
    fi

    # shellcheck source=/dev/null
    source /etc/os-release

    if [[ "$ID" == "sles" || "$ID" == "opensuse-leap" ]]; then
        print_info "Detected SUSE-based system. Installing Icinga2..."
        if [[ "$ID" == "sles" ]]; then
            zypper ar https://packages.icinga.com/subscription/sles/ICINGA-release.repo
            SUSEConnect -p PackageHub/"$VERSION_ID"/x86_64
        else
            zypper ar https://packages.icinga.com/openSUSE/ICINGA-release.repo
        fi
        zypper --gpg-auto-import-keys ref
        zypper --non-interactive install icinga2 || print_error "Icinga2 installation failed."

    elif [[ "$ID" == "ubuntu" ]]; then
        print_info "Detected Ubuntu system. Installing Icinga2..."
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get install -y apt-transport-https wget gnupg
        wget -O - https://packages.icinga.com/icinga.key | gpg --dearmor -o /usr/share/keyrings/icinga-archive-keyring.gpg
        DIST=$(lsb_release -c | awk '{print $2}')
        echo "deb [signed-by=/usr/share/keyrings/icinga-archive-keyring.gpg] https://packages.icinga.com/ubuntu icinga-${DIST} main" > /etc/apt/sources.list.d/"${DIST}-icinga.list"
        apt-get update -y
        apt-get install -y icinga2 || print_error "Icinga2 installation failed."
    else
        print_error "Unsupported operating system: $ID. Please install Icinga2 manually."
    fi
    print_success "Icinga2 installed successfully."
}

# 5. CONFIGURE AGENT
# Pulls config from Git and runs the agent-specific setup script.
configure_agent() {
    print_header "Configure Icinga2 Agent"
    
    # Select project
    local project_dirs=("$PROJECTS_CONF_DIR"/*/)
    if [ ${#project_dirs[@]} -eq 0 ]; then
        print_error "No project configurations found in the repository."
    fi

    echo "Available projects:"
    local i=1
    for dir in "${project_dirs[@]}"; do
        echo "$i. $(basename "$dir")"
        ((i++))
    done
    echo "0. Exit"
    read -p "Select the project this agent belongs to: " selection

    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 0 ] || [ "$selection" -gt "${#project_dirs[@]}" ]; then
        print_error "Invalid selection. Exiting."
    fi
    [ "$selection" -eq 0 ] && { echo "Exiting."; exit 0; }
    
    local selected_project_path="${project_dirs[$((selection-1))]}"
    
    # Find and run the agent's config script
    local agent_fqdn
    agent_fqdn=$(cat /etc/hostname)
    local agent_conf_script="${selected_project_path}${agent_fqdn}_conf.sh"

    if [ ! -f "$agent_conf_script" ]; then
        print_error "Configuration script for this host ('$agent_fqdn') not found in project '$(basename "$selected_project_path")'."
    fi

    # Copy master's trusted certificate
    print_info "Copying master certificate..."
    mkdir -p /var/lib/icinga2/certs
    cp "${selected_project_path}trusted-parent.crt" /var/lib/icinga2/certs/trusted-parent.crt || print_error "Failed to copy trusted certificate."
    
    local icinga_owner
    icinga_owner=$(stat -c "%U" /etc/icinga2/icinga2.conf)
    chown -R "$icinga_owner:$icinga_owner" /var/lib/icinga2/certs

    # Execute the configuration script
    print_info "Executing node setup script..."
    bash "$agent_conf_script"

    # Final checks and setup
    print_info "Finalizing agent setup..."
    ll /var/lib/icinga2/certs/
    openssl verify -CAfile /var/lib/icinga2/certs/ca.crt "/var/lib/icinga2/certs/${agent_fqdn}.crt"

    # Enable remote commands
    print_info "Enabling remote command execution..."
    if ! grep -q "include \"conf.d/commands.conf\"" /etc/icinga2/icinga2.conf; then
      echo -e "\n// Added by setup script at $(date)\ninclude \"conf.d/commands.conf\"" >> /etc/icinga2/icinga2.conf
    fi
    icinga2 feature enable command

    # Grant sudo permissions to icinga user
    print_info "Granting sudo permissions to '$icinga_owner' user..."
    echo "$icinga_owner ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/${icinga_owner}-nopasswd"
    chmod 440 "/etc/sudoers.d/${icinga_owner}-nopasswd"
    visudo -c || print_error "Failed to validate sudoers file."
    
    # SUSE specific sudo path fix
    if [[ "$(source /etc/os-release && echo $ID)" == "sles" ]]; then
        if ! grep -q "^Defaults[[:space:]]\+secure_path=.*:/usr/local/bin" /etc/sudoers; then
            sed -i '/^Defaults[[:space:]]\+secure_path=/ s~"$~:/usr/local/bin"~' /etc/sudoers
            print_info "Added /usr/local/bin to secure_path in /etc/sudoers for SUSE."
        fi
    fi
}


# --- Main Execution ---

# Main menu to choose the script's role
main_menu() {
    clear
    print_header "Icinga2 Automated Setup"
    echo "Please choose the role of this machine:"
    echo "1. Icinga Master Server (will discover and configure agents)"
    echo "2. Icinga Agent (will be configured by the master)"
    echo "0. Exit"
    read -p "Enter your choice [1-2]: " choice

    case $choice in
        1)
            # --- MASTER WORKFLOW ---
            print_header "Starting Master Setup"
            if ! icingacli director kickstart required | grep -q "Kickstart configured"; then
                print_error "This does not appear to be a configured Icinga Director master. Please run kickstart manually first."
            fi
            discover_hosts
            generate_agent_configs
            push_to_git
            print_info "Reloading Icinga2 and deploying Director configuration..."
            icinga2 daemon --validate && systemctl reload icinga2
            icingacli director kickstart run && icingacli director config deploy
            print_success "Master setup and configuration push complete."
            ;;
        2)
            # --- AGENT WORKFLOW ---
            print_header "Starting Agent Setup"
            # No need to clone inside the script, since no changes will be made to the repo.
            # read -p "Enter the Git repository URL to pull configurations from: " GIT_REPO_URL
            # if [ -z "$GIT_REPO_URL" ]; then print_error "Git repository URL cannot be empty."; fi

            # if [ ! -d "$GIT_REPO_DIR" ]; then
            #    git clone "$GIT_REPO_URL" "$GIT_REPO_DIR" || print_error "Failed to clone repository."
            # else
            #    cd "$GIT_REPO_DIR" || exit 1
            #    git pull || print_error "Failed to pull from repository."
            #    cd ..
            # fi

            install_icinga_agent
            configure_agent
            
            print_info "Validating configuration and restarting Icinga2..."
            icinga2 daemon --validate && systemctl restart icinga2
            if [ $? -ne 0 ]; then
                print_error "Icinga2 validation failed. Please check logs."
            fi
            print_success "Agent setup and configuration complete."
            ;;
        0)
            echo "Exiting."
            ;;
        *)
            print_error "Invalid option. Please try again."
            ;;
    esac
}

# Run the main menu if the script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_menu
fi
