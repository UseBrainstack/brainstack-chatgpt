# Brainstack — wire up automatic capture for Codex / ChatGPT-work (WINDOWS).
# Run once in PowerShell after installing the Brainstack plugin in the ChatGPT
# app and signing in. Safe to re-run. (macOS/Linux use install-codex-capture.sh.)
$ErrorActionPreference = "Stop"
$UP = $env:USERPROFILE

# 1) Locate the plugin binary (vgb.exe).
$bsb = Get-ChildItem "$UP\.codex\plugins\cache\*brainstack*\*\*\runtime\vgb.exe" -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $bsb) {
  Write-Host "Couldn't find the Brainstack plugin binary. Install the plugin first:"
  Write-Host "  codex plugin marketplace add UseBrainstack/brainstack-chatgpt"
  Write-Host "  codex plugin add brainstack@brainstack-chatgpt"
  exit 1
}

# 2) Copy to a stable path + place a co-located .mcp.json (endpoint self-location).
#    Forward slashes avoid JSON backslash-escaping and work fine for Go on Windows.
$bsDir = "$UP\.brainstack"
New-Item -ItemType Directory -Force -Path "$bsDir\bin" | Out-Null
Copy-Item $bsb.FullName "$bsDir\bin\bsb.exe" -Force
$stable = ("$bsDir\bin\bsb.exe") -replace '\\','/'
$pluginDir = Split-Path (Split-Path $bsb.FullName)
if (Test-Path "$pluginDir\.mcp.json") { Copy-Item "$pluginDir\.mcp.json" "$bsDir\.mcp.json" -Force }
else { '{ "mcpServers": { "brainstack": { "command": "./bin/bsb.exe", "args": ["connect","https://usebrainstack.com/mcp"] } } }' | Set-Content "$bsDir\.mcp.json" -Encoding UTF8 }

# 3) Write the capture hooks into the GLOBAL ~/.codex/hooks.json (back up first).
$codex = "$UP\.codex"
New-Item -ItemType Directory -Force -Path $codex | Out-Null
$hooksPath = "$codex\hooks.json"
if (Test-Path $hooksPath) { Copy-Item $hooksPath "$hooksPath.bak-$([int](Get-Date -UFormat %s))" -Force }
$hooks = @"
{
  "hooks": {
    "SessionStart": [ { "hooks": [
      { "type": "command", "command": "$stable hook session-start", "timeout": 10 },
      { "type": "command", "command": "$stable hook session-catchup", "timeout": 30 }
    ] } ],
    "Stop": [ { "hooks": [
      { "type": "command", "command": "$stable hook session-end", "timeout": 30 }
    ] } ]
  }
}
"@
$hooks | Set-Content -Encoding UTF8 $hooksPath

Write-Host "Done. Brainstack capture is wired for Codex on Windows."
Write-Host "  - Restart the ChatGPT app, then Settings > Hooks > User config > Trust the 3 hooks."
Write-Host "  - Sign in to Brainstack when the browser opens (first connector use)."
Write-Host "  - Coding sessions then capture automatically."
