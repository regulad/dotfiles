# git branch/dirty segment, spliced into whatever $PROMPT already is.
#
# This used to be hardcoded into the middle of the PROMPT literal in ~/.zshrc.
# It lives here instead so that the prompt in ~/.zshrc is just a prompt, and so
# that this can be dropped, or reordered against 90-osc133.zsh, by renaming a
# file rather than editing the literal.
#
# Ordering is what keeps this correct: ~/.zshrc builds the base prompt, then
# sources ~/.config/zsh/*.zsh once, in glob (i.e. numeric) order. 20 runs before
# 90 so the OSC 133 "user input starts here" marker ends up after this segment.
#
# == Why the substitution is NOT wrapped in %{...%}
#
# %{...%} declares "everything in here occupies zero columns" -- it is for
# terminal escape sequences (colours, OSC), which zsh must emit but must not
# count when it tracks where the cursor is. git_prompt_info emits *visible*
# text: with no ZSH_THEME set, omz's lib/theme-and-appearance.zsh leaves
# ZSH_THEME_GIT_PROMPT_PREFIX/SUFFIX/DIRTY as bare "git:(" / ")" / "*", so the
# whole " git:(master*)" is printable characters and nothing else.
#
# Wrapping it told zsh the prompt was ~14 columns narrower than it really was.
# Everything still *drew* correctly, because zsh emits the bytes either way --
# but every subsequent cursor calculation was off by the width of the git
# segment, so zle would wrap late and redraw the input line on top of
# "git:(master*)". That is not a zsh-autosuggestions conflict; the plugin only
# makes it obvious, because retracting ghost text is the operation that most
# often forces zle to reposition from a start column it already had wrong.
#
# The colour wrappers below really are zero-width, so they keep their %{...%}.
#
# Nothing else is needed to make the substitution safe: prompt expansion
# re-scans substitution results, so %-escapes from a theme's
# ZSH_THEME_GIT_PROMPT_* still work, and omz's lib/git.zsh already escapes
# literal % in the ref name (${ref//\%/%%}) so a branch called "100%" cannot
# inject prompt escapes.
_zsh_install_git_prompt() {
  emulate -L zsh
  setopt extended_glob

  # Needs the omz git plugin. This file is applied to every host, including
  # ones where oh-my-zsh has not been installed yet; without this an unguarded
  # $(git_prompt_info) would print command-not-found on every redraw.
  (( $+functions[git_prompt_info] )) || return 0

  # Opt-out, set by the Android branch in ~/.zshrc which deliberately wants a
  # one-character prompt.
  [[ -n ${ZSH_GIT_PROMPT_DISABLE-} ]] && return 0

  # Bold white, self-contained. The old inline version inherited bold from the
  # %B that styles %~ and only set the foreground; now that the segment can be
  # spliced into a prompt it did not author, it sets both and resets both.
  local segment='%{$fg_bold[white]%}$(git_info=$(git_prompt_info); echo -n "${git_info:+ $git_info}")%{$reset_color%}'

  # Splice the segment in just before the trailing prompt character, rather
  # than appending, so it reads "...~/path git:(master*)$ " and not
  # "...~/path$ git:(master*)".
  #
  # Terminators are tried most-specific-first and not as one alternation:
  # (*) is greedy, so with a single alternation zsh prefers the longest
  # possible prefix and would split "%# " into prefix "%" + terminator "#",
  # putting the segment between the % and the #.
  local term
  for term in '%\(\#[^\)]#\)' '%\#' '%%' '[$#>]'; do
    if [[ $PROMPT == (#b)(*)(${~term})([[:space:]]#) ]]; then
      PROMPT="${match[1]}${segment}${match[2]}${match[3]}"
      return 0
    fi
  done

  # Unrecognisable tail (many third-party themes end in a colour reset rather
  # than a prompt character) -- append and leave it looking slightly off rather
  # than guess at a splice point and corrupt the prompt.
  PROMPT="${PROMPT}${segment}"
}
_zsh_install_git_prompt
unfunction _zsh_install_git_prompt
