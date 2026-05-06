#!/bin/bash
set -e

export HA_TOKEN="$SUPERVISOR_TOKEN"
export HA_URL="http://supervisor/core"
PERSIST_DIR=/homeassistant/.claudecode

mkdir -p "$PERSIST_DIR/config" /root/.config

# Write CLAUDE.md for Claude's context
cat > "$PERSIST_DIR/CLAUDE.md" << 'CLAUDEMD'
# Claude Code - Home Assistant Add-on

## Path Mapping

In this add-on container, paths are mapped differently than HA Core:
- `/homeassistant` = HA config directory (equivalent to `/config` in HA Core)
- `/config` does NOT exist - always use `/homeassistant`

When users mention `/config/...`, translate to `/homeassistant/...`

## Available Paths

| Path | Description | Access |
|------|-------------|--------|
| `/homeassistant` | HA configuration | read-write |
| `/share` | Shared folder | read-write |
| `/media` | Media files | read-write |
| `/ssl` | SSL certificates | read-only |
| `/backup` | Backups | read-only |

## Home Assistant Integration

Use the `homeassistant` MCP server to query entities and call services.

## Reading Home Assistant Logs

**Log levels (from most to least verbose):**
- `debug` - Only shown if explicitly enabled in configuration.yaml
- `info` - General information, shown by default
- `warning` - Warnings, always shown
- `error` - Errors, always shown

**Commands to read logs:**
```bash
# View recent logs (ha CLI)
ha core logs 2>&1 | tail -100

# Filter by keyword
ha core logs 2>&1 | grep -i keyword

# Filter errors only
ha core logs 2>&1 | grep -iE "(error|exception)"

# Alternative: read log file directly
tail -100 /homeassistant/home-assistant.log
```

**To enable debug logging for an integration**, add to `configuration.yaml`:
```yaml
logger:
  default: info
  logs:
    custom_components.YOUR_INTEGRATION: debug
```

**Key insight:** `_LOGGER.debug()` calls are invisible unless the logger level is set to debug. Use `_LOGGER.info()` or `_LOGGER.warning()` for logs that should always appear.
CLAUDEMD

# Persistence symlinks — keep Claude auth and config across container rebuilds
[ ! -L /root/.claude ] && { rm -rf /root/.claude; ln -s "$PERSIST_DIR" /root/.claude; }
[ ! -L /root/.config/claude-code ] && { rm -rf /root/.config/claude-code; ln -s "$PERSIST_DIR/config" /root/.config/claude-code; }
[ ! -L /root/.claude.json ] && { touch "$PERSIST_DIR/.claude.json"; rm -f /root/.claude.json; ln -s "$PERSIST_DIR/.claude.json" /root/.claude.json; }

# Persist ~/.local/bin so `claude update` installs survive container rebuilds
mkdir -p "$PERSIST_DIR/local-bin"
[ ! -L /root/.local/bin ] && { rm -rf /root/.local/bin; ln -s "$PERSIST_DIR/local-bin" /root/.local/bin; }

# Bootstrap or repair the native (~/.local/bin) install of Claude Code.
# The npm-global binary fails to self-update in this container with
# "Insufficient permissions to install update". The native binary owns
# its own install path and updates cleanly.
#
# We test by actually running --version (not just `-x`) so an exec-blocked
# binary (e.g. AppArmor missing ixmr on the install path) triggers a repair
# instead of poisoning PATH. If even after install the binary still won't
# run, we delete it so PATH falls back to /usr/local/bin/claude (npm-global)
# and the rest of run.sh keeps working — better degraded than crash-looping.
if ! /root/.local/bin/claude --version >/dev/null 2>&1; then
    echo "[INFO] Bootstrapping native Claude Code install at /root/.local/bin/claude..."
    INSTALL_LOG=$(mktemp)
    INSTALL_RC=0
    env -u DISABLE_AUTOUPDATER timeout 120 claude install latest </dev/null >"$INSTALL_LOG" 2>&1 || INSTALL_RC=$?
    # `set -e` would fire on a failed standalone command-substitution assignment
    # (it's only suppressed inside `if`/`&&`/`||` contexts). Capture the rc with
    # `|| EXEC_RC=$?` so verification failures are reachable by the diagnostic
    # block below instead of silently killing the script before ttyd ever starts.
    EXEC_RC=0
    EXEC_OUT=$(timeout 30 /root/.local/bin/claude --version </dev/null 2>&1) || EXEC_RC=$?
    if [ $EXEC_RC -eq 0 ] && [ -n "$EXEC_OUT" ]; then
        echo "[INFO] Native install complete ($EXEC_OUT)"
    else
        echo "[WARN] Native install verification failed (install rc=$INSTALL_RC, exec rc=$EXEC_RC). Diagnostic:"
        echo "[WARN]   exec output: ${EXEC_OUT:-<empty>}"
        echo "[WARN]   active AppArmor profile:"
        cat /proc/self/attr/current 2>&1 | sed 's/^/[WARN]     /'
        echo "[WARN]   ls -la /root/.local/bin/:"
        ls -la /root/.local/bin/ 2>&1 | sed 's/^/[WARN]     /'
        echo "[WARN]   ls -la /homeassistant/.claudecode/:"
        ls -la /homeassistant/.claudecode/ 2>&1 | sed 's/^/[WARN]     /'
        echo "[WARN]   head -20 of launcher /root/.local/bin/claude:"
        head -20 /root/.local/bin/claude 2>&1 | sed 's/^/[WARN]     /'
        echo "[WARN]   install log:"
        sed 's/^/[WARN]     /' "$INSTALL_LOG"
        echo "[WARN] Removing /root/.local/bin/claude so PATH falls back to /usr/local/bin/claude (npm-global)."
        rm -f /root/.local/bin/claude
    fi
    rm -f "$INSTALL_LOG"
