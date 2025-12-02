#!/usr/bin/env bash
#
# portability.sh - Cross-platform compatibility abstractions
#

# Prevent multiple sourcing
[[ -n "${__PORTABILITY_SH_LOADED:-}" ]] && return 0
readonly __PORTABILITY_SH_LOADED=1

# ────────────────────────────────────────────────────────────────
# OS Detection
# ────────────────────────────────────────────────────────────────

detect_os() {
    case "$(uname -s)" in
        Linux*)  echo "linux" ;;
        Darwin*) echo "macos" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *)       echo "unknown" ;;
    esac
}

readonly __DETECTED_OS=$(detect_os)

is_linux() {
    [[ "${__DETECTED_OS}" == "linux" ]]
}

is_macos() {
    [[ "${__DETECTED_OS}" == "macos" ]]
}

is_windows() {
    [[ "${__DETECTED_OS}" == "windows" ]]
}

get_os() {
    echo "${__DETECTED_OS}"
}

# ────────────────────────────────────────────────────────────────
# Shell Detection & Verification
# ────────────────────────────────────────────────────────────────

detect_shell() {
    if [[ -n "${BASH_VERSION:-}" ]]; then
        echo "bash"
    elif [[ -n "${ZSH_VERSION:-}" ]]; then
        echo "zsh"
    else
        echo "sh"
    fi
}

get_bash_version() {
    if [[ -n "${BASH_VERSION:-}" ]]; then
        echo "${BASH_VERSION%%(*}"
    else
        echo "0"
    fi
}

get_bash_major_version() {
    if [[ -n "${BASH_VERSINFO[0]:-}" ]]; then
        echo "${BASH_VERSINFO[0]}"
    else
        echo "0"
    fi
}

require_bash_version() {
    local required="$1"
    local current
    current=$(get_bash_major_version)

    if [[ "${current}" -lt "${required}" ]]; then
        die_environment "Bash ${required}+ required, found ${current}"
    fi
}

verify_shell() {
    local shell
    shell=$(detect_shell)

    case "${shell}" in
        bash)
            require_bash_version 4
            ;;
        zsh)
            # Zsh is acceptable for completions
            ;;
        *)
            die_environment "Unsupported shell: ${shell}. Bash 4+ required."
            ;;
    esac
}

# ────────────────────────────────────────────────────────────────
# Feature Detection
# ────────────────────────────────────────────────────────────────

supports_arrays() {
    [[ -n "${BASH_VERSION:-}" ]] || [[ -n "${ZSH_VERSION:-}" ]]
}

supports_assoc_arrays() {
    [[ -n "${BASH_VERSION:-}" ]] && [[ "${BASH_VERSINFO[0]}" -ge 4 ]]
}

supports_extglob() {
    shopt -q extglob 2>/dev/null
}

supports_globstar() {
    shopt -q globstar 2>/dev/null
}

enable_extglob() {
    if [[ -n "${BASH_VERSION:-}" ]]; then
        shopt -s extglob 2>/dev/null || true
    fi
}

enable_globstar() {
    if [[ -n "${BASH_VERSION:-}" ]]; then
        shopt -s globstar 2>/dev/null || true
    fi
}

# ────────────────────────────────────────────────────────────────
# Path Utilities (portable, no GNU dependency)
# ────────────────────────────────────────────────────────────────

# Portable realpath implementation
portable_realpath() {
    local path="$1"

    # Try native realpath first
    if command -v realpath >/dev/null 2>&1; then
        realpath "${path}" 2>/dev/null && return 0
    fi

    # Try Python fallback
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import os; print(os.path.realpath('${path}'))" 2>/dev/null && return 0
    fi

    if command -v python >/dev/null 2>&1; then
        python -c "import os; print(os.path.realpath('${path}'))" 2>/dev/null && return 0
    fi

    # Manual resolution
    local dir file
    if [[ -d "${path}" ]]; then
        (cd "${path}" && pwd)
    elif [[ -f "${path}" ]]; then
        dir=$(dirname "${path}")
        file=$(basename "${path}")
        (cd "${dir}" && echo "$(pwd)/${file}")
    else
        # Path doesn't exist, normalize anyway
        echo "${path}"
    fi
}

# Portable dirname
portable_dirname() {
    local path="$1"
    local dir="${path%/*}"
    [[ "${dir}" == "${path}" ]] && dir="."
    echo "${dir}"
}

# Portable basename
portable_basename() {
    local path="$1"
    local suffix="${2:-}"
    local base="${path##*/}"
    [[ -n "${suffix}" ]] && base="${base%${suffix}}"
    echo "${base}"
}

# Get script directory (works when sourced)
get_script_dir() {
    local source="${BASH_SOURCE[0]:-$0}"
    portable_realpath "$(portable_dirname "${source}")"
}

# ────────────────────────────────────────────────────────────────
# Command Utilities
# ────────────────────────────────────────────────────────────────

# Find command with fallbacks
find_command() {
    local cmd
    for cmd in "$@"; do
        if command -v "${cmd}" >/dev/null 2>&1; then
            echo "${cmd}"
            return 0
        fi
    done
    return 1
}

# Get sed command (handles GNU vs BSD differences)
get_sed() {
    if is_macos; then
        # macOS sed requires '' for in-place
        echo "sed"
    else
        echo "sed"
    fi
}

# Portable sed in-place edit
sed_inplace() {
    local pattern="$1"
    local file="$2"

    if is_macos; then
        sed -i '' "${pattern}" "${file}"
    else
        sed -i "${pattern}" "${file}"
    fi
}

# Get date command with format
portable_date() {
    local format="${1:-%Y-%m-%dT%H:%M:%SZ}"

    if is_macos; then
        date -u "+${format}"
    else
        date -u "+${format}"
    fi
}

# Get timestamp in ISO 8601 format
get_timestamp() {
    portable_date "%Y-%m-%dT%H:%M:%SZ"
}

# ────────────────────────────────────────────────────────────────
# Terminal Utilities
# ────────────────────────────────────────────────────────────────

# Check if stdout is a TTY
is_tty() {
    [[ -t 1 ]]
}

# Check if stdin is a TTY
is_interactive() {
    [[ -t 0 ]]
}

# Get terminal width
get_term_width() {
    if command -v tput >/dev/null 2>&1; then
        tput cols 2>/dev/null || echo "80"
    else
        echo "80"
    fi
}

# Get terminal height
get_term_height() {
    if command -v tput >/dev/null 2>&1; then
        tput lines 2>/dev/null || echo "24"
    else
        echo "24"
    fi
}

# ────────────────────────────────────────────────────────────────
# Temp File Utilities
# ────────────────────────────────────────────────────────────────

# Create temp file portably
create_temp_file() {
    local prefix="${1:-cli}"
    mktemp "${TMPDIR:-/tmp}/${prefix}.XXXXXX"
}

# Create temp directory portably
create_temp_dir() {
    local prefix="${1:-cli}"
    mktemp -d "${TMPDIR:-/tmp}/${prefix}.XXXXXX"
}
