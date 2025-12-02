#!/usr/bin/env bash
#
# build.sh - Build the CLI into a single distributable file
#
# Usage:
#   ./build.sh          # Build dist/cli.sh only
#   ./build.sh -e       # Build dist/cli.sh + dist/install.sh (executable installer)
#
# This script:
# 1. Reads all command schemas from src/commands/*/schema.json
# 2. Embeds all core modules
# 3. Generates register_arg/register_command calls from JSON
# 4. Auto-generates shell completion scripts (bash & zsh)
# 5. Outputs a single self-contained dist/cli.sh file
#
# Options:
#   -e    Create an executable installer (install.sh)
#         Requires: src/commands/app/ directory with schema.json and main.sh
#         The 'app' command serves as the main entry point for the executable.
#
# ────────────────────────────────────────────────────────────────
# Executable Installer (-e flag)
# ────────────────────────────────────────────────────────────────
#
# When using -e, the script generates dist/install.sh - a self-contained
# installer that users can run via curl pipe:
#
#   curl -LsSf https://example.com/install.sh | sh
#   wget -qO- https://example.com/install.sh | sh
#
# The installer:
# - Embeds the entire CLI as a base64 payload
# - Installs to ~/.local/bin by default (configurable via INSTALL_DIR)
# - Works with /bin/sh for maximum portability
# - Detects if install directory is in PATH and provides guidance
# - Verifies installation by running --version
#
# Environment variables for install.sh:
#   INSTALL_DIR  - Custom installation directory (default: ~/.local/bin)
#   CLI_NAME     - Override the binary name (default: cli)
#
# ────────────────────────────────────────────────────────────────
# Shell Completions
# ────────────────────────────────────────────────────────────────
#
# The output file includes a 'completion' command for shell integration:
#
#   # Bash - add to ~/.bashrc
#   eval "$(./cli.sh completion)"
#
#   # Zsh - add to ~/.zshrc
#   eval "$(./cli.sh completion --shell zsh)"
#
# Completions are auto-generated from schema.json definitions and include:
# - Command name completion
# - Command-specific flag completion (--name, -n, etc.)
# - Type-aware value completion:
#   - bool: suggests "true" or "false"
#   - enum:a:b:c: suggests "a", "b", "c"
#   - path: uses file/directory completion
#

set -o errexit
set -o nounset
set -o pipefail

# ────────────────────────────────────────────────────────────────
# Parse build flags
# ────────────────────────────────────────────────────────────────

BUILD_EXECUTABLE=false

while getopts "e" opt; do
    case "${opt}" in
        e)
            BUILD_EXECUTABLE=true
            ;;
        *)
            echo "Usage: $0 [-e]"
            echo "  -e    Create an executable installer (install.sh)"
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/src"
DIST_DIR="${SCRIPT_DIR}/dist"
OUTPUT_FILE="${DIST_DIR}/cli.sh"
INSTALLER_FILE="${DIST_DIR}/install.sh"

# Arrays to collect command/flag data for completion generation
declare -a ALL_COMMANDS=("help" "version" "commands")
declare -A COMMAND_DESCRIPTIONS=(
    ["help"]="Show help information"
    ["version"]="Show version information"
    ["commands"]="List available commands"
)
declare -A COMMAND_FLAGS=()
declare -A FLAG_TYPES=()
declare -A FLAG_SHORTS=()

# ────────────────────────────────────────────────────────────────
# Simple JSON parsing (no jq dependency)
# ────────────────────────────────────────────────────────────────

# Extract a simple string value from JSON: json_get '{"name": "foo"}' "name" -> foo
json_get() {
    local json="$1"
    local key="$2"
    local default="${3:-}"

    # Match "key": "value" or "key": value (for booleans/numbers)
    local result
    result=$(echo "${json}" | grep -oP "\"${key}\"\\s*:\\s*\"?\\K[^\",}]+" | head -1) || true

    if [[ -z "${result}" ]]; then
        echo "${default}"
    else
        echo "${result}"
    fi
}

