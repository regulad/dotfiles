#!/bin/bash
sudo tee /etc/pam.d/sudo_local >/dev/null <<'EOF'
# sudo_local: local config file which survives system update and is included for sudo
# uncomment following line to enable Touch ID for sudo
auth       optional       /opt/homebrew/lib/pam/pam_reattach.so ignore_ssh
auth       sufficient     pam_tid.so
EOF
sudo chmod 444 /etc/pam.d/sudo_local
sudo chown root:wheel /etc/pam.d/sudo_local