fi

# Read options from HA config
FONT_SIZE=$(jq -r '.terminal_font_size // 14' /data/options.json)
THEME=$(jq -r --arg d dark '.terminal_theme // $d' /data/options.json)
SESSION_PERSIST=$(jq -r '.session_persistence // true' /data/options.json)
ENABLE_MCP=$(jq -r '.enable_mcp // true' /data/options.json)
ENABLE_PLAYWRIGHT=$(jq -r '.enable_playwright_mcp // false' /data/options.json)
PLAYWRIGHT_HOST=$(jq -r --arg d '' '.playwright_cdp_host // $d' /data/options.json)

# Auto-detect Playwright Browser hostname if not explicitly set
if [ -z "$PLAYWRIGHT_HOST" ] && [ "$ENABLE_PLAYWRIGHT" = "true" ]; then
    echo '[INFO] Auto-detecting Playwright Browser hostname...'
    PLAYWRIGHT_HOST=$(curl -s -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor/addons \
        | jq -r --arg s1 playwright-browser --arg s2 _playwright-browser \
          '.data.addons[] | select(.slug | (endswith($s1) or endswith($s2))) | .hostname' | head -1)
    if [ -n "$PLAYWRIGHT_HOST" ] && [ "$PLAYWRIGHT_HOST" != "null" ]; then
        echo "[INFO] Found Playwright Browser: $PLAYWRIGHT_HOST"
    else
        echo '[WARN] Playwright Browser add-on not found, using default hostname'
        PLAYWRIGHT_HOST="playwright-browser"
    fi
fi

# Auto-update Claude Code on startup if enabled
AUTO_UPDATE=$(jq -r '.auto_update_claude // true' /data/options.json)
if [ "$AUTO_UPDATE" = "true" ]; then
    CURRENT_VER=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    LATEST_VER=$(npm show @anthropic-ai/claude-code version 2>/dev/null)
    if [ -n "$LATEST_VER" ] && [ -n "$CURRENT_VER" ] && [ "$CURRENT_VER" != "$LATEST_VER" ]; then
        echo "[INFO] Updating Claude Code from $CURRENT_VER to $LATEST_VER..."
        # DISABLE_AUTOUPDATER=1 (set in Dockerfile to keep the background updater quiet)
        # also blocks the explicit `claude update` command in recent versions, so unset it
        # for the duration of this call only.
        UPDATE_LOG=$(mktemp)
        if env -u DISABLE_AUTOUPDATER timeout 120 claude update </dev/null >"$UPDATE_LOG" 2>&1; then
            UPDATE_RC=0
        else
            UPDATE_RC=$?
        fi
        NEW_VER=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [ "$NEW_VER" = "$LATEST_VER" ]; then
            echo "[INFO] Claude Code updated to $NEW_VER"
        else
            echo "[WARN] Claude Code update did not reach $LATEST_VER (still $NEW_VER, exit=$UPDATE_RC)"
            echo "[WARN] --- claude update output ---"
            sed 's/^/[WARN] /' "$UPDATE_LOG"
            echo "[WARN] --- end output ---"
        fi
        rm -f "$UPDATE_LOG"
    else
        echo "[INFO] Claude Code $CURRENT_VER is up to date"
    fi
fi

