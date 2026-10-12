REM Scoop persists uv's tools, interpreters and cache in its own directories.
REM A first apply installed Scoop's uv after chezmoi started, so the registry
REM has these settings but this process does not. Import only missing values,
REM preserving explicit process overrides, and prefer User over Machine.
REM Do not depend on Chocolatey's refreshenv: a fresh Scoop host has none.
for /f "tokens=1,* delims==" %%A in ('powershell -NoProfile -NonInteractive -Command "$names = 'UV_CACHE_DIR','UV_PYTHON_BIN_DIR','UV_PYTHON_INSTALL_DIR','UV_TOOL_BIN_DIR','UV_TOOL_DIR'; foreach ($name in $names) { if (-not [Environment]::GetEnvironmentVariable($name, 'Process')) { $value = [Environment]::GetEnvironmentVariable($name, 'User'); if (-not $value) { $value = [Environment]::GetEnvironmentVariable($name, 'Machine') }; if ($value) { Write-Output ($name + '=' + $value) } } }"') do set "%%A=%%B"
