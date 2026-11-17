# =====================================================================
#  Shared PowerShell profile (lives in ~/dotfiles, loaded by $PROFILE)
#  Machine-specific stuff goes in ~/.dotfiles-local.ps1 (not in git).
# =====================================================================

$env:DOTFILES = Join-Path $HOME 'dotfiles'
$env:STARSHIP_CONFIG = Join-Path $env:DOTFILES 'starship\starship.toml'

# Prompt
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}

# yazi: `y` opens yazi and cd's to wherever you were when you quit it
function y {
    $tmp = [System.IO.Path]::GetTempFileName()
    yazi $args --cwd-file="$tmp"
    $cwd = Get-Content -Path $tmp -Encoding UTF8
    if ($cwd -and $cwd -ne $PWD.Path) { Set-Location -LiteralPath $cwd }
    Remove-Item -Path $tmp
}

# zoxide: `z foo` jumps to a recent folder matching "foo"
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

# ---------------------------------------------------------------------
# Dotfiles helpers
# ---------------------------------------------------------------------
function dots      { Set-Location $env:DOTFILES }
function dots-edit { nvim $env:DOTFILES }

# Copy configs that apps own back into the repo, then commit + push
function dots-save {
    param([string]$Message = "Update dotfiles")
    & (Join-Path $env:DOTFILES 'install.ps1') -Collect
    Push-Location $env:DOTFILES
    try {
        git add -A
        # Safety net: refuse to push anything that looks like a login or key
        $staged = @(git diff --cached --name-only)
        $badNames = @($staged | Where-Object { $_ -match '(^|/)(auth\.json|\.claude\.json|credentials[^/]*|\.env[^/]*)$|token|secret|\.(pem|key|pfx)$' })
        $badText  = @(git diff --cached -U0 | Select-String -Pattern 'sk-ant-[A-Za-z0-9_-]{10,}|"(access|refresh)_?[Tt]oken"\s*:|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----')
        if ($badNames.Count -or $badText.Count) {
            git reset -q
            Write-Host 'dots-save STOPPED: this looks like a login/secret - nothing was committed:' -ForegroundColor Red
            $badNames | ForEach-Object { Write-Host "  file: $_" -ForegroundColor Red }
            if ($badText.Count) { Write-Host "  $($badText.Count) line(s) look like tokens/keys in the changes" -ForegroundColor Red }
            return
        }
        if (git status --porcelain) {
            git status --short
            git commit -m $Message
            git push
        } else { Write-Host "Nothing to save - dotfiles are up to date." -ForegroundColor Green }
    } finally { Pop-Location }
}

# Pull latest from GitHub and re-apply configs (no app installs)
function dots-pull {
    Push-Location $env:DOTFILES
    try { git pull --ff-only } finally { Pop-Location }
    & (Join-Path $env:DOTFILES 'install.ps1') -ConfigOnly
}

# Pull latest and run the full installer (installs any new apps too)
function dots-install {
    Push-Location $env:DOTFILES
    try { git pull --ff-only } finally { Pop-Location }
    & (Join-Path $env:DOTFILES 'install.ps1')
}

# Machine-specific additions (work shares, PYTHONPATH, etc.) - not in git
$local = Join-Path $HOME '.dotfiles-local.ps1'
if (Test-Path $local) { . $local }
