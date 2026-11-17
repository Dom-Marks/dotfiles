# =====================================================================
#  Dotfiles installer for Windows - no admin required.
#
#  Fresh machine - paste into cmd (no admin needed):
#    curl.exe -fsSLo %TEMP%\dotfiles.cmd https://raw.githubusercontent.com/Dom-Marks/dotfiles/main/install.cmd && %TEMP%\dotfiles.cmd
#
#  Same thing from Windows PowerShell or pwsh:
#    cmd /c "curl.exe -fsSLo %TEMP%\dotfiles.cmd https://raw.githubusercontent.com/Dom-Marks/dotfiles/main/install.cmd && %TEMP%\dotfiles.cmd"
#
#  ("irm ... | iex" also works where security software allows it.)
#
#  Works in Windows PowerShell 5.1 and PowerShell 7+.
#
#  From the repo:
#    .\install.ps1              install apps + apply configs
#    .\install.ps1 -ConfigOnly  only apply configs (used by dots-pull)
#    .\install.ps1 -Collect     copy app-owned configs back into the repo (used by dots-save)
#
#  Safe to re-run: anything already in place is skipped, anything replaced is
#  backed up next to the original as <name>.bak-<timestamp>.
# =====================================================================
param([switch]$ConfigOnly, [switch]$Collect)

& {
$ErrorActionPreference = 'Stop'
# Older Windows PowerShell defaults to TLS 1.0 - GitHub needs 1.2
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

$RepoUrl    = 'https://github.com/Dom-Marks/dotfiles.git'
$Dotfiles   = Join-Path $HOME 'dotfiles'
$ScoopRoot  = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $HOME 'scoop' }
$Stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
$Utf8NoBom  = New-Object System.Text.UTF8Encoding $false

$ScoopBuckets = @('extras', 'nerd-fonts')
$ScoopApps = @(
    '7zip', 'git',                       # needed first by scoop itself
    'neovim', 'ripgrep', 'fd', 'mingw', 'tree-sitter',   # editor + its tools
    'starship', 'zoxide', 'yazi',        # shell
    'windows-terminal', 'JetBrainsMono-NF'
)

# pi keys that pi writes itself - never stored in the repo
$PiIgnoredKeys = @('lastChangelogVersion', 'extensionChangelogVersions')

# ---------------------------------------------------------------------
function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    ok   $msg" -ForegroundColor DarkGray }
function Did($msg)  { Write-Host "    done $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    warn $msg" -ForegroundColor Yellow }

function Has($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

# Run external programs without Windows PowerShell treating their stderr output as fatal
function Native([scriptblock]$Block) {
    $ErrorActionPreference = 'Continue'
    & $Block
}

# Download an installer script to a file and run it. Avoids "irm | iex",
# which endpoint security often blocks.
function Run-Installer($Url, [string[]]$ExtraArgs = @()) {
    $file = Join-Path $env:TEMP ("dotfiles-" + [IO.Path]::GetFileName(([Uri]$Url).AbsolutePath))
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $file
    Native { powershell -NoProfile -ExecutionPolicy Bypass -File $file @ExtraArgs }
    Remove-Item $file -ErrorAction SilentlyContinue
}

function Is-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'Machine')
}

function Backup($path) {
    $bak = "$path.bak-$Stamp"
    Move-Item -LiteralPath $path -Destination $bak
    Warn "backed up existing $path -> $bak"
}

