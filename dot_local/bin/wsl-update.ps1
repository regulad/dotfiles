<#
.SYNOPSIS
    Bring a deployed regulad WSL instance's dotfiles up to this machine's
    chezmoi HEAD, then run a full apply in it.

.DESCRIPTION
    The third of the WSL helpers: wsl-deploy installs regulad-<flavor> from a
    built image, wsl-enter opens a shell in it, and this moves an existing one
    forward without redeploying it.

    An instance's chezmoi source is a plain copy of the tree its image was built
    from, and /etc/dotfiles-commit names that commit (.github/workflows/
    wsl-package.yml writes it). This builds the patch from that commit to HEAD
    of the chezmoi source on the Windows side, checks it against the instance's
    tree, applies it, records HEAD in /etc/dotfiles-commit, re-renders the
    chezmoi config, and runs `chezmoi apply` -- the full one, interactively,
    since it may ask for the Bitwarden master password.

    The commit is recorded as soon as the patch is in, before the apply: the
    file says what the source tree is, and if the apply then fails, running this
    again finds nothing left to patch and only retries the apply, where
    recording it afterwards would have it try to apply the same patch twice.

    Only committed work travels: HEAD is what gets patched in, and uncommitted
    changes on the Windows side are left out, with a note.

.NOTES
    Reachable as `wsl-update` in cmd via the doskey macro in .doskey.mac, which
    invokes it by full path for the same reason wsl-deploy does: ~/.local/bin is
    only put on PATH by .commonprofile, which is POSIX shells only.

.EXAMPLE
    wsl-update                    # ubuntu: patch to HEAD, then a full apply
    wsl-update fedora
    wsl-update.ps1 -Flavor fedora -DryRun   # show and check the patch, change nothing
    wsl-update.ps1 -NoApply                 # patch and re-init, apply later
#>
[CmdletBinding()]
param(
    # Positional so `wsl-update fedora` works through the doskey macro, which
    # forwards $* to `pwsh -File`. Matches wsl-deploy's and wsl-enter's.
    [Parameter(Position = 0)]
    [ValidateSet('fedora', 'ubuntu')]
    [string]$Flavor = 'ubuntu',

    # Build the patch, show it, and check that it applies inside the instance.
    # Nothing in the instance is changed.
    [switch]$DryRun,

    # Patch the source, record the commit and re-render the config, but leave
    # the apply for later (`chezmoi apply` inside the instance, or this again).
    [switch]$NoApply,

    # Go ahead without asking when HEAD does not contain the instance's commit,
    # which makes the patch take back whatever the instance has that HEAD lacks.
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Same reason as wsl-deploy: wsl.exe emits UTF-16LE by default, which lands in
# PowerShell as strings full of NULs that no comparison will match.
$env:WSL_UTF8 = '1'

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Note { param([string]$Message) Write-Host "    $Message" -ForegroundColor DarkGray }

function Assert-NativeSuccess {
    param([string]$What)
    if ($LASTEXITCODE -ne 0) { throw "$What failed with exit code $LASTEXITCODE" }
}

$distroName = "regulad-$Flavor"

# --- preflight -------------------------------------------------------------

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git is not on PATH. It comes from scoop; see .chezmoiscripts/00-nt/run_once_after_200-scoop-install.cmd.tmpl"
}

wsl.exe --version 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "WSL is not installed. Run .chezmoiscripts/00-nt/run_once_after_110-wsl-install.cmd, or 'wsl --install --no-distribution'."
}

if ((wsl.exe --list --quiet) -notcontains $distroName) {
    throw "'$distroName' is not installed. Deploy it first:  wsl-deploy $Flavor"
}

# The Windows side's chezmoi source, asked of chezmoi so a non-default
# sourceDir is honoured.
$source = $null
if (Get-Command chezmoi -ErrorAction SilentlyContinue) {
    $source = "$(chezmoi source-path 2>$null)".Trim()
}
if (-not $source) { $source = Join-Path $HOME '.local\share\chezmoi' }
git -C $source rev-parse --git-dir 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "$source is not a git repository" }

