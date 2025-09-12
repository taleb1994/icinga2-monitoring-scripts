#!/bin/bash

# =============================================================================
# Icinga Director Configuration Script - Project Configuration
# =============================================================================

# --- Script Setup ---
# This file is meant to be sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# --- Name ---
declare -r PROJECT_NAME="c2vba-p"

# --- Notifications ---
declare -r PROJECT_TIMEPERIOD="${PROJECT_NAME}-24x7"
declare -r PROJECT_USERGROUP="${PROJECT_NAME}-usergroup"
declare -r PROJECT_HOST_NOTIFICATION="${PROJECT_NAME}-24x7-host-notifications"
declare -r PROJECT_SERVICE_NOTIFICATION="${PROJECT_NAME}-24x7-services-notifications"

# --- Hostgroup ---
declare -r PROJECT_HOSTGROUP="${PROJECT_NAME}-nodes"

# --- Nodes ---
declare -ra PROJECT_NODES_ADDRESS=(
    "master1.p.c2vba.heuboe.hbintern"
    "worker1.p.c2vba.heuboe.hbintern"
    "worker2.p.c2vba.heuboe.hbintern"
    "worker3.p.c2vba.heuboe.hbintern"
)

declare -ra PROJECT_NODES_IPS=(
    "10.66.6.101"
    "10.66.6.111"
    "10.66.6.112"
    "10.66.6.113"
)

declare -ra PROJECT_NODES_DISPLAY_NAME=(
    "${PROJECT_NAME}-master1"
    "${PROJECT_NAME}-worker1"
    "${PROJECT_NAME}-worker2"
    "${PROJECT_NAME}-worker3"
)

# --- Users ---
declare -ra USER_DISPLAY_NAMES=(
    "M.T."
    "V.H."
    "A.G."
    "W.S."
    "A.H."
)

declare -ra USER_NAMES=(
    "mohammed-taleb"
    "vera-hermanns"
    "andrzej-grala"
    "wladislaw-schmidt"
    "andrea-haug"
)

declare -ra USER_EMAILS=(
    "mohammed.taleb@heuboe.de"
    "vera.hermanns@heuboe.de"
    "andrzej.grala@heuboe.de"
    "wladislaw.schmidt@heuboe.de"
    "andrea.haug@heuboe.de"
)