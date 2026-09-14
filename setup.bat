@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem Download the latest Codex CLI + code-mode-host archives for every supported
rem platform into bin\<platform>\. Requires curl.exe (Windows 10+) or PowerShell.
rem No jq needed.

set "SCRIPT_DIR=%~dp0"
set "BIN_ROOT=%SCRIPT_DIR%bin"
set "RELEASE_BASE=https://github.com/openai/codex/releases/latest/download"

echo Host: Windows %PROCESSOR_ARCHITECTURE%
echo Downloading latest Codex release assets for all platforms into:
echo   %BIN_ROOT%
echo.

where curl.exe >nul 2>&1
if errorlevel 1 (
  where powershell.exe >nul 2>&1
  if errorlevel 1 (
    echo Error: need curl.exe or PowerShell to download release assets.
    exit /b 1
  )
  set "FETCH=ps"
) else (
  set "FETCH=curl"
)

call :fetch_platform linux-x64 codex-x86_64-unknown-linux-musl.tar.gz codex-linux-x64.tar.gz codex-code-mode-host-x86_64-unknown-linux-musl.tar.gz codex-code-mode-host-linux-x64.tar.gz
if errorlevel 1 exit /b 1
call :fetch_platform macos-x64 codex-x86_64-apple-darwin.tar.gz codex-macos-x64.tar.gz codex-code-mode-host-x86_64-apple-darwin.tar.gz codex-code-mode-host-macos-x64.tar.gz
if errorlevel 1 exit /b 1
call :fetch_platform macos-arm64 codex-aarch64-apple-darwin.tar.gz codex-macos-arm64.tar.gz codex-code-mode-host-aarch64-apple-darwin.tar.gz codex-code-mode-host-macos-arm64.tar.gz
if errorlevel 1 exit /b 1
call :fetch_platform windows-x64 codex-x86_64-pc-windows-msvc.exe.tar.gz codex-windows-x64.tar.gz codex-code-mode-host-x86_64-pc-windows-msvc.exe.tar.gz codex-code-mode-host-windows-x64.tar.gz
if errorlevel 1 exit /b 1

echo ========================================
echo Setup complete. Downloaded into:
echo   linux-x64\codex-linux-x64.tar.gz
echo   linux-x64\codex-code-mode-host-linux-x64.tar.gz
echo   macos-x64\codex-macos-x64.tar.gz
echo   macos-x64\codex-code-mode-host-macos-x64.tar.gz
echo   macos-arm64\codex-macos-arm64.tar.gz
echo   macos-arm64\codex-code-mode-host-macos-arm64.tar.gz
echo   windows-x64\codex-windows-x64.tar.gz
echo   windows-x64\codex-code-mode-host-windows-x64.tar.gz
echo.
echo You can now launch with:
echo   sh launch.sh          ^(Linux / macOS^)
echo   launch.bat            ^(Windows^)
echo Archives stay on the USB; the launcher extracts them to host temp on first run.
exit /b 0

:fetch_platform
set "PLATFORM=%~1"
set "REMOTE_CODEX=%~2"
set "LOCAL_CODEX=%~3"
set "REMOTE_HOST=%~4"
set "LOCAL_HOST=%~5"
set "DEST_DIR=%BIN_ROOT%\%PLATFORM%"

echo === %PLATFORM% ===
if not exist "%DEST_DIR%" mkdir "%DEST_DIR%"

call :download "%RELEASE_BASE%/%REMOTE_CODEX%" "%DEST_DIR%\%LOCAL_CODEX%"
if errorlevel 1 exit /b 1

call :download "%RELEASE_BASE%/%REMOTE_HOST%" "%DEST_DIR%\%LOCAL_HOST%"
if errorlevel 1 exit /b 1
echo.
exit /b 0

:download
set "URL=%~1"
set "DEST=%~2"
echo -^> %~nx2
echo   from %URL%
if /I "%FETCH%"=="curl" (
  curl.exe -fL --progress-bar -o "%DEST%" "%URL%"
  if errorlevel 1 (
    echo Failed to download: %~nx2
    exit /b 1
  )
) else (
  powershell.exe -NoProfile -Command "try { Invoke-WebRequest -Uri '%URL%' -OutFile '%DEST%' -UseBasicParsing } catch { exit 1 }"
  if errorlevel 1 (
    echo Failed to download: %~nx2
    exit /b 1
  )
)
exit /b 0
