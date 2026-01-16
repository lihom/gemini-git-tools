#!/bin/bash
# setup.sh

read -p "please enter your git root path: " GIT_ROOT_PATH

CURRENT_DIR=$(pwd)

echo "Installing Gemini Git hooks..."

# Create symlinks from the repo's hooks folder to the actual git hooks folder
ln -sf $CURRENT_DIR/hooks/pre-commit $GIT_ROOT_PATH/.git/hooks/pre-commit
ln -sf $CURRENT_DIR/hooks/prepare-commit-msg $GIT_ROOT_PATH/.git/hooks/prepare-commit-msg

# Ensure they are executable
chmod +x hooks/*

echo "Hooks installed! Make sure Gemini is running with 'gemini --version'."
