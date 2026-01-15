#!/bin/bash -e

# DEP_HASH:e2c37f76e2ac4de4d54d9d2a1e3244fc16f09d9f777f17509efe02665f3ff949

if command -v code &>/dev/null; then
    # for some reason, on my machine vscode's --install-extension cli is privvy to fail intermittently
    retry -t 5 -d 2 -m 60 -- sh -c 'cat ~/.vscode-extensions.txt | xargs -I {} code --install-extension {} --force'
else
    echo "warning: VSCode 'code' command not found in PATH, skipping extension installation"
fi
