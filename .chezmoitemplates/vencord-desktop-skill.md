{{- /* .skills/desktop-discord.local.md in the Vencord clone, written by
       00-{nt,macos,linux}/*-vencord and kept out of git through the clone's
       .git/info/exclude. Upstream's own .skills are flat markdown files
       linked from AGENTS.md; this one matches them. */ -}}
{{- $cmd := "~/.local/bin/vencord-discord" -}}
{{- if eq .chezmoi.os "windows" }}{{ $cmd = "& \"$HOME\\.local\\bin\\vencord-discord.ps1\"" }}{{ end -}}
# Desktop Discord on This Machine

This clone is the Vencord that this machine's Discord stable desktop app runs. Discord loads `dist/patcher.js` from here directly, so whatever is built here is what Discord runs the next time it loads.
Use it to test in the real desktop client, for desktop-only code such as a plugin's `native.ts`. [Live Discord Sessions](discord-session.md) has console access and the webpack helpers.

This file is local to this machine: the user's dotfiles write it and keep it out of git through `.git/info/exclude`. Never commit it.

## Build and reload

- After each change, run `{{ $cmd }} dev --dev`. It runs `pnpm i` and `pnpm build --dev`, injects the build into Discord again if Discord lost it, and restarts Discord. Arguments after `dev` go to `pnpm build`
- `{{ $cmd }} restart` only restarts Discord, `{{ $cmd }} inject` only injects
- Restarting closes the user's Discord, a call they are in included. Tell the user before the first restart
- Renderer-only changes, most plugin code, would also load with {{ if eq .chezmoi.os "darwin" }}Cmd{{ else }}Ctrl{{ end }}+R in Discord. A plugin's `native.ts`, the patcher and the preload need the restart

## Branches

- Work on a branch, never on `main`. Every `chezmoi apply` fast-forwards `main` to `origin/main` and rebuilds it, but leaves a checkout on any other branch, and its build, as they are
- Back on `main`, the next apply builds `main` over the branch's build
- `origin` is the user's fork, regulad/Vencord, whose `main` follows upstream Vendicated/Vencord. All of the user's machines build origin's `main`. Push nothing unless the user asks, and never to `main`
- `src/userplugins/vencord-wakatime` is a separate clone (wakatime/vencord-wakatime) under the same rules

## This Platform

{{ if eq .chezmoi.os "windows" -}}
- `{{ $cmd }}` from PowerShell; `vencord-discord` from cmd
- Discord lives in `%LOCALAPPDATA%\Discord\app-*`. Injecting closes it and starts it again. Vencord carries its stub to each new version as Discord updates
- Vencord's settings are `%APPDATA%\Vencord\settings\settings.json`. The dotfiles merge their keys into it on every apply
{{- else if eq .chezmoi.os "darwin" -}}
- Discord is `/Applications/Discord.app`. Its updates replace the app and drop the stub until the next inject, which `dev` does
- Writing into the app needs App Management for the terminal (System Settings > Privacy & Security). The installer's output says when it was refused
- Vencord's settings are `~/Library/Application Support/Vencord/settings/settings.json`. The dotfiles merge their keys into it on every apply
{{- else -}}
- Discord is the user Flatpak `com.discordapp.Discord`, injected into its active deployment. The `vencord-discord-inject.path` user unit injects again after a Flatpak update
- The sandbox can read this clone's `dist/` and nothing else of it
- Vencord's settings are `~/.var/app/com.discordapp.Discord/config/Vencord/settings/settings.json`. The dotfiles merge their keys into it on every apply
{{- end }}
