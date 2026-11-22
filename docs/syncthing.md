# Syncthing

Syncthing on these machines is declarative: no machine is paired by hand. Every
node lists one hub, **aboriginal**, as its *introducer* and shares a fixed set of
folders with it. aboriginal holds a plaintext copy of each folder, as a backup
and as the path between machines that are never online at the same time.

## How a machine joins

1. An apply runs `155-syncthing` (`.chezmoiscripts/00-{linux,macos,nt}`). It adds
   aboriginal as this node's introducer, at its tailnet address alone,
   `tcp://aboriginal.tail11540.ts.net:22000`, and adds each folder at its path,
   shared with aboriginal.
2. The node connects to aboriginal over Tailscale. aboriginal does not know it
   yet, so the node shows up there as a *pending* device.
3. aboriginal's joining service, `syncthing-join` (homelab's `syncthing_hub`
   role), runs `tailscale whois` on the pending device's address. It accepts
   only untagged nodes owned by Parker's tailnet user, then shares with the
   node each folder the node offers from the table below.
4. aboriginal is every node's introducer, so every node that shares those
   folders learns about the newcomer, and the newcomer learns about them. A
   device removed from aboriginal disappears everywhere the same way.

Syncthing auto-accepts folders but never devices, which is why the joining
service exists. Only connections that arrive over the tailnet can be accepted,
which is why aboriginal is listed without `dynamic`: a node that reached it
through global discovery or a relay would come from a public address and stay
pending. Global discovery and relays stay on for everything else, so the peers
the introducer adds (with `dynamic`) still traverse NAT.

## What dotfiles sets on each node

All of it comes from `.chezmoidata/syncthing.toml`.

- **The hub**: name, address, introducer. Its device ID is age-encrypted in
  `.chezmoitemplates/secrets/syncthing-hub-id.age`: with global discovery on, a
  device ID is enough to look up the device's address. `155-syncthing`
  decrypts it at run time, and hosts with dummy secrets skip the script
  (`.chezmoiignore.tmpl`), so they have no hub and no peers -- all but the hub
  itself, below.
- **The folders**:

  | Folder ID | Path (Linux / macOS / Windows) | Notes |
  |---|---|---|
  | `claude` | `~/.claude` | Only `projects/`, `plans/` and `file-history/`, by `~/.claude/.stignore` (`private_dot_claude/dot_stignore`). Mode `700`. |
  | `local-config_rclone` | `~/.config/rclone` | `rclone.conf` holds the remotes' tokens: directory `700`, file `600`. |
  | `local-state_yt-dlp` | `~/.local/state/yt-dlp` | |
  | `prusaslicer` | `~/.config/PrusaSlicer` / `~/Library/Application Support/PrusaSlicer` / `%APPDATA%\PrusaSlicer` | |

  The modes are set on Linux and macOS, where Syncthing carries a file's
  permission bits to the other nodes.
- **Ignore patterns**: every folder but `claude` gets the table's `ignores`
  at the top of its `.stignore`, through the REST API: `(?d).DS_Store` and
  `(?d)._*` (Finder), `(?d)Thumbs.db` and `(?d)desktop.ini` (Explorer).
  Without them, a Mac that opens a synced folder in Finder spreads its
  `.DS_Store` to every node. `(?d)` lets Syncthing delete such a file when it
  is all that keeps a directory deleted elsewhere from going. Lines a node
  has of its own stay, below them. `claude` is marked `ownStignore`: its
  `.stignore` is chezmoi's file, written before the folder exists, and the
  script leaves it alone.
- **Options**: usage reporting declined and crash reports off, like the
  telemetry opt-outs in `.commonprofile`.

`155-syncthing` adds and updates and never removes, so devices, folders and
ignore patterns added in the GUI stay. A folder that already exists at another path keeps it,
with a warning. The script runs on every apply, so a node whose Syncthing was
not running yet is set up on the next apply after it is. A fresh machine joins
on its first apply all the same: a first start writes Syncthing's
configuration and keys before its REST API answers, and the script gives it
30 s. On Linux it waits while the user service `150-user-services` has just
started is active. On a Mac it waits after starting the launchd agent (below).
On Windows, where Setup installed as winget runs it starts Syncthing only at the
next logon, the script runs Setup's logon task itself, then waits. That first
start can bring up Windows Firewall's prompt for `syncthing.exe`, as a logon
would; the node dials the hub either way. It does nothing in a container,
where Syncthing is not started (`150-user-services`).

