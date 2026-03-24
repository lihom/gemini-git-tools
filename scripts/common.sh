#!/bin/bash

# Shared configuration
# You can override these via environment variables
EXCLUDE_PATTERN="${GEMINI_EXCLUDE_PATTERN:-":(exclude)package-lock.json" ":(exclude)pnpm-lock.yaml"}"
DEFAULT_MODEL="${GEMINI_MODEL:-gemini-3-flash-preview}"

# Centralized input safety validation
# Focuses on characters that can trigger command execution or break out of quotes.
validate_input_safety() {
    for var in "$@"; do
        # Use case for robust character matching without complex escaping issues
        case "$var" in
            *[";\`\$&|><"]*)
                echo "❌ Error: Invalid characters in arguments."
                exit 1
                ;;
        esac
    done
}

# Helper to validate that an argument value is provided and not another flag
validate_arg_value() {
    if [[ -z "$2" || "$2" == -* ]]; then
        echo "❌ Error: $1 requires a value."
        exit 1
    fi
}

# Centralized git diff retrieval
get_git_diff() {
    local target="$1"
    local pattern="$2"
    if [ -n "$pattern" ]; then
        # Use -- to ensure pattern parts are treated as pathspecs, not flags
        # Quote "$pattern" to ensure Git handles globbing, not the shell
        git diff "$target" -- "$pattern"
    else
        git diff "$target"
    fi
}
