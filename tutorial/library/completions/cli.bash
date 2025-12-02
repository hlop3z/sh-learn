#!/usr/bin/env bash
#
# Bash completion for CLI framework
#
# Installation:
#   source ./completions/cli.bash
#
# Or copy to:
#   /etc/bash_completion.d/cli
#   ~/.local/share/bash-completion/completions/cli
#

_cli_completions() {
    local cur prev words cword
    _init_completion 2>/dev/null || {
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        words=("${COMP_WORDS[@]}")
        cword="${COMP_CWORD}"
    }

    # Available commands
    local commands="greet info help version commands"

    # Global flags
    local global_flags="--help -h --verbose -v --quiet -q --no-color --version -V"

    # Command-specific flags
    local greet_flags="--name -n --uppercase -u --times -t"
    local info_flags=""

    # First argument: complete commands
    if [[ ${cword} -eq 1 ]]; then
        COMPREPLY=($(compgen -W "${commands} ${global_flags}" -- "${cur}"))
        return 0
    fi

    # Get the command (first non-flag argument)
    local cmd=""
    local i
    for ((i = 1; i < cword; i++)); do
        if [[ "${words[i]}" != -* ]]; then
            cmd="${words[i]}"
            break
        fi
    done

    # Complete based on command
    case "${cmd}" in
        greet)
            case "${prev}" in
                --name|-n)
                    # No specific completions for name
                    return 0
                    ;;
                --times|-t)
                    COMPREPLY=($(compgen -W "1 2 3 5 10" -- "${cur}"))
                    return 0
                    ;;
                *)
                    COMPREPLY=($(compgen -W "${greet_flags} ${global_flags}" -- "${cur}"))
                    return 0
                    ;;
            esac
            ;;
        info)
            COMPREPLY=($(compgen -W "${info_flags} ${global_flags}" -- "${cur}"))
            return 0
            ;;
        help)
            # Complete with command names for help topics
            COMPREPLY=($(compgen -W "${commands}" -- "${cur}"))
            return 0
            ;;
        *)
            # Default to global flags
            COMPREPLY=($(compgen -W "${global_flags}" -- "${cur}"))
            return 0
            ;;
    esac
}

# Register completion
complete -F _cli_completions cli
complete -F _cli_completions cli.sh
complete -F _cli_completions ./cli.sh
