#!/usr/bin/env bash
# One-time setup for a fresh clone: the submodules listed below, the MiniScript 2
# interpreter in 3rd-party/ (a gitignored folder, so a clone carries no binary), and a
# .env beside the runner.
# Safe to re-run; run it from anywhere.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
THIRD_DIR="$ROOT/3rd-party"
TARBALL="$THIRD_DIR/miniscript-linux.tar.gz"
EXE_PATH="$THIRD_DIR/miniscript-linux/miniscript"
ENV_FILE="$ROOT/.env"
# Tracks the latest release; pin a tag in this URL for a reproducible setup.
TARBALL_URL="https://github.com/JoeStrout/miniscript2/releases/latest/download/miniscript-linux.tar.gz"

fail() {
    echo "[bootstrap] $*" >&2
    exit 1
}

command -v git >/dev/null 2>&1 \
    || fail "git was not found on PATH - install Git, then run this again."

[ -f "$ROOT/.gitmodules" ] \
    || fail "No .gitmodules next to this script; that is not the project root."

cd "$ROOT"

# --- the submodules ---------------------------------------------------------
# One line per submodule: its path as .gitmodules spells it, a file that proves it
# checked out, and a name for the log. Extracting another one is a single line here.
# Failures are collected rather than raised, so one bad submodule still leaves the
# report for the other three behind it.
missing=""
while IFS='|' read -r path marker label; do
    [ -n "$path" ] || continue
    if [ ! -e "$path/$marker" ]; then
        echo "[bootstrap] Cloning $path ..."
        # sync re-reads the URLs from .gitmodules, so a renamed or moved remote is
        # picked up instead of the value cached in .git/config.
        git submodule sync --quiet --recursive
        git submodule update --init --recursive -- "$path" \
            || fail "Could not check out \"$path\" - see the error above."
    fi
    # Trust the file, not the exit code: an unregistered submodule makes update a
    # no-op that still reports success.
    if [ ! -e "$path/$marker" ]; then
        echo "[bootstrap] $marker is missing at \"$path/$marker\"."
        echo "[bootstrap] Check that .gitmodules lists $path."
        missing="$path"
    else
        echo "[bootstrap] $label in place: $path"
    fi
done <<'TABLE'
.agents/skills/miniscript-2|SKILL.md|Agent skill
vscode-miniscript|package.json|VS Code extension
src/cli|cli.ms|Command-line library
src/logging|logging.ms|Logger
TABLE

[ -z "$missing" ] || fail "Giving up on \"$missing\" - fix .gitmodules and run this again."

# --- the interpreter in 3rd-party/ ------------------------------------------
downloaded=""
if [ ! -f "$EXE_PATH" ]; then
    mkdir -p "$THIRD_DIR"

    echo "[bootstrap] Downloading miniscript-linux.tar.gz ..."
    if command -v curl >/dev/null 2>&1; then
        curl -L --fail --silent --show-error --output "$TARBALL" "$TARBALL_URL" \
            || fail "Download failed: $TARBALL_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget --quiet --output-document="$TARBALL" "$TARBALL_URL" \
            || fail "Download failed: $TARBALL_URL"
    else
        fail "Neither curl nor wget was found on PATH - install one, then run this again."
    fi
    [ -f "$TARBALL" ] || fail "Download reported success but \"$TARBALL\" is not there."
    # Only a file this run fetched gets cleaned up at the end.
    downloaded=1

    # Unpack into 3rd-party/, keeping the archive's own miniscript-linux/ folder.
    echo "[bootstrap] Extracting into 3rd-party ..."
    command -v tar >/dev/null 2>&1 \
        || fail "tar was not found on PATH - install it, then run this again."
    tar -xzf "$TARBALL" -C "$THIRD_DIR" \
        || fail "Extraction failed; \"$TARBALL\" was left in place for a retry."
fi

# Check the executable before deleting its archive.
[ -f "$EXE_PATH" ] || fail "No miniscript executable at \"$EXE_PATH\" after extracting.
[bootstrap] Check the archive layout; \"$TARBALL\" was left in place."
chmod +x "$EXE_PATH" || fail "Could not make \"$EXE_PATH\" executable."
echo "[bootstrap] Interpreter in place: 3rd-party/miniscript-linux/miniscript"

# --- .env -------------------------------------------------------------------
# An existing .env may point somewhere else on purpose, so it is never rewritten.
if [ -f "$ENV_FILE" ]; then
    echo "[bootstrap] Keeping the existing .env."
else
    echo "[bootstrap] Writing .env ..."
    printf 'MINISCRIPT_EXE_PATH=%s\nENTRY_POINT=./src/main.ms\n' "$EXE_PATH" > "$ENV_FILE" \
        || fail "Could not write \"$ENV_FILE\"."
    [ -f "$ENV_FILE" ] || fail "Could not write \"$ENV_FILE\"."
fi

if [ -n "$downloaded" ]; then
    rm -f "$TARBALL"
    echo "[bootstrap] Removed the downloaded 3rd-party/miniscript-linux.tar.gz"
fi

echo "[bootstrap] Ready."
# Reporting only: a status that cannot run does not undo a finished setup.
git submodule status || true
exit 0
