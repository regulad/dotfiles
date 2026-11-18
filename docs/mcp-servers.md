# MCP servers

Claude Code and Codex get their MCP servers from three places:

- Configured directly: `.chezmoitemplates/claude-code-config.json`, the
  `mcpServers` slice of `~/.claude.json`, and `dot_codex/modify_private_config.toml`,
  the `[mcp_servers]` of `~/.codex/config.toml`. Credentials come from
  Bitwarden, and the entries that need one are left out under
  `useDummySecrets`.
- Plugins: `.chezmoitemplates/claude-plugins.sh` and `codex-plugins.sh`.
- claude.ai connectors, which this repository does not manage.

The aim is that no machine signs in to anything by hand. A service whose
server takes a static token is configured directly with that token from
Bitwarden; one that only takes OAuth comes from its plugin and is signed in
to once per machine and per tool (`999-reminders` names Cloudflare's while it
is outstanding), or is left signed out until a machine needs it, as Vercel's
and OneSignal's are.

| Server | Claude Code | Codex | Signs in with |
| --- | --- | --- | --- |
| Sentry | configured directly, at the sentry plugin's own URL, so Claude Code skips the plugin's copy as a duplicate | configured directly | the `sentry.io` item's token, as `Authorization: Sentry-Bearer` |
| Supabase | configured directly, at the supabase plugin's own URL, so Claude Code skips the plugin's copy as a duplicate | configured directly | the `supabase.com` item's token, as `Authorization: Bearer` |
| GitHub | configured directly: read-only, and only the actions and github_support_docs_search toolsets | configured directly, likewise | the `github.com` item's `dotfiles` token, as `Authorization: Bearer` |
| Google Developer Knowledge | configured directly | configured directly | the `developers.google.com` item's `token`, as `X-Goog-Api-Key`: an API key that homelab's tofu/gcp makes in project `regulad`, restricted to the Developer Knowledge API |
| Cloudflare | cloudflare plugin | cloudflare plugin | OAuth |
| Vercel | vercel plugin | OpenAI's curated vercel plugin | OAuth; Vercel's server takes no token |
| OneSignal | onesignal plugin, from OneSignal's marketplace | onesignal plugin, from the same marketplace; `codex mcp login` fails against the server, so it stays signed out | OAuth; OneSignal's [documentation](https://documentation.onesignal.com/docs/en/model-context-protocol) says there is no API key to configure |
| Microsoft Learn | microsoft-docs plugin, from MicrosoftDocs' marketplace | microsoft-docs plugin, from the same repo's Codex marketplace | nothing |
| MDN | configured directly, with its analytics opt-out header | configured directly, likewise | nothing; Mozilla labels it experimental |
| Docker docs | docker-skills plugin, from Docker's marketplace | docker-skills plugin, likewise | nothing |
| Chrome DevTools (local, npx) | chrome-devtools-mcp plugin, from the DevTools team's marketplace | configured directly: the plugin's launch line only works in Claude Code | nothing |
| Xcode (macOS 26 on, local) | xcode plugin, built from the installed Xcode 27 by `claude-plugin-update.sh` | configured directly, `xcrun mcpbridge` | nothing; Xcode's MCP server in headless mode (`171-xcode-mcp-server`), and Xcode asks about each agent once |
| DuckDuckGo search | configured directly | none | nothing |
| Ghidra (x64 Windows) | configured directly, local | none | nothing |

## Not set up: ngrok

Decided on 2026-11-15, for now.

ngrok's MCP server, `https://mcp.ngrok.com/mcp`, takes an OAuth sign-in or a
personal access token sent as `Authorization: Bearer ngrok_pat_...`. Its
[documentation](https://ngrok.com/docs/mcp-server) says API keys and agent
authtokens don't work with it. Personal access tokens are made on the
dashboard's Access Tokens page, and ngrok says the account needs access to
the MCP server. On this account
`https://dashboard.ngrok.com/access-tokens/new` redirects to the Authtokens
page, so no token can be made, and that leaves only an OAuth sign-in on
every machine.

The CLI was left out with it. It needs nothing that isn't there already, should
it be wanted on its own:

- Install: scoop's `ngrok` on Windows; the `ngrok` cask on macOS, which every
  era in `.chezmoidata/brew-tiers.toml` has as v3 with a working download
  (3.1.0 on Catalina's pin); the same cask on x86-64 Linux, and none on ARM
  Linux, which it does not support.
- Config: `ngrok.yml`, `version: 3` with `agent.authtoken` (tunnels) and
  `agent.api_key` (`ngrok api ...`), filled from the Bitwarden item that holds
  the authtoken. It lives at `%LocalAppData%\ngrok\ngrok.yml`,
  `~/Library/Application Support/ngrok/ngrok.yml` and `~/.config/ngrok/ngrok.yml`,
  and ngrok rewrites it only through `ngrok config add-authtoken`.

Revisit when the Access Tokens page opens for the account: the server then
goes into both MCP templates beside Sentry's, with the token from Bitwarden.
