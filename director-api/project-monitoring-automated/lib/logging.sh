#!/bin/bash

# =============================================================================
# Icinga Director Configuration Script - Logging Library
# =============================================================================

# This file is meant to be sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# Ensure LOG_FILE is set (should be sourced from all_hosts_config.sh)
: "${LOG_FILE:?LOG_FILE is not set. Source main_config.sh first.}"
# Note: Redirection of stdout/stderr to the log file and terminal (via tee) is handled in the main script (icinga_setup.sh)

# Generic log function
# Arguments:
#   $1 (level): The log level string (e.g., "INFO", "ERROR").
#   $@ (message): The rest of the arguments are treated as the log message.
log() {
    local level="$1" # Store the first argument (log level) in a local variable.
    shift            # Remove the first argument ($level) from the list of positional parameters.

    # Print the formatted log message to standard error (stderr).
    # Stderr is used so that log messages don't interfere with potential stdout data
    # a command might produce. The main script redirects stderr to tee.
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] [$SCRIPT_NAME] $*" >&2
}

# Convenience wrapper functions for different log levels.
# "$@" passes all arguments received by these wrappers directly as the message to the 'log' function.
log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_success() { log "SUCCESS" "$@"; }