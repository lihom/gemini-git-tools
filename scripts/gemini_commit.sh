#!/bin/bash

# Source common logic
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# 1. Parse arguments
MODEL="$DEFAULT_MODEL"
CUSTOM_TASK="general commit"
NON_INTERACTIVE=false
OUTPUT_FILE=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --prompt) 
      validate_arg_value "$1" "$2"
      CUSTOM_TASK="$2"; shift ;;
    --prompt-file) 
      validate_arg_value "$1" "$2"
      if [[ -f "$2" ]]; then
        CUSTOM_TASK=$(cat "$2")
      else
        echo "❌ Error: File $2 not found or inaccessible."
        exit 1
      fi
      shift ;;
    --model)  
      validate_arg_value "$1" "$2"
      MODEL="$2"; shift ;;
    --non-interactive)
      NON_INTERACTIVE=true ;;
    --output)
      validate_arg_value "$1" "$2"
      OUTPUT_FILE="$2"; shift ;;
    *) echo "❌ Error: Invalid parameter: $1"; exit 1 ;;
  esac
  shift
done

# 2. Get the staged changes
if [ "$NON_INTERACTIVE" = true ]; then
  DIFF_COMMIT_ID_OR_BRANCH="--cached"
else
  read -p "please enter your diff commit id or branch: " DIFF_COMMIT_ID_OR_BRANCH

  if [ -z "$DIFF_COMMIT_ID_OR_BRANCH" ]; then
    DIFF_COMMIT_ID_OR_BRANCH="--cached"
  fi
fi

# Input Safety Validation - Include EXCLUDE_PATTERN
validate_input_safety "$DIFF_COMMIT_ID_OR_BRANCH" "$MODEL" "$CUSTOM_TASK" "$EXCLUDE_PATTERN"

# Check if there are any changes to commit (efficiently)
if ! get_git_diff "$DIFF_COMMIT_ID_OR_BRANCH" "$EXCLUDE_PATTERN" | grep -q .; then
  echo "❌ Error: No changes staged for commit."
  exit 1
fi

echo "🤖 $MODEL is drafting your commit message..."

# 3. Construct the AI Prompt safely in parts to avoid shell expansion (ARG_MAX)
TMP_PROMPT=$(mktemp) || exit 1
# Ensure cleanup on exit or interruption
trap 'rm -f "$TMP_PROMPT"' EXIT INT TERM

cat <<'EOF' > "$TMP_PROMPT"
You are an expert Git manager. Write a professional 'Conventional Commit' message based on the provided Git Diff.

### INSTRUCTIONS
1. **Format**: Use the format: '<type>: <description>'
2. **Tone**: Use the imperative mood (e.g., 'fix' instead of 'fixed', 'add' instead of 'added').
3. **Length**: Keep the message concise and under 72 characters (One-liner).
4. **Strict Rule**: Output ONLY the commit message. DO NOT include any preamble, explanations, or quotes.

### TYPE DEFINITIONS
Choose the most appropriate type:
- **feat**: A new feature or significant change.
- **fix**: A bug fix.
- **docs**: Changes only to documentation.
- **style**: Formatting, missing semi-colons, etc. (No logic change).
- **refactor**: Code changes that neither fix a bug nor add a feature.
- **perf**: A code change that improves performance.
- **test**: Adding missing tests or correcting existing tests.
- **build**: Changes that affect the build system or external dependencies (e.g., gulp, npm).
- **ci**: Changes to CI configuration files and scripts (e.g., GitHub Actions, Jenkins).
- **chore**: Other changes that don't modify src or test files.
- **revert**: Reverts a previous commit.

—
EOF

# Append dynamic parts safely - Stream diff directly to prevent ARG_MAX issues
{
  printf "\n1. **Specific Task**: %s\n" "$CUSTOM_TASK"
  printf "\nGit Diff to commit:\n"
  get_git_diff "$DIFF_COMMIT_ID_OR_BRANCH" "$EXCLUDE_PATTERN"
} >> "$TMP_PROMPT"

# 4. Generate message using Gemini with stdin redirection
AI_MSG=$(gemini -m "$MODEL" < "$TMP_PROMPT")

# 5. Output the AI message
if [ -n "$AI_MSG" ]; then
    if [ -n "$OUTPUT_FILE" ]; then
        # Prepend AI message to existing file content (important for prepare-commit-msg)
        TEMP_MSG=$(mktemp) || exit 1
        {
          echo "$AI_MSG"
          echo ""
          echo "# --- AI Generated Message Above ---"
          if [ -f "$OUTPUT_FILE" ]; then
            cat "$OUTPUT_FILE"
          fi
        } > "$TEMP_MSG" && mv "$TEMP_MSG" "$OUTPUT_FILE"
    else
        # Default to stdout if no output file specified
        echo "$AI_MSG"
        echo ""
        echo "# --- AI Generated Message Above ---"
    fi
else
    echo "⚠️ Warning: Gemini failed to generate a commit message."
fi
