{{ template "posix-preamble.sh" . }}
# "Needs brew" preamble: posix-preamble.sh plus require_brew, for scripts whose
# entire job is brew work (package lists, casks, taps, brew services). It is
# the brew counterpart of the require_sudo call the dnf/apt scripts open with:
# no brew, no degraded mode, stop now with a clear message.
#
# After this line $HOMEBREW_PREFIX is guaranteed set (brew shellenv exports
# it), brew is on PATH, and on an era-pinned macOS HOMEBREW_NO_AUTO_UPDATE and
# HOMEBREW_NO_INSTALL_FROM_API are already exported. Scripts that merely
# *prefer* brew and have a fallback (js-tooling, python-tooling on Linux) keep
# the plain preamble and branch on HAS_BREW instead.
require_brew "$(basename "$0")"
# brew's download queue does not print URLs, so this is the one place an
# apply's output says which host the bottles come from (brew-mirror-env.sh).
echo "debug: brew bottles from ${HOMEBREW_ARTIFACT_DOMAIN:-ghcr.io (no mirror)}" >&2
