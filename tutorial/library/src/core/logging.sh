#!/usr/bin/env bash
#
# logging.sh - Structured logging subsystem with levels and formatting
#

# Prevent multiple sourcing
[[ -n "${__LOGGING_SH_LOADED:-}" ]] && return 0
readonly __LOGGING_SH_LOADED=1

# ────────────────────────────────────────────────────────────────
# Log Levels (numeric for comparison)
# ────────────────────────────────────────────────────────────────
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3
readonly LOG_LEVEL_NONE=4

# Current log level (default: INFO)
__LOG_LEVEL="${LOG_LEVEL_INFO}"
__LOG_FILE=""
__LOG_COLOR=1

# ────────────────────────────────────────────────────────────────
# Color Codes
# ────────────────────────────────────────────────────────────────
readonly __COLOR_RESET='\033[0m'
readonly __COLOR_DEBUG='\033[0;36m'   # Cyan
readonly __COLOR_INFO='\033[0;32m'    # Green
readonly __COLOR_WARN='\033[0;33m'    # Yellow
readonly __COLOR_ERROR='\033[0;31m'   # Red
readonly __COLOR_BOLD='\033[1m'
readonly __COLOR_DIM='\033[2m'

# ────────────────────────────────────────────────────────────────
# Configuration
# ────────────────────────────────────────────────────────────────

set_log_level() {
    local level="$1"
    case "${level,,}" in
        debug) __LOG_LEVEL="${LOG_LEVEL_DEBUG}" ;;
        info)  __LOG_LEVEL="${LOG_LEVEL_INFO}" ;;
        warn)  __LOG_LEVEL="${LOG_LEVEL_WARN}" ;;
        error) __LOG_LEVEL="${LOG_LEVEL_ERROR}" ;;
        none)  __LOG_LEVEL="${LOG_LEVEL_NONE}" ;;
        *)     die_validation "Invalid log level: ${level}" ;;
    esac
}

set_log_file() {
    local path="$1"
    local dir
    dir=$(dirname "${path}")

    if [[ ! -d "${dir}" ]]; then
        mkdir -p "${dir}" || die_validation "Cannot create log directory: ${dir}"
    fi

    __LOG_FILE="${path}"
}

disable_log_color() {
    __LOG_COLOR=0
}

enable_log_color() {
    __LOG_COLOR=1
}

# Auto-detect color support
__detect_color_support() {
    # Disable if --no-color flag or NO_COLOR env
    if [[ -n "${NO_COLOR:-}" ]]; then
        __LOG_COLOR=0
        return
    fi

    # Disable if not a TTY
    if [[ ! -t 1 ]]; then
        __LOG_COLOR=0
        return
    fi

    # Check terminal color support
    if command -v tput >/dev/null 2>&1; then
        local colors
        colors=$(tput colors 2>/dev/null || echo 0)
        if [[ "${colors}" -lt 8 ]]; then
            __LOG_COLOR=0
        fi
    fi
}

# ────────────────────────────────────────────────────────────────
# Core Logging Functions
# ────────────────────────────────────────────────────────────────

