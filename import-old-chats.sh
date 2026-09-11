#!/bin/bash
# Brainstack — import your existing local AI chats (Mac/Linux).
# Self-contained: downloads a tiny uploader to a temp folder, signs you in,
# uploads your chosen chats, and DELETES ITSELF. Nothing is installed.
set -uo pipefail
REALHOME="$HOME"
WORK="$(mktemp -d 2>/dev/null || echo /tmp/bs-import-$$)"; mkdir -p "$WORK/bin" "$WORK/.bsb"
cleanup(){ rm -rf "$WORK" 2>/dev/null; }
trap cleanup EXIT INT TERM

echo "Setting up (nothing is installed — this removes itself when done)..."

# 1) Download the uploader into the temp folder + clear the macOS quarantine flag.
BSB="$WORK/bin/bsb"
curl -fsSL "https://raw.githubusercontent.com/UseBrainstack/brainstack-chatgpt/main/plugins/brainstack/runtime/bsb" -o "$BSB" || { echo "Download failed — check your connection."; exit 1; }
chmod +x "$BSB"; xattr -dr com.apple.quarantine "$BSB" 2>/dev/null || true

# 2) Endpoint config (so the uploader knows where to send).
cat > "$WORK/.mcp.json" <<'MCP'
{ "mcpServers": { "brainstack": { "command": "./bin/bsb", "args": ["connect","https://usebrainstack.com/mcp"] } } }
MCP
export CLAUDE_PLUGIN_ROOT="$WORK"
export HOME="$WORK"   # keep the sign-in token inside the temp folder → deleted on cleanup

# 3) Sign in to Brainstack — always a fresh browser sign-in via `bsb login` (no
#    token reuse, so it targets the RIGHT account). HOME is the temp folder, so the
#    token lands there → deleted on cleanup. `login` runs the whole OAuth flow
#    itself and exits — no stdin nudging, no background connect to babysit.
echo "A browser window will open — sign in with your work email to Brainstack."
"$BSB" login https://usebrainstack.com/mcp || true
[ -f "$WORK/.bsb/token.json" ] || { echo "Sign-in didn't finish — re-run when you're ready."; exit 1; }
echo "Signed in."

# 4) Find your chats (from your real home, not the temp folder).
list_all(){
  find "$REALHOME/.claude/projects" -name '*.jsonl' 2>/dev/null
  find "$REALHOME/Library/Application Support/Claude/local-agent-mode-sessions" -name 'audit.jsonl' 2>/dev/null
  find "$REALHOME/.codex/sessions" "$REALHOME/.codex/archived_sessions" -name 'rollout-*.jsonl' 2>/dev/null
}
NCLA=$( { find "$REALHOME/.claude/projects" -name '*.jsonl' 2>/dev/null; find "$REALHOME/Library/Application Support/Claude/local-agent-mode-sessions" -name 'audit.jsonl' 2>/dev/null; } | grep -c . )
NCDX=$( find "$REALHOME/.codex/sessions" "$REALHOME/.codex/archived_sessions" -name 'rollout-*.jsonl' 2>/dev/null | grep -c . )
TOTAL=$((NCLA+NCDX))
if [ "$TOTAL" -eq 0 ]; then echo "No local chats found on this computer. Nothing to import."; exit 0; fi
RATE=2                                                    # ~seconds per chat
ALLMIN=$(( (TOTAL*RATE + 59) / 60 )); [ "$ALLMIN" -lt 1 ] && ALLMIN=1
N50=$(( TOTAL < 50 ? TOTAL : 50 )); M50=$(( (N50*RATE + 59) / 60 )); [ "$M50" -lt 1 ] && M50=1

echo ""
echo "Found on this computer:  $NCLA Claude chats  ·  $NCDX Codex/ChatGPT chats  ·  $TOTAL total"
echo ""
echo "How many of your past chats should we bring in?"
echo ""
echo "  [1] Everything            ($TOTAL chats, ~${ALLMIN} min)   <- recommended"
echo "  [2] The $N50 most recent    (~${M50} min)"
echo "  [3] The 15 most recent    (~1 min)"
echo "  [4] A custom number"
echo "  [5] Skip for now"
echo ""
printf "Choose 1-5  (press Enter for 1 = everything): "
read -r CHOICE < /dev/tty || CHOICE=1
[ -z "$CHOICE" ] && CHOICE=1
case "$CHOICE" in
  1) LIMIT="$TOTAL";;
  2) LIMIT="$N50";;
  3) LIMIT=$(( TOTAL < 15 ? TOTAL : 15 ));;
  4) printf "How many? (a number, e.g. 500): "
     read -r NUM < /dev/tty || NUM=""
     case "$NUM" in ""|*[!0-9]*) echo "That wasn't a number — nothing imported. Re-run when ready."; exit 0;; esac
     LIMIT=$(( NUM < TOTAL ? NUM : TOTAL ));;
  *) echo "Skipped."; exit 0;;
esac

# 5) Upload the newest LIMIT sessions, 6 in parallel.
sid_for(){ case "$1" in
  *"/.claude/projects/"*)         basename "$1" .jsonl ;;
  *"local-agent-mode-sessions"*)  d="$(basename "$(dirname "$1")")"; echo "${d#local_}" ;;
  *"/.codex/"*)                   basename "$1" .jsonl | grep -oE '[0-9a-fA-F-]{36}$' ;;
  *)                              basename "$1" .jsonl ;; esac; }
send(){ [ -s "$2" ] || return 0; printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"Stop","cwd":"%s"}' "$1" "$2" "$REALHOME" | "$BSB" ingest >/dev/null 2>&1 && printf '.'; }

echo "Uploading..."
list_all | while IFS= read -r f; do m="$(stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f" 2>/dev/null)"; [ -n "$m" ] && printf '%s\t%s\n' "$m" "$f"; done \
  | sort -rn | head -n "$LIMIT" | cut -f2- | ( i=0; while IFS= read -r f; do send "$(sid_for "$f")" "$f" &  i=$((i+1)); [ $((i % 6)) -eq 0 ] && wait; done; wait )

echo ""
echo "Done — your chats are uploading in the background and will become notes within a little while."
echo "Check back later at usebrainstack.com, or just ask your AI to \"search my brain\"."
