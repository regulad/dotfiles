{{- /*
  uv's settings that chezmoi's own environment can lack, as NAME=VALUE lines:
  each of uv's directory variables the process does not set, from the User
  scope, else the Machine one. Scoop persists uv's tools, interpreters and
  cache in its own directories, and a first apply installs scoop's uv after
  chezmoi started, so the registry has these settings and the process does
  not. One line of PowerShell, so that uv-env.cmd can pass it to `powershell
  -Command` inside a `for /f`: no double quotes and no comments in it.
  00-nt/503-pyghidra-mcp runs the same line itself.
*/ -}}
$names = 'UV_CACHE_DIR','UV_PYTHON_BIN_DIR','UV_PYTHON_INSTALL_DIR','UV_TOOL_BIN_DIR','UV_TOOL_DIR'; foreach ($name in $names) { if (-not [Environment]::GetEnvironmentVariable($name, 'Process')) { $value = [Environment]::GetEnvironmentVariable($name, 'User'); if (-not $value) { $value = [Environment]::GetEnvironmentVariable($name, 'Machine') }; if ($value) { Write-Output ($name + '=' + $value) } } }
