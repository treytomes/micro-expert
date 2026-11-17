@echo off
setlocal

rem Ensures the MiniScript 2 agent skill submodule (miniscript-2-agent-skill) is
rem checked out at .agents\skills\miniscript-2\. A clone made without
rem --recurse-submodules leaves that folder empty. Safe to re-run; run it from
rem anywhere.

set "ROOT=%~dp0"
set "SKILL_DIR=%ROOT%.agents\skills\miniscript-2"
set "SKILL_FILE=%SKILL_DIR%\SKILL.md"

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

if exist "%SKILL_FILE%" (
    echo [bootstrap] MiniScript 2 agent skill already present.
    git submodule status -- .agents/skills/miniscript-2
    popd
    exit /b 0
)

echo [bootstrap] Cloning .agents\skills\miniscript-2 ...
rem sync re-reads the URLs from .gitmodules, so a renamed or moved remote is
rem picked up instead of the value cached in .git\config.
git submodule sync --quiet --recursive
git submodule update --init --recursive -- .agents/skills/miniscript-2
if errorlevel 1 (
    echo [bootstrap] git submodule update failed.
    popd
    exit /b 1
)

rem Trust the file, not the exit code: an unregistered submodule makes update a
rem no-op that still reports success.
if not exist "%SKILL_FILE%" (
    echo [bootstrap] SKILL.md is still missing at "%SKILL_FILE%".
    echo [bootstrap] Check that .gitmodules lists .agents/skills/miniscript-2.
    popd
    exit /b 1
)

echo [bootstrap] MiniScript 2 agent skill is in place:
git submodule status -- .agents/skills/miniscript-2
popd

exit /b 0
