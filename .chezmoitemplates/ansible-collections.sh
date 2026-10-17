# Ansible collections, shared verbatim by the linux and macos hooks (105).
# Every apply, with --upgrade. 100-python-tooling supplies ansible from brew,
# including the host's era-pinned version. Galaxy resolves collection versions
# separately; its failures remain visible below, including old-core conflicts.
#
# There is no Windows half. The Ansible controller is POSIX-only -- every
# ansible-* command dies at import on Windows (see 00-nt/500-python) -- so a
# Windows host gets ansible-core and these collections inside the WSL distro,
# whose apply runs this script.
#
# They land in ansible-galaxy's default path, ~/.ansible/collections, which
# ansible and ansible-lint (each in its own brew environment) both read.
# Append-only, like the Claude plugins: ansible-galaxy has no uninstall, so an
# entry dropped from this list stays installed until its directory is deleted.

ANSIBLE_COLLECTIONS=(
	containers.podman
	community.general
	ansible.posix
)

# Useful when this script is invoked on its own before 100 has run.
if ! command -v ansible-galaxy &>/dev/null; then
	echo "notice: ansible-galaxy is not installed, skipping Ansible collections" >&2
	exit 0
fi

echo "debug: installing/upgrading Ansible collections: ${ANSIBLE_COLLECTIONS[*]}" >&2
# Galaxy is one upstream with the occasional bad minute; ride those out. If it
# is down for longer, keep whatever is installed and say so rather than fail
# the apply -- the next apply catches up. retry reads all of stdin to replay it
# on each attempt; ansible-galaxy wants none, so it gets none, rather than the
# terminal of an interactive apply.
if ! retry -t 3 -d 10,30 -- ansible-galaxy collection install --upgrade "${ANSIBLE_COLLECTIONS[@]}" </dev/null; then
	echo "warning: ansible-galaxy collection install failed; the collections may be missing or stale until the next apply" >&2
fi
