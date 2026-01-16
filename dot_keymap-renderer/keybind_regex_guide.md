# Keybind Regex Pattern Guide

_This guide was written by Claude (Anthropic AI Assistant)_

## Regex Patterns

### Single Key Binds (No Modifiers)
```regex
^(?:[a-z0-9`\-=\[\]\\;',./]|<(?:F1[0-2]|F[1-9]|Space|Enter|Tab|Escape|Backspace|Delete|Home|End|PageUp|PageDown|Insert|Up|Down|Left|Right|Num(?:Lock|Div|Mul|Sub|Add|Enter|Dot|[0-9]))>)$
```

### Modifier Key Binds (With Ctrl/Meta/Alt)
```regex
^<[CMAS](?:-[CMAS])*>$
```

<C> - Control

<M> - Meta

<A> - Alt

<S> - Shift

synthesizes into

<A-S>

<C-S>

etc.

Make sure CMAS comes in that order.

## Pattern Rules

1. **Simple alphanumeric keys**: No brackets, just the character
2. **Simple special keys**: Brackets required, no modifiers
3. **Modified keys**: Brackets required with vim-style modifiers
4. **Shift modifier**: Represented by uppercase letters (no explicit shift notation needed)