#!/bin/bash -e

# belt-and-suspenders: this script is already WSL-gated in .chezmoiignore
# (masked unless WSL_DISTRO_NAME is set, which Docker containers never have),
# but skip explicitly too since containers have no real systemd --user session
# and this now hard-fails instead of warning.
if systemd-detect-virt --container &>/dev/null; then
	echo "note: containerized, skipping ssh-agent-relay.service" >&2
	exit 0
fi

if systemctl --user is-system-running &>/dev/null || systemctl --user status &>/dev/null; then
	systemctl --user daemon-reload
	systemctl --user enable --now ssh-agent-relay.service
else
	echo "error: user session broken (couldn't run systemd --user)" >&2
	exit 1
fi
