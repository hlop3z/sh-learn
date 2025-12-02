#!/usr/bin/env bash
#
# cli.sh - Main CLI entry point with command dispatch
#
# Usage:
#   ./cli.sh <command> [options] [arguments]
#
# Example:
#   ./cli.sh greet --name Alice
#   ./cli.sh --help
#   ./cli.sh greet -h
#

# ────────────────────────────────────────────────────────────────
# Resolve script location and load modules
# ────────────────────────────────────────────────────────────────

# Get the directory where this script lives
__CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__CLI_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
__CLI_VERSION="1.0.0"
__CLI_LIB_DIR="${__CLI_DIR}/core"

# Load library modules (order matters: errors first, then validation, etc.)
# shellcheck source=lib/errors.sh
source "${__CLI_LIB_DIR}/errors.sh"
# shellcheck source=lib/portability.sh
source "${__CLI_LIB_DIR}/portability.sh"
# shellcheck source=lib/validation.sh
source "${__CLI_LIB_DIR}/validation.sh"
# shellcheck source=lib/flags.sh
source "${__CLI_LIB_DIR}/flags.sh"
# shellcheck source=lib/logging.sh
source "${__CLI_LIB_DIR}/logging.sh"

# Enable strict mode
enable_strict_mode

# Verify shell compatibility
verify_shell

# ────────────────────────────────────────────────────────────────
# Command Registry
# ────────────────────────────────────────────────────────────────

declare -A __COMMAND_REGISTRY=()
declare -A __COMMAND_HELP=()

# Register a command with its handler and help text
register_command() {
    local name="$1"
    local help="${2:-}"
    local handler="${3:-cmd_${name}}"

    __COMMAND_REGISTRY["${name}"]="${handler}"
    __COMMAND_HELP["${name}"]="${help}"
}

# Check if command exists
command_exists() {
    local name="$1"
    [[ -n "${__COMMAND_REGISTRY[${name}]:-}" ]]
}

# Get command handler
get_command_handler() {
    local name="$1"
    echo "${__COMMAND_REGISTRY[${name}]:-}"
}

# List all registered commands
list_commands() {
    printf '%s\n' "${!__COMMAND_REGISTRY[@]}" | sort
}

# ────────────────────────────────────────────────────────────────
# Load Command Modules
# ────────────────────────────────────────────────────────────────

__load_commands() {
    local commands_dir="${__CLI_DIR}/commands"

    if [[ -d "${commands_dir}" ]]; then
        local cmd_file
        for cmd_file in "${commands_dir}"/*.sh; do
            [[ -f "${cmd_file}" ]] || continue
            # shellcheck disable=SC1090
            source "${cmd_file}"
        done
    fi
}

# ────────────────────────────────────────────────────────────────
# Help System
# ────────────────────────────────────────────────────────────────

show_version() {
    echo "${__CLI_NAME} version ${__CLI_VERSION}"
}

show_help() {
    local command="${1:-}"

    if [[ -n "${command}" ]] && command_exists "${command}"; then
        # Command-specific help
        show_command_help "${command}"
    else
        # Global help
        show_global_help
    fi
}

show_global_help() {
    cat <<EOF
${__CLI_NAME} - A shell CLI framework

Usage:
  ${__CLI_NAME} <command> [options] [arguments]
  ${__CLI_NAME} [global-options]

Commands:
EOF

    local cmd
    for cmd in $(list_commands); do
        printf "  %-20s %s\n" "${cmd}" "${__COMMAND_HELP[${cmd}]:-}"
    done

    cat <<EOF

Global Options:
EOF
    generate_flag_help "global"

    cat <<EOF

Run '${__CLI_NAME} <command> --help' for command-specific help.
EOF
}

show_command_help() {
    local command="$1"
    local help="${__COMMAND_HELP[${command}]:-No description available}"

    cat <<EOF
${__CLI_NAME} ${command} - ${help}

Usage:
  ${__CLI_NAME} ${command} [options] [arguments]

Options:
EOF
    generate_flag_help "${command}"
}

# ────────────────────────────────────────────────────────────────
# Command Dispatch
# ────────────────────────────────────────────────────────────────

dispatch() {
    local command="${1:-}"
    shift || true

    # No command provided
    if [[ -z "${command}" ]]; then
        show_global_help
        exit 0
    fi

    # Handle global flags before command
    case "${command}" in
        --help|-h)
            show_global_help
            exit 0
            ;;
        --version|-V)
            show_version
            exit 0
            ;;
    esac

    # Check if command exists
    if ! command_exists "${command}"; then
        log_error "Unknown command: ${command}"
        echo ""
        show_global_help
        exit "${EXIT_USAGE}"
    fi

    # Parse arguments for this command
    parse_args "${command}" "$@"

    # Configure logging based on flags
    configure_logging_from_flags

    # Handle --help for command
    if is_flag_true "help"; then
        show_command_help "${command}"
        exit 0
    fi

    # Get and execute handler
    local handler
    handler=$(get_command_handler "${command}")

    if ! type "${handler}" >/dev/null 2>&1; then
        die_internal "Handler '${handler}' for command '${command}' not found"
    fi

    log_debug "Executing command: ${command}"
    "${handler}"
}

# ────────────────────────────────────────────────────────────────
# Built-in Commands
# ────────────────────────────────────────────────────────────────

cmd_help() {
    local topic
    topic=$(get_positional 0 "")
    show_help "${topic}"
}

cmd_version() {
    show_version
}

cmd_commands() {
    echo "Available commands:"
    local cmd
    for cmd in $(list_commands); do
        printf "  %-20s %s\n" "${cmd}" "${__COMMAND_HELP[${cmd}]:-}"
    done
}

# Register built-in commands
register_command "help" "Show help information"
register_command "version" "Show version information"
register_command "commands" "List available commands"

# ────────────────────────────────────────────────────────────────
# Main Entry Point
# ────────────────────────────────────────────────────────────────

main() {
    # Load command modules
    __load_commands

    # Dispatch to command handler
    dispatch "$@"
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
