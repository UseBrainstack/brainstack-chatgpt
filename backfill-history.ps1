# Brainstack — one-time backfill of your existing local chats (WINDOWS).
# Sends past Claude Code, Cowork, and Codex/ChatGPT-work sessions to Brainstack.
# Run in PowerShell after installing a Brainstack plugin and signing in once.
# Safe to re-run (the server skips anything it already has).
# (macOS/Linux use backfill-history.sh.)
$ErrorActionPreference = "SilentlyContinue"
$UP = $env:USERPROFILE

# 1) Locate the Brainstack binary (bsb.exe / vgb.exe).
$cands = @("$UP\.brainstack\bin\bsb.exe")
$cands += (Get-ChildItem "$UP\.codex\plugins\cache\*brainstack*\*\*\runtime\vgb.exe" -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | ForEach-Object FullName)
$cands += (Get-ChildItem "$UP\.claude*\plugins\cache\*brainstack*\*\*\runtime\vgb.exe" -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | ForEach-Object FullName)
$bsb = $cands | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $bsb) { Write-Host "Couldn't find the Brainstack binary. Install a plugin and sign in first."; exit 1 }

# 2) Endpoint self-location: point CLAUDE_PLUGIN_ROOT at the dir holding .mcp.json.
$root = Split-Path (Split-Path $bsb)
if (-not (Test-Path "$root\.mcp.json")) { $root = "$UP\.brainstack" }
if (-not (Test-Path "$root\.mcp.json")) { Write-Host "Run the connector once (sign in) first."; exit 1 }
$env:CLAUDE_PLUGIN_ROOT = $root

$homeFwd = $UP -replace '\\','/'
$script:sent = 0
function Send-Session($id, $path) {
  if (-not $id -or -not (Test-Path $path)) { return }
  if ((Get-Item $path).Length -eq 0) { return }
  $p = ($path -replace '\\','/')
  $payload = '{"session_id":"' + $id + '","transcript_path":"' + $p + '","hook_event_name":"Stop","cwd":"' + $homeFwd + '"}'
  $payload | & $bsb hook session-end 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) { $script:sent++; Write-Host -NoNewline "." }
}

Write-Host "Sending your past chats to Brainstack (this can take a minute)..."

# Claude Code: %USERPROFILE%\.claude\projects\<proj>\<uuid>.jsonl
Get-ChildItem "$UP\.claude\projects" -Recurse -Filter *.jsonl -EA SilentlyContinue | ForEach-Object {
  Send-Session ([System.IO.Path]::GetFileNameWithoutExtension($_.Name)) $_.FullName
}
# Cowork: %APPDATA%\Claude\local-agent-mode-sessions\**\local_<uuid>\audit.jsonl  (path UNVERIFIED on Windows)
Get-ChildItem "$env:APPDATA\Claude\local-agent-mode-sessions" -Recurse -Filter audit.jsonl -EA SilentlyContinue | ForEach-Object {
  $d = Split-Path $_.DirectoryName -Leaf
  Send-Session ($d -replace '^local_','') $_.FullName
}
# Codex: %USERPROFILE%\.codex\sessions|archived_sessions\**\rollout-*-<uuid>.jsonl
Get-ChildItem "$UP\.codex\sessions","$UP\.codex\archived_sessions" -Recurse -Filter rollout-*.jsonl -EA SilentlyContinue | ForEach-Object {
  if ($_.BaseName -match '([0-9a-fA-F-]{36})$') { Send-Session $Matches[1] $_.FullName }
}

Write-Host ""
Write-Host "Done - sent $($script:sent) past session(s). They'll become notes in the background."
