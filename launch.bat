@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "SCRIPT_DIR=%~dp0"
set "ACCOUNTS_DIR=%SCRIPT_DIR%accounts"
set "LAST_ACCOUNT_FILE=%ACCOUNTS_DIR%\.last-account"
set "BIN_DIR=%SCRIPT_DIR%bin\windows-x64"
set "EXTRACT_DIR=%TEMP%\codexportable-windows-x64"
set "CODEX=%EXTRACT_DIR%\codex.exe"
set "HOST=%EXTRACT_DIR%\codex-code-mode-host.exe"
set "CODEX_ARCHIVE=%BIN_DIR%\codex-windows-x64.tar.gz"
set "HOST_ARCHIVE=%BIN_DIR%\codex-code-mode-host-windows-x64.tar.gz"
set "ARGS="
set "NEW_LOGIN="
set "FRESH="
set "RESUME_LAST="
set "FORCE_MENU="

if not exist "%ACCOUNTS_DIR%" mkdir "%ACCOUNTS_DIR%"

rem --delete / --remove is a standalone action; never combined with launch.
if /I "%~1"=="--delete" goto delete_account
if /I "%~1"=="--remove" goto delete_account

:parse_flags
if "%~1"=="" goto flags_done
if /I "%~1"=="--fresh" (
  set "FRESH=1"
  shift
  goto parse_flags
)
if /I "%~1"=="--resume-last" (
  set "RESUME_LAST=1"
  shift
  goto parse_flags
)
if /I "%~1"=="--switch" (
  set "FORCE_MENU=1"
  shift
  goto parse_flags
)
goto flags_done

:flags_done
set "ACCOUNT=%~1"
if defined FORCE_MENU set "ACCOUNT="
if not "%ACCOUNT%"=="" goto have_account

:account_menu
set "LAST_HINT="
if exist "%LAST_ACCOUNT_FILE%" (
  set /p "LAST_HINT=" < "%LAST_ACCOUNT_FILE%"
)
echo Saved accounts (each keeps its own Codex sessions on this USB):
if defined LAST_HINT echo   Last used profile: !LAST_HINT!
set /a ACCOUNT_COUNT=0
for /f "delims=" %%D in ('dir /b /ad "%ACCOUNTS_DIR%" 2^>nul') do (
  set "ACCNAME=%%D"
  if not "!ACCNAME:~0,1!"=="." (
    set /a ACCOUNT_COUNT+=1
    set "ACCOUNT_!ACCOUNT_COUNT!=%%D"
    set "MARKER="
    if defined LAST_HINT if /I "%%D"=="!LAST_HINT!" set "MARKER= *"
    echo   !ACCOUNT_COUNT!^) %%D!MARKER!
  )
)
if !ACCOUNT_COUNT! EQU 0 echo   ^(none^)
echo   n^) Sign in with a new account
echo   d^) Delete a saved account
set /p "CHOICE=Choose a saved account, n, or d: "
if /I "%CHOICE%"=="d" goto interactive_delete
if /I "%CHOICE%"=="n" goto new_account
if /I "%CHOICE%"=="new" goto new_account
if "%CHOICE%"=="" goto no_account_selected
set /a CHOICE_NUM=%CHOICE% 2>nul
if %CHOICE_NUM% LSS 1 goto no_account_selected
if %CHOICE_NUM% GTR !ACCOUNT_COUNT! goto no_account_selected
for %%N in (%CHOICE_NUM%) do set "ACCOUNT=!ACCOUNT_%%N!"
goto validate_account

:interactive_delete
echo Choose an account to delete:
set /a DEL_COUNT=0
for /f "delims=" %%D in ('dir /b /ad "%ACCOUNTS_DIR%" 2^>nul') do (
  set "ACCNAME=%%D"
  if not "!ACCNAME:~0,1!"=="." (
    set /a DEL_COUNT+=1
    set "DEL_ACCOUNT_!DEL_COUNT!=%%D"
    echo   !DEL_COUNT!^) %%D
  )
)
if !DEL_COUNT! EQU 0 (
  echo   ^(none^)
  goto account_menu
)
set /p "DEL_PICK=Account number to delete (or Enter to cancel): "
if "%DEL_PICK%"=="" goto account_menu
set /a DEL_PICK_NUM=%DEL_PICK% 2>nul
if %DEL_PICK_NUM% LSS 1 goto account_menu
if %DEL_PICK_NUM% GTR !DEL_COUNT! goto account_menu
for %%N in (%DEL_PICK_NUM%) do set "DEL_NAME=!DEL_ACCOUNT_%%N!"
call :confirm_delete "!DEL_NAME!"
goto account_menu

:confirm_delete
set "DEL_NAME=%~1"
set "DEL_DIR=%ACCOUNTS_DIR%\%DEL_NAME%"
if not exist "%DEL_DIR%\" (
  echo Account not found: %DEL_NAME%
  exit /b 1
)
echo WARNING: This permanently deletes the local login/session for
echo account "%DEL_NAME%" on this USB.
echo The account on OpenAI's side is NOT affected — only this USB's
echo saved credentials and Codex session history for this profile.
echo Folder to delete: %DEL_DIR%
set /p "CONFIRM=Type the account name again to confirm deletion: "
if not "%CONFIRM%"=="%DEL_NAME%" (
  echo Confirmation did not match. Deletion cancelled; no changes made.
  exit /b 1
)
rmdir /s /q "%DEL_DIR%"
if exist "%LAST_ACCOUNT_FILE%" (
  set /p "LAST_CHECK=" < "%LAST_ACCOUNT_FILE%"
  if /I "!LAST_CHECK!"=="%DEL_NAME%" del "%LAST_ACCOUNT_FILE%"
)
echo Deleted account "%DEL_NAME%" (%DEL_DIR%).
exit /b 0

