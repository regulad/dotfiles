#!/usr/bin/env python3
"""Render tooling for each platform and exercise migrations without installs.

Requires Python 3.11+, chezmoi and Bash. Use --bash to select Git Bash on Windows.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib


ROOT = Path(__file__).resolve().parents[1]


def run(args, **kwargs):
    result = subprocess.run(args, text=True, capture_output=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f"{args!r}\n{result.stdout}\n{result.stderr}")
    return result


def fixture(path, platform, arch, series, *, secondary=False, headless=False, dummy=True):
    prefix = "/home/linuxbrew/.linuxbrew" if platform == "linux" else (
        "/opt/homebrew" if arch == "arm64" else "/usr/local"
    )
    data = [
        f"homebrewPrefix = {json.dumps(prefix)}", f"useDummySecrets = {str(dummy).lower()}",
        f"useHeadless = {str(headless).lower()}",
        f"nativeArch = {str(not secondary).lower()}",
    ]
    if secondary:
        data.append('brewArch = "amd64"')
    data += [
        "[chezmoi]", f"os = {json.dumps(platform)}", f"arch = {json.dumps(arch)}",
        "[macos]", f"series = {json.dumps(series)}", f"major = {int(series.split('.')[0])}",
        "[brewMirror]", 'artifact_domain = "https://mirror.invalid"',
        'user = "test"', 'password = "test"',
    ]
    path.write_text("\n".join(data) + "\n", encoding="utf-8", newline="\n")


def render(source, data):
    return run([
        "chezmoi", "--source", str(ROOT), "execute-template",
        "--override-data-file", str(data), "--file", str(ROOT / source),
    ]).stdout.replace("\r", "")


MOCKS = r'''
set -e
record() { printf '%s' "$1" >> "$TEST_LOG"; shift; printf '\t%s' "$@" >> "$TEST_LOG"; printf '\n' >> "$TEST_LOG"; }
brew() {
    record brew "$@"
    if [ "$1" = --prefix ]; then printf '%s\n' "$TEST_WORK/native brew/opt/$2"; return; fi
    if [ "$TEST_FAILURE" = brew ]; then return 23; fi
}
uv() {
    record uv "$@"
    if [ "$1 $2" = 'tool list' ] && [ "$TEST_CLEAN" != 1 ]; then
        printf '%s\n' 'ruff v1.0' 'ty v1.0' 'pre-commit v1.0' 'ansible-core v1.0' 'ansible-lint v1.0' 'yamllint v1.0' 'oci-cli v1.0' 'frida-tools v13.7.1' 'rendercv v2.2' 'yt-dlp v1.0'
    fi
    if [ "$TEST_FAILURE" = uv ] && [ "$1 $2" = 'tool uninstall' ]; then return 24; fi
    return 0
}
pnpm() {
    record pnpm "$@"
    case "$1" in
        --version) printf '%s\n' "$TEST_PNPM_VERSION" ;;
        list)
            if [ "$TEST_CLEAN" = 1 ]; then printf '%s\n' '[{}]'; else
                printf '%s\n' '[{"dependencies":{"vercel":{},"cline":{},"@mermaid-js/mermaid-cli":{},"wrangler":{},"go-ios":{},"cf":{}}}]'
            fi ;;
        root) printf '%s\n' "$TEST_WORK/global project" ;;
        bin) printf '%s\n' "$PNPM_BIN" ;;
        remove)
            [ -n "${npm_config_prefix:-}" ] || return 26
            if [ "$TEST_FAILURE" = pnpm ]; then return 25; fi ;;
    esac
    return 0
}
python3() { "$TEST_PYTHON" "$@"; }
node() { record node "$@"; }
'''


def mock_install(bash, work, script, kind, *, clean=False, failure="", version="12.0.0"):
    log = work / "calls.tsv"
    log.write_text("")
    target = work / "mock.sh"
    target.write_text(MOCKS + script, encoding="utf-8", newline="\n")
    browser = work / "native brew/opt/mermaid-cli/libexec/lib/node_modules/@mermaid-js/mermaid-cli/node_modules/puppeteer"
    browser.mkdir(parents=True, exist_ok=True)
    for name in ("install.mjs", "install.js"):
        (browser / name).unlink(missing_ok=True)
    browser_installer = browser / ("install.js" if version.startswith("8.") else "install.mjs")
    browser_installer.write_text("")
    env = os.environ.copy()
    env.update({
        "TEST_LOG": log.as_posix(), "TEST_WORK": work.as_posix(),
        "TEST_PYTHON": Path(sys.executable).as_posix(), "TEST_CLEAN": "1" if clean else "0",
        "TEST_FAILURE": failure, "TEST_PNPM_VERSION": version,
        "PNPM_HOME": (work / "pnpm home").as_posix(),
    })
    result = subprocess.run([bash, str(target)], env=env, text=True, capture_output=True)
    calls = [line.split("\t") for line in log.read_text().splitlines()]
    if failure:
        assert result.returncode != 0, (failure, result.stdout, result.stderr)
        if failure == "brew":
            assert not any(c[:3] == ["uv", "tool", "uninstall"] or c[:2] == ["pnpm", "remove"] for c in calls)
        return
    assert result.returncode == 0, (result.stdout, result.stderr)
    removed_uv = [c[3] for c in calls if c[:3] == ["uv", "tool", "uninstall"]]
    removed_pnpm = [c[3] for c in calls if c[:3] == ["pnpm", "remove", "-g"]]
    if clean:
        assert not removed_uv and not removed_pnpm
    elif kind == "python":
        assert set(removed_uv) == {"ruff", "ty", "pre-commit", "ansible-core", "ansible-lint", "yamllint", "oci-cli"}
    else:
        assert set(removed_pnpm) == {"vercel", "cline", "@mermaid-js/mermaid-cli", "wrangler"}
    if kind == "python":
        installs = [c for c in calls if c[:3] == ["uv", "tool", "install"]]
        for tool in ("keydive", "pymobiledevice3", "claude-swap", "patatt"):
            call = next(c for c in installs if c[-1] == tool)
            assert call[call.index("--python") + 1] == (work / "native brew/opt/python@3.14/bin/python3.14").as_posix()
        assert any("frida==16.7.0" in c and "frida-tools==13.7.1" in c for c in installs)
        assert any("rendercv[full]@2.2" in c and "click<8.2" in c for c in installs)
        assert any("bgutil-ytdlp-pot-provider" in c for c in installs)
    else:
        install = next(c for c in calls if c[:3] == ["pnpm", "i", "-g"])
        assert set(install[3:]) == {"go-ios@latest", "cf@latest"}
        assert any("dangerouslyAllowAllBuilds" in c for c in calls) == (int(version.split('.')[0]) >= 10)
        assert ["node", browser_installer.as_posix()] in calls
        expected_prefix = work / "pnpm home" if int(version.split('.')[0]) >= 11 else work
        # The actual exported prefix is checked by appending a record below.
        prefix = next(c[1] for c in calls if c[0] == "prefix")
        assert prefix.replace("\\", "/") == expected_prefix.as_posix()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bash", default="bash")
    args = parser.parse_args()
    tiers = tomllib.loads((ROOT / ".chezmoidata/brew-tiers.toml").read_text())["brewTiers"]
    versions = tomllib.loads((ROOT / ".chezmoidata/tooling.toml").read_text())["tooling"]["pythonVersions"]
    tools = {
        "python": tomllib.loads((ROOT / ".chezmoidata/python-tools.toml").read_text())["pythonTools"]["packages"],
        "pnpm": tomllib.loads((ROOT / ".chezmoidata/pnpm-tools.toml").read_text())["pnpmTools"]["packages"],
        "go": tomllib.loads((ROOT / ".chezmoidata/go-tools.toml").read_text())["goTools"]["packages"],
        "cargo": tomllib.loads((ROOT / ".chezmoidata/cargo-tools.toml").read_text())["cargoTools"]["crates"],
    }
    cases = [("darwin", *key.rsplit("-", 1), value["era"]) for key, value in tiers["legacy"].items()]
    cases += [("darwin", version, "arm64", "mainline") for version in ("15", "26", "27")]
    cases += [("linux", "26", arch, "mainline") for arch in ("arm64", "amd64")]
    rendered_count = 0
    with tempfile.TemporaryDirectory(prefix="tooling-check-") as tmp:
        work = Path(tmp)
        data = work / "data.toml"
        for platform, series, arch, era in cases:
            fixture(data, platform, arch, series)
            package_source = ".chezmoitemplates/brew-packages-macos.sh" if platform == "darwin" else ".chezmoiscripts/00-linux/run_after_030-brew-extras.sh.tmpl"
            package = render(package_source, data)
            for version in ("3.10", "3.11", "3.12", "3.13", "3.14", "3.15"):
                assert ("python@" + version in package) == (version in versions[era]), (era, version)
            scripts = [package]
            for kind, number in (("js", "070"), ("python", "100")):
                host = "macos" if platform == "darwin" else "linux"
                text = render(f".chezmoiscripts/00-{host}/run_after_{number}-{kind}-tooling.sh.tmpl", data)
                scripts.append(text)
                # Every entry of the shared data reaches this host one way or the other.
                for entry in tools["python" if kind == "python" else "pnpm"]:
                    if platform not in entry.get("os", [platform]):
                        continue
                    if kind == "python":
                        assert (f'BREW_UV_REPLACEMENTS+=({entry["name"]})' in text) != (f' "{entry.get("spec", entry["name"])}"\n' in text), entry
                    else:
                        assert (f'BREW_PNPM_REPLACEMENTS+=("{entry["pnpm"]}")' in text) != (f'PNPM_CLI_PACKAGES+=("{entry["pnpm"]}@latest")' in text), entry
                if kind == "python":
                    assert 'uv tool install --python "$PYTHON314" -q "keydive"' in text
                    assert ('PYTHON314=/opt/local/bin/python3.14' in text) == ("3.14" not in versions[era])
                    assert ('BREW_PYTHON_TOOLS+=(ruff)' in text) == (era != "catalina")
                    assert ('BREW_PYTHON_TOOLS+=(ty)' in text) == (era in ("mainline", "current", "sonoma"))
                    assert ('uv() { /opt/local/bin/uv' in text) == (era in ("catalina", "bigsur", "monterey"))
                else:
                    assert 'pnpm i -g "${PNPM_CLI_PACKAGES[@]}"' in text
                    assert ('BREW_JS_TOOLS+=(mermaid-cli)' in text) == (era not in ("bigsur", "monterey"))
                    assert ('brew install -q --cask vercel' in text) == (era == "mainline")
                    assert ('BREW_JS_TOOLS+=(cline)' in text) == (era in ("mainline", "current", "sonoma") and not (platform == "darwin" and int(series.split('.')[0]) >= 27))
            for name, attempted in (("110-rust-tooling", "cargo install --locked"), ("120-go-tooling", "go install ")):
                text = render(f".chezmoiscripts/00-{host}/run_after_{name}.sh.tmpl", data)
                assert attempted in text and 'no tools are installed through it' not in text
                if name == "120-go-tooling":
                    assert 'export GOTOOLCHAIN=auto' in text
                    assert ('go install github.com/roy2220/osc52pty@master' in text) == (platform == "darwin")
                scripts.append(text)
            text = render(f".chezmoiscripts/00-{host}/run_after_101-pre-commit-templatedir.sh.tmpl", data)
            assert 'pre-commit init-templatedir --color never --hook-type pre-commit "$TEMPLATE_DIR"' in text
            scripts.append(text)
            if platform == "darwin":
                text = render(".chezmoiscripts/00-macos/run_after_080-vencord.sh.tmpl", data)
                assert 'pnpm i' in text and 'no tools are installed through it' not in text
                scripts.append(text)
                text = render(".chezmoiscripts/00-macos/run_once_after_160-install-vscode-ext.sh.tmpl", data)
                assert 'VS Code extensions are not installed' not in text
                scripts.append(text)
                scripts.append(render(".chezmoiscripts/00-macos/run_after_017-macports-packages.sh.tmpl", data))
                ignored = render(".chezmoiignore.tmpl", data)
                assert '.chezmoiscripts/00-macos/080-vencord.sh' not in ignored
                assert '.chezmoiscripts/00-macos/160-install-vscode-ext.sh' not in ignored
                assert '.chezmoiscripts/00-macos/055-projectm-presets.sh' not in ignored
                assert '\tpinentry-mac\n' in package and '\tmpv\n' in package
            for script in scripts:
                target = work / "syntax.sh"
                target.write_text(script, encoding="utf-8", newline="\n")
                run([args.bash, "-n", str(target)])
                rendered_count += 1
            print(f"PASS {platform} {series}/{arch} ({era})")
        fixture(data, "darwin", "arm64", "26", secondary=True)
        rosetta = render(".chezmoitemplates/brew-packages-macos.sh", data)
        assert "python@3.14" in rosetta and "python@3.15" not in rosetta
        fixture(data, "darwin", "arm64", "26", headless=True)
        ignored = render(".chezmoiignore.tmpl", data)
        assert '.chezmoiscripts/00-macos/080-vencord.sh' in ignored
        assert '.chezmoiscripts/00-macos/160-install-vscode-ext.sh' in ignored
        assert '.chezmoiscripts/00-macos/055-projectm-presets.sh' in ignored
        assert '.chezmoiscripts/00-macos/170-firefox-policies.sh' in ignored
        package = render(".chezmoitemplates/brew-packages-macos.sh", data)
        assert 'pinentry-mac' not in package and '\tmpv\n' not in package
        agent = render("private_dot_gnupg/private_gpg-agent.conf.tmpl", data)
        assert 'pinentry-program /opt/homebrew/bin/pinentry\n' in agent and 'pinentry-mac' not in agent
        for headless in (False, True):
            fixture(data, "linux", "amd64", "26", headless=headless)
            apt = render(".chezmoiscripts/00-linux/run_after_021-apt-packages.sh.tmpl", data)
            dnf = render(".chezmoiscripts/00-linux/run_after_020-dnf-packages.sh.tmpl", data)
            for gui in ('\tmpv\n', '\tvlc\n', '\tvlc-plugin-visualization\n', '\tmesa-utils  #'):
                assert (gui in apt) != headless, gui
            assert ('\tglx-utils  #' in dnf) != headless and '\tvainfo  #' in apt and '\tlibva-utils  #' in dnf
            scoop = render(".chezmoiscripts/00-nt/run_once_after_200-scoop-install.cmd.tmpl", data)
            for gui in ('tinyxnb ^', 'mongodb-compass ^', 'mpv ^', 'ffdec ^', 'autohotkey ^', 'icaros-np', 'portable_config'):
                assert (gui in scoop) != headless, gui
            assert 'shasum ^\ndeno ^' in scoop and 'languagetool-java ^\nnssm\n' in scoop
            fixture(data, "linux", "amd64", "26", headless=headless, dummy=False)
            reg = render(".chezmoitemplates/registry-system.reg", data)
            assert ('AutoSelectCertificateForUrls' in reg) != headless
        # Windows renders the same data into its own scripts.
        fixture(data, "windows", "amd64", "26")
        nt = {name: render(f".chezmoiscripts/00-nt/{name}.cmd.tmpl", data) for name in (
            "run_once_after_500-python", "run_after_550-cargo", "run_after_560-go-tooling", "run_after_570-pnpm-tooling")}
        for kind, script, line in (
                ("python", "run_once_after_500-python", lambda e: f' "{e.get("spec", e["name"])}" || goto :uv_install_failed'),
                ("cargo", "run_after_550-cargo", lambda e: f'call :cargoinstall {e["name"]} ||'),
                ("go", "run_after_560-go-tooling", lambda e: f'call :goinstall {e["module"]} ||'),
                ("pnpm", "run_after_570-pnpm-tooling", lambda e: "%GO_IOS_PACKAGE%" if e["pnpm"] == "go-ios" else f'! {e["pnpm"]}@latest"')):
            for entry in tools[kind]:
                assert (line(entry) in nt[script]) == ("windows" in entry.get("os", ["windows"])), (kind, entry)
        assert 'call :uvinstall --python "cpython-3.13-windows-x86_64-none" -q --with "bgutil-ytdlp-pot-provider"' in nt["run_once_after_500-python"]
        assert 'call :uvinstall --python "cp313" -q --with "rendercv-fonts<0.5"' in nt["run_once_after_500-python"]
        assert 'call :uvinstall -q "poetry" ||' in nt["run_once_after_500-python"]
        fixture(data, "linux", "arm64", "26")
        for kind in ("python", "js"):
            script = render(f".chezmoitemplates/{kind}-tooling.sh", data)
            if kind == "js":
                script += '\nrecord prefix "$npm_config_prefix"\n'
            mock_install(args.bash, work, script, kind)
            mock_install(args.bash, work, script, kind, clean=True)
            mock_install(args.bash, work, script, kind, failure="brew")
            mock_install(args.bash, work, script, kind, failure="uv" if kind == "python" else "pnpm")
            if kind == "js":
                mock_install(args.bash, work, script, kind, version="8.15.0")
        print(f"PASS {rendered_count} rendered scripts, shared tool data on every platform, Rosetta/headless gates (macOS, Linux packages, scoop, registry), and 9 mocked migrations")


if __name__ == "__main__":
    main()
