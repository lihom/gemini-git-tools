#!/bin/bash

# Shared configuration
# You can override these via environment variables
EXCLUDE_PATTERN="${GEMINI_EXCLUDE_PATTERN:-}"
DEFAULT_MODEL="${GEMINI_MODEL:-gemini-3-flash-preview}"

# Function to validate argument values
validate_arg_value() {
    local flag=$1
    local value=$2
    if [[ -z "$value" || "$value" == --* ]]; then
        echo "❌ Error: $flag requires a value"
        exit 1
    fi
}

# Function to check for dangerous shell characters to prevent command injection
# Focusing on characters that can trigger command execution or break out of quotes.
validate_input_safety() {
    for var in "$@"; do
        if [[ -n "$var" && "$var" == *[";\"'\\\`\$&|><()"]* ]]; then
            echo "❌ Error: Invalid characters in arguments."
            exit 1
        fi
    done
}
