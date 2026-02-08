#!/bin/bash

# Source common logic
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# 1. Parse arguments
MODEL="$DEFAULT_MODEL"
CUSTOM_TASK="general review"
NON_INTERACTIVE=false

while [[ "$#" -gt 0 ]]; do
  case $1 in
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

# Input Safety Validation
validate_input_safety "$DIFF_COMMIT_ID_OR_BRANCH" "$MODEL" "$CUSTOM_TASK"

STAGED_DIFF=$(git diff "$DIFF_COMMIT_ID_OR_BRANCH" "$EXCLUDE_PATTERN")

# If no changes are staged, exit early
if [ -z "$STAGED_DIFF" ]; then
  exit 0
fi

echo "🤖 $MODEL is reviewing your changes..."

# 3. Define the prompt
PROMPT="You are a Senior Code Reviewer. 

### CONTEXT
Your specific task for this session is: **$CUSTOM_TASK**

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

### EXAMPLE OF INCORRECT FORMAT (DO NOT DO THIS):
**ISSUE:** [HIGH] - Potential memory leak... (WRONG: Contains bolding)
* ISSUE: [LOW] - Spelling error... (WRONG: Contains bullet points)

### Template for each issue:
ISSUE: [CRITICAL/HIGH/MEDIUM/LOW] - [Short Description]
File: \`path/to/file/name.ext\`
Priority: [P0/P1/P2/P3]
* Explanation: Detailed explanation of the root cause.
* Suggestion: Concrete steps to fix the issue.
* Comparison:
[Original Code]
\`\`\`[language]
// Snippet of the current problematic code
\`\`\`

[Suggested Fix]
\`\`\`[language]
// The corrected code snippet
\`\`\`

---
Git Diff to Review:
$STAGED_DIFF"

# 4. Send to Gemini and capture response
# We use the 'instruct' variant for better adherence to the prompt
REVIEW_RESULT=$(gemini -m "$MODEL" -p "$PROMPT")

# Find the first line containing a non-whitespace character.
# Apply ltrim (remove leading whitespace) to that line.
# Print all subsequent lines (including indentation).
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

# Check if the review was approved (should only happen when no issues found)
if [ "$criticalCount" -eq 0 ] && [ "$highCount" -eq 0 ]; then
  echo "✅ Excellent! Code follows best practices."
  echo ""
  echo "🎉 Commit approved! Keep up the good coding practices!"
  echo ""
  echo " ✓ COMMIT WILL PROCEED ✓ "
  exit 0
fi

# Block commits based on NEW severity rules
if [ "$criticalCount" -gt 0 ]; then
  echo "🚫 COMMIT BLOCKED: Critical issues found ($criticalCount). Fix them before committing."
  echo ""
  echo " ✗ COMMIT REJECTED ✗ "
  exit 1
elif [ "$highCount" -gt 0 ]; then
  echo "🚫 COMMIT BLOCKED: High severity issues found ($highCount). Must be resolved."
  echo ""
  echo " ✗ COMMIT REJECTED ✗ "
  exit 1
elif [ "$mediumCount" -ge 3 ]; then
  echo "⚠️  COMMIT BLOCKED: Too many medium issues ($mediumCount found). Please address some before committing."
  echo "   To override, use: git commit --no-verify"
  echo ""
  echo " ✗ COMMIT REJECTED ✗ "
  exit 1
elif [ "$mediumCount" -gt 0 ]; then
  echo "⚠️  Medium severity issues detected ($mediumCount found). Consider fixing, but commit allowed."
  echo ""
  echo "🎉 Commit approved with minor concerns!"
  echo ""
  echo " ✓ COMMIT WILL PROCEED ✓ "
  exit 0
elif [ "$lowCount" -gt 0 ]; then
  echo "✅ Minor improvements suggested ($lowCount found). Good code quality overall."
  echo ""
  echo "🎉 Commit approved! Keep up the good coding practices!"
  echo ""
  echo " ✓ COMMIT WILL PROCEED ✓ "
  exit 0
else
  # No issues found but also no explicit approval (shouldn't happen with updated prompt)
  echo "✅ Code review completed. No blocking issues found."
  echo ""
  echo "🎉 Commit approved! Keep up the good coding practices!"
  echo ""
  echo " ✓ COMMIT WILL PROCEED ✓ "
  exit 0
fi
