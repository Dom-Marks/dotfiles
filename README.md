# dotfiles

My Windows dev setup: **Neovim**, **herdr**, **pi** (+ web search and skills), **starship**, **zoxide**, **yazi**, **Windows Terminal**.
Everything installs per-user via [scoop](https://scoop.sh) and official installers. **No admin needed.**

## Install on a fresh machine

From **cmd** (`Win+R`, then `cmd`):

```
curl.exe -fsSLo %TEMP%\dotfiles.cmd https://raw.githubusercontent.com/Dom-Marks/dotfiles/main/install.cmd && %TEMP%\dotfiles.cmd
```

From **Windows PowerShell** or **pwsh**:

```
cmd /c "curl.exe -fsSLo %TEMP%\dotfiles.cmd https://raw.githubusercontent.com/Dom-Marks/dotfiles/main/install.cmd && %TEMP%\dotfiles.cmd"
```

These commands download the files first and then run them. They avoid `irm ... | iex`, which security software often blocks ("Access is denied").

Then close the window, open a new one, and:

1. Run `pi`, then `/login`. Your login is never stored in this repo.
2. Open `nvim` once. Language servers and syntax parsers install on first launch.
3. Optional: put machine-specific bits in `~/.dotfiles-local.ps1`, such as network share shortcuts. That file is not in git.

### How long does it take?

| Situation | Typical time |
|---|---|
| Fresh machine (everything to install) | **About 10 to 15 minutes**, mostly downloads. The largest items are mingw (about 2.5 min), pi with Node.js (about 2 min), and Neovim plugins (about 1.5 min). |
| Re-run when everything is already installed | **Under 30 seconds** |
| `dots-pull` (configs only) | **A few seconds** |

The installer shows what's happening as it runs:
- Before starting, it lists what will be installed and an estimated total time.
- Each step is numbered (`[3/13]`) and shows the time elapsed and roughly how much is left. The window title shows the same.
- Slow items say how long they usually take before they start, then how long they actually took.
- At the end you get the total time and the slowest steps.
- Every run is logged to `%LOCALAPPDATA%\dotfiles\logs\`. If something fails, it says which step failed and where the log is. Run the same command again: finished steps are skipped.

You can re-run the installer at any time. It skips anything already in place. Anything it replaces is backed up as `<name>.bak-<timestamp>`.

## Day-to-day commands (PowerShell / pwsh)

| Command | What it does |
|---|---|
| `dots` | Go to `~/dotfiles` |
| `dots-edit` | Open the dotfiles in nvim |
| `dots-save ["message"]` | Copy app-owned configs back into the repo, then commit and push |
| `dots-pull` | Pull the latest and re-apply configs |
| `dots-install` | Pull the latest and run the full installer (picks up newly added apps) |

## What lives where

| Repo | On the machine | How |
|---|---|---|
| `nvim/` | `%LOCALAPPDATA%\nvim` | Folder link (junction). Edits are live in the repo. |
| `agents/` (pi skills) | `~/.agents` | Folder link (junction) |
| `powershell/profile.ps1` | `$PROFILE` (5.1 and 7) | The profile is a one-line stub that loads this file |
| `starship/starship.toml` | n/a | `STARSHIP_CONFIG` env var points here |
| `herdr/config.toml` | `%APPDATA%\herdr\config.toml` | Copied in. `dots-save` copies it back. |
| `windows-terminal/settings.json` | `~/scoop/persist/windows-terminal/settings/` | Copied in. `dots-save` copies it back. |
| `pi/settings.json` | `~/.pi/agent/settings.json` | Merged in, so pi's own state and login stay local |

Apps installed by scoop: 7zip, git, neovim, ripgrep, fd, mingw, tree-sitter, starship, zoxide, yazi, windows-terminal, JetBrainsMono Nerd Font.
Plus [herdr](https://herdr.dev) and [pi](https://pi.dev) with their own installers, then the `pi-web-access` and [`ponytail`](https://github.com/DietrichGebert/ponytail) packages and the herdr-to-pi integration.

## Neovim cheat sheet

Press `Space` and wait. A popup lists all shortcuts.

| Keys | Action |
|---|---|
| `Space f f` / `Space f g` | Find file / search text |
| `Space f b` | List open files |
| `Shift+h` / `Shift+l` | Previous / next tab |
| `Space 1..9` | Jump to tab N |
| `Space b d` | Close tab |
| `Space t` | File tree |
| `g d` / `Ctrl+o` | Go to definition / jump back |
