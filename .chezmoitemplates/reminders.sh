# Reminders for the per-machine sign-ins chezmoi cannot do itself, shared by
# the linux and macos hooks; Windows half:
# .chezmoiscripts/00-nt/run_after_999-reminders.cmd. Numbered last so they are
# the final lines of an apply. Each is checked first and only mentioned while
# still outstanding. Every probe reads /dev/null: none of them needs input, and
# a `cf` that is brew's unrelated timestamp filter would otherwise sit on stdin.

if command -v claude &>/dev/null; then
	if claude auth status >/dev/null 2>&1 </dev/null; then
		echo "debug: Claude Code is signed in" >&2
	else
		echo "notice: Claude Code is not signed in; start claude and run /login" >&2
	fi
else
	echo "debug: claude is not installed, skipping its sign-in reminder" >&2
fi

# The cloudflare plugin's MCP server signs in with OAuth, once per machine and
# per tool, so Claude Code and Codex are each checked. Neither probe connects to
# every configured server; a missing plugin simply matches nothing.
if command -v claude &>/dev/null &&
	claude mcp get plugin:cloudflare:cloudflare 2>/dev/null </dev/null | grep -qF 'Needs authentication'; then
	echo "notice: Claude Code is not signed in to Cloudflare's MCP server; run /mcp in claude and authenticate plugin:cloudflare:cloudflare" >&2
fi

# Starting codex once both signs it in and syncs OpenAI's curated plugin
# marketplace, which codex-plugins.sh installs the vercel plugin from.
if command -v codex &>/dev/null; then
	if ! codex login status >/dev/null 2>&1 </dev/null; then
		echo "notice: Codex is not signed in; run codex once and sign in" >&2
	elif ! codex plugin marketplace list 2>/dev/null </dev/null | grep -qE '^openai-(api-)?curated '; then
		echo "notice: Codex has not synced its curated plugin marketplace; run codex once, then re-apply to install the vercel plugin" >&2
	else
		echo "debug: Codex is signed in and has its curated plugin marketplace" >&2
	fi
	if codex mcp list 2>/dev/null </dev/null | grep -qE '^cloudflare[[:space:]].*Not logged in'; then
		echo "notice: Codex is not signed in to Cloudflare's MCP server; run codex mcp login cloudflare" >&2
	fi
else
	echo "debug: codex is not installed, skipping its reminder" >&2
fi

# `cf auth whoami` exits 0 either way and prints JSON; "authenticated" is
# false when there is neither a stored login nor CLOUDFLARE_API_TOKEN.
if command -v cf &>/dev/null; then
	if cf auth whoami 2>/dev/null </dev/null | grep -qF '"authenticated": true'; then
		echo "debug: cf is signed in" >&2
	else
		echo "notice: cf is not signed in; run cf auth login" >&2
	fi
else
	echo "debug: cf is not installed, skipping its sign-in reminder" >&2
fi
