#!/usr/bin/env bash
#
# flags.sh - Flag registry and argument parsing framework
#

# Prevent multiple sourcing
[[ -n "${__FLAGS_SH_LOADED:-}" ]] && return 0
readonly __FLAGS_SH_LOADED=1

# ────────────────────────────────────────────────────────────────
# Flag Registry Storage
# ────────────────────────────────────────────────────────────────
declare -a __FLAG_REGISTRY=()
declare -A __FLAG_VALUES=()
declare -a __POSITIONAL_ARGS=()
declare -A __FLAG_MUTEX_GROUPS=()

# ────────────────────────────────────────────────────────────────
# Flag Registration
# Format: long_name|short|type|required|default|help|scope
# Types: string, path, int, bool, enum:val1:val2, none (flag only)
# Scope: global, command_name
# ────────────────────────────────────────────────────────────────

register_arg() {
    local long_name="$1"
    local short_name="${2:-}"
    local type="${3:-string}"
    local required="${4:-false}"
    local default="${5:-}"
    local help_text="${6:-}"
    local scope="${7:-global}"

    __FLAG_REGISTRY+=("${long_name}|${short_name}|${type}|${required}|${default}|${help_text}|${scope}")

    # Set default value
    if [[ -n "${default}" ]]; then
        __FLAG_VALUES["${long_name}"]="${default}"
    fi
}

# Register mutually exclusive flags
register_mutex_group() {
    local group_name="$1"
    shift
    __FLAG_MUTEX_GROUPS["${group_name}"]="$*"
}

# ────────────────────────────────────────────────────────────────
# Flag Lookup Helpers
# ────────────────────────────────────────────────────────────────

__get_arg_entry() {
    local search="$1"
    local entry

    for entry in "${__FLAG_REGISTRY[@]}"; do
        local long short
        IFS='|' read -r long short _ <<< "${entry}"

        if [[ "${long}" == "${search}" ]] || [[ "${short}" == "${search}" ]]; then
            echo "${entry}"
            return 0
        fi
    done
    return 1
}

__get_arg_long_name() {
    local search="$1"
    local entry

    if entry=$(__get_arg_entry "${search}"); then
        echo "${entry%%|*}"
        return 0
    fi
    return 1
}

__get_arg_type() {
    local name="$1"
    local entry

    if entry=$(__get_arg_entry "${name}"); then
        IFS='|' read -r _ _ type _ <<< "${entry}"
        echo "${type}"
        return 0
    fi
    echo "string"
}

# ────────────────────────────────────────────────────────────────
# Argument Parsing
# ────────────────────────────────────────────────────────────────

parse_args() {
    local current_command="${1:-}"
    shift || true

    __POSITIONAL_ARGS=()
    local -A seen_flags=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            # Long flags with =
            --*=*)
                local key="${1%%=*}"
                local value="${1#*=}"
                key="${key#--}"

                __process_flag "${key}" "${value}" "${current_command}" seen_flags
                shift
                ;;

            # Long flags
            --*)
                local key="${1#--}"
                shift

                local type
                type=$(__get_arg_type "${key}")

                if [[ "${type}" == "none" ]] || [[ "${type}" == "bool" ]]; then
                    __process_flag "${key}" "true" "${current_command}" seen_flags
                elif [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
                    __process_flag "${key}" "$1" "${current_command}" seen_flags
                    shift
                else
                    __process_flag "${key}" "true" "${current_command}" seen_flags
                fi
                ;;

            # Short flags
            -*)
                local keys="${1#-}"
                shift

                # Handle grouped short flags: -abc
                if [[ ${#keys} -gt 1 ]]; then
                    local i
                    for ((i = 0; i < ${#keys}; i++)); do
                        local k="${keys:$i:1}"
                        __process_flag "${k}" "true" "${current_command}" seen_flags
                    done
                else
                    local type
                    type=$(__get_arg_type "${keys}")

                    if [[ "${type}" == "none" ]] || [[ "${type}" == "bool" ]]; then
                        __process_flag "${keys}" "true" "${current_command}" seen_flags
                    elif [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
                        __process_flag "${keys}" "$1" "${current_command}" seen_flags
                        shift
                    else
                        __process_flag "${keys}" "true" "${current_command}" seen_flags
                    fi
                fi
                ;;

            # Positional argument
            *)
                __POSITIONAL_ARGS+=("$1")
                shift
                ;;
        esac
    done

    # Validate required flags
    __validate_required_flags "${current_command}"

    # Check mutex groups
    __validate_mutex_groups
}

__process_flag() {
    local key="$1"
    local value="$2"
    local command="$3"
    local -n seen="$4"

    # Resolve to long name
    local long_name
    if ! long_name=$(__get_arg_long_name "${key}"); then
        die_usage "Unknown flag: --${key}"
    fi

    # Check scope
    local entry type
    entry=$(__get_arg_entry "${long_name}")
    IFS='|' read -r _ _ type _ _ _ scope <<< "${entry}"

    if [[ "${scope}" != "global" ]] && [[ "${scope}" != "${command}" ]]; then
        die_usage "Flag --${long_name} is not valid for command '${command}'"
    fi

    # Type validation
    __validate_flag_type "${long_name}" "${value}" "${type}"

    # Store value
    __FLAG_VALUES["${long_name}"]="${value}"
    seen["${long_name}"]=1
}

__validate_flag_type() {
    local name="$1"
    local value="$2"
    local type="$3"

    case "${type}" in
        int)
            if ! is_int "${value}"; then
                die_validation "Flag --${name} requires an integer, got '${value}'"
            fi
            ;;
        bool)
            if ! is_bool "${value}"; then
                die_validation "Flag --${name} requires a boolean, got '${value}'"
            fi
            __FLAG_VALUES["${name}"]=$(normalize_bool "${value}")
            ;;
        path)
            if ! is_valid_path "${value}"; then
                die_validation "Flag --${name} path does not exist: '${value}'"
            fi
            ;;
        enum:*)
            local allowed="${type#enum:}"
            IFS=':' read -ra values <<< "${allowed}"
            if ! is_enum "${value}" "${values[@]}"; then
                die_validation "Flag --${name} must be one of: ${allowed//:/, }"
            fi
            ;;
        string|none)
            # No validation needed
            ;;
        *)
            die_internal "Unknown flag type: ${type}"
            ;;
    esac
}

