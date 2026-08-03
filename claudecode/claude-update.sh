#!/bin/bash
# Update Claude Code, whichever install method is currently active.
#
# Used by both the startup auto-updater in run.sh and the interactive
# `claude-update` command. Deliberately does NOT use `set -e`: every step is
# allowed to fail so we can fall through to the next method and report what
# actually happened.
set -uo pipefail

PERSIST_DIR=/homeassistant/.claudecode

log() { echo "[claude-update] $*"; }
indent() { sed 's/^/[claude-update]   /'; }

installed_version() {
    claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

ACTIVE=$(command -v claude 2>/dev/null || true)
BEFORE=$(installed_version)
LATEST=$(npm show @anthropic-ai/claude-code version 2>/dev/null)

log "active binary: ${ACTIVE:-<none>}"
log "installed: ${BEFORE:-unknown}   latest: ${LATEST:-unknown}"

if [ -z "$LATEST" ]; then
    log "could not reach the npm registry - skipping update"
    exit 1
fi

if [ "$BEFORE" = "$LATEST" ]; then
    log "already up to date"
    rm -f "$PERSIST_DIR/.update_notice" 2>/dev/null
    exit 0
fi

# Step 1: the built-in updater. DISABLE_AUTOUPDATER=1 (set in the Dockerfile to
# keep the background updater quiet) also blocks the explicit `update` command
# in recent versions, so unset it for the duration of this call only.
log "running built-in updater..."
env -u DISABLE_AUTOUPDATER timeout 180 claude update </dev/null 2>&1 | indent

AFTER=$(installed_version)
if [ "$AFTER" = "$LATEST" ]; then
    log "updated to $AFTER"
    rm -f "$PERSIST_DIR/.update_notice" 2>/dev/null
    exit 0
fi

# Step 2: the built-in updater didn't get us there. Reinstall directly, using
# whichever mechanism owns the binary that's actually first on PATH.
log "built-in updater left us on ${AFTER:-unknown}; reinstalling..."
case "$ACTIVE" in
    */.local/bin/claude)
        log "active install is native - running 'claude install latest'"
        env -u DISABLE_AUTOUPDATER timeout 300 claude install latest </dev/null 2>&1 | indent
        ;;
    *)
        log "active install is npm-global - running 'npm install -g'"
        timeout 300 npm install -g @anthropic-ai/claude-code@latest --no-fund --no-audit 2>&1 | indent
        ;;
esac

AFTER=$(installed_version)
if [ "$AFTER" != "$LATEST" ]; then
    log "FAILED - still on ${AFTER:-unknown}, wanted $LATEST"
    exit 1
fi

log "updated to $AFTER"
rm -f "$PERSIST_DIR/.update_notice" 2>/dev/null
exit 0
