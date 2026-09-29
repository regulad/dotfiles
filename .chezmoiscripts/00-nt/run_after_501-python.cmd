@echo off
setlocal enabledelayedexpansion

echo debug: upgrading python tooling

uv tool upgrade --quiet --all
