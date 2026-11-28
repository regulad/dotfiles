REM Scoop persists uv's tools, interpreters and cache in its own directories.
REM A first apply installed Scoop's uv after chezmoi started, so the registry
REM has these settings but this process does not. Import only missing values,
REM preserving explicit process overrides, and prefer User over Machine.
REM Do not depend on Chocolatey's refreshenv: a fresh Scoop host has none.
{{- /* The PowerShell is uv-env.ps1's, which 503-pyghidra-mcp runs too. This
       file's rendered text is part of 500-python's run_once hash: keep it
       unchanged unless 500 should run again. */}}
for /f "tokens=1,* delims==" %%A in ('powershell -NoProfile -NonInteractive -Command "{{ includeTemplate "uv-env.ps1" . | trim }}"') do set "%%A=%%B"