# Make $Path a junction (folder link, no admin needed) pointing at $Target
function Link-Dir($Path, $Target) {
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        if ($item.LinkType -eq 'Junction' -and (@($item.Target) | ForEach-Object { $_.TrimEnd('\') }) -contains $Target.TrimEnd('\')) {
            Ok "$Path -> $Target"; return
        }
        Backup $Path
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
    New-Item -ItemType Junction -Path $Path -Target $Target | Out-Null
    Did "$Path -> $Target"
}

function Same-File($a, $b) {
    (Test-Path -LiteralPath $a) -and (Test-Path -LiteralPath $b) -and
    ((Get-FileHash -LiteralPath $a).Hash -eq (Get-FileHash -LiteralPath $b).Hash)
}

# Copy repo file into place (for apps that keep other state next to their config)
function Copy-Config($Source, $Dest) {
    if (Same-File $Source $Dest) { Ok $Dest; return }
    if (Test-Path -LiteralPath $Dest) { Backup $Dest }
    New-Item -ItemType Directory -Force -Path (Split-Path $Dest) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Dest
    Did $Dest
}

# Write JSON only if the content actually changed (PS 5.1 and 7 format JSON
# differently, so this avoids formatting-only churn). Returns $true if written.
function Write-Json($Path, $Obj) {
    if (Test-Path -LiteralPath $Path) {
        $old = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 20 -Compress
        if ($old -eq ($Obj | ConvertTo-Json -Depth 20 -Compress)) { return $false }
    }
    [IO.File]::WriteAllText($Path, ($Obj | ConvertTo-Json -Depth 20), $Utf8NoBom)
    return $true
}

# Paths of app-owned config files
$HerdrConfig = Join-Path $env:APPDATA 'herdr\config.toml'
$WTSettings  = Join-Path $ScoopRoot 'persist\windows-terminal\settings\settings.json'
$PiSettings  = Join-Path $HOME '.pi\agent\settings.json'

# ---------------------------------------------------------------------
# -Collect: copy live configs back into the repo
# ---------------------------------------------------------------------
if ($Collect) {
    Step 'Collecting app configs into the repo'
    if (Test-Path $HerdrConfig) { Copy-Item $HerdrConfig (Join-Path $Dotfiles 'herdr\config.toml') -Force; Ok 'herdr' }
    if (Test-Path $WTSettings)  { Copy-Item $WTSettings (Join-Path $Dotfiles 'windows-terminal\settings.json') -Force; Ok 'windows terminal' }
    if (Test-Path $PiSettings) {
        $live = Get-Content $PiSettings -Raw | ConvertFrom-Json
        foreach ($k in $PiIgnoredKeys) { $live.PSObject.Properties.Remove($k) }
        if (Write-Json (Join-Path $Dotfiles 'pi\settings.json') $live) { Did 'pi settings' } else { Ok 'pi settings' }
    }
    return
}

# ---------------------------------------------------------------------
# Apps
# ---------------------------------------------------------------------
if (-not $ConfigOnly) {
    Step 'PowerShell execution policy'
    $policy = Get-ExecutionPolicy -Scope CurrentUser
    if ($policy -in @('Undefined', 'Restricted', 'AllSigned')) {
        try {
            Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
            Did 'set CurrentUser policy to RemoteSigned (so your profile can load)'
        } catch { Warn "could not change execution policy (likely set by Group Policy): $($_.Exception.Message)" }
    } else { Ok "CurrentUser policy is $policy" }
    Set-ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue

    Step 'Scoop'
    if (-not (Has scoop)) {
        if (Is-Admin) {
            Warn 'running as administrator - installing scoop with -RunAsAdmin (still per-user)'
            Run-Installer 'https://raw.githubusercontent.com/ScoopInstaller/Install/master/install.ps1' @('-RunAsAdmin')
        } else {
            Run-Installer 'https://raw.githubusercontent.com/ScoopInstaller/Install/master/install.ps1'
        }
        Refresh-Path
        Did 'installed scoop'
    } else { Ok 'scoop already installed' }

    Step 'Scoop apps'
    foreach ($app in $ScoopApps) {
        if ($app -eq 'neovim') {   # buckets need git, so add them once git is in
            foreach ($b in $ScoopBuckets) {
                if (-not (Test-Path (Join-Path $ScoopRoot "buckets\$b"))) { Native { scoop bucket add $b }; Did "bucket $b" }
            }
        }
        if (Test-Path (Join-Path $ScoopRoot "apps\$app\current")) { Ok $app; continue }
        Native { scoop install $app }
        if (Test-Path (Join-Path $ScoopRoot "apps\$app\current")) { Did $app } else { Warn "$app failed to install - re-run later" }
    }
    Refresh-Path

    Step 'herdr'
    if (-not (Has herdr)) {
        Run-Installer 'https://herdr.dev/install.ps1'
        Refresh-Path
        Did 'installed herdr'
    } else { Ok 'herdr already installed' }

    Step 'pi'
    if (-not (Has pi)) {
        Run-Installer 'https://pi.dev/install.ps1'
        Refresh-Path
        Did 'installed pi'
    } else { Ok 'pi already installed' }
}

# ---------------------------------------------------------------------
# Repo
# ---------------------------------------------------------------------
Step 'Dotfiles repo'
if (-not (Test-Path (Join-Path $Dotfiles '.git'))) {
    if (Test-Path $Dotfiles) { Backup $Dotfiles }
    Native { git clone $RepoUrl $Dotfiles }
    if (-not (Test-Path (Join-Path $Dotfiles '.git'))) { throw "git clone of $RepoUrl failed" }
    Did "cloned to $Dotfiles"
} else { Ok $Dotfiles }

# ---------------------------------------------------------------------
# Configs
# ---------------------------------------------------------------------
Step 'Linking configs'
Link-Dir (Join-Path $env:LOCALAPPDATA 'nvim') (Join-Path $Dotfiles 'nvim')
Link-Dir (Join-Path $HOME '.agents')          (Join-Path $Dotfiles 'agents')

Step 'Copying app-owned configs'
Copy-Config (Join-Path $Dotfiles 'herdr\config.toml') $HerdrConfig
if (Test-Path (Join-Path $ScoopRoot 'apps\windows-terminal')) {
    Copy-Config (Join-Path $Dotfiles 'windows-terminal\settings.json') $WTSettings
}

Step 'pi settings (merged, your login is untouched)'
$repoPi = Get-Content (Join-Path $Dotfiles 'pi\settings.json') -Raw | ConvertFrom-Json
if (Test-Path $PiSettings) { $livePi = Get-Content $PiSettings -Raw | ConvertFrom-Json }
else { New-Item -ItemType Directory -Force -Path (Split-Path $PiSettings) | Out-Null; $livePi = New-Object PSObject }
foreach ($p in $repoPi.PSObject.Properties) { $livePi | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
if (Write-Json $PiSettings $livePi) { Did $PiSettings } else { Ok $PiSettings }

if (Has pi) {
    foreach ($pkg in @($repoPi.packages)) {
        $name = $pkg -replace '^npm:', '' -replace '(?<=.)@[^/]*$', ''
        if (Test-Path (Join-Path $HOME ".pi\agent\npm\node_modules\$name")) { Ok "pi package $pkg" }
        else { Native { pi install $pkg }; Did "pi package $pkg" }
    }
}
if ((Has herdr) -and (Has pi)) {
    if ((Native { herdr integration status 2>&1 } | Out-String) -match 'pi: current') { Ok 'herdr <-> pi integration' }
    else { Native { herdr integration install pi }; Did 'herdr <-> pi integration' }
}

Step 'User environment variables'
$envVars = @{
    'STARSHIP_CONFIG' = (Join-Path $Dotfiles 'starship\starship.toml')
    'YAZI_FILE_ONE'   = (Join-Path $ScoopRoot 'apps\git\current\usr\bin\file.exe')   # yazi file-type detection
}
foreach ($k in $envVars.Keys) {
    if ([Environment]::GetEnvironmentVariable($k, 'User') -ne $envVars[$k]) {
        [Environment]::SetEnvironmentVariable($k, $envVars[$k], 'User'); Did "$k = $($envVars[$k])"
    } else { Ok $k }
    Set-Item "env:$k" $envVars[$k]
}

Step 'Windows appearance (for Windows Terminal frosted glass)'
# Acrylic/glass only renders when "Transparency effects" is on. Per-user, no admin.
$personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
if (-not (Test-Path $personalize)) { New-Item -Path $personalize -Force | Out-Null }
if ((Get-ItemProperty $personalize -ErrorAction SilentlyContinue).EnableTransparency -ne 1) {
    Set-ItemProperty $personalize -Name EnableTransparency -Value 1 -Type DWord
    Did 'turned on Windows transparency effects'
} else { Ok 'transparency effects on' }

Step 'PowerShell profile'
$stub = @(
    '# Managed by ~/dotfiles/install.ps1 - edit ~/dotfiles/powershell/profile.ps1 instead.',
    '# Machine-specific additions go in ~/.dotfiles-local.ps1',
    '. (Join-Path $HOME ''dotfiles\powershell\profile.ps1'')'
) -join "`r`n"
$docs = [Environment]::GetFolderPath('MyDocuments')
foreach ($prof in @((Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
                    (Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1'))) {
    if ((Test-Path $prof) -and ((Get-Content $prof -Raw) -eq $stub)) { Ok $prof; continue }
    if (Test-Path $prof) { Backup $prof }
    New-Item -ItemType Directory -Force -Path (Split-Path $prof) | Out-Null
    [IO.File]::WriteAllText($prof, $stub, $Utf8NoBom)
    Did $prof
}
$localProfile = Join-Path $HOME '.dotfiles-local.ps1'
if (-not (Test-Path $localProfile)) {
    [IO.File]::WriteAllText($localProfile, "# Machine-specific PowerShell setup (not in git).`r`n# e.g. function jobs { Set-Location '\\server\share' }`r`n", $Utf8NoBom)
    Did "created $localProfile"
} else { Ok $localProfile }

Step 'Neovim plugins'
if (Has nvim) {
    Native { nvim --headless '+Lazy! restore' +qa 2>&1 | Out-Null }
    Did 'plugins installed at locked versions (language servers install on first launch)'
} else { Warn 'nvim not found - skipped' }

Write-Host "`nAll set. Close this window and open a new one (cmd, powershell or pwsh)" -ForegroundColor Green
Write-Host "so the new PATH and profile load. Then try: herdr, pi, nvim, y, z <folder>" -ForegroundColor Green
if (-not (Test-Path (Join-Path $HOME '.pi\agent\auth.json'))) {
    Write-Host "Next: run 'pi' and use /login to sign in." -ForegroundColor Yellow
}
}
