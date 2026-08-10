#!/bin/bash -e

# Split out of 010-fedora.sh so it can be masked independently in .chezmoiignore:
# VSCode is only installed on native GNU/Linux, never in containers (the images
# have no display and the ~1.5 GB of code + extensions is dead weight there).

# https://code.visualstudio.com/docs/setup/linux
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
dnf check-update || [ $? -eq 100 ]
sudo dnf install -q -y code
