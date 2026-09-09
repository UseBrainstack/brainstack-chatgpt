#!/bin/bash
# Brainstack — one-time backfill of your EXISTING local chats.
# Sends your past Claude Code, Cowork, and Codex/ChatGPT-work sessions to
# Brainstack so they become notes. Run AFTER installing a Brainstack plugin and
# signing in once. Safe to re-run — the server skips anything it already has.
set -uo pipefail

# --- 1) Locate the Brainstack binary (bsb, on disk as "vgb") + its .mcp.json ---
BSB=""
for c in \
  "$HOME/.brainstack/bin/bsb" \
  $(ls -t "$HOME"/.codex/plugins/cache/*brainstack*/*/*/runtime/vgb 2>/dev/null) \
  $(ls -t "$HOME"/.claude*/plugins/cache/*brainstack*/*/*/runtime/vgb 2>/dev/null); do
  [ -n "$c" ] && [ -x "$c" ] && BSB="$c" && break
done
[ -n "$BSB" ] || { echo "Couldn't find the Brainstack binary. Install a Brainstack plugin and sign in first."; exit 1; }

# The binary resolves the server endpoint from a co-located .mcp.json (two dirs
# up). Point CLAUDE_PLUGIN_ROOT at whichever dir actually has it, so backfill
# works regardless of which install we found.
ROOT="$(cd "$(dirname "$BSB")/.." && pwd)"
[ -f "$ROOT/.mcp.json" ] || ROOT="$HOME/.brainstack"
export CLAUDE_PLUGIN_ROOT="$ROOT"
[ -f "$CLAUDE_PLUGIN_ROOT/.mcp.json" ] || { echo "No .mcp.json found next to the binary — run the connector once (sign in) first."; exit 1; }

sent=0
send() { # <session_id> <transcript_path>
  [ -s "$2" ] || return 0
  printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"Stop","cwd":"%s"}' "$1" "$2" "$HOME" \
    | "$BSB" hook session-end >/dev/null 2>&1 && { sent=$((sent+1)); printf '.'; }
}

echo "Sending your past chats to Brainstack (this can take a minute)..."

# Claude Code: ~/.claude/projects/<proj>/<uuid>.jsonl  (id = filename stem)
while IFS= read -r f; do send "$(basename "$f" .jsonl)" "$f"; done \
  < <(find "$HOME/.claude/projects" -name '*.jsonl' 2>/dev/null)

# Cowork: .../local-agent-mode-sessions/**/local_<uuid>/audit.jsonl  (id = uuid)
while IFS= read -r f; do d="$(basename "$(dirname "$f")")"; send "${d#local_}" "$f"; done \
  < <(find "$HOME/Library/Application Support/Claude/local-agent-mode-sessions" -name 'audit.jsonl' 2>/dev/null)

# Codex / ChatGPT-work: ~/.codex/sessions|archived_sessions/**/rollout-*-<uuid>.jsonl
while IFS= read -r f; do
  id="$(basename "$f" .jsonl | grep -oE '[0-9a-fA-F-]{36}$' || true)"
  [ -n "$id" ] && send "$id" "$f"
done < <(find "$HOME/.codex/sessions" "$HOME/.codex/archived_sessions" -name 'rollout-*.jsonl' 2>/dev/null)

echo ""
echo "Done — sent $sent past session(s). They'll turn into notes in the background over the next little while."
