#!/bin/bash
# Brainstack — wire up automatic capture for Codex / ChatGPT-work sessions.
# Run this ONCE after installing the Brainstack plugin in the ChatGPT app
# (codex plugin marketplace add UseBrainstack/brainstack-chatgpt).
#
# It copies the Brainstack binary to a stable path and registers a capture
# hook in ~/.codex/hooks.json. Your next Codex session will ask you to approve
# the hook once; after that, coding sessions capture automatically.
# Safe to re-run. Plain ChatGPT chats are save-on-ask (use the connector), by design.
set -uo pipefail

# 1) Locate the Brainstack binary the plugin shipped (bsb, named "vgb" on disk).
BSB=""
for c in \
  "$(ls -t "$HOME"/.codex/plugins/cache/*brainstack*/*/*/runtime/vgb 2>/dev/null)" \
  "$(ls -t "$HOME"/.codex/.tmp/marketplaces/*brainstack*/plugins/brainstack/runtime/vgb 2>/dev/null)"; do
  [ -n "$c" ] && [ -x "$c" ] && BSB="$c" && break
done
if [ -z "$BSB" ]; then
  echo "Couldn't find the Brainstack plugin binary. Install the plugin first:"
  echo "  codex plugin marketplace add UseBrainstack/brainstack-chatgpt"
  echo "  codex plugin add brainstack@brainstack-chatgpt"
  exit 1
fi

# 2) Copy it to a stable path (survives plugin version bumps), and place a
#    co-located .mcp.json so the binary can self-locate the server endpoint
#    (the ChatGPT app doesn't set CLAUDE_PLUGIN_ROOT, and only GLOBAL hooks fire
#    in the app — plugin-declared command hooks are shown but not executed).
mkdir -p "$HOME/.brainstack/bin"
cp "$BSB" "$HOME/.brainstack/bin/bsb"
chmod +x "$HOME/.brainstack/bin/bsb"
STABLE="$HOME/.brainstack/bin/bsb"
# .mcp.json must sit at ~/.brainstack/.mcp.json (two dirs up from the binary).
PLUGIN_DIR="$(cd "$(dirname "$BSB")/.." && pwd)"
if [ -f "$PLUGIN_DIR/.mcp.json" ]; then
  cp "$PLUGIN_DIR/.mcp.json" "$HOME/.brainstack/.mcp.json"
else
  cat > "$HOME/.brainstack/.mcp.json" <<'MCP'
{ "mcpServers": { "brainstack": { "command": "./bin/bsb", "args": ["connect", "https://usebrainstack.com/mcp"] } } }
MCP
fi

# 3) Write the capture hook into ~/.codex/hooks.json (back up any existing one).
HOOKS="$HOME/.codex/hooks.json"
mkdir -p "$HOME/.codex"
[ -f "$HOOKS" ] && cp "$HOOKS" "$HOOKS.bak-$(date +%s)"
cat > "$HOOKS" <<EOF
{
  "hooks": {
    "SessionStart": [
      { "hooks": [
        { "type": "command", "command": "$STABLE hook session-start", "timeout": 10 },
        { "type": "command", "command": "$STABLE hook session-catchup", "timeout": 30 }
      ] }
    ],
    "Stop": [
      { "hooks": [
        { "type": "command", "command": "$STABLE hook session-end", "timeout": 30 }
      ] }
    ]
  }
}
EOF

echo "Done. Brainstack capture is wired for Codex."
echo "  - Your NEXT Codex session will ask you to approve the hook once."
echo "  - Sign in to Brainstack when the browser opens (first connector use)."
echo "  - Coding sessions then capture automatically; plain chats save on-ask."