$head = "$(git -C $source rev-parse HEAD)".Trim()
Assert-NativeSuccess 'git rev-parse HEAD'

# --- what the instance is at -------------------------------------------------

# As wsl-deploy reads it: --exec as root, so no login shell runs any dotfiles
# and no OOBE starts. Starts the instance if it is stopped.
$out = wsl.exe -d $distroName -u root --exec cat /etc/dotfiles-commit 2>$null
$readOk = $LASTEXITCODE -eq 0
$base = "$($out | Select-Object -First 1)".Trim()
if (-not $readOk -or $base -notmatch '^[0-9a-f]{40}$') {
    throw "'$distroName' has no readable /etc/dotfiles-commit, so there is no commit to patch from (an image built before images carried it?). Redeploy it:  wsl-deploy $Flavor"
}

Write-Step "updating '$distroName' from $($base.Substring(0, 7)) to HEAD $($head.Substring(0, 7)) of $source"

# The image may come from a commit this clone has not fetched -- one CI built
# and nothing here has pulled since.
git -C $source cat-file -e "$base^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Note "commit $($base.Substring(0, 7)) is not in this clone; fetching"
    git -C $source fetch --quiet origin
    Assert-NativeSuccess 'git fetch origin'
    git -C $source cat-file -e "$base^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "the instance's commit $base is not in $source even after a fetch"
    }
}

$dirty = @(git -C $source status --porcelain)
if ($dirty.Count -gt 0) {
    Write-Note "$($dirty.Count) uncommitted change(s) in $source are not included; only HEAD is"
}

# Normally HEAD is ahead of the instance. If it does not contain the instance's
# commit -- a rollback, or a branch that diverged -- the patch still makes the
# instance's tree HEAD's, which takes back whatever the instance has that HEAD
# lacks. That is worth a question.
git -C $source merge-base --is-ancestor $base $head
if ($LASTEXITCODE -ne 0 -and $base -ne $head) {
    Write-Host ""
    Write-Host "  HEAD does not contain the instance's commit $($base.Substring(0, 7))." -ForegroundColor Yellow
    Write-Host "  Patching makes the instance's source HEAD's tree, undoing what" -ForegroundColor Yellow
    Write-Host "  $($base.Substring(0, 7)) has that HEAD does not." -ForegroundColor Yellow
    Write-Host ""
    if (-not $Force -and -not $DryRun) {
        $reply = Read-Host "  Continue? [y/N]"
        # "$reply", as wsl-deploy compares it: with no console, Read-Host
        # outputs nothing, and a bare -notmatch on that is an empty array,
        # which `if` reads as false.
        if ("$reply" -notmatch '^[Yy]') {
            Write-Step 'left the instance alone; nothing was changed.'
            return
        }
    }
}

# --- the patch -------------------------------------------------------------

$work = Join-Path ([IO.Path]::GetTempPath()) "wsl-update-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
New-Item -ItemType Directory -Path $work | Out-Null

