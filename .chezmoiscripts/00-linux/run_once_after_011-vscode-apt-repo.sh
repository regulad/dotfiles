#!/bin/bash -e
set -o pipefail

# https://code.visualstudio.com/docs/setup/linux
# This runs before 021-apt-packages.sh, including in minimal container images.
sudo apt-get update -qq
sudo apt-get install -qq -y ca-certificates curl gnupg
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/keyrings/packages.microsoft.gpg >/dev/null
echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
sudo apt update -qq
sudo apt install -qq -y code
