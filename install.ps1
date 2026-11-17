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
#  Every run writes a log to %LOCALAPPDATA%\dotfiles\logs\.
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
$LogDir     = Join-Path $env:LOCALAPPDATA 'dotfiles\logs'
$LogFile    = Join-Path $LogDir "install-$Stamp.log"

$ScoopBuckets = @('extras', 'nerd-fonts')
$ScoopApps = @(
    '7zip', 'git',                       # needed first by scoop itself
    'neovim', 'ripgrep', 'fd', 'mingw', 'tree-sitter',   # editor + its tools
    'starship', 'zoxide', 'yazi',        # shell
    'windows-terminal', 'JetBrainsMono-NF'
)

# Rough time per item in seconds on a decent connection - used for the
# "usually ~Xs" hints and the time-left estimate. Mostly download + unzip.
$Est = @{
    'scoop' = 45; 'bucket' = 20
    '7zip' = 15; 'git' = 60; 'neovim' = 30; 'ripgrep' = 10; 'fd' = 10; 'mingw' = 150
    'tree-sitter' = 10; 'starship' = 10; 'zoxide' = 10; 'yazi' = 30
    'windows-terminal' = 45; 'JetBrainsMono-NF' = 40
    'herdr' = 30; 'pi' = 120; 'pi-package' = 30; 'herdr-integration' = 5
    'clone' = 15; 'nvim-plugins' = 90; 'nvim-check' = 10; 'configs' = 10
}

# pi keys that pi writes itself - never stored in the repo
$PiIgnoredKeys = @('lastChangelogVersion', 'extensionChangelogVersions')

# ---------------------------------------------------------------------
# Output + progress helpers
# ---------------------------------------------------------------------
$Prog = @{                                   # progress state (hashtable so functions can update it)
    Step = 0; Total = 0; Name = $null
    Clock = [Diagnostics.Stopwatch]::StartNew(); StepWatch = $null
    TaskWatch = $null; TaskEst = 0; Remaining = 0
    Times = New-Object System.Collections.ArrayList
}

function Fmt([double]$s) {
    $s = [int][math]::Round($s)
    if ($s -lt 60) { "${s}s" } else { '{0}m{1:00}s' -f [int][math]::Floor($s / 60), ($s % 60) }
}
$OrigTitle = try { $Host.UI.RawUI.WindowTitle } catch { $null }
function Set-Title($t) { try { $Host.UI.RawUI.WindowTitle = "dotfiles: $t" } catch {} }

function Ok($msg)   { Write-Host "    ok    $msg" -ForegroundColor DarkGray }
function Did($msg)  { Write-Host "    done  $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    warn  $msg" -ForegroundColor Yellow }
function Info($msg) { Write-Host "          $msg" -ForegroundColor DarkGray }

function End-Step {
    if (-not $Prog.Name) { return }
    $t = $Prog.StepWatch.Elapsed.TotalSeconds
    [void]$Prog.Times.Add([pscustomobject]@{ Step = $Prog.Name; Seconds = $t })
    if ($t -ge 3) { Info "step took $(Fmt $t)" }
    $Prog.Name = $null
}

# Start a numbered step:  [3/13] Scoop apps   (elapsed 1m02s, ~9m left)
function Step($msg) {
    End-Step
    $Prog.Step++; $Prog.Name = $msg; $Prog.StepWatch = [Diagnostics.Stopwatch]::StartNew()
    $meta = "elapsed $(Fmt $Prog.Clock.Elapsed.TotalSeconds)"
    if ($Prog.Remaining -ge 30) { $meta += ", ~$(Fmt $Prog.Remaining) left" }
    Write-Host ("`n[{0}/{1}] {2}" -f $Prog.Step, $Prog.Total, $msg) -ForegroundColor Cyan -NoNewline
    Write-Host "   ($meta)" -ForegroundColor DarkGray
    Set-Title "[$($Prog.Step)/$($Prog.Total)] $msg"
}

