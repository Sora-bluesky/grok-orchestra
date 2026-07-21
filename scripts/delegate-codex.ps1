#requires -Version 5.1
<#
.SYNOPSIS
  Delegate a job to Codex CLI (headless) with L0 single-writer guard.

.PARAMETER JobId
  Stable id used for log/result filenames.

.PARAMETER Type
  review|design|investigate|implement|fix

.PARAMETER PromptFile
  Path to Prompt Contract body (required fields checked lightly).

.PARAMETER RepoRoot
  Working directory for codex -C (default: repo root of this script).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string] $JobId,

  [Parameter(Mandatory = $true)]
  [ValidateSet('review', 'design', 'investigate', 'implement', 'fix')]
  [string] $Type,

  [Parameter(Mandatory = $true)]
  [string] $PromptFile,

  [string] $RepoRoot = ''
)

$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
  if ($RepoRoot) { return (Resolve-Path $RepoRoot).Path }
  return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Test-PromptContract {
  param([string] $Text)
  $required = @('## Objective', '## Constraints', '## Relevant files', '## Acceptance checks', '## Output format')
  $missing = @()
  foreach ($h in $required) {
    if ($Text -notmatch [regex]::Escape($h)) { $missing += $h }
  }
  return $missing
}

function Resolve-CodexNodeInvocation {
  # Prefer direct node + codex.js (avoids npm shim stderr quirks).
  $npmCodex = Join-Path $env:APPDATA 'npm\node_modules\@openai\codex\bin\codex.js'
  if (Test-Path -LiteralPath $npmCodex) {
    return @{ Exe = 'node'; ArgsPrefix = @($npmCodex) }
  }
  return @{ Exe = 'codex'; ArgsPrefix = @() }
}

$root = Get-RepoRoot
Set-Location $root

$promptPath = if ([System.IO.Path]::IsPathRooted($PromptFile)) { $PromptFile } else { Join-Path $root $PromptFile }
if (-not (Test-Path -LiteralPath $promptPath)) {
  Write-Error "Prompt file not found: $promptPath"
}

$promptText = Get-Content -LiteralPath $promptPath -Raw -Encoding UTF8
$missing = Test-PromptContract -Text $promptText
if ($missing.Count -gt 0) {
  Write-Error ("Prompt Contract incomplete. Missing: {0}" -f ($missing -join ', '))
}

$lockDir = Join-Path $root '.agents\locks'
New-Item -ItemType Directory -Force -Path $lockDir | Out-Null
$writeLock = Join-Path $lockDir 'write-job.lock'
$isWrite = $Type -in @('implement', 'fix')

if ($isWrite) {
  if (Test-Path -LiteralPath $writeLock) {
    $existing = Get-Content -LiteralPath $writeLock -Raw -ErrorAction SilentlyContinue
    Write-Error "L0 single-writer: another write job is running.`n$existing`nRemove $writeLock only if stale."
  }
  @"
job_id=$JobId
type=$Type
started=$(Get-Date -Format o)
"@ | Set-Content -LiteralPath $writeLock -Encoding UTF8
}

$sandbox = if ($isWrite) { 'workspace-write' } else { 'read-only' }

$logDir = Join-Path $root '.agents\logs\codex'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$outLast = Join-Path $logDir "$JobId.last.txt"
$outErr = Join-Path $logDir "$JobId.stderr.log"
$outCombined = Join-Path $logDir "$JobId.combined.log"

Write-Host "delegate-codex: job=$JobId type=$Type sandbox=$sandbox cwd=$root"

$inv = Resolve-CodexNodeInvocation
$argList = @()
$argList += $inv.ArgsPrefix
if ($inv.ArgsPrefix.Count -eq 0) {
  $argList += 'exec'
} else {
  $argList += 'exec'
}
$argList += @('-C', $root, '-s', $sandbox, '-o', $outLast)

try {
  $env:NO_COLOR = '1'
  # Capture all streams; do not use 2> file redirect with ErrorAction Stop
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $output = $promptText | & $inv.Exe @argList 2>&1
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prevEap

  $text = ($output | ForEach-Object { "$_" }) -join [Environment]::NewLine
  Set-Content -LiteralPath $outCombined -Value $text -Encoding UTF8

  if ($code -ne 0) {
    Set-Content -LiteralPath $outErr -Value $text -Encoding UTF8
    Write-Error "codex exec failed with exit $code. See $outCombined"
  }

  if (-not (Test-Path -LiteralPath $outLast) -or ((Get-Item -LiteralPath $outLast).Length -eq 0)) {
    # Fall back: write combined output as last message if -o empty
    if ($text.Trim().Length -gt 0) {
      Set-Content -LiteralPath $outLast -Value $text -Encoding UTF8
    } else {
      Write-Error "codex exec exit 0 but empty last message: $outLast"
    }
  }

  Write-Host "OK: wrote $outLast"
  exit 0
}
finally {
  if ($isWrite -and (Test-Path -LiteralPath $writeLock)) {
    $lockContent = Get-Content -LiteralPath $writeLock -Raw -ErrorAction SilentlyContinue
    if ($lockContent -match [regex]::Escape("job_id=$JobId")) {
      Remove-Item -LiteralPath $writeLock -Force -ErrorAction SilentlyContinue
    }
  }
}
