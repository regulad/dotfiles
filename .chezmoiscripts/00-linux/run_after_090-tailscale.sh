#!/bin/bash -e
# Ensure tailscale is installed, and that this account may drive it.
#
# Both halves are wanted on every Linux host, which is why this is no longer
# masked per-platform: bare metal, atomic, container and WSL all end up with a
# tailscale CLI the login user can actually use. What differs is only *how much*
# of this script has anything left to do, and each step guards itself.
#
# `run_after_`, deliberately NOT `run_once_after_`. The container images run a
# full apply at build time, so a run_once script is recorded as already done
# inside the published image and never runs again in anything deployed from it.
# The operator setting is exactly the part that must happen in the *instance*
# rather than the image -- tailscaled is not running during a build, so there is
# nothing to delegate at that point. Everything below is idempotent.

# --- install ---------------------------------------------------------------

if ! command -v tailscale >/dev/null 2>&1; then
	if command -v rpm-ostree >/dev/null 2>&1; then
		# Atomic host (Bluefin and friends). tailscale's install.sh shells out
		# to the system package manager, which cannot write to a read-only
		# /usr, so this would fail rather than help. Bluefin ships tailscale in
		# the image already -- build_files/base/04-packages.sh adds
		# pkgs.tailscale.com as a disabled repo and installs from it at build
		# time -- so reaching here means something unusual.
		echo "warning: tailscale missing on an atomic host; layer it with" >&2
		echo "warning:   rpm-ostree install tailscale" >&2
	else
		curl -fsSL https://tailscale.com/install.sh | sh
	fi
fi

if ! command -v tailscale >/dev/null 2>&1; then
	echo "note: no tailscale binary; nothing further to do" >&2
	exit 0
fi

# --- delegate the CLI to this user ------------------------------------------

# tailscaled runs as a system service and by default only root may drive it.
# Everything this repo does with tailscale runs as the login user -- most
# pointedly tailscale-ephemeral.service, which is a systemd --user unit and
# fails outright with "Access denied: this command must be run as root" without
# an operator. `tailscale set --operator` is the supported delegation and it
# persists in tailscaled's own state, so there is no file here to manage.

# No daemon, nothing to delegate. This is the normal path during a container
# build, where there is no PID 1 to talk to; the first apply inside a running
# instance picks it up.
if ! systemctl is-active --quiet tailscaled.service 2>/dev/null; then
	echo "note: tailscaled is not running; skipping operator setup" >&2
	exit 0
fi

# is-active can go true a moment before the socket is usable.
for _ in $(seq 1 30); do
	[ -S /run/tailscale/tailscaled.sock ] && break
	sleep 1
done
if ! [ -S /run/tailscale/tailscaled.sock ]; then
	echo "error: tailscaled socket never appeared; not setting operator" >&2
	exit 1
fi

# id -un rather than $USER: $USER is set by login shells and can be absent when
# an apply is driven from a non-login context. Same reasoning as 130-shell-setup.
ME="$(id -un)"

# Already ours? `tailscale set` would be a harmless no-op, but it needs sudo,
# and prompting for a password on every apply to change nothing is obnoxious.
# Reading prefs is itself operator-or-root gated, so succeeding here IS the
# check: if this works unprivileged, the delegation is already in place.
if tailscale debug prefs >/dev/null 2>&1; then
	exit 0
fi

if ! sudo -n true 2>/dev/null && ! [ -t 0 ]; then
	echo "warning: operator not set and sudo would prompt on a non-interactive apply" >&2
	echo "warning: run: sudo tailscale set --operator=$ME" >&2
	exit 0
fi

sudo tailscale set --operator="$ME"
echo "note: tailscale operator set to $ME" >&2