# Set Claude model
MODEL=$(jq -r --arg d claude-sonnet-4-6 '.model // $d' /data/options.json)
export ANTHROPIC_MODEL="$MODEL"
echo "[INFO] Using Claude model: $MODEL"

# Configure MCP servers
claude mcp remove homeassistant -s user 2>/dev/null || true
claude mcp remove playwright -s user 2>/dev/null || true

if [ "$ENABLE_MCP" = "true" ]; then
    claude mcp add-json homeassistant '{"command":"hass-mcp"}' -s user
    SETTINGS_FILE=/root/.claude/settings.json
    ALLOWED_TOOLS='[
      "mcp__homeassistant__get_version",
      "mcp__homeassistant__get_entity",
      "mcp__homeassistant__list_entities",
      "mcp__homeassistant__search_entities_tool",
      "mcp__homeassistant__domain_summary_tool",
      "mcp__homeassistant__list_automations",
      "mcp__homeassistant__get_history",
      "mcp__homeassistant__get_error_log",
      "Read(/homeassistant/**)",
      "Read(/config/**)",
      "Read(/share/**)",
      "Read(/media/**)",
      "Glob(/homeassistant/**)",
      "Glob(/config/**)",
      "Grep(/homeassistant/**)",
      "Grep(/config/**)"
    ]'
    jq --argjson tools "$ALLOWED_TOOLS" \
        '.permissions.allow = ($tools + (.permissions.allow // []) | unique)' \
        "$SETTINGS_FILE" > /tmp/settings.tmp && mv /tmp/settings.tmp "$SETTINGS_FILE"
    jq --arg token "$SUPERVISOR_TOKEN" \
        '.mcpServers.homeassistant.env.HASS_TOKEN = $token' \
        "$SETTINGS_FILE" > /tmp/settings.tmp && mv /tmp/settings.tmp "$SETTINGS_FILE"
    echo '[INFO] MCP configured with Home Assistant integration'
    echo '[INFO] Pre-authorized read-only MCP tools'
else
    echo '[INFO] MCP disabled'
fi

if [ "$ENABLE_PLAYWRIGHT" = "true" ]; then
    claude mcp add-json playwright \
        '{"command":"npx","args":["--no-install","@playwright/mcp","--cdp-endpoint","http://'"$PLAYWRIGHT_HOST"':9222"]}' \
        -s user
    echo "[INFO] Playwright MCP enabled (CDP: http://${PLAYWRIGHT_HOST}:9222)"
    echo '[INFO] Make sure the Playwright Browser add-on is installed and running'
else
    echo '[INFO] Playwright MCP disabled'
fi

# Set terminal colors based on theme
if [ "$THEME" = "dark" ]; then
    COLORS='background=#1e1e2e,foreground=#cdd6f4,cursor=#f5e0dc'
else
    COLORS='background=#eff1f5,foreground=#4c4f69,cursor=#dc8a78'
fi

# Set shell command based on session persistence setting
if [ "$SESSION_PERSIST" = "true" ]; then
    SHELL_CMD='tmux new-session -A -s claude'
else
    SHELL_CMD='bash --login'
fi

# Background update checker — runs hourly, posts HA notification when update is available
(while true; do
    IV=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    LV=$(npm show @anthropic-ai/claude-code version 2>/dev/null)
    if [ -n "$LV" ] && [ -n "$IV" ] && [ "$IV" != "$LV" ]; then
        echo "$LV" > "$PERSIST_DIR/.update_notice"
        echo "[INFO] Claude Code update available: $LV (installed: $IV)"
        printf '{"title":"Claude Code Update Available","message":"Version %s is available (installed: %s). Restart the add-on to update.","notification_id":"claude_code_update"}' "$LV" "$IV" \
            | curl -sf -X POST \
              -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
              -H "Content-Type: application/json" \
              -d @- http://supervisor/core/api/services/persistent_notification/create 2>/dev/null || true
    else
        rm -f "$PERSIST_DIR/.update_notice" 2>/dev/null
        printf '{"notification_id":"claude_code_update"}' \
            | curl -sf -X POST \
              -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
              -H "Content-Type: application/json" \
              -d @- http://supervisor/core/api/services/persistent_notification/dismiss 2>/dev/null || true
    fi
    sleep 3600
done) &

# Start web terminal
cd /homeassistant
exec ttyd --port 7681 --writable --ping-interval 30 --max-clients 5 \
    -t fontSize="$FONT_SIZE" \
    -t fontFamily=Monaco,Consolas,monospace \
    -t scrollback=20000 \
    -t "theme=$COLORS" \
    $SHELL_CMD