__log() {
    local level="$1"
    local level_name="$2"
    local color="$3"
    shift 3
    local message="$*"

    # Check if level is enabled
    [[ "${level}" -lt "${__LOG_LEVEL}" ]] && return 0

    # Format timestamp
    local timestamp
    timestamp=$(date -u "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date "+%Y-%m-%dT%H:%M:%S")

    # Build log line
    local log_line="${timestamp} ${level_name}: ${message}"

    # Output to file (no colors)
    if [[ -n "${__LOG_FILE}" ]]; then
        echo "${log_line}" >> "${__LOG_FILE}"
    fi

    # Output to stderr with colors
    if [[ "${__LOG_COLOR}" -eq 1 ]]; then
        printf '%b%s%b %b%-5s%b %s\n' \
            "${__COLOR_DIM}" "${timestamp}" "${__COLOR_RESET}" \
            "${color}" "${level_name}" "${__COLOR_RESET}" \
            "${message}" >&2
    else
        echo "${log_line}" >&2
    fi
}

log_debug() {
    __log "${LOG_LEVEL_DEBUG}" "DEBUG" "${__COLOR_DEBUG}" "$@"
}

log_info() {
    __log "${LOG_LEVEL_INFO}" "INFO" "${__COLOR_INFO}" "$@"
}

log_warn() {
    __log "${LOG_LEVEL_WARN}" "WARN" "${__COLOR_WARN}" "$@"
}

log_error() {
    __log "${LOG_LEVEL_ERROR}" "ERROR" "${__COLOR_ERROR}" "$@"
}

# Aliases
debug() { log_debug "$@"; }
info() { log_info "$@"; }
warn() { log_warn "$@"; }
error() { log_error "$@"; }

# ────────────────────────────────────────────────────────────────
# Formatted Output (stdout, respects quiet mode)
# ────────────────────────────────────────────────────────────────

# Print to stdout (suppressed in quiet mode)
out() {
    [[ "${__LOG_LEVEL}" -ge "${LOG_LEVEL_NONE}" ]] && return 0
    echo "$@"
}

# Print formatted message
outf() {
    [[ "${__LOG_LEVEL}" -ge "${LOG_LEVEL_NONE}" ]] && return 0
    # shellcheck disable=SC2059
    printf "$@"
}

# Print with color
outc() {
    local color="$1"
    shift

    [[ "${__LOG_LEVEL}" -ge "${LOG_LEVEL_NONE}" ]] && return 0

    if [[ "${__LOG_COLOR}" -eq 1 ]]; then
        printf '%b%s%b\n' "${color}" "$*" "${__COLOR_RESET}"
    else
        echo "$*"
    fi
}

# Print success message
success() {
    outc "${__COLOR_INFO}" "$@"
}

# Print warning message (to stdout)
warning() {
    outc "${__COLOR_WARN}" "$@"
}

# Print error message (to stdout)
failure() {
    outc "${__COLOR_ERROR}" "$@"
}

# Print bold message
bold() {
    outc "${__COLOR_BOLD}" "$@"
}

# ────────────────────────────────────────────────────────────────
# Hex Color Support (from original lib.sh)
# ────────────────────────────────────────────────────────────────

# Parse hex color and return ANSI escape sequence
color() {
    local hex="${1#"#"}"
    local bg="${2:-0}"

    # Validate hex format
    if [[ ! "${hex}" =~ ^[0-9A-Fa-f]{6}$ ]]; then
        echo "" # Return empty on invalid
        return 1
    fi

    # Parse RGB components
    local r g b
    r=$((16#${hex:0:2}))
    g=$((16#${hex:2:2}))
    b=$((16#${hex:4:2}))

    # Return foreground or background escape sequence
    if [[ "${bg}" -eq 1 ]]; then
        printf '\033[48;2;%d;%d;%dm' "${r}" "${g}" "${b}"
    else
        printf '\033[38;2;%d;%d;%dm' "${r}" "${g}" "${b}"
    fi
}

# Background color helper
color_bg() {
    color "$1" 1
}

# Print with hex color
print_color() {
    local hex="$1"
    shift

    if [[ "${__LOG_COLOR}" -eq 1 ]]; then
        local clr
        clr=$(color "${hex}")
        printf '%b%s%b\n' "${clr}" "$*" "${__COLOR_RESET}"
    else
        echo "$*"
    fi
}

# ────────────────────────────────────────────────────────────────
# Progress & Status
# ────────────────────────────────────────────────────────────────

# Print a status line (overwrites previous line)
status() {
    [[ "${__LOG_LEVEL}" -ge "${LOG_LEVEL_NONE}" ]] && return 0

    if [[ -t 1 ]]; then
        printf '\r\033[K%s' "$*"
    else
        echo "$*"
    fi
}

# Complete status line with newline
status_done() {
    [[ "${__LOG_LEVEL}" -ge "${LOG_LEVEL_NONE}" ]] && return 0

    if [[ -t 1 ]]; then
        printf '\r\033[K%s\n' "$*"
    else
        echo "$*"
    fi
}

# Simple spinner
spin() {
    local pid="$1"
    local message="${2:-Working...}"
    local spin_chars='|/-\'
    local i=0

    while kill -0 "${pid}" 2>/dev/null; do
        local char="${spin_chars:$((i % 4)):1}"
        status "${char} ${message}"
        sleep 0.1
        ((i++))
    done
    status_done "  ${message} done"
}

# ────────────────────────────────────────────────────────────────
# Initialization
# ────────────────────────────────────────────────────────────────

# Apply flag-based configuration
configure_logging_from_flags() {
    if is_flag_true "verbose"; then
        set_log_level "debug"
    elif is_flag_true "quiet"; then
        set_log_level "none"
    fi

    if is_flag_true "no-color"; then
        disable_log_color
    fi

    local log_file
    log_file=$(get_arg "log-file" "")
    if [[ -n "${log_file}" ]]; then
        set_log_file "${log_file}"
    fi
}

# Auto-detect on load
__detect_color_support