try {
    $patch = Join-Path $work 'changes.patch'
    $helper = Join-Path $work 'update.sh'

    if ($base -eq $head) {
        Write-Note 'the instance is already at HEAD; nothing to patch'
        $hasChanges = $false
    } else {
        $commits = "$(git -C $source rev-list --count "$base..$head")".Trim()
        Write-Step "patch: $commits commit(s)"
        git -C $source --no-pager diff --stat=100 --no-color $base $head | ForEach-Object { Write-Note $_ }

        # git writes the file itself (--output): through PowerShell's pipeline
        # the bytes would be decoded and re-encoded on the way, which a binary
        # patch (the age-encrypted files) does not survive. Pinned so that no
        # setting here changes what `git apply` inside the instance has to
        # read: no CRLF conversion, no textconv (Git for Windows ships
        # astextplain for a few binary types), no external diff, no colour,
        # and a/ b/ prefixes whatever diff.noprefix or diff.mnemonicPrefix say.
        git -C $source -c core.autocrlf=false diff --binary --no-color --no-ext-diff --no-textconv `
            --src-prefix=a/ --dst-prefix=b/ "--output=$patch" $base $head
        Assert-NativeSuccess 'git diff'
        $hasChanges = (Get-Item -LiteralPath $patch).Length -gt 0
    }

    # The part that runs inside the instance, as its default user in a login
    # shell, which is what puts brew's chezmoi on PATH. Written out with LF
    # endings, since bash takes a CR as part of the line.
    $helperText = @'
#!/bin/bash
# Written and run by wsl-update.ps1 on the Windows side; see there.
#   update.sh check|patch <patch file>    git apply --check / git apply
#   update.sh init                         chezmoi init, same dummy/headless flags
#   update.sh apply                        chezmoi apply
set -euo pipefail
src="$(chezmoi source-path)"
case "$1" in
check)
    git -C "$src" apply --check --binary "$2"
    echo "the patch applies cleanly to $src"
    ;;
patch)
    git -C "$src" apply --binary "$2"
    ;;
init)
    # The patch can change .chezmoi.toml.tmpl, which only `chezmoi init`
    # re-renders. init recomputes useDummySecrets from the environment
    # (CHEZMOI_USE_DUMMY), so it is handed in as the instance has it now: still
    # dummy before OOBE has run, real after. useHeadless needs nothing: WSL is
    # never headless.
    dummy="$(chezmoi execute-template '{{ .useDummySecrets }}')"
    vars=()
    [ "$dummy" = true ] && vars+=(CHEZMOI_USE_DUMMY=1)
    env -u CHEZMOI_USE_DUMMY "${vars[@]}" chezmoi init
    echo "chezmoi config re-rendered (useDummySecrets=$dummy)"
    ;;
apply)
    chezmoi apply
    ;;
esac
'@
    [IO.File]::WriteAllText($helper, ($helperText -replace "`r`n", "`n"), [Text.UTF8Encoding]::new($false))

    $helperWsl = "$(wsl.exe -d $distroName --exec wslpath -u $helper)".Trim()
    Assert-NativeSuccess 'wslpath (helper)'
    $patchWsl = "$(wsl.exe -d $distroName --exec wslpath -u $patch)".Trim()
    Assert-NativeSuccess 'wslpath (patch)'

    function Invoke-InInstance {
        param([string]$What, [string[]]$HelperArgs)
        wsl.exe -d $distroName --exec bash -l $helperWsl @HelperArgs
        Assert-NativeSuccess $What
    }

    if ($hasChanges) {
        Write-Step "checking the patch against $distroName's source"
        Invoke-InInstance 'git apply --check' @('check', $patchWsl)
    }

    if ($DryRun) {
        Write-Step 'dry run; nothing in the instance was changed.'
        return
    }

    if ($hasChanges) {
        Write-Step 'applying the patch'
        Invoke-InInstance 'git apply' @('patch', $patchWsl)

        # As root over --exec, no login shell: /etc is root's, and this must
        # not depend on the instance's sudo. One 40-hex line, as wsl-package.yml
        # writes it. No quotes in the script on purpose: it crosses wsl.exe's
        # Windows command line, and a 40-hex argument needs none.
        wsl.exe -d $distroName -u root --exec sh -c 'echo $1 > /etc/dotfiles-commit' sh $head
        Assert-NativeSuccess 'writing /etc/dotfiles-commit'
        Write-Note "/etc/dotfiles-commit is now $head"
    }

    Write-Step 're-rendering the chezmoi config'
    Invoke-InInstance 'chezmoi init' @('init')

    if ($NoApply) {
        # Running this again is the apply: there is nothing left to patch.
        Write-Step "patched; apply when ready:  wsl-update $Flavor"
        return
    }

    Write-Step "running a full chezmoi apply in $distroName"
    Write-Note 'it may ask for the Bitwarden master password'
    Invoke-InInstance 'chezmoi apply' @('apply')
    Write-Step "'$distroName' is at HEAD $($head.Substring(0, 7)), applied."
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
