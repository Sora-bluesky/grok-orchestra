#requires -Version 5.1
<#
.SYNOPSIS
  Shared segment-based repo-relative path normalization.

.DESCRIPTION
  Preserves leading-dot path segments (e.g. .agents) and whitespace inside
  path segments (e.g. " spaced.txt"). Must NOT use TrimStart('.') character-set
  trims, and must NOT Trim() whole paths (that collapses leading spaces).

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

  if ($null -eq $Path -or $Path.Length -eq 0) {
    if ($Strict) { throw 'owned_paths must not contain empty paths.' }
    return ''
  }

  if ([System.IO.Path]::IsPathRooted($Path)) {
    if ($Strict) { throw "owned_paths must be repo-relative: $Path" }
    # Keep spaces; only normalize separators and trailing slash for comparison.
    $rooted = $Path.Replace('\', '/')
    while ($rooted.EndsWith('/') -and $rooted.Length -gt 1) {
      $rooted = $rooted.Substring(0, $rooted.Length - 1)
    }
    return $rooted.ToLowerInvariant()
  }

  # Normalize separators only. Do not Trim() the whole path (preserves " spaced").
  $normalized = $Path.Replace('\', '/')
  while ($normalized.StartsWith('./')) { $normalized = $normalized.Substring(2) }
  while ($normalized.StartsWith('/')) { $normalized = $normalized.Substring(1) }
  if ($normalized.Length -eq 0) {
    if ($Strict) { throw "owned_paths must stay inside the repository: $Path" }
    return ''
  }

  # Keep whitespace inside segments; drop only empty and '.' segments.
  $segments = @($normalized -split '/' | Where-Object { $_ -ne '' -and $_ -ne '.' })
  if ($segments.Count -eq 0 -or ($segments | Where-Object { $_ -eq '..' })) {
    if ($Strict) { throw "owned_paths must stay inside the repository: $Path" }
    return ''
  }

  return ($segments -join '/').ToLowerInvariant()
}
