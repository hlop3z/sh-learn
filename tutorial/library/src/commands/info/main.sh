#!/usr/bin/env bash
#
# info - Display CLI and system information
#

cmd_info() {
    local blue cyan reset
    blue=$(color "#5599FF")
    cyan=$(color "#00CCCC")
    reset="${__COLOR_RESET}"

    printf '%b%s%b\n' "${blue}" "CLI Framework Information" "${reset}"
    echo "─────────────────────────────"

    printf '%b%-15s%b %s\n' "${cyan}" "CLI Name:" "${reset}" "${__CLI_NAME}"
    printf '%b%-15s%b %s\n' "${cyan}" "Version:" "${reset}" "${__CLI_VERSION}"
    printf '%b%-15s%b %s\n' "${cyan}" "Shell:" "${reset}" "$(detect_shell) $(get_bash_version)"
    printf '%b%-15s%b %s\n' "${cyan}" "OS:" "${reset}" "$(get_os)"
    printf '%b%-15s%b %s\n' "${cyan}" "Terminal:" "${reset}" "$(get_term_width)x$(get_term_height)"

    echo ""
    printf '%b%s%b\n' "${blue}" "Registered Commands" "${reset}"
    echo "─────────────────────────────"

    local cmd
    for cmd in $(list_commands); do
        printf '  %b%-15s%b %s\n' "${cyan}" "${cmd}" "${reset}" "${__COMMAND_HELP[${cmd}]:-}"
    done

    echo ""
    printf '%b%s%b\n' "${blue}" "Features" "${reset}"
    echo "─────────────────────────────"

    printf '  %-20s %s\n' "Arrays:" "$(supports_arrays && echo 'Yes' || echo 'No')"
    printf '  %-20s %s\n' "Assoc Arrays:" "$(supports_assoc_arrays && echo 'Yes' || echo 'No')"
    printf '  %-20s %s\n' "Extended Glob:" "$(supports_extglob && echo 'Yes' || echo 'No')"
    printf '  %-20s %s\n' "Color Support:" "$([[ ${__LOG_COLOR} -eq 1 ]] && echo 'Yes' || echo 'No')"
}
