# Cross-Platform Shell CLI Framework

A production-ready shell CLI framework with structured command dispatch, type-safe flag parsing, and comprehensive error handling. Compatible with **Linux**, **macOS**, and **Git Bash (Windows)**.

---

## Features

- **Command Registry**: Structured command dispatch with automatic discovery
- **Type-Safe Flags**: Flag parsing with validation (`string`, `int`, `bool`, `path`, `enum`)
- **JSON Schema Config**: Define command arguments in `schema.json` files
- **Single-File Build**: Compile to a single distributable `cli.sh`
- **Error Handling**: Standardized exit codes, `set -euo pipefail`, and trap handlers
- **Logging System**: Leveled logging (DEBUG/INFO/WARN/ERROR) with timestamps
- **Hex Colors**: True-color output support with automatic TTY detection
- **Cross-Platform**: Portable implementations for path resolution, sed, date
- **Shell Completions**: Generated Bash and Zsh completions

---

## Project Structure

```
library/
├── build.sh                    # Build script (compiles to single file)
├── dist/
│   └── cli.sh                  # Built distributable (single file)
├── src/
│   ├── cli.sh                  # Development entry point
│   ├── core/
│   │   ├── errors.sh           # Error handling & exit codes
│   │   ├── validation.sh       # Type validators
│   │   ├── flags.sh            # Flag registry & parsing
│   │   ├── portability.sh      # Cross-platform abstractions
│   │   └── logging.sh          # Logging subsystem
│   └── commands/
│       ├── greet/
│       │   ├── schema.json     # Argument definitions
│       │   └── main.sh         # Command handler
│       └── info/
│           ├── schema.json
│           └── main.sh
└── completions/
    ├── cli.bash                # Bash completions
    └── _cli                    # Zsh completions
```

---

## Quick Start

```sh
# Build the CLI
./build.sh

# Run CLI
./dist/cli.sh --help
./dist/cli.sh greet --name Alice
./dist/cli.sh info

# With flags
./dist/cli.sh greet -n Bob --times 3 --uppercase
./dist/cli.sh --verbose greet -n World
```

---

## Adding Commands

1. Create a new folder in `src/commands/`:

```text
src/commands/deploy/
├── schema.json
└── main.sh
```

2. Define arguments in `schema.json`:

```json
{
  "name": "deploy",
  "description": "Deploy application to target environment",
  "args": [
    {
      "name": "env",
      "short": "e",
      "type": "enum:dev:staging:prod",
      "required": true,
      "default": "",
      "help": "Target environment"
    },
    {
      "name": "dry-run",
      "short": "d",
      "type": "bool",
      "required": false,
      "default": "false",
      "help": "Simulate deployment"
    }
  ]
}
```

3. Implement the handler in `main.sh`:

```sh
#!/usr/bin/env bash
#
# deploy - Deploy application to target environment
#

cmd_deploy() {
    local env dry_run
    env=$(get_arg "env")
    dry_run=$(get_arg "dry-run")

    if [[ "${dry_run}" == "true" ]]; then
        log_info "Dry run: would deploy to ${env}"
    else
        log_info "Deploying to ${env}..."
        # deployment logic here
    fi
}
```

4. Run `./build.sh` to rebuild the CLI.

---

## Schema.json Reference

| Field      | Type    | Description                        |
| ---------- | ------- | ---------------------------------- |
| `name`     | string  | Argument long name (e.g., `"env"`) |
| `short`    | string  | Short flag (e.g., `"e"` for `-e`)  |
| `type`     | string  | Type validation (see types below)  |
| `required` | boolean | Whether the argument is required   |
| `default`  | string  | Default value if not provided      |
| `help`     | string  | Help text shown in `--help`        |

---

## Flag Types

| Type         | Description             | Example                       |
| ------------ | ----------------------- | ----------------------------- |
| `string`     | Any string value        | `--name Alice`                |
| `int`        | Integer value           | `--port 8080`                 |
| `bool`       | Boolean flag            | `--verbose` or `--debug true` |
| `path`       | Existing file/directory | `--config ./app.conf`         |
| `enum:a:b:c` | One of allowed values   | `--env dev`                   |
| `none`       | Flag-only (no value)    | `--force`                     |

---

## Exit Codes

| Code | Constant           | Description                   |
| ---- | ------------------ | ----------------------------- |
| 0    | `EXIT_SUCCESS`     | Success                       |
| 1    | `EXIT_USAGE`       | Invalid usage/unknown command |
| 2    | `EXIT_VALIDATION`  | Validation error              |
| 3    | `EXIT_ENVIRONMENT` | Missing dependency            |
| 4    | `EXIT_INTERNAL`    | Internal error                |
| 5    | `EXIT_EXTERNAL`    | External command failed       |

---

## Logging

```sh
# Set level via flags
./dist/cli.sh --verbose command   # DEBUG level
./dist/cli.sh --quiet command     # Suppress output

# In code
log_debug "Detailed info"
log_info "Normal info"
log_warn "Warning message"
log_error "Error message"

# Colored output
print_color "#FF5500" "Orange text"
success "Green success message"
```

---

## Shell Completions

```sh
# Bash
source ./completions/cli.bash

# Zsh
cp ./completions/_cli ~/.zsh/completions/
autoload -Uz compinit && compinit
```

---

## Requirements

- **Bash 4+** (Linux, macOS, Git Bash, WSL)
- Zsh supported for completions only
- No external dependencies (no jq required)

---

## API Reference

### Errors (`core/errors.sh`)

- `die <code> <message>` - Exit with error
- `die_usage`, `die_validation`, `die_environment` - Category-specific exits
- `enable_strict_mode` - Enable `set -euo pipefail` + ERR trap
- `try <command>` - Execute without triggering ERR trap
- `assert <condition>` - Assert condition or die

### Validation (`core/validation.sh`)

- `is_int`, `is_bool`, `is_valid_path`, `is_enum` - Type validators (return 0/1)
- `require_int`, `require_bool`, `require_path` - Validators that die on failure

### Flags (`core/flags.sh`)

- `register_arg <long> <short> <type> <required> <default> <help> <scope>`
- `parse_args <command> "$@"` - Parse arguments
- `get_arg <name> [default]` - Get flag value
- `has_flag`, `is_flag_true` - Check flag state
- `get_positional <index>` - Get positional argument

### Portability (`core/portability.sh`)

- `detect_os`, `is_linux`, `is_macos`, `is_windows`
- `require_bash_version <major>`
- `portable_realpath`, `get_script_dir`
- `is_tty`, `get_term_width`

### Logging (`core/logging.sh`)

- `log_debug`, `log_info`, `log_warn`, `log_error`
- `set_log_level`, `set_log_file`
- `color "#RRGGBB"`, `print_color "#RRGGBB" "text"`
- `success`, `warning`, `failure`, `bold`
