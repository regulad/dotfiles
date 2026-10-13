#!/usr/bin/env bash
# Claude Code status line mirroring the zsh prompt: user@host:cwd git:(branch*)
# followed by more widgets in the same style:
#   usage5h:(36%) usage7d:(18%) context:(26%) model:(claude-opus-5-5)
# Wired up by statusLine in .chezmoitemplates/claude-settings.json, which runs
# it with bash on every platform: Git Bash on Windows, /bin/bash 3.2 on macOS.
input=$(cat)
# One jq for every field; one value per line, since @tsv would escape the
# backslashes in a Windows path; tr because a native Windows jq.exe ends lines
# with CRLF. rate_limits is absent until the first API response, and for
# accounts without plan limits; context_window's percentage is null before the
# first response too. An empty value drops its widget.
{ IFS= read -r cwd; IFS= read -r five; IFS= read -r seven; IFS= read -r ctx; IFS= read -r model; } <<EOF
$(printf '%s' "$input" | jq -r '
  def pct: if . == null then "" else (. + 0.5 | floor | tostring) end;
  (.workspace.current_dir // .cwd // ""),
  (.rate_limits.five_hour.used_percentage | pct),
  (.rate_limits.seven_day.used_percentage | pct),
  (.context_window.used_percentage | pct),
  (.model.id // .model.display_name // "")' | tr -d '\r')
EOF
[ -n "$cwd" ] || cwd=$(pwd)
# Normalise Windows paths (C:\Users\x) for bash/git use
if command -v cygpath >/dev/null 2>&1; then
  cwd=$(cygpath -u "$cwd" 2>/dev/null || printf '%s' "$cwd")
fi
user=$(whoami)
user=${user##*\\}
# bash sets HOSTNAME itself; minimal Fedora has no hostname(1) to ask
host=${HOSTNAME:-$(uname -n)}
host=${host%%.*}
case "$cwd" in
  "$HOME") disp='~' ;;
  "$HOME"/*) disp="~${cwd#"$HOME"}" ;;
  *) disp=$cwd ;;
esac
# Widgets, each " name:(value)" in bold white like the zsh git segment.
segs=""
seg() { segs="$segs$(printf ' \033[1;37m%s:(%s)\033[0m' "$1" "$2")"; }
if branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short -q HEAD 2>/dev/null || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null); then
  dirty=""
  if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain --untracked-files=normal 2>/dev/null | head -n 1)" ]; then
    dirty="*"
  fi
  seg git "$branch$dirty"
fi
[ -n "$five" ] && seg usage5h "$five%"
[ -n "$seven" ] && seg usage7d "$seven%"
[ -n "$ctx" ] && seg context "$ctx%"
[ -n "$model" ] && seg model "$model"
printf '\033[01;32m%s@%s\033[00m:\033[01;34m%s\033[00m%s' "$user" "$host" "$disp" "$segs"
