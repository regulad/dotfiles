# Exit-status tint for the prompt character.
#
# Sets __prompt_char_color, which ~/.zshrc references from inside the prompt
# terminator, to a %F{...} escape for the previous command's exit status:
# muted green (256-colour 108) for 0, muted red (174) for anything else, and
# nothing at all when there is no previous command, so the character keeps
# whatever colour the prompt gives it by default.
#
# == Why a variable and a hook, not %(?.green.red) in the prompt itself
#
# Two reasons. The obvious %(?.%F{108}.%F{174}) cannot express the third case:
# %? is never empty in zsh, it just starts at 0, so the first prompt of every
# shell would claim a success that never happened. A preexec hook is the only
# thing that knows whether a command really ran, so the status has to pass
# through a hook anyway.
#
# Less obviously, the tint has to be applied *inside* the %(#.#.$) conditional
# that ends the prompt, and a nested %(?. . ) would put a ")" in there.
# 20-git-prompt.zsh finds the terminator with a pattern that forbids ")" inside
# it, and would fall back to appending the git segment after the prompt
# character. A ${variable} reference has no ")" and, with PROMPT_SUBST, is
# expanded fresh on every redraw. It has to be inside the conditional rather
# than before it because the git segment is spliced in immediately before the
# terminator and ends in a full attribute reset, which would discard a colour
# set any earlier.
#
# == Order
#
# Does not matter. zsh restores $? before calling each precmd hook, so every
# hook sees the user's status on its first line no matter what the hooks
# before it returned (verified: a hook registered ahead of this one that
# returns 42 has no effect on what this one captures, nor on what
# 90-osc133.zsh's hook emits). $? is only reliable on the *first line* of the
# hook, though -- the [[ ]] test below would overwrite it.
#
# Pressing Enter on an empty line runs no command, so preexec does not fire
# and the character goes back to untinted until something actually runs.
autoload -Uz add-zsh-hook

__prompt_status_preexec() { __prompt_status_ran=1; }

__prompt_status_precmd() {
  local rc=$?   # not "status": that is a read-only alias of $? in zsh
  if [[ -n ${__prompt_status_ran-} ]]; then
    __prompt_status=$rc
  else
    __prompt_status=''
  fi
  unset __prompt_status_ran
  case $__prompt_status in
    '') __prompt_char_color='' ;;
    0)  __prompt_char_color='%F{108}' ;;
    *)  __prompt_char_color='%F{174}' ;;
  esac
}

add-zsh-hook preexec __prompt_status_preexec
add-zsh-hook precmd  __prompt_status_precmd