# Parse schema.json and output register_arg/register_command calls
# Also collects data for completion generation
parse_schema() {
    local schema_file="$1"
    local json
    json=$(tr -d '\n\r' < "${schema_file}")

    # Get command name and description
    local cmd_name cmd_desc
    cmd_name=$(json_get "${json}" "name")
    cmd_desc=$(json_get "${json}" "description")

    # Collect for completions
    ALL_COMMANDS+=("${cmd_name}")
    COMMAND_DESCRIPTIONS["${cmd_name}"]="${cmd_desc}"
    local cmd_flags=""

    # Extract args array content
    local args_section
    args_section=$(echo "${json}" | grep -oP '"args"\s*:\s*\[\K[^\]]*' || echo "")

    # Parse each arg object
    if [[ -n "${args_section}" ]]; then
        # Split by }, and process each arg
        local IFS='}'
        local arg_objects
        read -ra arg_objects <<< "${args_section}"

        for arg_obj in "${arg_objects[@]}"; do
            # Skip empty
            [[ -z "${arg_obj//[[:space:],\[]/}" ]] && continue

            local arg_name arg_short arg_type arg_required arg_default arg_help
            arg_name=$(json_get "${arg_obj}" "name")
            arg_short=$(json_get "${arg_obj}" "short" "")
            arg_type=$(json_get "${arg_obj}" "type" "string")
            arg_required=$(json_get "${arg_obj}" "required" "false")
            arg_default=$(json_get "${arg_obj}" "default" "")
            arg_help=$(json_get "${arg_obj}" "help" "")

            [[ -z "${arg_name}" ]] && continue

            # Collect for completions
            cmd_flags="${cmd_flags} --${arg_name}"
            [[ -n "${arg_short}" ]] && cmd_flags="${cmd_flags} -${arg_short}"
            FLAG_TYPES["${cmd_name}:${arg_name}"]="${arg_type}"
            FLAG_SHORTS["${cmd_name}:${arg_name}"]="${arg_short}"

            echo "register_arg \"${arg_name}\" \"${arg_short}\" \"${arg_type}\" \"${arg_required}\" \"${arg_default}\" \"${arg_help}\" \"${cmd_name}\""
        done
    fi

    COMMAND_FLAGS["${cmd_name}"]="${cmd_flags}"

    # Output register_command
    echo "register_command \"${cmd_name}\" \"${cmd_desc}\""
}

# ────────────────────────────────────────────────────────────────
# Build Process
# ────────────────────────────────────────────────────────────────

# Ensure dist directory exists
mkdir -p "${DIST_DIR}"

# Start building the output file
cat > "${OUTPUT_FILE}" << 'HEADER'
#!/usr/bin/env bash
#
# cli.sh - CLI Framework (Built Distribution)
#
# This is an auto-generated file. Do not edit directly.
# Generated by build.sh
#

HEADER

# Add generation timestamp
echo "# Built: $(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "${OUTPUT_FILE}"
echo "" >> "${OUTPUT_FILE}"

# ────────────────────────────────────────────────────────────────
# Embed core modules
# ────────────────────────────────────────────────────────────────

embed_module() {
    local file="$1"
    local name
    name=$(basename "${file}" .sh)

    echo "" >> "${OUTPUT_FILE}"
    echo "# ════════════════════════════════════════════════════════════════" >> "${OUTPUT_FILE}"
    echo "# Module: ${name}" >> "${OUTPUT_FILE}"
    echo "# ════════════════════════════════════════════════════════════════" >> "${OUTPUT_FILE}"
    echo "" >> "${OUTPUT_FILE}"

    # Strip shebang line and write content
    tail -n +2 "${file}" >> "${OUTPUT_FILE}"
}

echo "Embedding core modules..."
embed_module "${SRC_DIR}/core/errors.sh"
embed_module "${SRC_DIR}/core/portability.sh"
embed_module "${SRC_DIR}/core/validation.sh"
embed_module "${SRC_DIR}/core/flags.sh"
embed_module "${SRC_DIR}/core/logging.sh"

# ────────────────────────────────────────────────────────────────
# Add CLI framework code
# ────────────────────────────────────────────────────────────────

cat >> "${OUTPUT_FILE}" << 'CLI_FRAMEWORK'

# ════════════════════════════════════════════════════════════════
# CLI Framework
# ════════════════════════════════════════════════════════════════

# Get the directory where this script lives
__CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
__CLI_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
__CLI_VERSION="1.0.0"

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
# Help System
# ────────────────────────────────────────────────────────────────

show_version() {
    echo "${__CLI_NAME} version ${__CLI_VERSION}"
}

