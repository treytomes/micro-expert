@echo off
setlocal

rem Builds the Micro-Expert Knowledge VS Code extension in vscode-knowledge\ into
rem vscode-knowledge\out\micro-expert-knowledge.vsix (git-ignored build output).
rem Run this from anywhere; it works out the repo root itself.

set "ROOT=%~dp0"
set "EXT_DIR=%ROOT%vscode-knowledge"
set "OUT_DIR=%EXT_DIR%\out"
set "VSIX=%OUT_DIR%\micro-expert-knowledge.vsix"

if not exist "%EXT_DIR%\package.json" (
    echo [build-kb-ext] Extension not found: "%EXT_DIR%\package.json"
    exit /b 1
)

rem Prefer a globally installed vsce; fall back to npx, which fetches it on demand.
where vsce >nul 2>nul
if errorlevel 1 (
    where npx >nul 2>nul
    if errorlevel 1 (
        echo [build-kb-ext] Neither vsce nor npx was found.
        echo [build-kb-ext] Install Node.js, then run: npm install -g @vscode/vsce
        exit /b 1
    )
    set "VSCE_CMD=npx --yes @vscode/vsce"
) else (
    set "VSCE_CMD=vsce"
)

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

rem Drop a stale package so a failed build can't be mistaken for a fresh one.
if exist "%VSIX%" del "%VSIX%"

pushd "%EXT_DIR%"
rem The version VS Code compares when installing: bump it in package.json for
rem each change you want VS Code to take as an update.
for /f "delims=" %%V in ('node -p "require('./package.json').version"') do set "VERSION=%%V"
if not defined VERSION set "VERSION=unknown"
call %VSCE_CMD% package --out "%VSIX%"
set "EXIT_CODE=%ERRORLEVEL%"
popd

if not "%EXIT_CODE%"=="0" (
    echo [build-kb-ext] vsce failed with exit code %EXIT_CODE%.
    exit /b %EXIT_CODE%
)

if not exist "%VSIX%" (
    echo [build-kb-ext] vsce reported success but "%VSIX%" was not created.
    exit /b 1
)

for %%F in ("%VSIX%") do echo [build-kb-ext] Built Micro-Expert Knowledge %VERSION% - %%~nxF (%%~zF bytes)
echo [build-kb-ext] Install it with: code --install-extension "%VSIX%"

exit /b 0
