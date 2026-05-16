# Caveman skill installer for Claude Code (Windows PowerShell)
#
# Usage:
#   iwr -useb https://raw.githubusercontent.com/aliaksei-hlazkou/agentic-sdlc/master/caveman/install.ps1 | iex
#
# Or with parameters (non-interactive):
#   $script = iwr -useb https://raw.githubusercontent.com/aliaksei-hlazkou/agentic-sdlc/master/caveman/install.ps1
#   & ([scriptblock]::Create($script)) -Scope user
#   & ([scriptblock]::Create($script)) -Scope project -ProjectPath C:\my\repo

param(
  [ValidateSet('user','project','')]
  [string]$Scope = '',
  [string]$ProjectPath = ''
)

$ErrorActionPreference = 'Stop'

$RepoRaw  = 'https://raw.githubusercontent.com/aliaksei-hlazkou/agentic-sdlc/master/caveman'
$SkillUrl = "$RepoRaw/SKILL.md"
$RelPath  = '.claude\skills\productivity\caveman\SKILL.md'

function Info($msg)  { Write-Host $msg -ForegroundColor White }
function Ok($msg)    { Write-Host "[OK] $msg" -ForegroundColor Green }
function Warn($msg)  { Write-Host "[!]  $msg" -ForegroundColor Yellow }
function Fail($msg)  { Write-Host "[X]  $msg" -ForegroundColor Red; exit 1 }

if (-not $Scope) {
  Write-Host "Install scope?"
  Write-Host "  1) user    (`$env:USERPROFILE\.claude\skills) — default"
  Write-Host "  2) project (.\.claude\skills)"
  $choice = Read-Host "Choice [1]"
  if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }
  switch ($choice) {
    '1'       { $Scope = 'user' }
    'u'       { $Scope = 'user' }
    'user'    { $Scope = 'user' }
    '2'       { $Scope = 'project' }
    'p'       { $Scope = 'project' }
    'project' { $Scope = 'project' }
    default   { Fail "invalid choice: $choice" }
  }
}

switch ($Scope) {
  'user'    { $base = $env:USERPROFILE }
  'project' { if ($ProjectPath) { $base = $ProjectPath } else { $base = (Get-Location).Path } }
}

$dest    = Join-Path $base $RelPath
$destDir = Split-Path $dest -Parent

if (-not (Test-Path $base)) { Fail "target base does not exist: $base" }

Info "Installing caveman skill (scope: $Scope)"
Info "  target: $dest"

if (Test-Path $dest) {
  $ts  = Get-Date -Format 'yyyyMMdd-HHmmss'
  $bak = "$dest.bak.$ts"
  Copy-Item -LiteralPath $dest -Destination $bak -Force
  Ok "backed up existing SKILL.md -> $bak"
}

New-Item -ItemType Directory -Path $destDir -Force | Out-Null
try {
  Invoke-WebRequest -UseBasicParsing -Uri $SkillUrl -OutFile $dest
} catch {
  Fail "download failed from $SkillUrl ($($_.Exception.Message))"
}
Ok "installed -> $dest"

Write-Host ""
Write-Host "Done. Restart Claude Code (or start a new session) to activate." -ForegroundColor White
Write-Host "To trigger: say `"caveman mode`" in any session." -ForegroundColor DarkGray
