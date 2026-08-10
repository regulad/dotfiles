#!/bin/bash -e

# belt-and-suspenders: this script is already WSL-gated in .chezmoiignore
# (masked unless WSL_DISTRO_NAME is set), but re-check here rather than
# trusting the mask alone, since this hard-fails instead of warning.
#
# NOTE: do NOT swap this for `systemd-detect-virt --container`. systemd
# classifies WSL itself as a container -- it prints "wsl" and exits 0 inside a
# genuine distro -- so that check made this entire script a permanent no-op and
# ssh-agent-relay.service was never actually enabled.
if [ -z "${WSL_DISTRO_NAME:-}" ]; then
	echo "note: not a WSL session, skipping ssh-agent-relay.service" >&2
	exit 0
fi

if systemctl --user is-system-running &>/dev/null || systemctl --user status &>/dev/null; then
	systemctl --user daemon-reload
	systemctl --user enable --now ssh-agent-relay.service
else
	echo "error: user session broken (couldn't run systemd --user)" >&2
	exit 1
fi
