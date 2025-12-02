#!/usr/bin/env bash
#
# validation.sh - Type validators and input validation
#

# Prevent multiple sourcing
[[ -n "${__VALIDATION_SH_LOADED:-}" ]] && return 0
readonly __VALIDATION_SH_LOADED=1

# ────────────────────────────────────────────────────────────────
# Type Validators (return 0/1 only, no output)
# ────────────────────────────────────────────────────────────────

# Check if value is an integer (positive, negative, or zero)
is_int() {
    local value="$1"
    [[ "${value}" =~ ^-?[0-9]+$ ]]
}

# Check if value is a positive integer
is_positive_int() {
    local value="$1"
    [[ "${value}" =~ ^[0-9]+$ ]] && [[ "${value}" -gt 0 ]]
}

# Check if value is a non-negative integer (0 or positive)
is_non_negative_int() {
    local value="$1"
    [[ "${value}" =~ ^[0-9]+$ ]]
}

# Check if value is a boolean (true/false, yes/no, 1/0)
is_bool() {
    local value="$1"
    case "${value,,}" in
        true|false|yes|no|1|0|on|off) return 0 ;;
        *) return 1 ;;
    esac
}

# Normalize boolean to true/false
normalize_bool() {
    local value="$1"
    case "${value,,}" in
        true|yes|1|on) echo "true" ;;
        false|no|0|off) echo "false" ;;
        *) echo "false" ;;
    esac
}

# Check if path exists (file or directory)
is_valid_path() {
    local path="$1"
    [[ -e "${path}" ]]
}

# Check if path is an existing file
is_file() {
    local path="$1"
    [[ -f "${path}" ]]
}

# Check if path is an existing directory
is_dir() {
    local path="$1"
    [[ -d "${path}" ]]
}

# Check if path is readable
is_readable() {
    local path="$1"
    [[ -r "${path}" ]]
}

# Check if path is writable
is_writable() {
    local path="$1"
    [[ -w "${path}" ]]
}

# Check if path is executable
is_executable() {
    local path="$1"
    [[ -x "${path}" ]]
}

# Check if value is a valid identifier (variable/function name)
is_valid_key() {
    local key="$1"
    [[ "${key}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]
}

# Check if value is one of allowed enum values
is_enum() {
    local value="$1"
    shift
    local allowed
    for allowed in "$@"; do
        [[ "${value}" == "${allowed}" ]] && return 0
    done
    return 1
}

# Check if string is non-empty
is_nonempty() {
    local value="$1"
    [[ -n "${value}" ]]
}

# Check if string matches regex
matches_regex() {
    local value="$1"
    local pattern="$2"
    [[ "${value}" =~ ${pattern} ]]
}

# Check if value is a valid URL
is_url() {
    local value="$1"
    [[ "${value}" =~ ^https?://[^[:space:]]+$ ]]
}

# Check if value is a valid email (basic check)
is_email() {
    local value="$1"
    [[ "${value}" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]
}

# Check if value is a valid port number (1-65535)
is_port() {
    local value="$1"
    is_positive_int "${value}" && [[ "${value}" -le 65535 ]]
}

# Check if value is valid IPv4 address
is_ipv4() {
    local value="$1"
    local IFS='.'
    local -a octets
    read -ra octets <<< "${value}"

    [[ ${#octets[@]} -eq 4 ]] || return 1

    local octet
    for octet in "${octets[@]}"; do
        is_non_negative_int "${octet}" && [[ "${octet}" -le 255 ]] || return 1
    done
    return 0
}

# ────────────────────────────────────────────────────────────────
# Validation with Error Messages (uses die_validation from errors.sh)
# ────────────────────────────────────────────────────────────────

require_int() {
    local name="$1"
    local value="$2"
    if ! is_int "${value}"; then
        die_validation "'${name}' must be an integer, got '${value}'"
    fi
}

require_bool() {
    local name="$1"
    local value="$2"
    if ! is_bool "${value}"; then
        die_validation "'${name}' must be a boolean (true/false/yes/no/1/0), got '${value}'"
    fi
}

require_path() {
    local name="$1"
    local path="$2"
    if ! is_valid_path "${path}"; then
        die_validation "'${name}' path does not exist: '${path}'"
    fi
}

require_file() {
    local name="$1"
    local path="$2"
    if ! is_file "${path}"; then
        die_validation "'${name}' is not a file: '${path}'"
    fi
}

require_dir() {
    local name="$1"
    local path="$2"
    if ! is_dir "${path}"; then
        die_validation "'${name}' is not a directory: '${path}'"
    fi
}

require_enum() {
    local name="$1"
    local value="$2"
    shift 2
    if ! is_enum "${value}" "$@"; then
        die_validation "'${name}' must be one of: $*, got '${value}'"
    fi
}

require_nonempty() {
    local name="$1"
    local value="$2"
    if ! is_nonempty "${value}"; then
        die_validation "'${name}' cannot be empty"
    fi
}

require_port() {
    local name="$1"
    local value="$2"
    if ! is_port "${value}"; then
        die_validation "'${name}' must be a valid port (1-65535), got '${value}'"
    fi
}
