#!/bin/bash
if command -v code &> /dev/null; then
    cat ~/vscode-extensions.txt | xargs -L 1 code --install-extension --force
else
    echo "VSCode 'code' command not found in PATH, skipping extension installation"
fi

