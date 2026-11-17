@echo off
rem Dotfiles installer launcher for cmd.exe (no admin needed).
rem Use this if security software blocks "irm ... | iex":
rem   curl.exe -fsSLo %TEMP%\dotfiles.cmd https://raw.githubusercontent.com/Dom-Marks/dotfiles/main/install.cmd && %TEMP%\dotfiles.cmd
setlocal
set "PS1=%~dp0install.ps1"
if not exist "%PS1%" (
  set "PS1=%TEMP%\dotfiles-install.ps1"
  curl.exe -fsSLo "%TEMP%\dotfiles-install.ps1" https://raw.githubusercontent.com/Dom-Marks/dotfiles/main/install.ps1 || (echo Download failed & exit /b 1)
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