:new_account
set "NEW_LOGIN=1"
set /p "ACCOUNT=Name for this saved account: "
if "%ACCOUNT%"=="" goto bad_account
if exist "%ACCOUNTS_DIR%\%ACCOUNT%\" (
  echo An account named "%ACCOUNT%" already exists. Choose it from the saved accounts list.
  exit /b 1
)
goto validate_account

:no_account_selected
echo No valid account selected.
exit /b 1

:delete_account
set "DEL_NAME=%~2"
if "%DEL_NAME%"=="" (
  echo Usage: launch.bat --delete ^<account-name^>
  exit /b 1
)
if "%DEL_NAME%"=="." goto bad_delete_name
if "%DEL_NAME%"==".." goto bad_delete_name
echo %DEL_NAME%| findstr /R "\\/" >nul && goto bad_delete_name
call :confirm_delete "%DEL_NAME%"
exit /b %ERRORLEVEL%

:bad_delete_name
echo Invalid account name: %DEL_NAME%
exit /b 1

:have_account
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
if not defined NEW_LOGIN if not exist "%ACCOUNTS_DIR%\%ACCOUNT%\" (
  echo Stored account not found: %ACCOUNT%
  echo Run launch.bat or launch.bat --switch to sign in, select, or delete an account.
  exit /b 1
)

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
if defined NEW_LOGIN goto login_new_account
if not exist "%CODEX_HOME%\" goto missing_account
echo Using account: %ACCOUNT% (%CODEX_HOME%)
echo Tip: exit Codex anytime and run launch.bat --switch to change profile; sessions stay in that profile folder.
> "%LAST_ACCOUNT_FILE%" echo %ACCOUNT%
if exist "%CODEX_HOME%\.portable-last-cwd" (
  set /p "LAST_CWD=" < "%CODEX_HOME%\.portable-last-cwd"
  if exist "!LAST_CWD!" echo Last workspace for %ACCOUNT%: !LAST_CWD!
)
cd > "%CODEX_HOME%\.portable-last-cwd" 2>nul

if defined RESUME_LAST if not defined ARGS (
  "%CODEX%" resume --last
  exit /b %ERRORLEVEL%
)
if defined FRESH goto run_codex_plain
if defined ARGS goto run_codex_plain
set /p "RESUME_CHOICE=Continue where you left off on %ACCOUNT%? [Y=resume last / n=new / p=pick]: "
if /I "%RESUME_CHOICE%"=="n" goto run_codex_plain
if /I "%RESUME_CHOICE%"=="p" (
  "%CODEX%" resume
  exit /b %ERRORLEVEL%
)
if /I "%RESUME_CHOICE%"=="no" goto run_codex_plain
"%CODEX%" resume --last
exit /b %ERRORLEVEL%

:run_codex_plain
"%CODEX%"%ARGS%
exit /b %ERRORLEVEL%

:login_new_account
set "LOGIN_HOME=%ACCOUNTS_DIR%\.login-%RANDOM%%RANDOM%"
if exist "%LOGIN_HOME%\" goto login_new_account
mkdir "%LOGIN_HOME%"
> "%LOGIN_HOME%\config.toml" echo cli_auth_credentials_store = "file"
set "CODEX_HOME=%LOGIN_HOME%"
echo Starting Codex sign-in for profile: %ACCOUNT%
"%CODEX%" login
if errorlevel 1 goto login_failed
if not exist "%LOGIN_HOME%\auth.json" goto login_missing_auth
move "%LOGIN_HOME%" "%ACCOUNTS_DIR%\%ACCOUNT%" >nul
if errorlevel 1 goto login_move_failed
set "CODEX_HOME=%ACCOUNTS_DIR%\%ACCOUNT%"
echo Saved account: %ACCOUNT%
echo Using account: %ACCOUNT% (%CODEX_HOME%)
> "%LAST_ACCOUNT_FILE%" echo %ACCOUNT%
cd > "%CODEX_HOME%\.portable-last-cwd" 2>nul
"%CODEX%"%ARGS%
exit /b %ERRORLEVEL%

:login_failed
rmdir /s /q "%LOGIN_HOME%"
echo Login was not completed; no account was saved.
exit /b 1

:login_missing_auth
rmdir /s /q "%LOGIN_HOME%"
echo Login finished but no portable credential file was created; no account was saved.
exit /b 1

:login_move_failed
rmdir /s /q "%LOGIN_HOME%"
echo Could not save the new account profile.
exit /b 1

:bad_account
echo Invalid account name: %ACCOUNT%
exit /b 1

:missing_account
echo Stored account not found: %ACCOUNT%
exit /b 1

:missing_archives
echo Codex archives are incomplete in: %BIN_DIR%
exit /b 1

:extract_failed
echo Failed to prepare Codex binaries in: %EXTRACT_DIR%
exit /b 1
