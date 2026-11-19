#!/usr/bin/env bash
# Runs the entry point named in .env with the interpreter named in .env, forwarding
# every argument and handing the script's exit code back.
# Safe to run from anywhere; the entry point is resolved against the repo root.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT/.env"

fail() {
    echo "[run] $*" >&2
    exit 1
}

[ -f "$ENV_FILE" ] \
    || fail "Missing .env - copy .env.example to .env and set MINISCRIPT_EXE_PATH."

# Prints the last value a KEY=value line in .env gives, quotes and a trailing CR from a
# .env written on Windows removed. Non-zero when the key never appears.
read_env() {
    local key="$1" line name value found=""
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"
        case "$line" in
            ''|'#'*) continue ;;
            *=*) ;;
            *) continue ;;
        esac
        name="${line%%=*}"
        value="${line#*=}"
        name="${name%"${name##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        [ "$name" = "$key" ] || continue
        # Tolerate quoted values in .env, e.g. MINISCRIPT_EXE_PATH="/opt/My Tools/miniscript"
        case "$value" in
            \"*\") value="${value#\"}"; value="${value%\"}" ;;
            \'*\') value="${value#\'}"; value="${value%\'}" ;;
        esac
        found="$value"
    done < "$ENV_FILE"
    [ -n "$found" ] || return 1
    printf '%s\n' "$found"
}

MINISCRIPT_EXE_PATH="$(read_env MINISCRIPT_EXE_PATH || true)"
ENTRY_POINT="$(read_env ENTRY_POINT || true)"
[ -n "$ENTRY_POINT" ] || ENTRY_POINT="src/main.ms"

[ -n "$MINISCRIPT_EXE_PATH" ] || fail "MINISCRIPT_EXE_PATH is not set in .env"

# Everything below is relative to the repo root, the way the runner works there.
cd "$ROOT"

[ -f "$MINISCRIPT_EXE_PATH" ] \
    || fail "MINISCRIPT_EXE_PATH does not exist: \"$MINISCRIPT_EXE_PATH\""
[ -x "$MINISCRIPT_EXE_PATH" ] \
    || fail "MINISCRIPT_EXE_PATH is not executable: \"$MINISCRIPT_EXE_PATH\"
[run] chmod +x it, then run this again."

[ -f "$ENTRY_POINT" ] || fail "Entry point not found: \"$ROOT/$ENTRY_POINT\""

# Pass any command-line arguments straight through to the script; they arrive in shellArgs.
rc=0
"$MINISCRIPT_EXE_PATH" "$ENTRY_POINT" "$@" || rc=$?
exit "$rc"
