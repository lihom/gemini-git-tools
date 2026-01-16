#!/bin/bash

# 1. Parse arguments
MODEL="gemini-3-flash-preview"
CUSTOM_TASK="general commit"

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --prompt) 
      CUSTOM_TASK=$(echo "$2" | sed 's/[;\"`$&]/ /g'); shift ;;
    --prompt-file) 
      if [[ -f "$2" ]]; then
        CUSTOM_TASK=$(cat "$2")
      else
        echo "❌ Error: File $2 not found or inaccessible."
        exit 1
      fi
      shift ;;
    --model)  
      MODEL="$2"; shift ;;
    *) echo "❌ Error: Invalid parameter: $1"; exit 1 ;;
  esac
  shift
done

# 2. Get the staged changes
read -p "please enter your diff commit id or branch: " DIFF_COMMIT_ID_OR_BRANCH

if [ -z "$DIFF_COMMIT_ID_OR_BRANCH" ]; then
  DIFF_COMMIT_ID_OR_BRANCH="--cached"
fi

STAGED_DIFF=$(git diff $DIFF_COMMIT_ID_OR_BRANCH ":(exclude)package-lock.json")

# If no changes are staged, just exit
if [ -z "$STAGED_DIFF" ]; then
    exit 0
fi

echo "🤖 $MODEL is drafting your commit message..."

# 3. Construct the AI Prompt
PROMPT="You are an expert Git manager. Write a professional 'Conventional Commit' message based on the provided Git Diff.

### INSTRUCTIONS
1. **Specific Task**: **$CUSTOM_TASK**
2. **Format**: Use the format: '<type>: <description>'
3. **Tone**: Use the imperative mood (e.g., 'fix' instead of 'fixed', 'add' instead of 'added').
4. **Length**: Keep the message concise and under 72 characters (One-liner).
5. **Strict Rule**: Output ONLY the commit message. DO NOT include any preamble, explanations, or quotes.

### TYPE DEFINITIONS
Choose the most appropriate type:
- **feat**: A new feature or significant change.
- **fix**: A bug fix.
- **docs**: Changes only to documentation.
- **style**: Formatting, missing semi-colons, etc. (No logic change).
- **refactor**: Code changes that neither fix a bug nor add a feature.
- **perf**: A code change that improves performance.
- **test**: Adding missing tests or correcting existing tests.
- **chore**: Updating build tasks, package manager configs, etc.

---
Git Diff to commit:
$STAGED_DIFF"

# 4. Generate message using Gemini
# We use a smaller/faster model here since commit messages should be quick
AI_MSG=$(gemini -m "$MODEL" -p "$PROMPT")

# 5. Prepend the AI message to the commit file
# We leave a comment so the user knows it was AI-generated
echo "$AI_MSG"
echo ""
echo "# --- AI Generated Message Above ---"
