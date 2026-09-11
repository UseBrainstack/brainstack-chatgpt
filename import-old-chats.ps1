# Brainstack — import your existing local AI chats (WINDOWS, PowerShell).
# Self-contained: downloads a tiny uploader to a temp folder, signs you in,
# uploads your chosen chats, then DELETES ITSELF. Nothing is installed.
$ErrorActionPreference = "Stop"
$REAL = $env:USERPROFILE
$WORK = Join-Path ([System.IO.Path]::GetTempPath()) ("bs-import-" + [System.Guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Force -Path (Join-Path $WORK "bin"), (Join-Path $WORK ".bsb") | Out-Null

try {
  Write-Host "Setting up (nothing is installed — this removes itself when done)..."

  # 1) Download the uploader + clear the "downloaded from the internet" flag.
  $BSB = Join-Path $WORK "bin\bsb.exe"
  Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/UseBrainstack/brainstack-chatgpt/main/plugins/brainstack/runtime/bsb.exe" -OutFile $BSB
  Unblock-File $BSB -ErrorAction SilentlyContinue

  # 2) Endpoint config. Write WITHOUT a BOM: Windows PowerShell 5.1
  # `Set-Content -Encoding UTF8` prepends a UTF-8 BOM, and the binary's JSON
  # parser rejects a leading BOM — which silently zeroed out the endpoint and
  # made every upload a no-op (sign-in still worked, so it looked fine). The
  # .NET writer with UTF8Encoding($false) guarantees no BOM on 5.1 and 7+.
  [System.IO.File]::WriteAllText((Join-Path $WORK ".mcp.json"), '{ "mcpServers": { "brainstack": { "command": "./bin/bsb.exe", "args": ["connect","https://usebrainstack.com/mcp"] } } }', (New-Object System.Text.UTF8Encoding($false)))
  $env:CLAUDE_PLUGIN_ROOT = $WORK
  $env:USERPROFILE = $WORK   # keep the sign-in token inside the temp folder → deleted on cleanup

  # 3) Sign in to Brainstack — always a fresh browser sign-in via `bsb login`
  #    (no token reuse, so it targets the RIGHT account — not whatever was cached
  #    on this machine). USERPROFILE is the temp folder, so the token lands there
  #    and is deleted on exit. `login` runs the whole OAuth handshake itself and
  #    exits — no stdin nudging, no background process to kill.
  $tok = Join-Path $WORK ".bsb\token.json"
  Write-Host "A browser window will open — sign in with your work email to Brainstack."
  Write-Host "(If it doesn't open, copy the https://usebrainstack.com/... link it prints into your browser.)"
  # Run the sign-in BARE (no 2>&1 pipe): piping a native command's stderr is what
  # produced the confusing 'System.Management.Automation.RemoteException' lines.
  # Its progress now prints cleanly; judge success by exit code + token presence.
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  & $BSB login "https://usebrainstack.com/mcp"
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  if ($code -ne 0 -or -not (Test-Path $tok)) { Write-Host "Sign-in didn't finish — re-run when you're ready."; return }
  Write-Host "Signed in.  Give it a second — finding your chats..."

  # 4) Find your chats (from your real home).
  # -Force is required: the Store-app data folders are hidden, so without it Get-ChildItem skips them.
  $claude = @()
  $claude += Get-ChildItem "$REAL\.claude\projects" -Recurse -Filter *.jsonl -Force -EA SilentlyContinue
  # Cowork (Claude desktop) — the Windows Store app redirects data into Packages\Claude_*\LocalCache\Roaming.
  $pkg = Get-ChildItem "$env:LOCALAPPDATA\Packages" -Directory -Filter "Claude_*" -Force -EA SilentlyContinue | Select-Object -First 1
  if ($pkg) { $claude += Get-ChildItem (Join-Path $pkg.FullName "LocalCache\Roaming\Claude\local-agent-mode-sessions") -Recurse -Filter audit.jsonl -Force -EA SilentlyContinue }
  $claude += Get-ChildItem "$env:APPDATA\Claude\local-agent-mode-sessions" -Recurse -Filter audit.jsonl -Force -EA SilentlyContinue
  $codex  = Get-ChildItem "$REAL\.codex\sessions","$REAL\.codex\archived_sessions" -Recurse -Filter rollout-*.jsonl -Force -EA SilentlyContinue
  $all = @($claude) + @($codex) | Sort-Object LastWriteTime -Descending
  $total = $all.Count
  if ($total -eq 0) { Write-Host "No local chats found on this computer. Nothing to import."; return }
  $rate = 3                                                    # ~seconds per chat
  $mAll = [Math]::Max(1, [Math]::Ceiling($total*$rate/60))
  $n50  = [Math]::Min(50, $total)
  $m50  = [Math]::Max(1, [Math]::Ceiling($n50*$rate/60))

  Write-Host ""
  Write-Host ("Found on this computer:  {0} Claude chats  ·  {1} Codex/ChatGPT chats  ·  {2} total" -f $claude.Count, $codex.Count, $total)
  Write-Host ""
  Write-Host "How many of your past chats should we bring in?"
  Write-Host ""
  Write-Host ("  [1] Everything            ({0} chats, ~{1} min)   <- recommended" -f $total, $mAll)
  Write-Host ("  [2] The {0} most recent    (~{1} min)" -f $n50, $m50)
  Write-Host "  [3] The 15 most recent    (~1 min)"
  Write-Host "  [4] A custom number"
  Write-Host "  [5] Skip for now"
  Write-Host ""
  $choice = Read-Host "Choose 1-5  (press Enter for 1 = everything)"
  if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }
  switch ($choice) {
    "1" { $limit = $total }
    "2" { $limit = $n50 }
    "3" { $limit = [Math]::Min(15, $total) }
    "4" {
      $n = Read-Host "How many? (a number, e.g. 500)"
      $parsed = 0
      if ([int]::TryParse($n, [ref]$parsed) -and $parsed -gt 0) { $limit = [Math]::Min($parsed, $total) }
      else { Write-Host "That wasn't a number — nothing imported. Re-run when ready."; return }
    }
    default { Write-Host "Skipped."; return }
  }

  # 5) Upload the newest $limit sessions.
  function Get-Sid($f) {
    if ($f.FullName -match "\\.claude\\projects\\")       { return [System.IO.Path]::GetFileNameWithoutExtension($f.Name) }
    if ($f.FullName -match "local-agent-mode-sessions")   { return (Split-Path $f.DirectoryName -Leaf) -replace '^local_','' }
    if ($f.BaseName -match '([0-9a-fA-F-]{36})$')         { return $Matches[1] }
    return [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
  }
  $realFwd = $REAL -replace '\\','/'
  Write-Host "Uploading..."
  # Uploads run native bsb.exe repeatedly; keep ErrorAction on Continue so a hook's
  # stderr chatter can't abort the batch (hook always exits 0 anyway).
  $ErrorActionPreference = 'Continue'
  foreach ($f in ($all | Select-Object -First $limit)) {
    if ($f.Length -eq 0) { continue }
    $sid = Get-Sid $f
    $pth = ($f.FullName -replace '\\','/')
    $payload = '{"session_id":"' + $sid + '","transcript_path":"' + $pth + '","hook_event_name":"Stop","cwd":"' + $realFwd + '"}'
    $payload | & $BSB ingest 2>$null | Out-Null
    Write-Host -NoNewline "."
  }
  Write-Host ""
  Write-Host "Done — your chats are uploading in the background and will become notes within a little while."
  Write-Host "Check back later at usebrainstack.com, or just ask your AI to `"search my brain`"."
}
finally {
  $env:USERPROFILE = $REAL
  Remove-Item $WORK -Recurse -Force -ErrorAction SilentlyContinue
}
