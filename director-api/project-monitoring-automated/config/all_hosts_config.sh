#!/bin/bash

# =============================================================================
# Icinga Director Configuration Script - Common Config Used For All Hosts
# =============================================================================

# --- Script Setup ---
# This file is meant to be sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# --- Logging Configuration ---
readonly LOG_FILE="/var/log/icinga-director-setup-script.log"

# --- Generic Notifications Templates ---
declare -r GENERIC_TIMEPERIOD_TEMPLATE="generic-24x7-template"
declare -r GENERIC_USER_TEMPLATE="generic-user-template"
declare -r GENERIC_HOST_NOTIFICATION_TEMPLATE="generic-24x7-host-notifications-template"
declare -r GENERIC_SERVICE_NOTIFICATION_TEMPLATE="generic-24x7-services-notifications-template"

# --- Generic Master/Agent Templates ---
declare -r GENERIC_MASTER_TEMPLATE="icinga-master-template"
declare -r GENERIC_AGENT_TEMPLATE="icinga-agent-template"

# --- Generic Host Groups ---
declare -r K8S_MASTERS_HOSTGROUP="k8s-masters-hostgroup"
declare -r K8S_WORKERS_HOSTGROUP="k8s-workers-hostgroup"
declare -r K8S_SINGLE_NODE_HOSTGROUP="k8s-single-node-hostgroup"

# --- Generic Services Templates ---
declare -r GENERIC_CHECK_DISK_TEMPLATE="check-disk-template"
declare -r GENERIC_CHECK_MEMORY_TEMPLATE="check-memory-template"
declare -r GENERIC_CHECK_CPU_TEMPLATE="check-cpu-template"

# --- Apply Check Disk For All Hosts ---
# service check_disk is to relay on host.notes, since disk configuration vary from one cluster to another
declare -r CHECK_DISK_SDA_SDB_SERVICE_NAME="check-disk-sda-sdb"
declare -r CHECK_DISK_SDA_SERVICE_NAME="check-disk-sda"
# during agent creation, a note must be added to guide check_disk 
declare -r NODE_SDB_TRUE_NOTES="node has sdb: true"
declare -r NODE_SDB_FALSE_NOTES="node has sdb: false"

# --- Apply Check CPU & Memory For All Hosts ---
declare -r CHECK_MEMORY_SERVICE_NAME="check-memory"
declare -r CHECK_CPU_SERVICE_NAME="check-cpu"