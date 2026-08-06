@echo off
setlocal enabledelayedexpansion

REM matches unix script (pnpm branch; bitwarden-cli covered by scoop instead)

set pnpm_packages=^
@mermaid-js/mermaid-cli@latest ^
typescript@latest ^
typescript-language-server@latest ^
bash-language-server@latest ^
yaml-language-server@latest

echo debug: installing pnpm global tooling
call pnpm i -g --silent %pnpm_packages%
call pnpm update --global --silent
