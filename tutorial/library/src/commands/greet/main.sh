#!/usr/bin/env bash
#
# greet - Greet a user with a friendly message
#

cmd_greet() {
    local name times uppercase
    name=$(get_arg "name")
    times=$(get_arg "times")
    uppercase=$(get_arg "uppercase")

    log_debug "Greeting ${name} ${times} time(s)"

    local message="Hello, ${name}!"

    if [[ "${uppercase}" == "true" ]]; then
        message="${message^^}"
    fi

    local i
    for ((i = 0; i < times; i++)); do
        print_color "#00FF00" "${message}"
    done
}
