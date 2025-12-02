#!/usr/bin/env bash
set -euo pipefail

#
# Git Helper CLI
# Usage: ./scripts/git.sh <command> [options]
#
# Commands:
#   commit [-m "message"]   Commit and push (auto-generates ID if no message)
#   status                  Show git status
#

# ────────────────────────────────────────────────────────────────
# Settings
# ────────────────────────────────────────────────────────────────

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get project root (parent of scripts dir)
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ────────────────────────────────────────────────────────────────
# Colors
# ────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ────────────────────────────────────────────────────────────────
# Helper Functions
# ────────────────────────────────────────────────────────────────

print_usage() {
    echo -e "${CYAN}Git Helper CLI${NC}"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  commit [-m \"message\"]          Commit and push changes"
    echo "                                   Auto-generates short ID if no message provided"
    echo ""
    echo "  status                           Show git status"
    echo ""
    echo "Examples:"
    echo "  $0 commit                        # Commit with auto-generated ID"
    echo "  $0 commit -m \"fix: bug fix\"    # Commit with custom message"
    echo "  $0 status                        # Show current git status"
}

generate_id() {
    # Generate a short random ID using /dev/urandom (works on Linux/macOS/WSL)
    if command -v openssl &> /dev/null; then
        openssl rand -hex 4
    elif [[ -r /dev/urandom ]]; then
        head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n'
    else
        # Fallback: use date-based ID
        date +%s | tail -c 8
    fi
}

# ────────────────────────────────────────────────────────────────
# Git Functions
# ────────────────────────────────────────────────────────────────

do_commit() {
    local message="${1:-}"

    cd "$PROJECT_ROOT"

    # Check if there are changes to commit
    if git diff --quiet && git diff --cached --quiet && [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
        echo -e "${YELLOW}No changes to commit.${NC}"
        return 0
    fi

    # Generate ID message if not provided
    if [[ -z "$message" ]]; then
        message="auto: $(generate_id)"
        echo -e "${BLUE}Generated commit message:${NC} $message"
    fi

    echo -e "${CYAN}Staging changes...${NC}"
    git add -A

    echo -e "${CYAN}Committing...${NC}"
    git commit -m "$message"

    echo -e "${CYAN}Pushing to remote...${NC}"
    git push

    echo -e "${GREEN}[OK] Commit and push complete!${NC}"
}

do_status() {
    cd "$PROJECT_ROOT"

    echo -e "${CYAN}Git Status${NC}"
    echo "────────────────────────────────────────"
    git status
}

# ────────────────────────────────────────────────────────────────
# Main CLI
# ────────────────────────────────────────────────────────────────

main() {
    if [[ $# -eq 0 ]]; then
        print_usage
        exit 0
    fi

    local command="$1"
    shift

    case "$command" in
        commit)
            local message=""
            while [[ $# -gt 0 ]]; do
                case $1 in
                    -m|--message)
                        message="$2"
                        shift 2
                        ;;
                    *)
                        echo -e "${RED}Unknown option for commit: $1${NC}"
                        exit 1
                        ;;
                esac
            done
            do_commit "$message"
            ;;
        status)
            do_status
            ;;
        --help|-h|help)
            print_usage
            ;;
        *)
            echo -e "${RED}Unknown command: $command${NC}"
            echo ""
            print_usage
            exit 1
            ;;
    esac
}

main "$@"
