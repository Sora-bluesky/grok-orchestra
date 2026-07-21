#requires -Version 5.1
<#
.SYNOPSIS
  Install grok-orchestra harness files into another project tree (init skill mechanized).

.PARAMETER Target
  Existing directory that will receive the harness (must not be this repository root).

.PARAMETER Force
  Only path that overwrites existing target files.

.PARAMETER DryRun
  Enumerate planned writes without creating or modifying any files.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string] $Target,

  [switch] $Force,

  [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

function Write-InstallInfo {
  param([string] $Message)
  Write-Host $Message
}

function Get-SourceRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Test-SamePath {
  param([string] $Left, [string] $Right)
  $l = [System.IO.Path]::GetFullPath($Left).TrimEnd('\', '/').ToLowerInvariant()
  $r = [System.IO.Path]::GetFullPath($Right).TrimEnd('\', '/').ToLowerInvariant()
  return $l -eq $r
}

function Get-OrchestraGitignoreBlock {
  return @'
# --- grok-orchestra begin ---
# Secrets & env
.env
.env.*
!.env.example
*.pem
auth.json

# Local workspace session files (not published)
PROGRESS.md
.agents/STATE.md
HANDOFF.md

# Orchestra runtime
.agents/logs/codex/*.last.txt
.agents/logs/codex/*.stderr.log
.agents/logs/codex/*.combined.log
.agents/logs/codex/*.jsonl
.agents/worktrees/
.agents/locks/write-job.lock
.agents/locks/*.lease.json
.agents/locks/leases.json

# Keep structure
!.agents/logs/codex/.gitkeep
!.agents/worktrees/.gitkeep
!.agents/locks/.gitkeep
# --- grok-orchestra end ---
'@
}

function Get-TargetSmokePacket {
  return @'
## Objective
Review a small, target-app-owned file for clarity for a new contributor.

## Constraints
- read-only; do not modify any files
- Respond in Japanese
- Keep the whole answer under 40 lines
- Do not run network tools

## Relevant files
- TODO(target-app): replace with a real path in THIS project (do not use grok-orchestra fixtures/)
- AGENTS.md (optional skim)

## Acceptance checks
- Answer includes ## TL;DR
- Answer includes at least one concrete improvement suggestion with a sample rewrite line
- TODO(target-app): adjust checks to match the chosen file

## Output format
## TL;DR
## Analysis
## Plan
## Patch Strategy
## Validation
## Risks

## Assumptions
- Reader is an intermediate developer new to this app tree

## Unverified
- None
'@
}

function Test-ShouldExcludeAgentsPath {
  param(
    [string] $SourceRoot,
    [string] $FullPath
  )
  $rel = $FullPath.Substring($SourceRoot.Length).TrimStart('\', '/')
  $norm = $rel.Replace('\', '/')

  if ($norm -eq '.agents/STATE.md' -or $norm -eq 'agents/STATE.md') { return $true }
  if ($norm -eq '.agents/docs/packets/smoke-001.prompt.txt') { return $true }
  # Dogfooding / plan review packets from this repo — not for target apps
  if ($norm -match '^\.agents/docs/packets/plan-.*\.prompt\.txt$') { return $true }
  # Live / local-only runtime trees (never ship into another app)
  if ($norm -match '^\.agents/worktrees(/|$)') { return $true }

  # logs/locks: keep only .gitkeep
  if ($norm -match '^\.agents/(logs|locks)(/|$)') {
    if ($norm -match '/\.gitkeep$' -or $norm -eq '.agents/logs/.gitkeep' -or $norm -eq '.agents/locks/.gitkeep') {
      return $false
    }
    # directory entries handled by file enumeration; skip non-gitkeep files
    if ($norm -match '^\.agents/(logs|locks)$') { return $false }
    return $true
  }
  return $false
}

function Copy-FileSafe {
  param(
    [string] $SourceFile,
    [string] $DestFile,
    [string] $Label,
    [ref] $Copied,
    [ref] $Skipped
  )
  if ($DryRun) {
    if ((Test-Path -LiteralPath $DestFile) -and -not $Force) {
      Write-InstallInfo "[dry-run][skip] exists: $Label"
      $Skipped.Value++
    }
    else {
      Write-InstallInfo "[dry-run][write] $Label"
      $Copied.Value++
    }
    return
  }

  $destDir = Split-Path -Parent $DestFile
  if (-not (Test-Path -LiteralPath $destDir)) {
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  }

  if ((Test-Path -LiteralPath $DestFile) -and -not $Force) {
    Write-InstallInfo "[skip] exists (use -Force to overwrite): $Label"
    $Skipped.Value++
    return
  }

  Copy-Item -LiteralPath $SourceFile -Destination $DestFile -Force
  Write-InstallInfo "[write] $Label"
  $Copied.Value++
}

function Write-TextSafe {
  param(
    [string] $DestFile,
    [string] $Content,
    [string] $Label,
    [ref] $Copied,
    [ref] $Skipped
  )
  if ($DryRun) {
    if ((Test-Path -LiteralPath $DestFile) -and -not $Force) {
      Write-InstallInfo "[dry-run][skip] exists: $Label"
      $Skipped.Value++
    }
    else {
      Write-InstallInfo "[dry-run][write] $Label"
      $Copied.Value++
    }
    return
  }

  $destDir = Split-Path -Parent $DestFile
  if (-not (Test-Path -LiteralPath $destDir)) {
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  }

  if ((Test-Path -LiteralPath $DestFile) -and -not $Force) {
    Write-InstallInfo "[skip] exists (use -Force to overwrite): $Label"
    $Skipped.Value++
    return
  }

  $Content | Set-Content -LiteralPath $DestFile -Encoding UTF8
  Write-InstallInfo "[write] $Label"
  $Copied.Value++
}

# --- validate ---
if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
  throw "Target must be an existing directory: $Target"
}

$sourceRoot = Get-SourceRoot
$targetRoot = (Resolve-Path -LiteralPath $Target).Path

if (Test-SamePath $sourceRoot $targetRoot) {
  throw "Target must not be this repository root: $targetRoot"
}

$copied = 0
$skipped = 0
$copiedRef = [ref]$copied
$skippedRef = [ref]$skipped

Write-InstallInfo "install.ps1: source=$sourceRoot"
Write-InstallInfo "install.ps1: target=$targetRoot"
if ($DryRun) { Write-InstallInfo 'install.ps1: DRY-RUN (no writes)' }
if ($Force) { Write-InstallInfo 'install.ps1: Force=true (existing files may be overwritten)' }

# --- 1) .agents/ tree ---
$agentsSrc = Join-Path $sourceRoot '.agents'
if (Test-Path -LiteralPath $agentsSrc) {
  $files = Get-ChildItem -LiteralPath $agentsSrc -Recurse -File -Force
  foreach ($f in $files) {
    if (Test-ShouldExcludeAgentsPath -SourceRoot $sourceRoot -FullPath $f.FullName) { continue }
    $rel = $f.FullName.Substring($sourceRoot.Length).TrimStart('\', '/')
    $dest = Join-Path $targetRoot $rel
    Copy-FileSafe -SourceFile $f.FullName -DestFile $dest -Label $rel.Replace('\', '/') -Copied $copiedRef -Skipped $skippedRef
  }
}

# --- 2) scripts ---
$scriptFiles = @(
  'scripts\delegate-codex.ps1',
  'scripts\lease-paths.ps1',
  'scripts\check.ps1',
  'scripts\verify-job.ps1',
  'scripts\lib\path-normalize.ps1'
)
foreach ($rel in $scriptFiles) {
  $src = Join-Path $sourceRoot $rel
  if (-not (Test-Path -LiteralPath $src)) {
    Write-InstallInfo "[skip] source missing: $($rel.Replace('\', '/'))"
    continue
  }
  $dest = Join-Path $targetRoot $rel
  Copy-FileSafe -SourceFile $src -DestFile $dest -Label $rel.Replace('\', '/') -Copied $copiedRef -Skipped $skippedRef
}

# --- 3) .codex / .grok ---
$codexSrc = Join-Path $sourceRoot '.codex\AGENTS.md'
if (Test-Path -LiteralPath $codexSrc) {
  Copy-FileSafe -SourceFile $codexSrc -DestFile (Join-Path $targetRoot '.codex\AGENTS.md') -Label '.codex/AGENTS.md' -Copied $copiedRef -Skipped $skippedRef
}
$grokRules = Join-Path $sourceRoot '.grok\rules'
if (Test-Path -LiteralPath $grokRules) {
  $ruleFiles = Get-ChildItem -LiteralPath $grokRules -Recurse -File -Force
  foreach ($f in $ruleFiles) {
    $rel = $f.FullName.Substring($sourceRoot.Length).TrimStart('\', '/')
    $dest = Join-Path $targetRoot $rel
    Copy-FileSafe -SourceFile $f.FullName -DestFile $dest -Label $rel.Replace('\', '/') -Copied $copiedRef -Skipped $skippedRef
  }
}

# --- 4) AGENTS.md ---
$agentsMdSrc = Join-Path $sourceRoot 'AGENTS.md'
$agentsMdDest = Join-Path $targetRoot 'AGENTS.md'
$agentsAltDest = Join-Path $targetRoot 'AGENTS.grok-orchestra.md'
if (Test-Path -LiteralPath $agentsMdSrc) {
  if ((Test-Path -LiteralPath $agentsMdDest) -and -not $Force) {
    # Never overwrite existing AGENTS.md; place proposal file instead.
    if ($DryRun) {
      if ((Test-Path -LiteralPath $agentsAltDest) -and -not $Force) {
        Write-InstallInfo '[dry-run][skip] exists: AGENTS.grok-orchestra.md'
        $skipped++
      }
      else {
        Write-InstallInfo '[dry-run][write] AGENTS.grok-orchestra.md (existing AGENTS.md preserved; merge manually)'
        $copied++
      }
    }
    else {
      if ((Test-Path -LiteralPath $agentsAltDest) -and -not $Force) {
        Write-InstallInfo '[skip] exists (use -Force to overwrite): AGENTS.grok-orchestra.md'
        $skipped++
      }
      else {
        $altDir = Split-Path -Parent $agentsAltDest
        if (-not (Test-Path -LiteralPath $altDir)) { New-Item -ItemType Directory -Force -Path $altDir | Out-Null }
        Copy-Item -LiteralPath $agentsMdSrc -Destination $agentsAltDest -Force
        Write-InstallInfo '[write] AGENTS.grok-orchestra.md'
        $copied++
      }
      Write-InstallInfo 'NOTE: existing AGENTS.md was left unchanged. Merge with AGENTS.grok-orchestra.md manually (priority: init skill).'
    }
  }
  else {
    Copy-FileSafe -SourceFile $agentsMdSrc -DestFile $agentsMdDest -Label 'AGENTS.md' -Copied $copiedRef -Skipped $skippedRef
  }
}

# --- 5) .gitignore ---
$giDest = Join-Path $targetRoot '.gitignore'
$block = Get-OrchestraGitignoreBlock
$marker = '# --- grok-orchestra begin ---'
if (-not (Test-Path -LiteralPath $giDest)) {
  Write-TextSafe -DestFile $giDest -Content $block -Label '.gitignore (new with orchestra block)' -Copied $copiedRef -Skipped $skippedRef
}
else {
  $existing = Get-Content -LiteralPath $giDest -Raw -Encoding UTF8
  if ($null -eq $existing) { $existing = '' }
  if ($existing -like "*$marker*") {
    Write-InstallInfo '[skip] .gitignore already contains grok-orchestra block'
    $skipped++
  }
  else {
    if ($DryRun) {
      Write-InstallInfo '[dry-run][append] .gitignore orchestra block'
      $copied++
    }
    else {
      # Append only — do not rewrite the whole file (preserves encoding/BOM of the prefix).
      $nl = [Environment]::NewLine
      $prefix = if ($existing.Length -eq 0 -or $existing.EndsWith("`n") -or $existing.EndsWith("`r")) { '' } else { $nl }
      $toAppend = $prefix + $nl + $block + $nl
      $utf8NoBom = New-Object System.Text.UTF8Encoding $false
      [System.IO.File]::AppendAllText($giDest, $toAppend, $utf8NoBom)
      Write-InstallInfo '[append] .gitignore orchestra block'
      $copied++
    }
  }
}

# --- 6) smoke packet (generate, never bulk-copy source) ---
$smokeDest = Join-Path $targetRoot '.agents\docs\packets\smoke-001.prompt.txt'
Write-TextSafe -DestFile $smokeDest -Content (Get-TargetSmokePacket) -Label '.agents/docs/packets/smoke-001.prompt.txt (target-specific)' -Copied $copiedRef -Skipped $skippedRef

# --- 7) next actions ---
Write-InstallInfo ''
Write-InstallInfo "install.ps1 summary: wrote/planned=$copied skipped=$skipped dryRun=$([bool]$DryRun)"
Write-InstallInfo 'Next actions:'
Write-InstallInfo '  1. cd <target>'
Write-InstallInfo '  2. Copy-Item .agents\STATE.example.md .agents\STATE.md   # seed live state (local only)'
Write-InstallInfo '  3. Edit .agents\docs\packets\smoke-001.prompt.txt (replace TODO(target-app) paths)'
Write-InstallInfo '  4. .\scripts\check.ps1'
Write-InstallInfo '  5. .\scripts\delegate-codex.ps1 -JobId smoke-001 -Type review -PromptFile .agents\docs\packets\smoke-001.prompt.txt'
Write-InstallInfo '  6. After product writes: .\scripts\verify-job.ps1 -JobId <id>  (or -SkipLog for Grok-direct)'

exit 0
