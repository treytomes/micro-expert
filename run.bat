@echo off
setlocal

set "ROOT=%~dp0"
set "ENV_FILE=%ROOT%.env"

if not exist "%ENV_FILE%" (
    echo [run] Missing .env - copy .env.example to .env and set MINISCRIPT_EXE_PATH.
    exit /b 1
)

set "MINISCRIPT_EXE_PATH="
set "ENTRY_POINT="
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%ENV_FILE%") do (
    if /i "%%A"=="MINISCRIPT_EXE_PATH" set "MINISCRIPT_EXE_PATH=%%B"
    if /i "%%A"=="ENTRY_POINT" set "ENTRY_POINT=%%B"
)

rem Tolerate quoted values in .env, e.g. MINISCRIPT_EXE_PATH="C:\Program Files\miniscript.exe"
if defined MINISCRIPT_EXE_PATH set "MINISCRIPT_EXE_PATH=%MINISCRIPT_EXE_PATH:"=%"
if defined ENTRY_POINT set "ENTRY_POINT=%ENTRY_POINT:"=%"

if not defined ENTRY_POINT set "ENTRY_POINT=src\main.ms"

if not defined MINISCRIPT_EXE_PATH (
    echo [run] MINISCRIPT_EXE_PATH is not set in .env
    exit /b 1
)

if not exist "%MINISCRIPT_EXE_PATH%" (
    echo [run] MINISCRIPT_EXE_PATH does not exist: "%MINISCRIPT_EXE_PATH%"
    exit /b 1
)

if not exist "%ROOT%%ENTRY_POINT%" (
    echo [run] Entry point not found: "%ROOT%%ENTRY_POINT%"
    exit /b 1
)

pushd "%ROOT%"
rem Pass any command-line arguments straight through to the script; they arrive in shellArgs.
"%MINISCRIPT_EXE_PATH%" "%ENTRY_POINT%" %*
set "EXIT_CODE=%ERRORLEVEL%"
popd

exit /b %EXIT_CODE%
