#!/usr/bin/env bash
# Claude Code's Stop and Notification hooks: a toast with the event's own
# text. Wired up by hooks in .chezmoitemplates/claude-settings.json, which
# runs it with bash on every platform, as the status line is run: Git Bash on
# Windows, /bin/bash 3.2 on macOS.
#   notify-hook.sh osc      print terminalSequence JSON: BEL plus
#                           OSC 777;notify, for the terminal Claude Code runs in
#   notify-hook.sh desktop  in the VS Code extension's native panel only
#                           (CLAUDE_CODE_ENTRYPOINT is claude-vscode), which
#                           has no terminal: a desktop notification through
#                           toastify (.chezmoidata/cargo-tools.toml)
# Title: a Notification's own title where it has one, else "Claude Code · "
# and the working directory, with ~ for the home directory. Body: a
# Notification's message, or the first non-blank line of Stop's
# last_assistant_message. Field names are from the hooks reference,
# https://code.claude.com/docs/en/hooks (Notification input, Stop input).
# Always exits 0, so a failure never shows as a hook error.
mode=$1
if [ "$mode" = desktop ] && [ "$CLAUDE_CODE_ENTRYPOINT" != claude-vscode ]; then
    exit 0
fi
input=$(cat)
# Control characters (newlines included) become spaces: they would end the
# escape sequence early, and Claude Code ignores a terminalSequence holding
# anything its allowlist doesn't. tr because a native Windows jq.exe ends
# lines with CRLF.
{ IFS= read -r title; IFS= read -r body; } <<EOF
$(printf '%s' "$input" | jq -r --arg home "$HOME" '
  def oneline: gsub("[\u0000-\u001f\u007f]+"; " ") | gsub("^ +| +$"; "");
  def cut($n): if length > $n then .[:$n - 1] + "…" else . end;
  (.cwd // "") as $cwd
  | (if $home != "" and ($cwd == $home or ($cwd | startswith($home + "/")))
     then "~" + $cwd[($home | length):] else $cwd end) as $where
  | (if .hook_event_name == "Notification" and ((.title // "") | test("\\S"))
     then .title else "Claude Code · " + $where end | oneline | cut(80)),
    (if .hook_event_name == "Notification" then (.message // "")
     else ((.last_assistant_message // "") | split("\n")
           | map(select(test("\\S"))) | .[0] // "")
     end | oneline | cut(120))' 2>/dev/null | tr -d '\r')
EOF
title=${title:-Claude Code}
if [ -z "$body" ]; then
    if [ "$mode" = osc ] && [ "$(printf '%s' "$input" | jq -r .hook_event_name 2>/dev/null | tr -d '\r')" = Notification ]; then
        body="Needs your attention"
    else
        body="Response ready"
    fi
fi
case $mode in
osc)
    # OSC 777;notify;<title>;<body>: a semicolon would move the split.
    jq -nc --arg t "${title//;/,}" --arg b "${body//;/,}" \
        '{terminalSequence: ("\u0007\u001b]777;notify;" + $t + ";" + $b + "\u0007")}'
    ;;
desktop)
    # -- so a body such as "- item" isn't read as an option.
    toastify send -- "$title" "$body" >/dev/null 2>&1
    ;;
esac
exit 0
