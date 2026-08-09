#!/bin/bash -e

if systemctl --user is-system-running &>/dev/null || systemctl --user status &>/dev/null; then
	systemctl --user daemon-reload
	systemctl --user enable --now ssh-agent-relay.service
else
	echo "warning: user session broken (couldn't run systemd --user)" >&2
fi
