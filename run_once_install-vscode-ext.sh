#!/bin/bash
if command -v code &> /dev/null; then
    cat ~/.vscode-extensions.txt | xargs -I {} code --install-extension {} --force
else
    echo "warning: VSCode 'code' command not found in PATH, skipping extension installation"
fi

