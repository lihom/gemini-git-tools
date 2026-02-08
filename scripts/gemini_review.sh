#!/bin/bash

# Source common logic
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# 1. Parse arguments
MODEL="$DEFAULT_MODEL"
CUSTOM_TASK="general review"
NON_INTERACTIVE=false

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
    *) echo "❌ Error: Invalid parameter: $1"; exit 1 ;;
  esac
  shift
done

# 2. Get the staged changes (diff)
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

# Check if there are any changes to review (efficiently)
if ! get_git_diff "$DIFF_COMMIT_ID_OR_BRANCH" "$EXCLUDE_PATTERN" | grep -q .; then
  echo "✅ No changes detected to review."
  exit 0
fi

echo "🤖 $MODEL is reviewing your changes..."

# 3. Construct the prompt safely in parts to avoid shell expansion of the diff (ARG_MAX)
TMP_PROMPT=$(mktemp) || exit 1
# Ensure cleanup on exit or interruption
trap 'rm -f "$TMP_PROMPT"' EXIT INT TERM

cat <<'EOF' > "$TMP_PROMPT"
You are a Senior Code Reviewer. 

### REVIEW SCOPE
Analyze the provided Git Diff focusing on:
1. SECURITY & BUGS: Vulnerabilities, credential leaks, and logic errors.
2. CLEAN CODE: Readability, simplicity, and maintainability.
3. BEST PRACTICES: Language-specific standards and idiomatic patterns.
4. PERFORMANCE: Complexity issues, resource leaks, and bottlenecks.

### SEVERITY & PRIORITY DEFINITIONS
- **CRITICAL (P0)**: Security risks, data loss, or system crashes. (Blocker)
- **HIGH (P1)**: Functional bugs or major violations of best practices. (High Priority)
- **MEDIUM (P2)**: Code smells, poor readability, or suboptimal patterns. (Normal)
- **LOW (P3)**: Purely aesthetic nits, minor naming suggestions, or style. (Optional)

### OUTPUT FORMAT INSTRUCTIONS
1. **STRICT RULE**: Start each issue line with exactly the string: 'ISSUE: [LEVEL]'.
2. **STRICT RULE**: DO NOT use numbering (e.g., '1.', '2.', 'Issue #1').
3. **STRICT RULE**: NO MARKDOWN BOLDING: Never write **ISSUE:**. Use plain text "ISSUE:" only.
4. **STRICT RULE**: NO VISUAL EMBELLISHMENTS: Do not use bullet points or bold text for the headers.

### WHITESPACE & INDENTATION RULES:
1. NO LEADING WHITESPACE: Every issue line must start at the very beginning of the line (Column 0).
2. NO INDENTATION: Do not use spaces, tabs, or any padding before the word "ISSUE:".

### Template for each issue:
ISSUE: [LEVEL] - [Short Description]
File: `path/to/file/name.ext`
Priority: P[0-3]
* Explanation: Detailed explanation of the root cause.
* Suggestion: Concrete steps to fix the issue.
* Comparison:
[Original Code]
```[language]
// Snippet of the current problematic code
```

[Suggested Fix]
```[language]
// The corrected code snippet
```

---
EOF

# Append dynamic parts safely - Stream diff directly to prevent ARG_MAX issues
{
  printf "\n### CONTEXT\nYour specific task for this session is: %s\n" "$CUSTOM_TASK"
  printf "\nGit Diff to Review:\n"
  get_git_diff "$DIFF_COMMIT_ID_OR_BRANCH" "$EXCLUDE_PATTERN"
} >> "$TMP_PROMPT"

# Check if diff was actually added (efficiency)
# We check the size of the file after appending the diff
# The template is ~1500 bytes. If it's still small and the diff part is empty, we might want to exit.
# But git diff --cached might return empty even if staged files exist (if no changes).
# Better to check if the diff portion specifically has content.

# 4. Send to Gemini using stdin redirection
REVIEW_RESULT=$(gemini -m "$MODEL" < "$TMP_PROMPT")

# Check for empty response
if [ -z "$REVIEW_RESULT" ]; then
  echo "❌ Error: Gemini failed to generate a review response."
  exit 1
fi

# Find the first line containing a non-whitespace character.
REVIEW=$(echo "$REVIEW_RESULT" | awk '
  !found && /^[[:space:]]*$/ { next }
  !found { sub(/^[[:space:]]+/, ""); found=1 }
  { print }
')

echo ""
echo "📋 COMPREHENSIVE CODE REVIEW RESULTS"
echo "=========================================="
echo "$REVIEW"
echo "=========================================="

# Count actual issues only
criticalCount=$(echo "$REVIEW" | grep -Ei "^ISSUE: \[?CRITICAL\]?" | wc -l | xargs)
highCount=$(echo "$REVIEW" | grep -Ei "^ISSUE: \[?HIGH\]?" | wc -l | xargs)
mediumCount=$(echo "$REVIEW" | grep -Ei "^ISSUE: \[?MEDIUM\]?" | wc -l | xargs)
lowCount=$(echo "$REVIEW" | grep -Ei "^ISSUE: \[?LOW\]?" | wc -l | xargs)

echo ""
echo "📈 REVIEW SUMMARY:"
echo "  🔴 Critical Issues: $criticalCount"
echo "  🟠 High Severity: $highCount"
echo "  🟡 Medium Severity: $mediumCount"
echo "  🟢 Low Severity: $lowCount"
echo ""

# 5. Logic for block/approve
if [ "$criticalCount" -gt 0 ] || [ "$highCount" -gt 0 ] || [ "$mediumCount" -ge 3 ]; then
  [ "$criticalCount" -gt 0 ] && echo "🚫 COMMIT BLOCKED: Critical issues found ($criticalCount)."
  [ "$highCount" -gt 0 ] && echo "🚫 COMMIT BLOCKED: High severity issues found ($highCount)."
  [ "$mediumCount" -ge 3 ] && echo "⚠️  COMMIT BLOCKED: Too many medium issues ($mediumCount found)."
  echo ""
  echo " ✗ COMMIT REJECTED ✗ "
  exit 1
elif [ "$criticalCount" -eq 0 ] && [ "$highCount" -eq 0 ] && [ "$mediumCount" -eq 0 ]; then
  echo "✅ Excellent! Code follows best practices."
  echo ""
  echo "🎉 Code review completed. No significant issues found. Commit approved!"
  echo ""
  echo " ✓ COMMIT WILL PROCEED ✓ "
  exit 0
else
  echo "⚠️  Minor issues detected (Medium: $mediumCount, Low: $lowCount). Consider fixing, but commit allowed."
  echo ""
  echo "🎉 Commit approved with minor concerns!"
  echo ""
  echo " ✓ COMMIT WILL PROCEED ✓ "
  exit 0
fi
