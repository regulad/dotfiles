# OSC 133 / FinalTerm shell integration -- lets the terminal find prompts,
# commands and their exit statuses, which drives things like jump-to-previous-
# prompt, per-command exit markers, and selecting a command's output.
#
# - https://iterm2.com/documentation-escape-codes.html#:~:text=s%20source%20code.-,FTCS_PROMPT,-OSC%20133%20%3B%20A
# - https://iterm2.com/documentation-escape-codes.html#:~:text=of%20shell%20prompt.-,FTCS_COMMAND_START,-OSC%20133%20%3B%20B
# - https://iterm2.com/documentation-escape-codes.html#:~:text=user%2Dentered%20command.-,FTCS_COMMAND_EXECUTED,-OSC%20133%20%3B%20C
# - https://iterm2.com/documentation-escape-codes.html#:~:text=the%20empty%20string.-,FTCS_COMMAND_FINISHED,-OSC%20133%20%3B%20D
#
# Numbered 90 so it runs after everything else that touches $PROMPT: the B
# marker means "the prompt ends and user input begins here" and so has to be
# the last thing in the string, in particular after 20-git-prompt.zsh's segment.
#
# This lived in ~/.zshrc, above the PROMPT assignment, where the assignment
# immediately overwrote the wrapped value -- the markers were built and then
# discarded on every startup, so B was never emitted at all and the terminal had
# no way to tell the prompt from the input. Running it from here, after ~/.zshrc
# has finished building the prompt, is what fixes that.
#
# Originally prepared using Anthropic Claude Sonnet 4.6.
autoload -Uz add-zsh-hook

# $? has to be read before anything else runs in the function, hence the
# printf-then-printf rather than one call with the status interpolated later.
__osc133_precmd()  { printf '\e]133;D;%s\a' "$?"; printf '\e]133;A\a'; }
__osc133_preexec() { printf '\e]133;C\a'; }

add-zsh-hook precmd  __osc133_precmd
add-zsh-hook preexec __osc133_preexec

# Only B is appended to the prompt. A ("prompt starts") is already emitted by
# the precmd hook, which runs immediately before the prompt is drawn and so is
# in exactly the right place; wrapping the prompt in an A as well would put two
# of them on the wire for every prompt.
#
# The escape is resolved to real bytes HERE, in a variable, and not left in
# $PROMPT as the literal text $'\e]133;B\a' -- because prompt expansion will not
# resolve it. PROMPT_SUBST performs parameter, command and arithmetic
# substitution on the prompt, and $'...' is none of the three, so it would be
# expanded by nothing and the terminal would receive those 18 characters
# verbatim. Inside %{...%} they would be counted as zero columns while occupying
# 18, which is exactly the miscount 20-git-prompt.zsh exists to document. The
# version of this that used to live in ~/.zshrc did write the literal form, and
# got away with it only because the PROMPT assignment underneath it threw the
# whole string away before any prompt was ever drawn.
#
# B is a genuine zero-width escape sequence, so %{...%} is correct here (unlike
# the git segment in 20-git-prompt.zsh, which is visible text).
_osc133_b=$'\e]133;B\a'
PROMPT="${PROMPT}%{${_osc133_b}%}"
unset _osc133_b
