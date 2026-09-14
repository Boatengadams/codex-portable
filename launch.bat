@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
set "ACCOUNTS_DIR=%SCRIPT_DIR%accounts"
set "BIN_DIR=%SCRIPT_DIR%bin\windows-x64"
set "EXTRACT_DIR=%TEMP%\codexportable-windows-x64"
set "CODEX=%EXTRACT_DIR%\codex.exe"
set "HOST=%EXTRACT_DIR%\codex-code-mode-host.exe"
set "CODEX_ARCHIVE=%BIN_DIR%\codex-windows-x64.tar.gz"
set "HOST_ARCHIVE=%BIN_DIR%\codex-code-mode-host-windows-x64.tar.gz"
set "ARGS="

if not exist "%ACCOUNTS_DIR%" mkdir "%ACCOUNTS_DIR%"

rem --delete / --remove is a standalone action; never combined with launch.
if /I "%~1"=="--delete" goto delete_account
if /I "%~1"=="--remove" goto delete_account

set "ACCOUNT=%~1"
if not "%ACCOUNT%"=="" goto have_account

echo Available accounts:
dir /b /ad "%ACCOUNTS_DIR%" 2>nul
if errorlevel 1 echo   (none yet — type a name to create one)
set /p "ACCOUNT=Enter account name (existing or new): "
if "%ACCOUNT%"=="" (
  echo No account selected.
  exit /b 1
)
goto validate_account

:delete_account
set "DEL_NAME=%~2"
if "%DEL_NAME%"=="" (
  echo Usage: launch.bat --delete ^<account-name^>
  exit /b 1
)
if "%DEL_NAME%"=="." goto bad_delete_name
if "%DEL_NAME%"==".." goto bad_delete_name
echo %DEL_NAME%| findstr /R "\\/" >nul && goto bad_delete_name

set "DEL_DIR=%ACCOUNTS_DIR%\%DEL_NAME%"
if not exist "%DEL_DIR%\" (
  echo Account not found: %DEL_NAME%
  echo Available accounts:
  dir /b /ad "%ACCOUNTS_DIR%" 2>nul
  if errorlevel 1 echo   ^(none^)
  exit /b 1
)

echo WARNING: This permanently deletes the local login/session for
echo account "%DEL_NAME%" on this USB.
echo The account on OpenAI's side is NOT affected — only this USB's
echo saved credentials for it will be removed.
echo Folder to delete: %DEL_DIR%
set /p "CONFIRM=Type the account name again to confirm deletion: "
if not "%CONFIRM%"=="%DEL_NAME%" (
  echo Confirmation did not match. Deletion cancelled; no changes made.
  exit /b 1
)
rmdir /s /q "%DEL_DIR%"
echo Deleted account "%DEL_NAME%" (%DEL_DIR%).
exit /b 0

:bad_delete_name
echo Invalid account name: %DEL_NAME%
exit /b 1

:have_account
rem Rebuild remaining args after the account name so they are passed to Codex.
shift
:collect_args
if "%~1"=="" goto validate_account
set "ARGS=%ARGS% %1"
shift
goto collect_args

:validate_account
if "%ACCOUNT%"=="." goto bad_account
if "%ACCOUNT%"==".." goto bad_account
echo %ACCOUNT%| findstr /R "\\/" >nul && goto bad_account

set "CODEX_HOME=%ACCOUNTS_DIR%\%ACCOUNT%"

if not exist "%CODEX_ARCHIVE%" goto missing_archives
if not exist "%HOST_ARCHIVE%" goto missing_archives

if not exist "%CODEX%" goto extract
if not exist "%HOST%" goto extract
goto run

:extract
if not exist "%EXTRACT_DIR%" mkdir "%EXTRACT_DIR%"
tar -xzf "%CODEX_ARCHIVE%" -C "%EXTRACT_DIR%"
if errorlevel 1 goto extract_failed
tar -xzf "%HOST_ARCHIVE%" -C "%EXTRACT_DIR%"
if errorlevel 1 goto extract_failed

rem Archives unpack with platform-specific names; normalize for the host sibling check.
if exist "%EXTRACT_DIR%\codex-x86_64-pc-windows-msvc.exe" move /Y "%EXTRACT_DIR%\codex-x86_64-pc-windows-msvc.exe" "%CODEX%" >nul
if exist "%EXTRACT_DIR%\codex-code-mode-host-x86_64-pc-windows-msvc.exe" move /Y "%EXTRACT_DIR%\codex-code-mode-host-x86_64-pc-windows-msvc.exe" "%HOST%" >nul

if not exist "%CODEX%" goto extract_failed
if not exist "%HOST%" goto extract_failed

:run
if not exist "%CODEX_HOME%" mkdir "%CODEX_HOME%"
echo Using account: %ACCOUNT% (%CODEX_HOME%)
"%CODEX%"%ARGS%
exit /b %ERRORLEVEL%

:bad_account
echo Invalid account name: %ACCOUNT%
exit /b 1

:missing_archives
echo Codex archives are incomplete in: %BIN_DIR%
exit /b 1

:extract_failed
echo Failed to prepare Codex binaries in: %EXTRACT_DIR%
exit /b 1
