# Update pass for both editors' plugin managers; runs on every apply, shared
# verbatim by the linux and macos hooks. The Windows half is
# .chezmoiscripts/00-nt/run_after_806-vim-plugin-update.cmd. Installation and
# pinning live in the vim-plugins bootstrap (165 / 805); this pass only moves
# what is already declared forward.

if command -v vim &>/dev/null && [ -d "$HOME/.vim/bundle/Vundle.vim" ]; then
	# :PluginUpdate is a `git pull` of each checkout's own tracking branch
	# (vundle/installer.vim s:sync), so the coc.nvim release pin set by the
	# bootstrap moves along origin/release rather than being dragged back to
	# the default branch. Same headless caveats as the bootstrap: -E -s
	# because a normal-mode headless vim stops on the startup "Press ENTER"
	# prompt and never reaches the queued commands, and Vundle exits non-zero
	# from ex mode even on success, so the exit code means nothing here.
	echo "note: updating vim plugins with Vundle" >&2
	vim -E -s -N -u "$HOME/.vimrc" -c 'PluginUpdate' -c 'qall!' </dev/null >/dev/null || true
else
	echo "note: vim or Vundle not present, skipping Vundle update" >&2
fi

if command -v nvim &>/dev/null; then
	# Lazy! sync rather than Lazy! update: install what is missing, update
	# the rest, and delete anything no longer declared in lua/plugins.lua --
	# the plugin list is the whole truth on every apply, the same contract as
	# dot_vscode-extensions.txt and dot_coc-extensions.txt. The bang makes
	# headless nvim block until the tasks finish instead of quitting
	# mid-flight, and a fresh machine's first run also bootstraps lazy.nvim
	# itself via config.lazy.
	echo "note: syncing nvim plugins with lazy.nvim" >&2
	nvim --headless '+Lazy! sync' +qa </dev/null
else
	echo "note: nvim is not installed, skipping lazy.nvim sync" >&2
fi
