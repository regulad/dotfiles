@echo off
setlocal enabledelayedexpansion

echo note: upgrading python tooling

uv tool upgrade --quiet --all
