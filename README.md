# Brainstack — ChatGPT / Codex plugin (macOS + Windows)

One Codex plugin, one native binary, both OSes. It provides the Brainstack
connector (query your brain) **and** the automatic capture hooks for your local
Codex / ChatGPT-work sessions — no Node required.

This is the ChatGPT/Codex counterpart to
[`brainstack-claude`](https://github.com/UseBrainstack/brainstack-claude) (the
Claude Code version). Same `vgb` binary, same OAuth, same
`https://usebrainstack.com/mcp` endpoint — re-shaped for the Codex plugin system
that the ChatGPT desktop app uses.

## Install

```
codex plugin marketplace add UseBrainstack/brainstack-chatgpt
codex plugin add brainstack@brainstack-chatgpt
```

Restart the Codex CLI / ChatGPT desktop app, approve the hooks once, and sign in
to usebrainstack.com when prompted (secret-less OAuth; the token is stored at
`~/.vgb/token.json` and auto-renews). From then on your local sessions capture
automatically.

## Backfill your old chats (optional, one-time)

After installing and signing in once:

```
bash backfill-old-chats.sh
```

This sends your past Codex / ChatGPT-work rollout transcripts
(`~/.codex/sessions` + `~/.codex/archived_sessions`) to Brainstack. Plain
ChatGPT chats (the app's own thread history) are **save-on-ask** by design and
are not scraped.

## What's in here

```
.agents/plugins/marketplace.json          Codex marketplace manifest
plugins/brainstack/
  .codex-plugin/plugin.json               Codex plugin manifest
  .mcp.json                               connector -> https://usebrainstack.com/mcp
  hooks.json                              capture hooks (SessionStart / Stop / PreCompact)
  runtime/vgb                             Mac universal binary (arm64 + x86_64)
  runtime/vgb.exe                         Windows binary
backfill-old-chats.sh                     one-time Codex history backfill
GENERATED_FROM                            provenance
```

## ⚠ Assumptions to verify live (undocumented Codex behavior)

This scaffold matches the Codex plugin/hook schema found on the build machine,
but three things could only be confirmed by running it against a live Codex /
ChatGPT desktop app. Verify before shipping to customers:

1. **Does the ChatGPT *desktop app* fire `~/.codex` hooks?** The Codex *CLI*
   demonstrably does (there are working Brainstack hooks in `~/.codex/hooks.json`
   on this machine). Whether the packaged **ChatGPT desktop app** runs the same
   hook engine is undocumented — test a real desktop-app session and confirm a
   note lands.
2. **Are plugin-bundled `hooks.json` files honored (not just the global
   `~/.codex/hooks.json`)?** The codex binary references plugin-relative hooks
   (`./hooks.json`, `hook.scope`, `hook.source`) and a real plugin (figma) ships
   one, so this is expected to work — but confirm the plugin's hooks actually
   fire after `codex plugin add`. If they do **not**, fall back to merging the
   three hook entries into `~/.codex/hooks.json` by hand (see below).
3. **Does `Stop` deliver `session_id` + `transcript_path` to `vgb`?** The
   installed Codex capture hook reads exactly those fields from the `Stop`
   payload, so `vgb hook session-end` should get what it needs. Confirm capture
   works end-to-end (not just that the hook runs). `Stop` fires once per
   assistant turn — that is intended: `vgb` does incremental, cursor-based delta
   ingest, so per-turn firing is correct, not duplicative.

### Fallback if plugin-bundled hooks are ignored

Add these to `~/.codex/hooks.json` (point the command at the installed binary,
e.g. `~/.codex/plugins/cache/brainstack-chatgpt/brainstack/<version>/runtime/vgb`):

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [
        { "type": "command", "command": "<abs>/runtime/vgb hook session-start", "timeout": 10 },
        { "type": "command", "command": "<abs>/runtime/vgb hook session-catchup", "timeout": 30 }
      ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "<abs>/runtime/vgb hook session-end", "timeout": 30 } ] }
    ]
  }
}
```

### Notes

- The connector (MCP) half is the lower-risk path: Codex stdio MCP plugins are
  well-supported, so `codex plugin add` should give you the six Brainstack tools
  regardless of the hook questions above.
- `authentication` is set to `ON_USE` (vgb does its own OAuth on first connect).
  If Codex should instead prompt sign-in at install time, switch it to
  `ON_INSTALL` in `.agents/plugins/marketplace.json`.
