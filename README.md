# Gemini Git Tools: Local AI-Powered Git Hooks

**Gemini Git Tools** brings the power of Large Language Models (LLMs) directly into your local development workflow. By leveraging **Gemini**, this repository provides automated code reviews and commit message generation—all running 100% on your machine. No APIs, no tokens, and no code ever leaves your computer.

---

## ✨ Features

* **AI Code Review (`pre-commit`):** Automatically analyzes your staged changes for bugs, security risks, and code smells before you commit.
* **Auto-Commit Messages (`prepare-commit-msg`):** Drafts high-quality, Conventional Commit messages based on your `git diff`.
* **Privacy First:** Everything runs locally via Gemini.
* **Human-in-the-Loop:** The AI suggests, but you always have the final say (edit the message or bypass the review).

---

## 🚀 Getting Started

### 1. Prerequisites
* **Git:** Installed and configured.
* **Gemini:** [Download and install Gemini](https://geminicli.com/docs/get-started/installation/).
    ```bash
    npm install -g @google/gemini-cli
    ```

### 2. Installation
Clone this repository and run the setup script to link the hooks to your current project.

```bash
git clone [https://github.com/lihom/gemini-git-tools.git](https://github.com/lihom/gemini-git-tools.git)
cd gemini-git-tools
chmod +x setup.sh
./setup.sh

```

> **Note:** The `setup.sh` script creates symbolic links from `.git/hooks/` to the `hooks/` directory in this repo.

---

## 🛠️ Usage

### 🚦 Severity Definitions

To ensure consistent reviews, the AI flags issues based on the following criteria:

| Level | Definition | Examples |
| --- | --- | --- |
| **P0 (Critical)** | **Must Fix.** Blocks commit. Security risks or logic that crashes the app. | Hardcoded API keys, SQL injection, null pointer risks, infinite loops. |
| **P1 (High)** | **Should Fix.** Highly recommended to resolve before pushing. | Breaking naming conventions, lack of error handling, redundant heavy loops. |
| **P2 (Minor)** | **Suggestion.** Does not block commit. | Typo in comments, slightly better way to write a function, style nits. |

### AI Code Review (`pre-commit`)

When you run `git commit`, AI analyzes your changes. If the AI detects **P0 / P1 issues**, the commit is automatically **aborted**.

* **To proceed:** Fix the identified issues and commit again.
* **To bypass:** Run `git commit --no-verify` to skip the AI review entirely.

### AI Commit Drafting (`prepare-commit-msg`)

If the review passes (or you bypass it), your text editor will open with a pre-filled commit message like:
`feat: add user authentication logic to login controller`

Simply save and exit to finish the commit.

### Manual Run Scripts

You can run an AI review or draft a commit message at any time without starting the actual commit process. The scripts support custom instructions and model selection via arguments.

#### Usage

```bash
sh ./scripts/gemini_review.sh [options]
sh ./scripts/gemini_commit.sh [options]
```

#### Available Options

| Option | Argument | Description |
| --- | --- | --- |
| `--prompt` | `"text"` | Provide a direct, one-line instruction to the AI (e.g., "Focus on security"). |
| `--prompt-file` | `path/to/file` | Load a complex set of review rules or a checklist from a text file. |
| `--model` | `model_name` | Specify which Gemini model to use (Default: `gemini-3-flash-preview`). |

**Model Options**
| Model | Description |
| --- | --- |
| `gemini-3-pro-preview` | Newest 3rd generation preview, strongest in logical reasoning and Agent capabilities. |
| `gemini-3-flash-preview` | (Default) 3rd generation fast version, balances speed and performance. |
| `gemini-2.5-pro` | Stable and powerful flagship model, suitable for large-scale tasks. |
| `gemini-2.5-flash` | Extremely fast response speed, suitable for simple Q&A or single script analysis. |
| `gemini-2.5-flash-lite` | Extremely fast and lightweight, suitable for simple tasks extremely sensitive to latency. |

---

#### Examples

**1. General review with a specific focus:**

```bash
sh ./scripts/gemini_review.sh --prompt "Check for potential memory leaks and resource management."
```

**2. Audit using a team-standard rule file:**

```bash
sh ./scripts/gemini_review.sh --prompt-file docs/prompt.md
```

**3. Test with a different gemini model:**

```bash
sh ./scripts/gemini_review.sh --model gemini-3-pro-preview
```

**4. Generate a draft commit message focusing on breaking changes:**

```bash
sh ./scripts/gemini_commit.sh --prompt "Highlight any breaking changes in the API."
```

---

## ⚙️ Configuration

You can customize the AI's behavior by editing the scripts in the `hooks/` folder:

| Script | Purpose | Model Used |
| --- | --- | --- |
| `pre-commit` | Reviewing code for bugs | `gemini-3-flash-preview` |
| `prepare-commit-msg` | Writing the commit summary | `gemini-3-flash-preview` |

---

## 🤝 Contributing

Found a way to make the prompts better? Open a Pull Request! I'm always looking to improve the "senior developer" persona of the AI.

## 📄 License

MIT