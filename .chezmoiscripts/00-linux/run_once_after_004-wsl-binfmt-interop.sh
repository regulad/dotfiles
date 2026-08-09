#!/bin/bash -e

# systemd (as WSL2's PID1 under `systemd=true` in wsl.conf) processes its own
# /usr/lib/binfmt.d/*.conf at boot via systemd-binfmt.service, which races WSL's
# own WSLInterop binfmt_misc registration. The kernel doesn't support namespacing
# binfmt_misc interpreters, so whichever loses ends up registered only as
# WSLInterop-late (or not at all), breaking direct `foo.exe` invocation from any
# systemd-managed process (e.g. --user services). Explicitly registering
# WSLInterop via binfmt.d fixes it. https://github.com/microsoft/WSL/issues/8843
conf=/usr/lib/binfmt.d/WSLInterop.conf
if [ ! -f "$conf" ] || ! grep -qxF ':WSLInterop:M::MZ::/init:PF' "$conf"; then
	sudo mkdir -p /usr/lib/binfmt.d
	echo ':WSLInterop:M::MZ::/init:PF' | sudo tee "$conf" >/dev/null
	sudo systemctl restart systemd-binfmt
fi
