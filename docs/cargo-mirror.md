# Crate mirror

Every cargo this repo configures downloads crates through a Sonatype Nexus cargo (proxy) repository of crates.io at `repo.regulad.xyz`, the same arrangement as the [bottle mirror](brew-mirror.md). The index URL and the registry name, `regulad-crates-io`, are in `.chezmoidata/cargo-mirror.toml`. Nexus keeps a copy of every crate that passes through, and repeat builds come off the cache.

## How it is set

`.chezmoitemplates/cargo-config.toml` replaces the `crates-io` source with the registry `regulad-crates-io` (`[source.crates-io] replace-with`) and names `cargo:token` as that registry's credential provider. Cargo refuses an authenticated alternative registry with no provider named, and `cargo:token` reads the token from `credentials.toml`.

`.chezmoitemplates/cargo-credentials.toml` holds the token, `Basic <base64 of user:password>`. Nexus takes HTTP Basic, and cargo sends a token verbatim as the `Authorization` header, so the token is the whole header value. The account is the Maven repository's, the Bitwarden item that `regulad-releases` and `regulad-snapshots` use in `dot_m2/settings.xml.tmpl`. Without Bitwarden (`useDummySecrets`) it is the read-only guest account in `.chezmoidata/brew-mirror.toml`, committed in the clear. That is why `.cargo/credentials.toml` is no longer masked under dummy secrets; the crates.io publish token in it is still rendered only with Bitwarden.

macOS and Linux get the two as `~/.cargo/config.toml` and `~/.cargo/credentials.toml` through the `dot_cargo` wrappers. On Windows `00-nt/065-tool-homes` writes them into `%CARGO_HOME%` on the Dev Drive, as it already did with the credentials.

Source replacement is invisible to lockfiles: `Cargo.lock` still records `registry+https://github.com/rust-lang/crates.io-index`, so a project locked through the mirror builds unchanged on a host without it.

## When the credentials are sent

Cargo sends a token to a sparse registry only when the registry requires one: when its `config.json` says `"auth-required": true`, or answers 401, after which cargo asks again with the token and keeps sending it. The `crates-io` repository answers anonymous requests and its `config.json` carries no `auth-required`, so for now cargo fetches anonymously and the token goes unused. Nexus adds `auth-required` once the repository's *Restrict repository content to authenticated users* box is ticked (Nexus 3.75 and later). Nexus checks any credentials it does receive: a wrong password gets a 401 even where anonymous reads succeed.

## Where it is not used

- **Catalina and Big Sur.** cargo on macOS downloads through Apple's `/usr/lib/libcurl` (`cargo -vV` reports `system ssl:(SecureTransport) LibreSSL/...`), and on macOS 10.15 and 11 that is LibreSSL 2.8.3, the client `brew-era-env.sh` routes brew around because it could not reach the mirror. Cargo has no brewed-curl switch, so `cargo-config.toml` leaves crates.io in place there, gated on `.macos.major`.
- **Commands that talk to crates.io itself**: `publish`, `login`, `owner`, `yank` and `search`. With the source replaced, each needs `--registry crates-io`, which uses the `[registry]` token.

GitHub-hosted runners use the mirror like any host. crates.io has none of the per-IP pull limit that keeps brew on ghcr.io there, and cargo's config is a static file with no run-time switch.

## No fallback

Unlike brew's, cargo's source does not switch when the mirror stops answering: cargo fails, and so does an apply that installs `.chezmoidata/cargo-tools.toml`. Nor can a single command opt out. `--config "source.crates-io.replace-with='crates-io'"` is rejected as a cycle, and any other source pointing at crates.io's index is rejected as a second definition of `crates-io`. To get past a mirror outage, move `config.toml` out of `~/.cargo` (or `%CARGO_HOME%`); the next apply puts it back.
