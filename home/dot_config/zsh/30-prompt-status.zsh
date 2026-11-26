# Exit-status tint for the prompt character.
#
# Sets __prompt_char_color, which ~/.zshrc references from inside the prompt
# terminator, to a %F{...} escape for the previous command's exit status:
# pale green (256-colour 151) for 0, pale red (181) for anything else -- one
# step off white on the colour cube, so it reads as a hint and not an alarm.
#
# == Why a variable and a hook, not %(?.green.red) in the prompt itself
#
# The tint has to be applied *inside* the %(#.#.$) conditional that ends the
# prompt, and a nested %(?. . ) would put a ")" in there. 20-git-prompt.zsh
# finds the terminator with a pattern that forbids ")" inside it, and would
# fall back to appending the git segment after the prompt character. A
# ${variable} reference has no ")" and, with PROMPT_SUBST, is expanded fresh
# on every redraw. It has to be inside the conditional rather than before it
# because the git segment is spliced in immediately before the terminator and
# ends in a full attribute reset, which would discard a colour set any earlier.
#
# Hook order does not matter: zsh restores $? before calling each precmd hook,
# so every hook sees the user's status on its first line no matter what the
# hooks before it returned. It is only reliable on the *first line*, though --
# anything else in the function would overwrite it.
autoload -Uz add-zsh-hook

__prompt_status_precmd() {
  if (( $? == 0 )); then
    __prompt_char_color='%F{151}'
  else
    __prompt_char_color='%F{181}'
  fi
}

add-zsh-hook precmd __prompt_status_precmd