# Announce something slow before it starts, then report how long it took
function Task($what, $key) {
    $Prog.TaskEst = if ($Est.ContainsKey($key)) { $Est[$key] } else { 30 }
    Write-Host ("    ...   {0}  (usually ~{1})" -f $what, (Fmt $Prog.TaskEst)) -ForegroundColor White
    $left = if ($Prog.Remaining -ge 30) { " - ~$(Fmt $Prog.Remaining) left" } else { '' }
    Set-Title "[$($Prog.Step)/$($Prog.Total)] $what$left"
    $Prog.TaskWatch = [Diagnostics.Stopwatch]::StartNew()
}
function Task-Done($msg, [switch]$Failed) {
    $t = Fmt $Prog.TaskWatch.Elapsed.TotalSeconds
    $Prog.Remaining = [math]::Max(0, $Prog.Remaining - $Prog.TaskEst)
    if ($Failed) { Warn "$msg  ($t)" } else { Did "$msg  ($t)" }
}

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

# Scoop writes scoop-install.json (older versions: install.json) as the last step,
# so an install interrupted part-way counts as "not installed" and is retried -
# scoop itself purges/repairs the half-finished copy.
function App-Installed($app) {
    $cur = Join-Path $ScoopRoot "apps\$app\current"
    (Test-Path (Join-Path $cur 'scoop-install.json')) -or (Test-Path (Join-Path $cur 'install.json'))
}

# A repo counts as present only if the clone actually finished (has a commit checked out)
function Repo-Ok {
    if (-not (Test-Path (Join-Path $Dotfiles '.git'))) { return $false }
    Native { git -C $Dotfiles rev-parse --verify --quiet HEAD 2>&1 | Out-Null }
    ($LASTEXITCODE -eq 0) -and (Test-Path (Join-Path $Dotfiles 'install.ps1'))
}

# scoop installed but its shims folder not on PATH yet (e.g. a run was cancelled)
$scoopShims = Join-Path $ScoopRoot 'shims'
if ((Test-Path (Join-Path $scoopShims 'scoop.ps1')) -and ($env:Path -notlike "*$scoopShims*")) {
    $env:Path = "$scoopShims;$env:Path"
}
function Pi-Package-Name($pkg) { $pkg -replace '^npm:', '' -replace '(?<=.)@[^/]*$', '' }
function Pi-Package-Installed($pkg) { Test-Path (Join-Path $HOME ".pi\agent\npm\node_modules\$(Pi-Package-Name $pkg)") }

# Paths of app-owned config files
$HerdrConfig = Join-Path $env:APPDATA 'herdr\config.toml'
$WTSettings  = Join-Path $ScoopRoot 'persist\windows-terminal\settings\settings.json'
$PiSettings  = Join-Path $HOME '.pi\agent\settings.json'
$LazyDir     = Join-Path $env:LOCALAPPDATA 'nvim-data\lazy\lazy.nvim'

