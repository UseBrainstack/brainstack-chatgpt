#!/bin/bash
# Brainstack — one-time backfill of your existing local Codex / ChatGPT-work chats.
# Drives the Brainstack plugin's own binary (vgb) to send your past Codex sessions
# (the rollout transcripts the ChatGPT desktop app and the Codex CLI both write
# under ~/.codex) to Brainstack. Run AFTER installing the plugin and signing in
# once. Safe to re-run (the server skips anything it already has).
#
# NOTE: This backfills Codex/ChatGPT-work *rollout* transcripts only. Plain
# ChatGPT chats (the app's own sqlite thread history) are save-on-ask by design
# and are NOT scraped here.
set -uo pipefail

# Locate the vgb binary: local plugin copy first, then an installed plugin that
# Codex snapshotted into its plugin cache (~/.codex/plugins/cache/<marketplace>/
# brainstack/<version>/runtime/vgb).
VGB=""
for c in \
  "$(cd "$(dirname "$0")" && pwd)/plugins/brainstack/runtime/vgb" \
  $(ls -t "$HOME"/.codex/plugins/cache/*/brainstack/*/runtime/vgb 2>/dev/null) \
  $(ls -t "$HOME"/.codex/plugins/cache/*/brainstack/runtime/vgb 2>/dev/null); do
  [ -x "$c" ] && VGB="$c" && break
done
[ -n "$VGB" ] || { echo "Couldn't find the Brainstack plugin binary. Install the plugin + sign in first."; exit 1; }
# vgb resolves its OAuth token from ~/.vgb/token.json; CLAUDE_PLUGIN_ROOT is set
# for parity with the plugin runtime but is not required for the token lookup.
export CLAUDE_PLUGIN_ROOT="$(dirname "$(dirname "$VGB")")"

sent=0
send() { # session_id  transcript_path
  printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"SessionEnd","cwd":"%s"}' "$1" "$2" "$HOME" \
    | "$VGB" hook session-end >/dev/null 2>&1 && sent=$((sent+1)) && printf '.'
}

echo "Uploading your past Codex / ChatGPT-work chats through the Brainstack plugin..."
# Codex: ~/.codex/sessions|archived_sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl
# The trailing uuid in the filename == payload.session_id in the session_meta line.
while IFS= read -r f; do
  id="$(basename "$f" .jsonl | grep -oE '[0-9a-fA-F-]{36}$' || true)"
  [ -n "$id" ] && [ -s "$f" ] && send "$id" "$f"
done < <(find "$HOME/.codex/sessions" "$HOME/.codex/archived_sessions" -name 'rollout-*.jsonl' 2>/dev/null)

echo ""
echo "Done -- sent $sent past session(s) to Brainstack. They'll turn into notes in the background over the next little while."
