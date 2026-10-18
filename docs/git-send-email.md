# git send-email

Patches go out through `mail.regulad.xyz` over SMTPS, signed with patatt.

## SMTP

The server, port and Bitwarden item are in `.chezmoidata/smtp.toml`. `.gitconfig` gets a `[sendemail]` section with the username, never the password: `send-email` asks git's credential helpers for that, and `.gitconfig` pins one for `smtp://mail.regulad.xyz:465` per platform:

| Platform | Helper | Filled by |
|---|---|---|
| Windows | Git Credential Manager (Windows Credential Manager) | `00-nt/240-git-smtp-credential.ps1`, every apply, from Bitwarden |
| WSL | the Windows GCM, through `/mnt/c` | nothing: it reads the entry Windows stored |
| macOS | `osxkeychain` (login keychain), Apple's git | `00-macos/146-git-smtp-credential.sh`, every apply, from Bitwarden |
| Linux | none yet (README TODOs) | `send-email` asks for the password |

On macOS the login keychain is locked over SSH, so 146 warns and leaves it for an apply from the Mac's own session. A failed login makes git erase the stored password; the next apply puts it back.

## Signing

[patatt](https://github.com/mricon/patatt) adds an `X-Developer-Signature` header made with the managed GPG key (`[patatt]` in `.gitconfig`). It runs from a `sendemail-validate` hook, which git only looks for in each repository's own hooks directory, so `init.templateDir` points at `~/.config/git/template`: every `git init` and `git clone` copies the hook in. For a repository that predates it, run `git init` inside it; re-initialising only adds what is missing. All at once, touching only directories that already are repositories (`git init` anywhere else would create one):

```sh
for g in ~/repositories/*/.git; do [ -e "$g" ] && git -C "${g%/.git}" init -q; done
```

The hook refuses to send when patatt is missing, rather than send unsigned. `--no-validate` skips it, and sends unsigned. A cover letter from `--compose` is never signed, since its text is still a template when the hook runs.

Signing is on with real secrets on every host, including era-pinned Macs: `.gitconfig` gets `[patatt]`, and the template gets the hook, which `.chezmoiignore.tmpl` leaves out with dummy secrets (the template itself, with its [pre-commit hook](git-hooks.md), is there either way). The python-tooling hookscripts (`00-{linux,macos}/100`, `00-nt/500`) all install patatt. This is decided from configuration data, not by looking for patatt, because `.gitconfig` is applied before the `run_after_` scripts that install it. On a first apply the hook is in place a few scripts before patatt is; nothing sends mail in between, and if the install fails, the hook refuses to send until the next apply has installed patatt.

Only the GPG key signs, not the SSH key as well. patatt keeps one signature per message, and its validator picks signatures by sender address alone, so a second signature from the same address shows up as a bad signature to anyone holding both keys. OpenPGP is the one a verifier can check against their ordinary gpg keyring.

To check a signed patch: `patatt validate <file>` (maintainers usually use `b4 am`).

## Sending

`send-email` Cc's every address it finds in a `*-by:` trailer, so a commit carrying `Co-Authored-By: Claude <noreply@anthropic.com>` copies Anthropic. `--suppress-cc=misc-by` drops those but keeps `Signed-off-by:` and `Cc:`.

A test patch to yourself, from a throwaway repository:

```powershell
git init "$env:TEMP\send-email-test"; cd "$env:TEMP\send-email-test"
Set-Content test.txt 'hello from git send-email'; git add test.txt; git commit -m 'send-email test'
git send-email --to=regulad@regulad.xyz --suppress-cc=all --confirm=always -1
```

`--dry-run` shows the headers without connecting.
