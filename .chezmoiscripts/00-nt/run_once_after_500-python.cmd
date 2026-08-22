@echo off
setlocal enabledelayedexpansion

echo note: installing python tooling
REM matches unix script

uv tool install -q "ruff"
uv tool install -q "ty"
uv tool install -q "hf"
uv tool install -q "pre-commit"
uv tool install --python cp310 -q "git+https://github.com/regulad/keymap-renderer.git@master"
uv tool install --python cp314 -q "rendercv[full]@2.3"
uv tool install -q "hatch"
uv tool install -q "autopep8"
uv tool install --python cp314 -q "yt-dlp[default]"
uv tool install --python cp314 -q "pymobiledevice3"
uv tool install --python cp314 -q "claude-swap"
