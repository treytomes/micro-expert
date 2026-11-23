#!/usr/bin/env bash
# Builds the Micro-Expert Knowledge VS Code extension in vscode-knowledge/ into
# vscode-knowledge/out/micro-expert-knowledge.vsix (git-ignored build output).
# Run this from anywhere; it works out the repo root itself.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
EXT_DIR="$ROOT/vscode-knowledge"
OUT_DIR="$EXT_DIR/out"
VSIX="$OUT_DIR/micro-expert-knowledge.vsix"

fail() {
    echo "[build-kb-ext] $*" >&2
    exit 1
}

[ -f "$EXT_DIR/package.json" ] || fail "Extension not found: \"$EXT_DIR/package.json\""

command -v node >/dev/null 2>&1 \
    || fail "node was not found on PATH - install Node.js, then run this again."

# Prefer a globally installed vsce; fall back to npx, which fetches it on demand.
if command -v vsce >/dev/null 2>&1; then
    VSCE=(vsce)
elif command -v npx >/dev/null 2>&1; then
    VSCE=(npx --yes @vscode/vsce)
else
    fail "Neither vsce nor npx was found.
[build-kb-ext] Install Node.js, then run: npm install -g @vscode/vsce"
fi

mkdir -p "$OUT_DIR"

# Drop a stale package so a failed build can't be mistaken for a fresh one.
rm -f "$VSIX"

# The version VS Code compares when installing: bump it in package.json for
# each change you want VS Code to take as an update.
VERSION="$(cd "$EXT_DIR" && node -p "require('./package.json').version" 2>/dev/null)" \
    || VERSION=""
[ -n "$VERSION" ] || VERSION="unknown"

# vsce resolves paths against its working directory, so package from the extension root.
rc=0
(cd "$EXT_DIR" && "${VSCE[@]}" package --out "$VSIX") || rc=$?
if [ "$rc" -ne 0 ]; then
    fail "vsce failed with exit code $rc."
fi

[ -f "$VSIX" ] || fail "vsce reported success but \"$VSIX\" was not created."

BYTES="$(wc -c < "$VSIX" | tr -d '[:space:]')"
echo "[build-kb-ext] Built Micro-Expert Knowledge $VERSION - $(basename "$VSIX") ($BYTES bytes)"
echo "[build-kb-ext] Install it with: code --install-extension \"$VSIX\""

exit 0
