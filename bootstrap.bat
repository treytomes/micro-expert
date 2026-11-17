@echo off
setlocal

rem One-time setup for a fresh clone: the submodules listed below, the MiniScript 2
rem interpreter in 3rd-party\ (a gitignored folder, so a clone carries no binary), and a
rem .env beside the runner.
rem Safe to re-run; run it from anywhere.

set "ROOT=%~dp0"
set "THIRD_DIR=%ROOT%3rd-party"
set "ZIP_PATH=%THIRD_DIR%\miniscript-win.zip"
set "EXE_PATH=%THIRD_DIR%\miniscript-win\miniscript.exe"
set "ENV_FILE=%ROOT%.env"
rem Tracks the latest release; pin a tag in this URL for a reproducible setup.
set "ZIP_URL=https://github.com/JoeStrout/miniscript2/releases/latest/download/miniscript-win.zip"

where git >nul 2>nul
if errorlevel 1 (
    echo [bootstrap] git was not found on PATH - install Git, then run this again.
    exit /b 1
)

if not exist "%ROOT%.gitmodules" (
    echo [bootstrap] No .gitmodules next to this script; that is not the project root.
    exit /b 1
)

pushd "%ROOT%"

rem --- the submodules ---------------------------------------------------------
rem One line per submodule: its path as .gitmodules spells it, a file that proves it
rem checked out, and a name for the log. Extracting another one is a single line here.
rem No goto, no call to a label, and no exit /b inside the loop: cmd.exe cannot find a
rem label in a batch file with Unix line endings, and an exit inside these nested blocks
rem loses its code, so failures are collected and the exit happens after the loop.
set "MISSING="
for %%M in (
    ".agents/skills/miniscript-2|SKILL.md|Agent skill"
    "vscode-miniscript|package.json|VS Code extension"
    "src/cli|cli.ms|Command-line library"
    "src/logging|logging.ms|Logger"
) do for /f "tokens=1-3 delims=|" %%P in ("%%~M") do (
    if not exist "%%~P/%%Q" (
        echo [bootstrap] Cloning %%~P ...
        rem sync re-reads the URLs from .gitmodules, so a renamed or moved remote is
        rem picked up instead of the value cached in .git\config.
        git submodule sync --quiet --recursive
        git submodule update --init --recursive -- %%~P
    )
    rem Trust the file, not the exit code: an unregistered submodule makes update a
    rem no-op that still reports success.
    if not exist "%%~P/%%Q" (
        echo [bootstrap] %%~Q is missing at "%%~P/%%Q".
        echo [bootstrap] Check that .gitmodules lists %%~P.
        set "MISSING=%%~P"
    ) else (
        echo [bootstrap] %%~R in place: %%~P
    )
)
if defined MISSING (
    echo [bootstrap] Giving up on "%MISSING%" - fix .gitmodules and run this again.
    popd
    exit /b 1
)

rem --- the interpreter in 3rd-party\ -----------------------------------------
if not exist "%EXE_PATH%" (
    if not exist "%THIRD_DIR%" mkdir "%THIRD_DIR%"

    echo [bootstrap] Downloading miniscript-win.zip ...
    where curl >nul 2>nul
    if errorlevel 1 (
        powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%ZIP_URL%' -OutFile '%ZIP_PATH%' -UseBasicParsing"
    ) else (
        curl -L --fail --silent --show-error --output "%ZIP_PATH%" "%ZIP_URL%"
    )
    if errorlevel 1 (
        echo [bootstrap] Download failed: %ZIP_URL%
        popd
        exit /b 1
    )
    if not exist "%ZIP_PATH%" (
        echo [bootstrap] Download reported success but "%ZIP_PATH%" is not there.
        popd
        exit /b 1
    )
    rem Only a file this run fetched gets cleaned up at the end.
    set "DOWNLOADED=1"

    rem Unpack into 3rd-party\, keeping the archive's own miniscript-win\ folder.
    rem Expand-Archive rather than tar: a Git-for-Windows tar on PATH reads "C:\..."
    rem as a remote host and fails with "Cannot connect to C".
    echo [bootstrap] Extracting into 3rd-party ...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%ZIP_PATH%' -DestinationPath '%THIRD_DIR%' -Force"
    if errorlevel 1 (
        echo [bootstrap] Extraction failed; "%ZIP_PATH%" was left in place for a retry.
        popd
        exit /b 1
    )
)

rem Check the executable before deleting its archive.
if not exist "%EXE_PATH%" (
    echo [bootstrap] No miniscript.exe at "%EXE_PATH%" after extracting.
    echo [bootstrap] Check the archive layout; "%ZIP_PATH%" was left in place.
    popd
    exit /b 1
)
echo [bootstrap] Interpreter in place: 3rd-party\miniscript-win\miniscript.exe

rem --- .env -------------------------------------------------------------------
rem An existing .env may point somewhere else on purpose, so it is never rewritten.
if exist "%ENV_FILE%" (
    echo [bootstrap] Keeping the existing .env.
) else (
    echo [bootstrap] Writing .env ...
    >"%ENV_FILE%" echo MINISCRIPT_EXE_PATH=%EXE_PATH%
    >>"%ENV_FILE%" echo ENTRY_POINT=./src/main.ms
    if not exist "%ENV_FILE%" (
        echo [bootstrap] Could not write "%ENV_FILE%".
        popd
        exit /b 1
    )
)

if defined DOWNLOADED (
    del "%ZIP_PATH%"
    echo [bootstrap] Removed the downloaded 3rd-party\miniscript-win.zip
)

echo [bootstrap] Ready.
git submodule status
popd

exit /b 0
