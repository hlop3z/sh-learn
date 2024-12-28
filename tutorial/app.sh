#!/bin/sh

# =======================================================================================
# Script Documentation
# =======================================================================================
# This script demonstrates how to parse command-line arguments, validate required fields,
# and process inputs. It supports both positional and keyword parameters.
# =======================================================================================

# ---------------------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------------------

SINGLE_COMMAND=false
# SINGLE_COMMAND:
#   - If `true`: Script uses options without a command.
#       Example: script.sh [options]
#   - If `false`: Script requires a command followed by options.
#       Example: script.sh <command> [options]

# ---------------------------------------------------------------------------------------
# Command-Line Interface (CLI)
# ---------------------------------------------------------------------------------------

# CLI: Main entry point for user interaction.
# Usage: app.sh -n "hello world" -y
# Usage: app.sh command -n "hello world" -y
CLI() {
    # Variables
    local name
    local y_value

    # Retrieve input values
    name=$(Get n name)
    y_value=$(Get y yes)

    # Display retrieved values
    echo "Name   : $name"
    echo "Var-Y  : $y_value"

    # Example usage of `Set` and `Get`
    Set "key" "value"
    echo "Var-Key: $(Get key)"
    echo "Command: $(Get CMD)"

    # Ensure 'name' is provided (Required example)
    Required "$name" "Please provide a name using --name <name>."
}

# ---------------------------------------------------------------------------------------
# @ Methods
# ---------------------------------------------------------------------------------------
# - Get         : Retrieve a global variable value.
# - Set         : Store a global variable value.
# - Required    : Check if a required field is provided.
# ---------------------------------------------------------------------------------------
# _________ _______  _______  _        _______
# \__   __/(  ___  )(  ___  )( \      (  ____ \
#    ) (   | (   ) || (   ) || (      | (    \/
#    | |   | |   | || |   | || |      | (_____
#    | |   | |   | || |   | || |      (_____  )
#    | |   | |   | || |   | || |            ) |
#    | |   | (___) || (___) || (____/\/\____) |
#    )_(   (_______)(_______)(_______/\_______)
#
# ---------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------
# Global Methods (@Wrapper)
# ---------------------------------------------------------------------------------------

# Initialize the script with provided arguments.
Init() {
    # Parse arguments
    __kwargs__ "$@"

    # Store the first argument as the command
    Set "CMD" "$1"

    # Check if command is required
    if ! $SINGLE_COMMAND; then
        Required "$(Get CMD)" "Please enter a command."
    fi
}

# Set: Store a key-value pair globally.
# Usage: Set <key> <value>
Set() {
    __set__ "$@"
}

# Get: Retrieve a value for a given key.
# Usage: Get <key>
Get() {
    __get__ "$@"
}

# Required: Ensure a mandatory value is provided.
# Usage: Required <value> <error_message>
Required() {
    __required__ "$@"
}

# ---------------------------------------------------------------------------------------
# Internal Functions
# ---------------------------------------------------------------------------------------

# Prefix for global variables to avoid naming conflicts.
__PREFIX__="x________"

# Set a global variable
__set__() {
    local key="${__PREFIX__}$1"
    local val="$2"
    eval "$key=\"$val\""
}

# Get a global variable
__get__() {
    local key val=""
    for key in "$@"; do
        val=$(__getter__ "$key")
        if [ -n "$val" ]; then
            break
        fi
    done
    echo "$val"
}

# Helper to retrieve a global variable value.
__getter__() {
    local key="${__PREFIX__}$1"
    eval "echo \${$key:-}"
}

# Parse arguments into key-value pairs.
__kwargs__() {
    # Arguments
    local key=""
    local val=""
    local expecting_command=$SINGLE_COMMAND

    # Logic to process arguments
    while [ "$1" != "" ]; do
        if ! $expecting_command && $SINGLE_COMMAND; then
            expecting_command=false
            shift
            continue
        fi

        if [[ "$1" == -?* ]]; then
            # Get Key
            key=$(__strip_prefix__ "$1")

            # Attempt to shift to get the value
            shift || true

            # Check if a value is provided
            if [ -z "$1" ] || [[ "$1" == -?* ]]; then
                val="true"
            else
                val="$1"
                shift
            fi

            # Set Value
            __set__ "$key" "$val"
        else
            shift
        fi
    done
}

# Remove leading dashes from argument keys.
__strip_prefix__() {
    local input="$1"
    input="${input#--}"
    input="${input#-}"
    echo "$input"
}

# Ensure a required value is provided.
__required__() {
    if [ -z "$1" ]; then
        echo
        echo ==========================================================================
        echo "Error @ $2" >&2
        echo ==========================================================================
        exit 1
    fi
}

# ---------------------------------------------------------------------------------------
# Main Execution
# ---------------------------------------------------------------------------------------

# Initialize the script with arguments.
Init "$@"

# Execute the CLI function.
CLI
