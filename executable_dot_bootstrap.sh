#!/opt/homebrew/bin/bash
# for use with the following bootstrap command
# /Users/regulad/go/bin/osc52pty /Users/regulad/.bootstrap.sh
exec /opt/homebrew/bin/tmux new-session -A -s term-${TERM_SESSION_ID:0:8}
