#requires -Version 5.1
<#
.SYNOPSIS
  Shared segment-based repo-relative path normalization.

.DESCRIPTION
  Preserves leading-dot path segments (e.g. .agents). Must NOT use
  TrimStart('.') / TrimStart('./') character-set trims, which collapse
  ".agents/x" into "agents/x" and break owned_paths scope gates.

  Dot-sourced by lease-paths.ps1 and verify-job.ps1.
#>

function ConvertTo-NormalizedRepoPath {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string] $Path,

    # When set, throw on empty / absolute / ".." segments (lease-paths contract).
    [switch] $Strict
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    if ($Strict) { throw 'owned_paths must not contain empty paths.' }
    return ''
  }

  if ([System.IO.Path]::IsPathRooted($Path)) {
    if ($Strict) { throw "owned_paths must be repo-relative: $Path" }
    return $Path.Trim().Replace('\', '/').TrimEnd('/').ToLowerInvariant()
  }

  # Normalize separators only. Strip leading "./" prefixes as whole segments,
  # never TrimStart('.') which eats the dot of ".agents".
  $normalized = $Path.Trim().Replace('\', '/')
  while ($normalized.StartsWith('./')) { $normalized = $normalized.Substring(2) }
  $normalized = $normalized.TrimStart('/')
  if (-not $normalized) {
    if ($Strict) { throw "owned_paths must stay inside the repository: $Path" }
    return ''
  }

  $segments = @($normalized -split '/' | Where-Object { $_ -ne '' -and $_ -ne '.' })
  if ($segments.Count -eq 0 -or ($segments | Where-Object { $_ -eq '..' })) {
    if ($Strict) { throw "owned_paths must stay inside the repository: $Path" }
    return ''
  }

  return ($segments -join '/').ToLowerInvariant()
}
