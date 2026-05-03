# Claude Code

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code), Anthropic's AI-powered coding assistant, directly in your Home Assistant sidebar with full access to your configuration.

## Quick Start

```bash
claude "List all my automations"
claude "Turn off all lights in the living room"
claude "Create an automation to turn on lights at sunset"
claude "Why isn't my motion sensor automation working?"
```

## Requirements

- Home Assistant OS or Supervised installation
- [Anthropic account](https://console.anthropic.com/) (authentication handled in terminal)

## Setup

### 1. Install the Add-on

1. Add the repository to Home Assistant
2. Install the "Claude Code" add-on
3. Start the add-on
4. Open the Web UI from the sidebar

### 2. Authenticate with Claude Code

On first launch, Claude Code will prompt you to authenticate:

1. Open the terminal from the HA sidebar
2. Type `claude` to start
3. Follow the authentication prompts
4. Your credentials are stored securely by Claude Code

The add-on does NOT require you to enter API keys in the configuration. Claude Code handles authentication itself, storing credentials securely in its own configuration directory (`~/.claude/`).

## Using Claude Code

Once authenticated, Claude Code can help with:

- Editing Home Assistant YAML configurations
- Creating automations and scripts
- Debugging configuration issues
- Writing custom integrations

With `enable_mcp` set, Claude can also:

- Query entity states: "What's the temperature in the living room?"
- Control devices: "Turn off all lights in the bedroom"
- List services: "What services are available for climate control?"
- Debug automations: "Why didn't my morning routine trigger?"

### Example Commands

```bash
# Start interactive session
claude

# One-off commands
claude "Add a new automation that turns on the porch light at sunset"
claude "Check my configuration.yaml for errors"
claude "List all unavailable entities"

# Continue previous conversation
claude --continue
```

### Keyboard Shortcuts

| Shortcut | Command |
|----------|---------|
| `c` | `claude` |
| `cc` | `claude --continue` |
| `ha-config` | Navigate to config directory |
| `ha-logs` | View Home Assistant logs |

## Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `enable_mcp` | Enable HA integration via hass-mcp | `true` |
| `enable_playwright_mcp` | Enable Playwright MCP (requires Playwright Browser add-on) | `false` |
| `playwright_cdp_host` | Hostname of the Playwright Browser add-on | `""` |
| `terminal_font_size` | Font size (10–24) | `14` |
| `terminal_theme` | `dark` or `light` | `dark` |
| `working_directory` | Start directory | `/homeassistant` |
| `session_persistence` | Use tmux for persistent sessions | `true` |
| `auto_update_claude` | Auto-update Claude Code on startup | `true` |
| `model` | Claude model to use | `claude-sonnet-4-6` |

### Model Selection

| Model | Best for |
|-------|----------|
| `claude-sonnet-4-6` | Best balance of speed and capability (default) |
| `claude-opus-4-6` | Most powerful, for complex tasks |
| `claude-haiku-4-5-20251001` | Fastest, for simple queries |

Enable `auto_update_claude` to ensure new models become available as Anthropic releases them, without needing an add-on update.

## Update Notifications

When `auto_update_claude` is enabled, the add-on checks for newer versions of Claude Code in the background every hour. If an update is available:

- A **persistent notification** appears in the HA notification bell with the title "Claude Code Update Available"
- A **yellow banner** is shown in the terminal each time you open a session

Both clear automatically after restarting the add-on, which installs the latest version on startup.

## File Locations

| Path | Description | Access |
|------|-------------|--------|
| `/homeassistant` | HA configuration directory | read-write |
| `/share` | Shared folder | read-write |
| `/media` | Media folder | read-write |
| `/ssl` | SSL certificates | read-only |
| `/backup` | Backups | read-only |

## Session Persistence

When `session_persistence` is enabled, the add-on uses tmux to keep your terminal session running across page refreshes, disconnects, and reconnects. Claude Code conversations are preserved.

Since v2.3.0, tmux mouse mode is **off**, so the browser handles mouse events natively. You don't normally need to touch tmux directly. Keyboard shortcuts still work:

| Key | Action |
|-----|--------|
| `Ctrl+b d` | Detach from session (keeps it running) |
| `Ctrl+b [` | Enter keyboard scroll/copy mode (use arrow keys) |
| `q` | Exit keyboard scroll/copy mode |

### Copy and Paste

Mouse copy/paste works the same as any other browser terminal:

| Action | How to do it |
|--------|--------------|
| **Copy** | Select text with the mouse (or `Ctrl+Shift+C`) |
| **Paste** | Right-click, middle-click, or `Ctrl+Shift+V` |

### Authenticating (first launch)

1. Click the displayed authentication URL (opens in a new tab)
2. Complete authentication in the browser and copy the auth code
3. Switch back to the terminal and paste with right-click or `Ctrl+Shift+V`

## Security

- **No API keys in add-on config**: Claude Code stores credentials in `~/.claude/`, not in HA's add-on configuration.
- The Supervisor token is managed by the add-on and not exposed to the user.
- File access is limited to the mapped directories listed above.
- A custom AppArmor profile (`apparmor.txt`) is shipped with the add-on and applied automatically by Home Assistant.

## Troubleshooting

### Authentication issues

1. Type `claude` to start the authentication flow
2. Follow the prompts to log in or enter your API key
3. Credentials are saved automatically for future sessions

If you can't paste the auth code, use right-click or `Ctrl+Shift+V`.

### hass-mcp not working

1. Verify `enable_mcp` is `true` in configuration
2. Check add-on logs for connection errors
3. Restart the add-on after configuration changes

### Terminal not loading

1. Check that the add-on is running (green indicator)
2. Try refreshing the page
3. Check browser console for errors
4. Review add-on logs for ttyd errors

### Session not persisting

1. Ensure `session_persistence` is `true`
2. The session is named `claude` and will auto-attach on reconnect

### Configuration changes not applying

After changing configuration:

1. Save the configuration
2. Restart the add-on completely (not just reload)