How Syncthing runs differs by platform. On Linux it is the distro's or brew's
user service, which `150-user-services` starts. A WSL instance runs it the same
way, as a node separate from its Windows host, while the instance is up. Under
WSL's NAT its connections leave through the host, so the hub's joining service
sees the host's tailnet address and admits it by the owner rule like any other
machine of the owner's. On Windows it is
BillStewart.SyncthingWindowsSetup, started at logon by its scheduled task
(`stctl.exe --start`), which `155-syncthing` runs when Syncthing is not
running. On a Mac it is brew's
formula, run by launchd as the user's agent (`brew services start syncthing`),
which macOS's `155-syncthing` starts: it runs from then on and at every login,
but not at boot, so a Mac with nobody logged in after a restart has no Syncthing
until someone logs in. The same holds on headless and headful Macs alike. The
`syncthing-app` cask is not installed, and `155-syncthing` uninstalls it where
an older apply left it, since it starts a second Syncthing at login on the
same configuration.

On aboriginal itself the same script runs: chezmoi applies there too, with dummy
secrets. `.chezmoiignore.tmpl` keeps the script for a dummy-secrets host whose
hostname is the hub's name, and there the script skips the decryption: an empty
hub ID means "this is the hub". (A hub with real secrets would recognise its own
device ID instead.) The hub lists no introducer, and creates the folders shared
with no one, since the joining service does the sharing.

The REST calls are in `.chezmoitemplates/syncthing-apply.py` on Linux and macOS,
and in `00-nt/155-syncthing.ps1` on Windows; both were tested against a
throwaway Syncthing instance (adding, a second run that changes nothing,
repairing a hub entry changed in the GUI, and the hub's own view). Syncthing 2
is protocol compatible with 1.x, so Ubuntu's 1.29 and everyone else's 2.x share
a mesh, and the CLI calls the scripts make exist in both.

## What homelab sets on aboriginal

aboriginal's Syncthing is regulad's systemd user unit (`syncthing.service`, from
Ubuntu's package). homelab keeps only the hub's own pieces: its identity
(`cert.pem` and `key.pem`, in SOPS, so a rebuild keeps the device ID), its API
key (SOPS, given to Syncthing and the joining service), lingering for regulad,
and the joining service. The tailnet policy already lets Parker's devices and
aboriginal reach each other on port 22000. The synced folders on aboriginal are
in regulad's home, and go into aboriginal's restic backup with it.

## Claude Code's state

The `claude` folder carries what can follow you between machines:

- **Session transcripts** (`projects/<project>/<session>.jsonl`, with their
  subagent transcripts and stored tool results). Each is written by the one
  machine running that session. `<project>` is the session's working
  directory with every non-alphanumeric character replaced by `-`, so the same
  repository has a different directory on each OS. `claude --resume <session
  id>` searches every project directory on the machine, and resumes in the
  current directory when the original path doesn't exist there; `Ctrl+A` in
  the `/resume` picker lists sessions from all of them.
- **Auto memory** (`projects/<project>/memory/`), shared between machines whose
  checkout paths match. For a repository checked out at different paths, its
  committed `.claude/settings.json` can set `autoMemoryDirectory` to a `~/`
  path that every machine shares.
- **Plans** (`plans/`) and **rewind checkpoints** (`file-history/<session>/`).

Everything else in `~/.claude` stays local: `history.jsonl` (every session on a
machine appends to the one file, so syncing it would only produce conflict
copies), `.credentials.json`, `~/.claude.json`, `sessions/`, `jobs/`,
`daemon/`, `session-env/`, `shell-snapshots/`, and what chezmoi or a hookscript
manages (`settings.json`, `plugins/`, `skills/`).

Two consequences of syncing transcripts:

- **Deletions travel.** Claude Code deletes transcripts older than
  `cleanupPeriodDays` on each machine, and Syncthing then deletes them
  everywhere. `.chezmoitemplates/claude-settings.json` pins it (30, the
  default), so every machine keeps them equally long.
- **Transcripts are plaintext**, and hold whatever passed through a tool,
  secrets included. Every node in the mesh and aboriginal's backup get them.

A WSL instance's `~/.claude` is a node's copy of its own, separate from the
Windows host's `~\.claude`: its project directories are named after Linux paths
(`-home-...`), so the two share auto memory only through
`autoMemoryDirectory`.

## Rotating the hub's ID

If aboriginal's identity ever changes, re-encrypt the new ID:

```sh
printf '%s' '<new device ID>' | chezmoi encrypt --output .chezmoitemplates/secrets/syncthing-hub-id.age
```

`155-syncthing` embeds the ciphertext, so the change reruns it everywhere on the
next apply. The old hub entry stays on each node (the script never removes) and
can be deleted in the GUI.
