#!/bin/bash -e

# DEP_HASH:72b0187b068f6c39d4337b413e587875ac18b6e058f2b2ae41c5102f595dc95c

if command -v code &>/dev/null; then
    # for some reason, on my machine vscode's --install-extension cli is privvy to fail intermittently
    retry -t 5 -d 2 -m 60 -- sh -c 'cat ~/.vscode-extensions.txt | xargs -I {} code --install-extension {} --force'
else
    echo "warning: VSCode 'code' command not found in PATH, skipping extension installation"
fi
