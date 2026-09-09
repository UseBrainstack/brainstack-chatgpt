# Brainstack — import your existing local AI chats (WINDOWS, PowerShell).
# Self-contained: downloads a tiny uploader to a temp folder, signs you in,
# uploads your chosen chats, then DELETES ITSELF. Nothing is installed.
$ErrorActionPreference = "Stop"
$REAL = $env:USERPROFILE
$WORK = Join-Path ([System.IO.Path]::GetTempPath()) ("bs-import-" + [System.Guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Force -Path (Join-Path $WORK "bin"), (Join-Path $WORK ".vgb") | Out-Null

try {
  Write-Host "Setting up (nothing is installed — this removes itself when done)..."

  # 1) Download the uploader + clear the "downloaded from the internet" flag.
  $BSB = Join-Path $WORK "bin\vgb.exe"
  Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/UseBrainstack/brainstack-chatgpt/main/plugins/brainstack/runtime/vgb.exe" -OutFile $BSB
  Unblock-File $BSB -ErrorAction SilentlyContinue

  # 2) Endpoint config.
  '{ "mcpServers": { "brainstack": { "command": "./bin/vgb.exe", "args": ["connect","https://usebrainstack.com/mcp"] } } }' | Set-Content (Join-Path $WORK ".mcp.json") -Encoding UTF8
  $env:CLAUDE_PLUGIN_ROOT = $WORK
  $env:USERPROFILE = $WORK   # keep the sign-in token inside the temp folder → deleted on cleanup

  # 3) Sign in — reuse existing if present, else open the browser.
  $realTok = Join-Path $REAL ".vgb\token.json"
  $tok = Join-Path $WORK ".vgb\token.json"
  if (Test-Path $realTok) { Copy-Item $realTok $tok -Force }
  if (-not (Test-Path $tok)) {
    Write-Host "A browser window will open — sign in with your work email to Brainstack."
    $init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"import","version":"1"}}}'
    $p = Start-Process -FilePath $BSB -ArgumentList @("connect","https://usebrainstack.com/mcp") -PassThru -RedirectStandardInput ([System.IO.Path]::GetTempFileName()) -WindowStyle Hidden
    $init | & $BSB connect "https://usebrainstack.com/mcp" 2>$null | Out-Null   # nudge auth
    for ($i=0; $i -lt 90 -and -not (Test-Path $tok); $i++) { Start-Sleep -Seconds 2 }
    if ($p -and -not $p.HasExited) { $p.Kill() }
  }
  if (-not (Test-Path $tok)) { Write-Host "Sign-in didn't finish — re-run when you're ready."; return }
  Write-Host "Signed in."

  # 4) Find your chats (from your real home).
  $claude = @()
  $claude += Get-ChildItem "$REAL\.claude\projects" -Recurse -Filter *.jsonl -EA SilentlyContinue
  $claude += Get-ChildItem "$env:APPDATA\Claude\local-agent-mode-sessions" -Recurse -Filter audit.jsonl -EA SilentlyContinue
  $codex  = Get-ChildItem "$REAL\.codex\sessions","$REAL\.codex\archived_sessions" -Recurse -Filter rollout-*.jsonl -EA SilentlyContinue
  $all = @($claude) + @($codex) | Sort-Object LastWriteTime -Descending
  $total = $all.Count
  if ($total -eq 0) { Write-Host "No local chats found on this computer. Nothing to import."; return }
  $allmin = [Math]::Max(1, [Math]::Ceiling($total*3/60))

  Write-Host ""
  Write-Host ("Found on this computer:  {0} Claude chats  ·  {1} Codex/ChatGPT chats  ·  {2} total" -f $claude.Count, $codex.Count, $total)
  Write-Host ""
  Write-Host "  [1] Upload the 15 most recent   (~1 min)"
  Write-Host ("  [2] Upload everything           (~{0} min)" -f $allmin)
  Write-Host "  [3] Skip"
  $choice = Read-Host "Choose [1/2/3]"
  switch ($choice) { "1" { $limit = 15 } "2" { $limit = $total } default { Write-Host "Skipped."; return } }

  # 5) Upload the newest $limit sessions.
  function Get-Sid($f) {
    if ($f.FullName -match "\\.claude\\projects\\")       { return [System.IO.Path]::GetFileNameWithoutExtension($f.Name) }
    if ($f.FullName -match "local-agent-mode-sessions")   { return (Split-Path $f.DirectoryName -Leaf) -replace '^local_','' }
    if ($f.BaseName -match '([0-9a-fA-F-]{36})$')         { return $Matches[1] }
    return [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
  }
  $realFwd = $REAL -replace '\\','/'
  Write-Host "Uploading..."
  foreach ($f in ($all | Select-Object -First $limit)) {
    if ($f.Length -eq 0) { continue }
    $sid = Get-Sid $f
    $pth = ($f.FullName -replace '\\','/')
    $payload = '{"session_id":"' + $sid + '","transcript_path":"' + $pth + '","hook_event_name":"Stop","cwd":"' + $realFwd + '"}'
    $payload | & $BSB hook session-end 2>$null | Out-Null
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
