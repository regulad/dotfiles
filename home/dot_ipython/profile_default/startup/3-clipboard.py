# Copy each cell's Out[n], as displayed, to the system clipboard.
#
# Shells out to the same tools, in the same order, as ~/.vim/plugin/clipboard.vim
# and ~/.config/nvim/init.lua, falling back to OSC 52 when the session owns no
# clipboard (ssh, bare tty) or the tool fails.

import base64
import os
import platform
import shutil
import subprocess
import sys


def _copy_cmd():
    if sys.platform == "darwin":
        return ["pbcopy"]
    elif "microsoft" in platform.uname().release.lower():  # has('wsl')
        return ["clip.exe"]
    elif sys.platform == "win32":
        return ["win32yank", "-i", "--crlf"] if shutil.which("win32yank") else []
    elif os.environ.get("PREFIX") and shutil.which("termux-clipboard-set"):
        # PREFIX is set by Termux
        return ["termux-clipboard-set"]
    elif os.environ.get("WAYLAND_DISPLAY"):
        return ["wl-copy", "--type", "text/plain"] if shutil.which("wl-copy") else []
    elif os.environ.get("DISPLAY"):
        if shutil.which("xclip"):
            return ["xclip", "-selection", "clipboard", "-i"]
        elif shutil.which("xsel"):
            return ["xsel", "--clipboard", "--input"]
    return []


_COPY_CMD = _copy_cmd()


def _copy(text):
    if _COPY_CMD:
        try:
            # No pipes on stdout/stderr: wl-copy and xclip fork a child that
            # keeps serving the selection, and it would hold them open.
            proc = subprocess.run(
                _COPY_CMD,
                input=text.encode("utf-8"),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if proc.returncode == 0:
                return
        except OSError:
            pass

    # OSC 52; tmux forwards this itself given `set -s set-clipboard on`.
    sys.__stdout__.write(
        "\x1b]52;c;" + base64.b64encode(text.encode("utf-8")).decode("ascii") + "\x07"
    )
    sys.__stdout__.flush()


def _copy_out(result):
    # result.result is only set when an Out[n] was displayed: not for None,
    # statements, a trailing `;`, or errors.
    if result is None or result.result is None:
        return
    text = get_ipython().history_manager.output_hist_reprs.get(result.execution_count)
    if text:
        _copy(text)


get_ipython().events.register("post_run_cell", _copy_out)