# ---------------------------------------------------------------------
# -Collect: copy live configs back into the repo (quick, no progress UI)
# ---------------------------------------------------------------------
if ($Collect) {
    Write-Host "`n==> Collecting app configs into the repo" -ForegroundColor Cyan
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
# Plan: work out what's missing so we can show an honest time estimate
# ---------------------------------------------------------------------
$todo = New-Object System.Collections.ArrayList
if (-not $ConfigOnly) {
    if (-not (Has scoop)) { [void]$todo.Add('scoop') }
    foreach ($b in $ScoopBuckets) { if (-not (Test-Path (Join-Path $ScoopRoot "buckets\$b"))) { [void]$todo.Add("bucket:$b") } }
    foreach ($app in $ScoopApps) { if (-not (App-Installed $app)) { [void]$todo.Add($app) } }
    if (-not (Has herdr)) { [void]$todo.Add('herdr') }
    if (-not (Has pi))    { [void]$todo.Add('pi') }
}
if (-not (Has git) -or -not (Repo-Ok)) { [void]$todo.Add('clone') }
$piRepoSettings = Join-Path $Dotfiles 'pi\settings.json'
if (Test-Path $piRepoSettings) {
    foreach ($pkg in @((Get-Content $piRepoSettings -Raw | ConvertFrom-Json).packages)) {
        if ($pkg -and -not (Pi-Package-Installed $pkg)) { [void]$todo.Add('pi-package') }
    }
} elseif ('clone' -in $todo) { [void]$todo.Add('pi-package') }
$nvimKey = if (Test-Path $LazyDir) { 'nvim-check' } else { 'nvim-plugins' }

$Prog.Remaining = $Est['configs'] + $Est[$nvimKey]
foreach ($t in $todo) { $k = ($t -split ':')[0]; $Prog.Remaining += $(if ($Est.ContainsKey($k)) { $Est[$k] } else { 30 }) }
$Prog.Total = if ($ConfigOnly) { 8 } else { 13 }

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
try { Start-Transcript -Path $LogFile -ErrorAction Stop | Out-Null; $transcript = $true } catch { $transcript = $false }

Write-Host ''
Write-Host '  Dotfiles installer' -ForegroundColor Cyan
Write-Host "  Mode:        $(if ($ConfigOnly) { 'apply configs only' } else { 'install apps + apply configs' })"
$installList = @($todo | Where-Object { $_ -notin @('clone', 'pi-package') } | ForEach-Object { $_ -replace '^bucket:', 'bucket ' })
if ($installList.Count) {
    Write-Host "  To install:  $($installList -join ', ')"
} elseif (-not $ConfigOnly) {
    Write-Host '  To install:  nothing - all apps already present'
}
Write-Host "  Estimated:   ~$(Fmt $Prog.Remaining)" -NoNewline
Write-Host '  (mostly downloads - depends on connection speed)' -ForegroundColor DarkGray
if ($transcript) { Write-Host "  Log file:    $LogFile" -ForegroundColor DarkGray }
Write-Host '  Progress is also shown in the window title. Safe to re-run if interrupted.' -ForegroundColor DarkGray

try {
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

    Step 'Scoop (per-user package manager)'
    if (-not (Has scoop)) {
        Task 'installing scoop' 'scoop'
        $scoopUrl = 'https://raw.githubusercontent.com/ScoopInstaller/Install/master/install.ps1'
        if (Is-Admin) {
            Warn 'running as administrator - installing scoop with -RunAsAdmin (still per-user)'
            Run-Installer $scoopUrl @('-RunAsAdmin')
        } else { Run-Installer $scoopUrl }
        Refresh-Path
        Task-Done 'installed scoop'
    } else { Ok 'scoop already installed' }

    $missingApps = @($ScoopApps | Where-Object { -not (App-Installed $_) })
    Step "Scoop apps ($($missingApps.Count) of $($ScoopApps.Count) to install)"
    $n = 0
    foreach ($app in $ScoopApps) {
        if ($app -eq 'neovim') {   # buckets need git, so add them once git is in
            foreach ($b in $ScoopBuckets) {
                if (-not (Test-Path (Join-Path $ScoopRoot "buckets\$b"))) {
                    Task "adding scoop bucket '$b'" 'bucket'
                    Native { scoop bucket add $b }
                    Task-Done "bucket $b"
                }
            }
        }
        if (App-Installed $app) { Ok $app; continue }
        $n++
        Task "installing $app ($n of $($missingApps.Count))" $app
        Native { scoop install $app }
        if (App-Installed $app) { Task-Done $app } else { Task-Done "$app failed to install - re-run later" -Failed }
    }
    Refresh-Path

    Step 'herdr (terminal workspace manager)'
    if (-not (Has herdr)) {
        Task 'installing herdr' 'herdr'
        Run-Installer 'https://herdr.dev/install.ps1'
        Refresh-Path
        Task-Done 'installed herdr'
    } else { Ok 'herdr already installed' }

    Step 'pi (coding agent)'
    if (-not (Has pi)) {
        Task 'installing pi (may also install Node.js)' 'pi'
        Run-Installer 'https://pi.dev/install.ps1'
        Refresh-Path
        Task-Done 'installed pi'
    } else { Ok 'pi already installed' }
}

# ---------------------------------------------------------------------
# Repo
# ---------------------------------------------------------------------
Step 'Dotfiles repo'
if (-not (Repo-Ok)) {
    if (Test-Path $Dotfiles) { Warn 'existing dotfiles folder is incomplete (interrupted clone?)'; Backup $Dotfiles }
    Task "cloning $RepoUrl" 'clone'
    Native { git clone $RepoUrl $Dotfiles }
    if (-not (Test-Path (Join-Path $Dotfiles '.git'))) { throw "git clone of $RepoUrl failed" }
    Task-Done "cloned to $Dotfiles"
} else { Ok $Dotfiles }

# ---------------------------------------------------------------------
# Configs
# ---------------------------------------------------------------------
Step 'Linking configs (nvim, pi skills)'
Link-Dir (Join-Path $env:LOCALAPPDATA 'nvim') (Join-Path $Dotfiles 'nvim')
Link-Dir (Join-Path $HOME '.agents')          (Join-Path $Dotfiles 'agents')

Step 'Copying app configs (herdr, Windows Terminal)'
Copy-Config (Join-Path $Dotfiles 'herdr\config.toml') $HerdrConfig
if (Test-Path (Join-Path $ScoopRoot 'apps\windows-terminal')) {
    Copy-Config (Join-Path $Dotfiles 'windows-terminal\settings.json') $WTSettings
}

Step 'pi settings + packages (your login is untouched)'
$repoPi = Get-Content (Join-Path $Dotfiles 'pi\settings.json') -Raw | ConvertFrom-Json
if (Test-Path $PiSettings) { $livePi = Get-Content $PiSettings -Raw | ConvertFrom-Json }
else { New-Item -ItemType Directory -Force -Path (Split-Path $PiSettings) | Out-Null; $livePi = New-Object PSObject }
foreach ($p in $repoPi.PSObject.Properties) { $livePi | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
if (Write-Json $PiSettings $livePi) { Did $PiSettings } else { Ok $PiSettings }

if (Has pi) {
    foreach ($pkg in @($repoPi.packages)) {
        if (Pi-Package-Installed $pkg) { Ok "pi package $pkg" }
        else {
            Task "installing pi package $pkg" 'pi-package'
            Native { pi install $pkg }
            if (Pi-Package-Installed $pkg) { Task-Done "pi package $pkg" } else { Task-Done "pi package $pkg may have failed - check 'pi list'" -Failed }
        }
    }
} else { Warn 'pi not found - skipped packages' }
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
    if ($nvimKey -eq 'nvim-plugins') {
        Task 'downloading Neovim plugins - no output until finished' 'nvim-plugins'
    } else {
        Task 'checking Neovim plugins match lazy-lock.json' 'nvim-check'
    }
    Native { nvim --headless '+Lazy! restore' +qa 2>&1 | Out-Null }
    Task-Done 'plugins at locked versions (language servers install on first launch)'
} else { Warn 'nvim not found - skipped' }

End-Step

# ---------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------
$total = $Prog.Clock.Elapsed.TotalSeconds
Write-Host ''
Write-Host "  Finished in $(Fmt $total)." -ForegroundColor Green
$slow = @($Prog.Times | Where-Object { $_.Seconds -ge 3 } | Sort-Object Seconds -Descending | Select-Object -First 4)
if ($slow.Count) {
    Write-Host ("  Slowest: " + (($slow | ForEach-Object { "$($_.Step) $(Fmt $_.Seconds)" }) -join ' | ')) -ForegroundColor DarkGray
}
if ($transcript) { Write-Host "  Log: $LogFile" -ForegroundColor DarkGray }
Write-Host ''
Write-Host '  Close this window and open a new one (cmd, powershell or pwsh) so the' -ForegroundColor Green
Write-Host '  new PATH and profile load. Then try: herdr, pi, nvim, y, z <folder>' -ForegroundColor Green
if (-not (Test-Path (Join-Path $HOME '.pi\agent\auth.json'))) {
    Write-Host "  Next: run 'pi' and use /login to sign in." -ForegroundColor Yellow
}
}
catch {
    Write-Host ''
    Write-Host "  FAILED during step [$($Prog.Step)/$($Prog.Total)] $($Prog.Name) after $(Fmt $Prog.Clock.Elapsed.TotalSeconds)" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    if ($transcript) { Write-Host "  Full log: $LogFile" -ForegroundColor Yellow }
    Write-Host '  Fix the issue (or just retry) and run the same command again -' -ForegroundColor Yellow
    Write-Host '  finished steps are skipped, so it picks up where it left off.' -ForegroundColor Yellow
    throw
}
finally {
    if ($transcript) { try { Stop-Transcript | Out-Null } catch {} }
    if ($OrigTitle) { try { $Host.UI.RawUI.WindowTitle = $OrigTitle } catch {} }
}
}
