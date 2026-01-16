#!/bin/bash -e

# DEP_HASH:cf4bdd972d00eb38eb47769364e056922209f00f2eae0add38a412bb570e4190

if command -v code &>/dev/null; then
    # for some reason, on my machine vscode's --install-extension cli is privvy to fail intermittently
    retry -t 5 -d 2 -m 60 -- sh -c 'cat ~/.vscode-extensions.txt | xargs -I {} code --install-extension {} --force'
else
    echo "warning: VSCode 'code' command not found in PATH, skipping extension installation"
fi
