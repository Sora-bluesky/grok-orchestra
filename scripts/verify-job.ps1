#requires -Version 5.1
<#
.SYNOPSIS
  Mechanical verification gate (judge only — never commit/merge/fix).
.PARAMETER JobId
  Job id used for Codex log path .agents/logs/codex/{JobId}.last.txt
.PARAMETER OwnedPaths
  Optional repo-relative path prefixes; all changed files must fall under one.
.PARAMETER BaseRef
  Optional git ref for comparison. Resolved to a commit SHA first; values starting
  with '-' are rejected (prevents git option injection such as --output=...).
.PARAMETER SkipLog
  Skip Codex log non-empty check (Grok-direct implement).
.PARAMETER AcceptTestChanges
  Explicit override for F07 test-weakening FAIL.
.PARAMETER RepoRoot
  Override repository root.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string] $JobId,

  [string[]] $OwnedPaths = @(),

  [string] $BaseRef = '',

  [switch] $SkipLog,

  [switch] $AcceptTestChanges,

  [string] $RepoRoot = ''
)

$ErrorActionPreference = 'Stop'
$script:GitFailed = $false
$script:GitFailMessages = [System.Collections.Generic.List[string]]::new()

. (Join-Path $PSScriptRoot 'lib\path-normalize.ps1')

