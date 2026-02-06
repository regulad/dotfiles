#!/opt/homebrew/bin/bash
exec /opt/homebrew/bin/tmux new-session -A -s term-${TERM_SESSION_ID:0:8}