__validate_required_flags() {
    local command="$1"
    local entry

    for entry in "${__FLAG_REGISTRY[@]}"; do
        local long _ _ required _ _ scope
        IFS='|' read -r long _ _ required _ _ scope <<< "${entry}"

        if [[ "${required}" == "true" ]]; then
            if [[ "${scope}" == "global" ]] || [[ "${scope}" == "${command}" ]]; then
                if [[ -z "${__FLAG_VALUES[${long}]:-}" ]]; then
                    die_usage "Required flag --${long} is missing"
                fi
            fi
        fi
    done
}

__validate_mutex_groups() {
    local group_name flags
    for group_name in "${!__FLAG_MUTEX_GROUPS[@]}"; do
        local -a set_flags=()
        IFS=' ' read -ra flags <<< "${__FLAG_MUTEX_GROUPS[${group_name}]}"

        local flag
        for flag in "${flags[@]}"; do
            if [[ -n "${__FLAG_VALUES[${flag}]:-}" ]]; then
                set_flags+=("--${flag}")
            fi
        done

        if [[ ${#set_flags[@]} -gt 1 ]]; then
            die_usage "Flags ${set_flags[*]} are mutually exclusive"
        fi
    done
}

# ────────────────────────────────────────────────────────────────
# Value Accessors
# ────────────────────────────────────────────────────────────────

get_arg() {
    local name="$1"
    local default="${2:-}"
    echo "${__FLAG_VALUES[${name}]:-${default}}"
}

has_flag() {
    local name="$1"
    [[ -n "${__FLAG_VALUES[${name}]:-}" ]]
}

is_flag_true() {
    local name="$1"
    local value="${__FLAG_VALUES[${name}]:-false}"
    [[ "${value}" == "true" ]]
}

get_positional() {
    local index="$1"
    local default="${2:-}"
    echo "${__POSITIONAL_ARGS[${index}]:-${default}}"
}

get_positional_count() {
    echo "${#__POSITIONAL_ARGS[@]}"
}

get_all_positional() {
    printf '%s\n' "${__POSITIONAL_ARGS[@]}"
}

# ────────────────────────────────────────────────────────────────
# Help Generation
# ────────────────────────────────────────────────────────────────

generate_flag_help() {
    local scope="${1:-global}"
    local entry

    for entry in "${__FLAG_REGISTRY[@]}"; do
        local long short type required default help flag_scope
        IFS='|' read -r long short type required default help flag_scope <<< "${entry}"

        # Filter by scope
        if [[ "${scope}" != "all" ]] && [[ "${flag_scope}" != "global" ]] && [[ "${flag_scope}" != "${scope}" ]]; then
            continue
        fi

        # Build flag string
        local flag_str="  --${long}"
        [[ -n "${short}" ]] && flag_str+=", -${short}"

        # Add type hint
        case "${type}" in
            string) flag_str+=" <string>" ;;
            int) flag_str+=" <int>" ;;
            path) flag_str+=" <path>" ;;
            enum:*) flag_str+=" <${type#enum:}>" ;;
            bool|none) ;;
        esac

        # Print with padding
        printf "%-22s %s" "${flag_str}" "${help}"

        # Add default/required info
        if [[ "${required}" == "true" ]]; then
            printf " (required)"
        elif [[ -n "${default}" ]]; then
            printf " [default: %s]" "${default}"
        fi
        printf "\n"
    done
}

# ────────────────────────────────────────────────────────────────
# Built-in Global Flags
# ────────────────────────────────────────────────────────────────

__register_builtin_flags() {
    register_arg "help" "h" "none" "false" "" "Show help message" "global"
    register_arg "verbose" "v" "none" "false" "" "Enable verbose output" "global"
    register_arg "quiet" "q" "none" "false" "" "Suppress output" "global"
    register_arg "no-color" "" "none" "false" "" "Disable colored output" "global"
    register_arg "version" "V" "none" "false" "" "Show version" "global"

    register_mutex_group "verbosity" "verbose" "quiet"
}

# Auto-register built-in flags
__register_builtin_flags
