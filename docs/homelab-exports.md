# Homelab exports

regulad/homelab generates the SSH client configuration and the host keys for
the homelab hosts reached by SSH directly: its `exported` inventory groups.
This repository deploys them and doesn't define those hosts itself.

## How they get here

homelab renders `ssh_config` and `known_hosts` from its inventories,
age-encrypts both to the recipient in `.chezmoi.toml.tmpl`, and commits them
straight to this repository's master through GitHub's API, as regubot
(`bot@regulad.net`), so GitHub signs the commit:

- `dot_ssh/config.d/encrypted_private_98-homelab.age`, deployed to
  `~/.ssh/config.d/98-homelab`;
- `dot_ssh/known_hosts.d/encrypted_private_homelab.age`, deployed to
  `~/.ssh/known_hosts.d/homelab`.

The commit is `[no ci]`: CI holds no age key to decrypt the files with, and
its applies run with `--exclude encrypted`, so the commit can't change what
CI checks. Machines with dummy secrets apply the same way and get neither
file. Master's ruleset (`.github/settings.yml`) lets regubot's write role
past the required check.

`dot_ssh/config.tmpl` reads the second file through `UserKnownHostsFile` and
tags every host `rsa3072` by default, so the generated blocks carry no `Tag`.
`98-` sorts before the hand-written `99-*` files, so its values win.

`~/.ssh/known_hosts` itself isn't managed: it is each machine's state, where
ssh records the keys accepted there, and `.chezmoiignore.tmpl` keeps it out
of this repository. github.com's keys come from the managed
`known_hosts.d/github` beside homelab's.

To pick up a new export on a machine: `git pull` the source, then
`chezmoi apply ~/.ssh/config.d/98-homelab ~/.ssh/known_hosts.d/homelab`.

## What stays here

Hosts homelab doesn't define keep their hand-written `config.d/99-*` file:
the forges, NC State's hosts, the iOS devices, winlite, u5g-us, the JetKVM,
and Forgejo's SSH behind Cloudflare Access.