function Get-RepoRoot {
  if ($RepoRoot) { return (Resolve-Path -LiteralPath $RepoRoot).Path }
  return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Write-Item {
  param(
    [ValidateSet('PASS', 'WARN', 'FAIL')]
    [string] $Level,
    [string] $Name,
    [string] $Message
  )
  Write-Host ("[{0}] {1}: {2}" -f $Level, $Name, $Message)
  [pscustomobject]@{ Level = $Level; Name = $Name; Message = $Message }
}

function ConvertTo-StringArray {
  # Normalize PowerShell pipeline/assignment quirks (scalar vs array vs nested).
  # Always return via unary comma so a 1-element string[] is NOT unrolled to [string]
  # (otherwise $arr[0] indexes characters of the SHA).
  param($Value)
  $list = New-Object System.Collections.Generic.List[string]
  if ($null -eq $Value) {
    return , ([string[]]@())
  }
  # Strings are IEnumerable[char] — must not foreach the characters.
  if ($Value -is [string]) {
    return , ([string[]]@([string]$Value))
  }
  foreach ($item in $Value) {
    if ($null -eq $item) { continue }
    if ($item -is [string]) {
      $list.Add([string]$item) | Out-Null
    }
    elseif ($item -is [System.Array] -and -not ($item -is [string])) {
      foreach ($sub in $item) {
        if ($null -ne $sub) { $list.Add([string]$sub) | Out-Null }
      }
    }
    else {
      $list.Add([string]$item) | Out-Null
    }
  }
  return , ([string[]]$list.ToArray())
}

function Invoke-GitChecked {
  param(
    [Parameter(Mandatory = $true)]
    [string[]] $GitArgs
  )
  # Defense in depth: never pass a bare option-looking token after subcommand without allowlist.
  foreach ($a in $GitArgs) {
    if ($a -match '^--output(=|$)') {
      throw "Refusing git argument that can write files: $a"
    }
  }
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $out = & git @GitArgs 2>&1
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  $lines = ConvertTo-StringArray $out
  if ($code -ne 0) {
    $script:GitFailed = $true
    $msg = "git $($GitArgs -join ' ') exit=$code :: $(($lines | Select-Object -First 3) -join ' | ')"
    $script:GitFailMessages.Add($msg) | Out-Null
    return , ([string[]]@())
  }
  return , $lines
}

function Resolve-BaseRefSha {
  param([string] $Ref)
  if ([string]::IsNullOrWhiteSpace($Ref)) { return '' }
  $trimmed = $Ref.Trim()
  # Reject option-shaped input (F10: BaseRef must not inject git flags).
  if ($trimmed.StartsWith('-')) {
    throw "BaseRef must be a ref/SHA, not a git option: $trimmed"
  }
  if ($trimmed -match '[\s"''`]|--') {
    throw "BaseRef contains forbidden characters: $trimmed"
  }
  # Do not index a bare string: ConvertTo-StringArray keeps a real string[].
  $shaLines = ConvertTo-StringArray (Invoke-GitChecked @('rev-parse', '--verify', "$trimmed^{commit}"))
  if ($script:GitFailed -or $null -eq $shaLines -or @($shaLines).Count -eq 0) {
    throw "BaseRef could not be resolved to a commit: $trimmed"
  }
  # Prefer pipeline-safe first element extraction (never $string[0] char index).
  $sha = (ConvertTo-StringArray $shaLines | Select-Object -First 1)
  if ($sha -is [System.Array]) { $sha = -join $sha }
  $sha = ([string]$sha).Trim()
  if ($sha.Length -lt 40 -or $sha -notmatch '^[0-9a-fA-F]+$') {
    throw "BaseRef resolved to unexpected value (len=$($sha.Length)): $sha"
  }
  return $sha
}

function Get-UntrackedPaths {
  $paths = New-Object System.Collections.Generic.List[string]
  foreach ($line in (ConvertTo-StringArray (Invoke-GitChecked @('status', '--porcelain', '-uall')))) {
    if ($line.Length -lt 4) { continue }
    $xy = $line.Substring(0, 2)
    if ($xy -eq '??') {
      $path = $line.Substring(3).Trim().Trim('"').Replace('\', '/')
      if ($path) { $paths.Add($path) | Out-Null }
    }
  }
  return [string[]]$paths.ToArray()
}

function Add-UntrackedPaths {
  param([System.Collections.Generic.HashSet[string]] $Set)
  foreach ($path in (ConvertTo-StringArray (Get-UntrackedPaths))) {
    if ($path) { [void]$Set.Add($path) }
  }
}

function Get-ChangedPaths {
  param([string] $BaseSha)
  $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

  if ([string]::IsNullOrWhiteSpace($BaseSha)) {
    foreach ($line in (ConvertTo-StringArray (Invoke-GitChecked @('diff', '--name-only')))) {
      $t = $line.Trim()
      if ($t) { [void]$set.Add($t.Replace('\', '/')) }
    }
    foreach ($line in (ConvertTo-StringArray (Invoke-GitChecked @('diff', '--cached', '--name-only')))) {
      $t = $line.Trim()
      if ($t) { [void]$set.Add($t.Replace('\', '/')) }
    }
  }
  else {
    foreach ($line in (ConvertTo-StringArray (Invoke-GitChecked @('diff', '--name-only', $BaseSha)))) {
      $t = $line.Trim()
      if ($t) { [void]$set.Add($t.Replace('\', '/')) }
    }
    foreach ($line in (ConvertTo-StringArray (Invoke-GitChecked @('diff', '--cached', '--name-only', $BaseSha)))) {
      $t = $line.Trim()
      if ($t) { [void]$set.Add($t.Replace('\', '/')) }
    }
  }
  # Always include untracked (owned_paths can escape via new files under any BaseRef mode).
  Add-UntrackedPaths -Set $set
  return @($set)
}

function Get-AddedDiffLines {
  param([string] $BaseSha)
  $chunks = New-Object System.Collections.Generic.List[string]
  if ([string]::IsNullOrWhiteSpace($BaseSha)) {
    foreach ($l in (ConvertTo-StringArray (Invoke-GitChecked @('diff', '-U0')))) { $chunks.Add($l) | Out-Null }
    foreach ($l in (ConvertTo-StringArray (Invoke-GitChecked @('diff', '--cached', '-U0')))) { $chunks.Add($l) | Out-Null }
  }
  else {
    foreach ($l in (ConvertTo-StringArray (Invoke-GitChecked @('diff', '-U0', $BaseSha)))) { $chunks.Add($l) | Out-Null }
    foreach ($l in (ConvertTo-StringArray (Invoke-GitChecked @('diff', '--cached', '-U0', $BaseSha)))) { $chunks.Add($l) | Out-Null }
  }
  $added = New-Object System.Collections.Generic.List[string]
  foreach ($line in $chunks) {
    if ($line.StartsWith('+') -and -not $line.StartsWith('+++')) {
      $added.Add($line.Substring(1)) | Out-Null
    }
  }
  # Untracked files are invisible to git diff; read their full contents for F07/stub scans.
  foreach ($path in (ConvertTo-StringArray (Get-UntrackedPaths))) {
    if (-not $path) { continue }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    try {
      foreach ($fl in (ConvertTo-StringArray (Get-Content -LiteralPath $path -Encoding UTF8 -ErrorAction Stop))) {
        $added.Add($fl) | Out-Null
      }
    }
    catch {
      # Unreadable untracked file: ignore content scan (path still in scope set).
    }
  }
  return [string[]]$added.ToArray()
}

function Test-IsTestLikePath {
  param([string] $Path)
  return $Path -match '(?i)(test|spec|Tests)'
}

function Get-DeletedPaths {
  param([string] $BaseSha)
  $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $argSets = if ([string]::IsNullOrWhiteSpace($BaseSha)) {
    @(@('diff', '--name-status'), @('diff', '--cached', '--name-status'))
  }
  else {
    @(@('diff', '--name-status', $BaseSha), @('diff', '--cached', '--name-status', $BaseSha))
  }
  foreach ($args in $argSets) {
    foreach ($line in (ConvertTo-StringArray (Invoke-GitChecked $args))) {
      # Prefer tab-separated name-status (git default); fall back to whitespace.
      if ($line -match '^[D]\t(.+)$' -or $line -match '^[D]\s+(.+)$') {
        [void]$set.Add($Matches[1].Trim().Replace('\', '/'))
        continue
      }
      # Rename: R100\told\tnew — treat test→non-test rename as test removal (F07).
      $oldPath = $null
      $newPath = $null
      if ($line -match '^R\d*\t(.+)\t(.+)$') {
        $oldPath = $Matches[1].Trim().Replace('\', '/')
        $newPath = $Matches[2].Trim().Replace('\', '/')
      }
      elseif ($line -match '^R\d*\s+(\S+)\s+(\S+)$') {
        $oldPath = $Matches[1].Trim().Replace('\', '/')
        $newPath = $Matches[2].Trim().Replace('\', '/')
      }
      if ($oldPath -and $newPath) {
        if ((Test-IsTestLikePath $oldPath) -and -not (Test-IsTestLikePath $newPath)) {
          [void]$set.Add($oldPath)
        }
      }
    }
  }
  return @($set)
}

function Test-UnderOwnedPaths {
  param(
    [string] $Path,
    [string[]] $Owned
  )
  # Segment normalize (shared with lease-paths). Never TrimStart('.') — that strips ".agents".
  $p = ConvertTo-NormalizedRepoPath -Path $Path
  if (-not $p) { return $false }
  foreach ($o in $Owned) {
    $own = ConvertTo-NormalizedRepoPath -Path $o
    if (-not $own) { continue }
    if ($p -eq $own -or $p.StartsWith($own + '/', [System.StringComparison]::OrdinalIgnoreCase)) {
      return $true
    }
  }
  return $false
}

$root = Get-RepoRoot
Set-Location $root
$items = [System.Collections.Generic.List[object]]::new()
$fail = $false

# 1. Status / log
if ($SkipLog) {
  $items.Add((Write-Item PASS 'status:log' 'skipped (-SkipLog)')) | Out-Null
}
else {
  $logPath = Join-Path $root ".agents\logs\codex\$JobId.last.txt"
  if (-not (Test-Path -LiteralPath $logPath)) {
    $items.Add((Write-Item FAIL 'status:log' "missing: $logPath")) | Out-Null
    $fail = $true
  }
  elseif ((Get-Item -LiteralPath $logPath).Length -eq 0) {
    $items.Add((Write-Item FAIL 'status:log' "empty: $logPath")) | Out-Null
    $fail = $true
  }
  else {
    $items.Add((Write-Item PASS 'status:log' "non-empty: $logPath")) | Out-Null
  }
}

# Resolve BaseRef early (fail closed)
$baseSha = ''
try {
  if (-not [string]::IsNullOrWhiteSpace($BaseRef)) {
    $baseSha = Resolve-BaseRefSha -Ref $BaseRef
    $items.Add((Write-Item PASS 'git:baseref' "resolved to $baseSha")) | Out-Null
  }
}
catch {
  $items.Add((Write-Item FAIL 'git:baseref' $_.Exception.Message)) | Out-Null
  $fail = $true
}

# 2. Diff scope (worktree + index + untracked; BaseRef uses resolved SHA only)
$changed = @()
if (-not $fail) {
  $changed = @(Get-ChangedPaths -BaseSha $baseSha)
}
if ($script:GitFailed) {
  $items.Add((Write-Item FAIL 'git' (($script:GitFailMessages | Select-Object -First 3) -join '; '))) | Out-Null
  $fail = $true
}

if (-not $fail) {
  if ($OwnedPaths.Count -gt 0) {
    $escapes = @()
    foreach ($path in $changed) {
      if (-not (Test-UnderOwnedPaths -Path $path -Owned $OwnedPaths)) {
        $escapes += $path
      }
    }
    if ($escapes.Count -gt 0) {
      $items.Add((Write-Item FAIL 'diff:scope' ("outside owned_paths: {0}" -f ($escapes -join ', ')))) | Out-Null
      $fail = $true
    }
    else {
      $items.Add((Write-Item PASS 'diff:scope' ("{0} path(s) within owned_paths" -f $changed.Count))) | Out-Null
    }
  }
  else {
    $items.Add((Write-Item PASS 'diff:scope' ("owned_paths not set; {0} changed path(s) observed" -f $changed.Count))) | Out-Null
  }
}

# 3. Stub detection (WARN only)
$addedLines = @()
$deleted = @()
if (-not $fail) {
  $addedLines = @(Get-AddedDiffLines -BaseSha $baseSha)
  $deleted = @(Get-DeletedPaths -BaseSha $baseSha)
  if ($script:GitFailed) {
    $items.Add((Write-Item FAIL 'git' (($script:GitFailMessages | Select-Object -First 3) -join '; '))) | Out-Null
    $fail = $true
  }
}

if (-not $fail) {
  $stubHits = @()
  foreach ($line in $addedLines) {
    if ($line -match 'NotImplementedError' -or $line -match 'TODO:' -or $line -match "throw new Error\('not implemented'\)") {
      $stubHits += $line.Trim()
    }
  }
  if ($stubHits.Count -gt 0) {
    $sample = ($stubHits | Select-Object -First 3) -join ' | '
    $items.Add((Write-Item WARN 'stub' "possible stub markers in added lines: $sample")) | Out-Null
  }
  else {
    $items.Add((Write-Item PASS 'stub' 'no stub markers in added lines')) | Out-Null
  }

  # 4. Test weakening (F07) — staged + unstaged
  $testDeleteHits = @($deleted | Where-Object { Test-IsTestLikePath $_ })
  $skipHits = @()
  foreach ($line in $addedLines) {
    if ($line -match 'Skip\s*=\s*\$true' -or $line -match 'it\.skip' -or $line -match 'describe\.skip' -or $line -match '@pytest\.mark\.skip') {
      $skipHits += $line.Trim()
    }
  }

  if ($testDeleteHits.Count -gt 0 -or $skipHits.Count -gt 0) {
    $msgParts = @()
    if ($testDeleteHits.Count -gt 0) { $msgParts += "deleted test-like paths: $($testDeleteHits -join ', ')" }
    if ($skipHits.Count -gt 0) { $msgParts += "skip markers: $(($skipHits | Select-Object -First 3) -join ' | ')" }
    $msg = $msgParts -join '; '
    if ($AcceptTestChanges) {
      $items.Add((Write-Item PASS 'f07:tests' "accepted via -AcceptTestChanges: $msg")) | Out-Null
    }
    else {
      $items.Add((Write-Item FAIL 'f07:tests' "$msg (use -AcceptTestChanges to override)")) | Out-Null
      $fail = $true
    }
  }
  else {
    $items.Add((Write-Item PASS 'f07:tests' 'no test deletion or skip markers detected')) | Out-Null
  }
}

# 5. Summary
if ($fail) {
  Write-Host 'verify-job: FAIL'
  exit 1
}
Write-Host 'verify-job: PASS'
exit 0
