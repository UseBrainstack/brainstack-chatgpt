# Brainstack — ChatGPT / Codex plugin (macOS + Windows)

One Codex plugin, one native binary, both OSes. It provides the **Brainstack MCP
connector** so your AI can save durable takeaways to your brain and search it
back — no Node required.

This is the ChatGPT/Codex counterpart to
[`brainstack-claude`](https://github.com/UseBrainstack/brainstack-claude) (the
Claude Code version). Same `bsb` binary, same OAuth, same
`https://usebrainstack.com/mcp` endpoint — re-shaped for the Codex plugin system
that the ChatGPT desktop app uses.

## Install

```
codex plugin marketplace add UseBrainstack/brainstack-chatgpt
codex plugin add brainstack@brainstack-chatgpt
```

Restart the Codex CLI / ChatGPT desktop app and sign in to usebrainstack.com when
prompted (secret-less OAuth; the token is stored at `~/.brainstack/token.json`).
That's the whole setup — **no hooks to approve, nothing installed system-wide.**

## Capture is MCP-driven (no local hooks)

There are no local capture hooks. Capture happens over the connector: your AI
files durable takeaways when you ask it to ("save this to the brain") and at the
end of a substantive session. **Everything lands private by default** — you
decide, in the moment or later in the web app, what to share and with whom.
Deterministic auto-capture is a Compliance-API (Enterprise) feature.

## Backfill your old chats (optional, one-time)

To pull your existing local history into your brain in one shot, run:

```
curl -fsSL "https://raw.githubusercontent.com/UseBrainstack/brainstack-chatgpt/main/import-old-chats.sh?cb=$RANDOM" | bash
```

Windows (PowerShell):

```
irm "https://raw.githubusercontent.com/UseBrainstack/brainstack-chatgpt/main/import-old-chats.ps1?cb=$(Get-Random)" | iex
```

It signs you in, scans your local Claude Code / Cowork / Codex transcripts, lets
you choose how many to bring in, uploads them, and deletes itself. Nothing is
installed.

## What's in here

```
.agents/plugins/marketplace.json          Codex marketplace manifest
plugins/brainstack/
  .codex-plugin/plugin.json               Codex plugin manifest (connector only)
  .mcp.json                               connector -> https://usebrainstack.com/mcp
  runtime/bsb                             Mac universal binary (arm64 + x86_64)
  runtime/bsb.exe                         Windows binary
import-old-chats.sh / .ps1                one-time history backfill (Mac / Windows)
GENERATED_FROM                            provenance
```

## Notes

- `authentication` is `ON_USE` — `bsb` does its own OAuth on first connect.
- The `bsb` binary has two verbs the connector/importer use: `bsb connect <url>`
  (the MCP stdio bridge) and `bsb login <url>` / `bsb ingest` (used by the
  one-time importer). There is no capture-hook verb — capture is MCP-driven.