show_help() {
    local command="${1:-}"

    if [[ -n "${command}" ]] && command_exists "${command}"; then
        show_command_help "${command}"
    else
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

Enable tab completion:
  eval "\$(${__CLI_NAME} completion)"          # bash (add to ~/.bashrc)
  eval "\$(${__CLI_NAME} completion -s zsh)"   # zsh  (add to ~/.zshrc)
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

    if [[ -z "${command}" ]]; then
        show_global_help
        exit 0
    fi

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

    if ! command_exists "${command}"; then
        log_error "Unknown command: ${command}"
        echo ""
        show_global_help
        exit "${EXIT_USAGE}"
    fi

    parse_args "${command}" "$@"
    configure_logging_from_flags

    if is_flag_true "help"; then
        show_command_help "${command}"
        exit 0
    fi

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

register_command "help" "Show help information"
register_command "version" "Show version information"
register_command "commands" "List available commands"

CLI_FRAMEWORK

# ────────────────────────────────────────────────────────────────
# Process command schemas
# ────────────────────────────────────────────────────────────────

echo "" >> "${OUTPUT_FILE}"
echo "# ════════════════════════════════════════════════════════════════" >> "${OUTPUT_FILE}"
echo "# Command Registrations (generated from schema.json files)" >> "${OUTPUT_FILE}"
echo "# ════════════════════════════════════════════════════════════════" >> "${OUTPUT_FILE}"
echo "" >> "${OUTPUT_FILE}"

for cmd_dir in "${SRC_DIR}"/commands/*/; do
    [[ -d "${cmd_dir}" ]] || continue

    schema_file="${cmd_dir}schema.json"
    main_file="${cmd_dir}main.sh"

    if [[ ! -f "${schema_file}" ]]; then
        echo "Warning: No schema.json in ${cmd_dir}, skipping" >&2
        continue
    fi

    if [[ ! -f "${main_file}" ]]; then
        echo "Warning: No main.sh in ${cmd_dir}, skipping" >&2
        continue
    fi

    # Get command name for display
    cmd_name=$(json_get "$(cat "${schema_file}")" "name")
    echo "Processing command: ${cmd_name}"

    echo "" >> "${OUTPUT_FILE}"
    echo "# ────────────────────────────────────────────────────────────────" >> "${OUTPUT_FILE}"
    echo "# Command: ${cmd_name}" >> "${OUTPUT_FILE}"
    echo "# ────────────────────────────────────────────────────────────────" >> "${OUTPUT_FILE}"
    echo "" >> "${OUTPUT_FILE}"

    # Generate registrations from schema
    parse_schema "${schema_file}" >> "${OUTPUT_FILE}"
    echo "" >> "${OUTPUT_FILE}"

    # Embed command handler
    tail -n +2 "${main_file}" >> "${OUTPUT_FILE}"
done

# ────────────────────────────────────────────────────────────────
# Generate and embed completions
# ────────────────────────────────────────────────────────────────
#
# This function generates shell completion scripts embedded in the CLI.
# It uses metadata collected during schema parsing (ALL_COMMANDS,
# COMMAND_FLAGS, FLAG_TYPES, FLAG_SHORTS) to build completion functions
# for both bash and zsh.
#
# The generated 'completion' command outputs the appropriate script
# when invoked, enabling users to set up completions with:
#   eval "$(./cli.sh completion)"
#

generate_completions() {
    local commands_list="${ALL_COMMANDS[*]}"
    local global_flags="--help -h --verbose -v --quiet -q --no-color --version -V"

    # Build command flags string for embedding
    local cmd_flags_defs=""
    for cmd in "${ALL_COMMANDS[@]}"; do
        local flags="${COMMAND_FLAGS[${cmd}]:-}"
        cmd_flags_defs="${cmd_flags_defs}    local ${cmd}_flags=\"${flags}\"\n"
    done

    # Build case statements for commands
    local case_entries=""
    for cmd in "${ALL_COMMANDS[@]}"; do
        case_entries="${case_entries}        ${cmd})\n"
        case_entries="${case_entries}            case \"\\\${prev}\" in\n"

        # Generate value completions based on flag types
        for flag_key in "${!FLAG_TYPES[@]}"; do
            if [[ "${flag_key}" == "${cmd}:"* ]]; then
                local flag_name="${flag_key#*:}"
                local flag_type="${FLAG_TYPES[${flag_key}]}"
                local flag_short="${FLAG_SHORTS[${flag_key}]:-}"

                case "${flag_type}" in
                    bool)
                        case_entries="${case_entries}                --${flag_name}|-${flag_short})\n"
                        case_entries="${case_entries}                    COMPREPLY=(\\\$(compgen -W \"true false\" -- \"\\\${cur}\"))\n"
                        case_entries="${case_entries}                    return 0\n"
                        case_entries="${case_entries}                    ;;\n"
                        ;;
                    path)
                        case_entries="${case_entries}                --${flag_name}|-${flag_short})\n"
                        case_entries="${case_entries}                    COMPREPLY=(\\\$(compgen -f -- \"\\\${cur}\"))\n"
                        case_entries="${case_entries}                    return 0\n"
                        case_entries="${case_entries}                    ;;\n"
                        ;;
                    enum:*)
                        local enum_values="${flag_type#enum:}"
                        enum_values="${enum_values//:/ }"
                        case_entries="${case_entries}                --${flag_name}|-${flag_short})\n"
                        case_entries="${case_entries}                    COMPREPLY=(\\\$(compgen -W \"${enum_values}\" -- \"\\\${cur}\"))\n"
                        case_entries="${case_entries}                    return 0\n"
                        case_entries="${case_entries}                    ;;\n"
                        ;;
                esac
            fi
        done

        case_entries="${case_entries}            esac\n"
        case_entries="${case_entries}            COMPREPLY=(\\\$(compgen -W \"\\\${${cmd}_flags} \\\${global_flags}\" -- \"\\\${cur}\"))\n"
        case_entries="${case_entries}            return 0\n"
        case_entries="${case_entries}            ;;\n"
    done

    # Build zsh command descriptions
    local zsh_commands=""
    for cmd in "${ALL_COMMANDS[@]}"; do
        local desc="${COMMAND_DESCRIPTIONS[${cmd}]:-}"
        desc="${desc//\"/\\\"}"
        zsh_commands="${zsh_commands}        '${cmd}:${desc}'\n"
    done

    # Build zsh case entries
    local zsh_cases=""
    for cmd in "${ALL_COMMANDS[@]}"; do
        zsh_cases="${zsh_cases}                ${cmd})\n"
        zsh_cases="${zsh_cases}                    _arguments \\\\\n"

        for flag_key in "${!FLAG_TYPES[@]}"; do
            if [[ "${flag_key}" == "${cmd}:"* ]]; then
                local flag_name="${flag_key#*:}"
                local flag_short="${FLAG_SHORTS[${flag_key}]:-}"
                zsh_cases="${zsh_cases}                        '--${flag_name}[${flag_name}]' \\\\\n"
                [[ -n "${flag_short}" ]] && zsh_cases="${zsh_cases}                        '-${flag_short}[${flag_name}]' \\\\\n"
            fi
        done

        zsh_cases="${zsh_cases}                        \\\${global_opts}\n"
        zsh_cases="${zsh_cases}                    ;;\n"
    done

    # Write the completion functions
    cat >> "${OUTPUT_FILE}" << COMPLETION_EOF

# ════════════════════════════════════════════════════════════════
# Shell Completions (auto-generated)
# ════════════════════════════════════════════════════════════════

__cli_generate_bash_completion() {
    local cli_name="\$1"
    cat << EOF
_\${cli_name}_completions() {
    local cur prev words cword
    _init_completion 2>/dev/null || {
        COMPREPLY=()
        cur="\\\${COMP_WORDS[COMP_CWORD]}"
        prev="\\\${COMP_WORDS[COMP_CWORD-1]}"
        words=("\\\${COMP_WORDS[@]}")
        cword="\\\${COMP_CWORD}"
    }

    local commands="${commands_list}"
    local global_flags="${global_flags}"

$(echo -e "${cmd_flags_defs}")
    # First argument: complete commands
    if [[ \\\${cword} -eq 1 ]]; then
        COMPREPLY=(\\\$(compgen -W "\\\${commands} \\\${global_flags}" -- "\\\${cur}"))
        return 0
    fi

    # Get the command (first non-flag argument)
    local cmd=""
    local i
    for ((i = 1; i < cword; i++)); do
        if [[ "\\\${words[i]}" != -* ]]; then
            cmd="\\\${words[i]}"
            break
        fi
    done

    # Complete based on command
    case "\\\${cmd}" in
$(echo -e "${case_entries}")        help)
            COMPREPLY=(\\\$(compgen -W "\\\${commands}" -- "\\\${cur}"))
            return 0
            ;;
        *)
            COMPREPLY=(\\\$(compgen -W "\\\${global_flags}" -- "\\\${cur}"))
            return 0
            ;;
    esac
}

complete -F _\${cli_name}_completions "\${cli_name}"
complete -F _\${cli_name}_completions "\${cli_name}.sh"
complete -F _\${cli_name}_completions "./\${cli_name}.sh"
EOF
}

__cli_generate_zsh_completion() {
    local cli_name="\$1"
    cat << EOF
#compdef \${cli_name} \${cli_name}.sh

_\${cli_name}() {
    local -a commands
    local -a global_opts

    global_opts=(
        '--help[Show help message]'
        '-h[Show help message]'
        '--verbose[Enable verbose output]'
        '-v[Enable verbose output]'
        '--quiet[Suppress output]'
        '-q[Suppress output]'
        '--no-color[Disable colored output]'
        '--version[Show version]'
        '-V[Show version]'
    )

    commands=(
$(echo -e "${zsh_commands}")    )

    _arguments -C \\
        '1: :->command' \\
        '*: :->args' \\
        \\\${global_opts}

    case \\\$state in
        command)
            _describe -t commands 'commands' commands
            ;;
        args)
            case \\\$words[2] in
$(echo -e "${zsh_cases}")            esac
            ;;
    esac
}

_\${cli_name} "\\\$@"
EOF
}

# Completion command handler
cmd_completion() {
    local shell_type
    shell_type=\$(get_arg "shell" "")

    # Auto-detect shell if not specified
    if [[ -z "\${shell_type}" ]]; then
        if [[ -n "\${ZSH_VERSION:-}" ]]; then
            shell_type="zsh"
        elif [[ -n "\${BASH_VERSION:-}" ]]; then
            shell_type="bash"
        else
            shell_type="bash"
        fi
    fi

    case "\${shell_type}" in
        bash)
            __cli_generate_bash_completion "\${__CLI_NAME}"
            ;;
        zsh)
            __cli_generate_zsh_completion "\${__CLI_NAME}"
            ;;
        *)
            log_error "Unsupported shell: \${shell_type}. Use 'bash' or 'zsh'."
            exit "\${EXIT_USAGE}"
            ;;
    esac
}

register_arg "shell" "s" "enum:bash:zsh" "false" "" "Shell type (bash, zsh)" "completion"
register_command "completion" "Generate shell completion script"

COMPLETION_EOF
}

echo "Generating completions..."
generate_completions

# ────────────────────────────────────────────────────────────────
# Add main entry point
# ────────────────────────────────────────────────────────────────

cat >> "${OUTPUT_FILE}" << 'MAIN_ENTRY'

# ════════════════════════════════════════════════════════════════
# Main Entry Point
# ════════════════════════════════════════════════════════════════

main() {
    dispatch "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
MAIN_ENTRY

chmod +x "${OUTPUT_FILE}"

echo ""
echo "Build complete: ${OUTPUT_FILE}"
echo "File size: $(wc -c < "${OUTPUT_FILE}") bytes"

# ────────────────────────────────────────────────────────────────
# Generate executable installer (if -e flag is set)
# ────────────────────────────────────────────────────────────────

if [[ "${BUILD_EXECUTABLE}" == "true" ]]; then
    echo ""
    echo "Generating executable installer..."

    # Verify that the 'app' command exists (required for executable mode)
    APP_DIR="${SRC_DIR}/commands/app"
    if [[ ! -d "${APP_DIR}" ]]; then
        echo "Error: The 'app' command is required for executable mode (-e)" >&2
        echo "Please create: ${APP_DIR}/" >&2
        echo "  - ${APP_DIR}/schema.json" >&2
        echo "  - ${APP_DIR}/main.sh" >&2
        exit 1
    fi

    if [[ ! -f "${APP_DIR}/schema.json" ]] || [[ ! -f "${APP_DIR}/main.sh" ]]; then
        echo "Error: The 'app' command is incomplete" >&2
        echo "Required files:" >&2
        [[ ! -f "${APP_DIR}/schema.json" ]] && echo "  - ${APP_DIR}/schema.json (missing)" >&2
        [[ ! -f "${APP_DIR}/main.sh" ]] && echo "  - ${APP_DIR}/main.sh (missing)" >&2
        exit 1
    fi

    # Get CLI name from the output file
    CLI_NAME=$(basename "${OUTPUT_FILE}" .sh)

    # Base64 encode the CLI script for embedding
    CLI_PAYLOAD=$(base64 < "${OUTPUT_FILE}")

    cat > "${INSTALLER_FILE}" << 'INSTALLER_HEADER'
#!/usr/bin/env sh
#
# install.sh - Auto-installer for CLI
#
# Usage:
#   curl -LsSf https://example.com/install.sh | sh
#   wget -qO- https://example.com/install.sh | sh
#
# Environment variables:
#   INSTALL_DIR  - Installation directory (default: ~/.local/bin)
#   CLI_NAME     - Name for the installed binary (default: cli)
#

set -e

INSTALLER_HEADER

    # Add configuration
    cat >> "${INSTALLER_FILE}" << EOF
CLI_NAME="${CLI_NAME}"
DEFAULT_INSTALL_DIR="\${HOME}/.local/bin"
EOF

    cat >> "${INSTALLER_FILE}" << 'INSTALLER_BODY'

# ────────────────────────────────────────────────────────────────
# Helper functions
# ────────────────────────────────────────────────────────────────

info() {
    printf '\033[0;34m[INFO]\033[0m %s\n' "$1"
}

success() {
    printf '\033[0;32m[OK]\033[0m %s\n' "$1"
}

error() {
    printf '\033[0;31m[ERROR]\033[0m %s\n' "$1" >&2
}

warn() {
    printf '\033[0;33m[WARN]\033[0m %s\n' "$1"
}

# Check if a command exists
has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# Decode base64 (portable across systems)
decode_base64() {
    if has_cmd base64; then
        base64 -d 2>/dev/null || base64 -D 2>/dev/null
    elif has_cmd openssl; then
        openssl base64 -d
    else
        error "No base64 decoder found (need base64 or openssl)"
        exit 1
    fi
}

# ────────────────────────────────────────────────────────────────
# Installation
# ────────────────────────────────────────────────────────────────

main() {
    info "Installing ${CLI_NAME}..."

    # Determine installation directory
    INSTALL_DIR="${INSTALL_DIR:-${DEFAULT_INSTALL_DIR}}"
    TARGET="${INSTALL_DIR}/${CLI_NAME}"

    # Create install directory if needed
    if [ ! -d "${INSTALL_DIR}" ]; then
        info "Creating directory: ${INSTALL_DIR}"
        mkdir -p "${INSTALL_DIR}"
    fi

    # Extract and install the CLI
    info "Extracting ${CLI_NAME} to ${TARGET}..."

    # The payload is embedded below this line
    sed -n '/^__PAYLOAD_BEGIN__$/,/^__PAYLOAD_END__$/p' "$0" \
        | sed '1d;$d' \
        | decode_base64 > "${TARGET}"

    chmod +x "${TARGET}"
    success "Installed ${CLI_NAME} to ${TARGET}"

    # Check if install directory is in PATH
    case ":${PATH}:" in
        *":${INSTALL_DIR}:"*)
            success "${CLI_NAME} is ready to use!"
            ;;
        *)
            warn "${INSTALL_DIR} is not in your PATH"
            echo ""
            echo "Add the following to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
            echo ""
            echo "    export PATH=\"\${PATH}:${INSTALL_DIR}\""
            echo ""
            echo "Then restart your shell or run:"
            echo ""
            echo "    source ~/.bashrc  # or ~/.zshrc"
            echo ""
            ;;
    esac

    # Show version
    echo ""
    info "Verifying installation..."
    "${TARGET}" --version || true

    echo ""
    success "Installation complete!"
    echo ""
    echo "Enable shell completions by adding to your shell profile:"
    echo ""
    echo "    eval \"\$(${CLI_NAME} completion)\""
    echo ""
}

# Run if executed directly (not sourced)
# When piped via curl | sh, this script runs as stdin
main "$@"
exit 0

# ────────────────────────────────────────────────────────────────
# Embedded payload (base64 encoded CLI)
# ────────────────────────────────────────────────────────────────
__PAYLOAD_BEGIN__
INSTALLER_BODY

    # Embed the base64-encoded CLI payload
    echo "${CLI_PAYLOAD}" >> "${INSTALLER_FILE}"

    cat >> "${INSTALLER_FILE}" << 'INSTALLER_FOOTER'
__PAYLOAD_END__
INSTALLER_FOOTER

    chmod +x "${INSTALLER_FILE}"

    echo "Installer created: ${INSTALLER_FILE}"
    echo "Installer size: $(wc -c < "${INSTALLER_FILE}") bytes"
    echo ""
    echo "Usage:"
    echo "  curl -LsSf https://example.com/install.sh | sh"
    echo "  wget -qO- https://example.com/install.sh | sh"
    echo ""
    echo "Or run directly:"
    echo "  sh ${INSTALLER_FILE}"
fi
