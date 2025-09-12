#!/bin/bash

# Configuration directory
CONF_DIR="conf"
PROJECTS_CONF_DIR="project-agents-conf"

# Check if conf directory exists
if [ ! -d "$CONF_DIR" ]; then
    echo "Error: Configuration directory '$CONF_DIR' not found!"
    echo "Creating empty directory..."
    mkdir -p "$CONF_DIR"
    echo "Please add configuration files to $CONF_DIR/ and run again."
    exit 1
fi

# Get list of configuration files
config_files=("$CONF_DIR"/*.conf)
if [ ${#config_files[@]} -eq 0 ] || [ ! -f "${config_files[0]}" ]; then
    echo "Error: No .conf files found in $CONF_DIR/"
    echo "Please add configuration files (e.g., project1.conf, project2.conf) to $CONF_DIR/"
    exit 1
fi

# Present numbered list of configuration files
echo "Available configuration files:"
echo "=============================="
for i in "${!config_files[@]}"; do
    filename=$(basename "${config_files[$i]}")
    echo "$((i+1)). $filename"
done
echo "0. Exit"

# Get user selection
read -p "Select a configuration file (number): " selection

# Validate selection
if [[ ! "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 0 ] || [ "$selection" -gt "${#config_files[@]}" ]; then
    echo "Invalid selection. Exiting."
    exit 1
fi

if [ "$selection" -eq 0 ]; then
    echo "Exiting."
    exit 0
fi

# Get selected config file
CONFIG_FILE="${config_files[$((selection-1))]}"
CONFIG_BASENAME=$(basename "$CONFIG_FILE" .conf)
echo "Selected: $CONFIG_BASENAME"
echo "=============================="

# Load the configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file $CONFIG_FILE not found!"
    exit 1
fi

source "$CONFIG_FILE"

# Validate required variables
if [ -z "${DOMAIN_S[*]}" ] || [ -z "${NODES[*]}" ] || [ -z "$TLD" ]; then
    echo "Error: Configuration file missing required variables (DOMAIN_S, NODES, or TLD)"
    exit 1
fi

# Check if project-agents-conf directory exists
if [ ! -d "$PROJECTS_CONF_DIR" ]; then
    echo "INFO: Project related directory '$PROJECTS_CONF_DIR/$PROJECT' not found!"
    echo "Creating directory $PROJECTS_CONF_DIR/$PROJECT ..."
    mkdir -p "$PROJECTS_CONF_DIR/$PROJECT"
fi

# Create project-specific output filename
OUTPUT_FILE="${PROJECTS_CONF_DIR}/${PROJECT}/${PROJECT}_agents.txt"

# Main
echo "Starting host discovery with configuration from $CONFIG_FILE"
echo "Domains: ${DOMAIN_S[*]}"
echo "Nodes: ${NODES[*]}"
echo "TLD: $TLD"
echo "Output file: $OUTPUT_FILE"
echo "=========================================="

> "$OUTPUT_FILE"
reachable_count=0
unreachable_count=0

for domain in "${DOMAIN_S[@]}"; do
    echo "Checking domain: $domain"

    for node_pattern in "${NODES[@]}"; do
        # Expand brace patterns (kafka{1..3} becomes kafka1 kafka2 kafka3)
        for node in $(eval echo "$node_pattern"); do
            if [[ "$domain" == *.* ]]; then
                host="${node}.${domain}.${TLD}"
            fi
            
            # Not needed when compining with other scripts
            # printf "Testing %-60s" "$host"

            if ping -c 1 -W 1 "$host" &>/dev/null; then
                # echo "✓ REACHABLE"
                echo "$host" >> "$OUTPUT_FILE"
                ((reachable_count++))
            else
                # echo "✗ unreachable"
                ((unreachable_count++))
            fi
        done
    done
    echo
done

echo "=========================================="
echo "Found $reachable_count reachable hosts"
echo "Results saved to $OUTPUT_FILE"
