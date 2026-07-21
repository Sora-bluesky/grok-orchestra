#requires -Version 5.1
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('acquire', 'check', 'release')]
  [string] $Action,
  [string] $JobId = '',
  [string[]] $OwnedPaths = @(),
  [string] $Type = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$lockDir = Join-Path $repoRoot '.agents\locks'
New-Item -ItemType Directory -Force -Path $lockDir | Out-Null

function ConvertTo-OwnedPath {
  param([string] $Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { throw 'owned_paths must not contain empty paths.' }
  if ([System.IO.Path]::IsPathRooted($Path)) { throw "owned_paths must be repo-relative: $Path" }
  $normalized = $Path.Trim().Replace('\', '/').TrimStart('.', '/')
  if (-not $normalized -or $normalized -eq '..' -or $normalized.StartsWith('../')) {
    throw "owned_paths must stay inside the repository: $Path"
  }
  return $normalized.TrimEnd('/').ToLowerInvariant()
}

function Test-PathOverlap {
  param([string] $Left, [string] $Right)
  return $Left -eq $Right -or
    $Left.StartsWith($Right + '/', [System.StringComparison]::OrdinalIgnoreCase) -or
    $Right.StartsWith($Left + '/', [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-RunningLeases {
  $leases = @()
  foreach ($file in Get-ChildItem -LiteralPath $lockDir -Filter '*.lease.json' -File -ErrorAction SilentlyContinue) {
    try {
      $lease = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($lease.status -eq 'running') { $leases += $lease }
    }
    catch { throw "Invalid lease file: $($file.FullName). $($_.Exception.Message)" }
  }
  return $leases
}

function Find-Overlaps {
  param([string[]] $Requested)
  $hits = @()
  foreach ($lease in Get-RunningLeases) {
    foreach ($requestedPath in $Requested) {
      foreach ($leasedPathValue in @($lease.owned_paths)) {
        $leasedPath = ConvertTo-OwnedPath $leasedPathValue
        if (Test-PathOverlap $requestedPath $leasedPath) {
          $hits += [pscustomobject]@{ job_id = $lease.job_id; requested = $requestedPath; leased = $leasedPath }
        }
      }
    }
  }
  return @($hits)
}

if ($Action -in @('acquire', 'check') -and $OwnedPaths.Count -eq 0) {
  throw '-OwnedPaths is required for acquire and check.'
}
if ($Action -in @('acquire', 'release') -and [string]::IsNullOrWhiteSpace($JobId)) {
  throw '-JobId is required for acquire and release.'
}
if ($JobId -and $JobId -notmatch '^[A-Za-z0-9._-]+$') { throw "Invalid JobId: $JobId" }

$normalizedPaths = @($OwnedPaths | ForEach-Object { ConvertTo-OwnedPath $_ } | Select-Object -Unique)

switch ($Action) {
  'check' {
    $overlaps = @(Find-Overlaps $normalizedPaths)
    if ($overlaps.Count -gt 0) {
      foreach ($hit in $overlaps) {
        Write-Host "overlap: job=$($hit.job_id) requested=$($hit.requested) leased=$($hit.leased)"
      }
      exit 1
    }
    Write-Host 'lease check: free'
    exit 0
  }
  'acquire' {
    $overlaps = @(Find-Overlaps $normalizedPaths)
    if ($overlaps.Count -gt 0) {
      $jobIds = @($overlaps | ForEach-Object { $_.job_id } | Select-Object -Unique)
      throw "lease overlap; refuse acquire for job '$JobId'; running jobs: $($jobIds -join ', ')"
    }
    $leasePath = Join-Path $lockDir "$JobId.lease.json"
    $lease = [ordered]@{
      job_id = $JobId
      owned_paths = $normalizedPaths
      status = 'running'
      acquired_at = (Get-Date -Format o)
    }
    if ($Type) { $lease.type = $Type }
    $lease | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $leasePath -Encoding UTF8
    Write-Host "lease acquired: job=$JobId"
    exit 0
  }
  'release' {
    $leasePath = Join-Path $lockDir "$JobId.lease.json"
    if (-not (Test-Path -LiteralPath $leasePath)) {
      Write-Host "lease release: no lease for job=$JobId"
      exit 0
    }
    $lease = Get-Content -LiteralPath $leasePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $lease.status = 'released'
    $lease | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $leasePath -Encoding UTF8
    Write-Host "lease released: job=$JobId"
    exit 0
  }
}
