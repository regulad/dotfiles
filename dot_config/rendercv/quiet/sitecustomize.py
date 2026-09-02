"""Silence RenderCV's startup banner.

RenderCV 2.2 prints a "Welcome to RenderCV! Some useful links:" table on every
single `rendercv render`, and immediately above it a "A new version of RenderCV
is available!" warning. Both come from `printer.welcome()`, which
`cli/commands.py` calls unconditionally as the first statement of the render
command. There is no flag, no config key and no environment variable to turn
either off -- the package contains no `os.environ` or `getenv` reference at all.

The version warning is the worse half: `warn_if_new_version_is_available()`
makes a blocking urllib request to https://pypi.org/pypi/rendercv/json before
any work starts, so every render pays a network round trip to be told to install
the version this repo is deliberately pinned away from.

This file is not on the default path. It is reached only because a `rendercv`
wrapper puts this directory on PYTHONPATH, and CPython imports `sitecustomize`
from the path at startup. So it applies to RenderCV and to nothing else -- no
other interpreter on the system sees it. There are two such wrappers, one per
shell family: the `rendercv` function in ~/.commonrc on Linux and macOS, and the
`rendercv` doskey macro in ~/.doskey.mac on Windows. Both scope PYTHONPATH to
the single invocation rather than exporting it.

Everything is wrapped in a bare try/except on purpose: if a future version
renames or moves these functions, the patch silently does nothing and the banner
comes back. That is the correct failure mode for a cosmetic patch -- it must
never be able to stop a CV from rendering.
"""

try:
    from rendercv.cli import printer

    printer.welcome = lambda: None
    printer.warn_if_new_version_is_available = lambda: False
except Exception:  # noqa: BLE001 - cosmetic only; must never break the CLI
    pass
