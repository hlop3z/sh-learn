#!/usr/bin/env bash
#
# errors.sh - Centralized error handling with standardized exit codes
#

# Prevent multiple sourcing
[[ -n "${__ERRORS_SH_LOADED:-}" ]] && return 0
readonly __ERRORS_SH_LOADED=1

# ────────────────────────────────────────────────────────────────
# Exit Codes (standardized)
# ────────────────────────────────────────────────────────────────
readonly EXIT_SUCCESS=0
readonly EXIT_USAGE=1          # Invalid usage / command not found
readonly EXIT_VALIDATION=2     # Validation errors (type mismatch, invalid input)
readonly EXIT_ENVIRONMENT=3    # Missing dependency or environment issue
readonly EXIT_INTERNAL=4       # Internal/unexpected error
readonly EXIT_EXTERNAL=5       # External command failed

# ────────────────────────────────────────────────────────────────
# Error State
# ────────────────────────────────────────────────────────────────
__ERROR_CONTEXT=""
__ERROR_HANDLER_SET=0

# ────────────────────────────────────────────────────────────────
# Error Handler (trap ERR)
# ────────────────────────────────────────────────────────────────
__error_handler() {
    local exit_code=$?
    local line_no="${1:-unknown}"
    local command="${BASH_COMMAND:-unknown}"

    # Avoid recursive error handling
    set +e

    if [[ -n "${__ERROR_CONTEXT}" ]]; then
        printf '\033[1;31mError [%s]: %s\033[0m\n' "${exit_code}" "${__ERROR_CONTEXT}" >&2
    else
        printf '\033[1;31mError [%s]: Command failed at line %s\033[0m\n' "${exit_code}" "${line_no}" >&2
        printf '\033[1;31m  Command: %s\033[0m\n' "${command}" >&2
    fi

    # Call cleanup if defined
    if type __cleanup >/dev/null 2>&1; then
        __cleanup
    fi

    exit "${exit_code}"
}

# ────────────────────────────────────────────────────────────────
# Enable strict mode and error trapping
# ────────────────────────────────────────────────────────────────
enable_strict_mode() {
    set -o errexit
    set -o nounset
    set -o pipefail

    if [[ "${__ERROR_HANDLER_SET}" -eq 0 ]]; then
        trap '__error_handler ${LINENO}' ERR
        __ERROR_HANDLER_SET=1
    fi
}

# ────────────────────────────────────────────────────────────────
# Error functions
# ────────────────────────────────────────────────────────────────

# Set context for next potential error
set_error_context() {
    __ERROR_CONTEXT="$1"
}

# Clear error context
clear_error_context() {
    __ERROR_CONTEXT=""
}

# Print error and exit with code
die() {
    local code="${1:-$EXIT_INTERNAL}"
    shift
    local message="$*"

    printf '\033[1;31mError: %s\033[0m\n' "${message}" >&2
    exit "${code}"
}

# Usage error (invalid command, missing args)
die_usage() {
    die "${EXIT_USAGE}" "$@"
}

# Validation error (type mismatch, invalid value)
die_validation() {
    die "${EXIT_VALIDATION}" "$@"
}

# Environment error (missing dependency)
die_environment() {
    die "${EXIT_ENVIRONMENT}" "$@"
}

# Internal error (unexpected state)
die_internal() {
    die "${EXIT_INTERNAL}" "$@"
}

# External command error
die_external() {
    die "${EXIT_EXTERNAL}" "$@"
}

# ────────────────────────────────────────────────────────────────
# Try/Catch pattern
# ────────────────────────────────────────────────────────────────

# Execute command, capture exit code without triggering ERR trap
try() {
    local result
    set +e
    "$@"
    result=$?
    set -e
    return "${result}"
}

# Check if last command failed
failed() {
    [[ $? -ne 0 ]]
}

# ────────────────────────────────────────────────────────────────
# Assertions
# ────────────────────────────────────────────────────────────────

assert() {
    local condition="$1"
    local message="${2:-Assertion failed}"

    if ! eval "${condition}"; then
        die_internal "${message}"
    fi
}

assert_not_empty() {
    local var_name="$1"
    local value="${!var_name:-}"

    if [[ -z "${value}" ]]; then
        die_validation "Required variable '${var_name}' is empty"
    fi
}

assert_command_exists() {
    local cmd="$1"

    if ! command -v "${cmd}" >/dev/null 2>&1; then
        die_environment "Required command '${cmd}' not found"
    fi
}
