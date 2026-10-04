# Takes scoop's gradle off a machine that still has it. 200-scoop-install
# dropped it from its list, and says why: the manifest's post_install points a
# per-user GRADLE_USER_HOME into scoop's persist directory, and scoop cannot be
# told to skip a hook. Dropping a package from a list never uninstalls it,
# though, and 210-scoop-update's `scoop update --all` would upgrade a leftover
# gradle and run that hook again, so this runs ahead of 210. Projects bring
# their own Gradle through gradlew.
#
# --purge takes scoop's persist\gradle with it. That only ever held what Gradle
# downloads or regenerates; its home is GRADLE_USER_HOME on the D: Dev Drive
# (registry-system.reg). The manifest has no uninstall hook, so the per-user
# GRADLE_USER_HOME that registry-user.reg set stays put.
#
# run_once_: chezmoi records the script only after a clean exit, so a failed
# uninstall (exit 1 below) means the next apply tries again, and a machine
# without scoop's gradle finds nothing to do.
#
# Same shape as the act removal in 105-docker-desktop-remove: `scoop list
# gradle` is a substring query, hence the anchored match on the name column,
# and scoop is a .ps1 shim that sets no $LASTEXITCODE, so the uninstall is
# checked by listing again.
function Test-ScoopGradle {
    $Listing = & scoop list gradle 6>$null 2>$null | Out-String
    return ($Listing -match '(?m)^\s*gradle\s+\d')
}

if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Host 'debug: scoop is not installed, so neither is its gradle'
}
elseif (-not (Test-ScoopGradle)) {
    Write-Host "debug: scoop's gradle is not installed"
}
else {
    Write-Host "notice: uninstalling scoop's gradle; projects use gradlew, see 200-scoop-install"
    & scoop uninstall gradle --purge
    if (Test-ScoopGradle) {
        Write-Host 'error: scoop uninstall gradle did not remove it'
        exit 1
    }
}
