#requires -Version 5.1
<#
.SYNOPSIS
  Mechanical verification gate (judge only - never commit/merge/fix).
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
  # Strings are IEnumerable[char] - must not foreach the characters.
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

# Raw stdout for -z (NUL-separated) paths. Capture via temp file so NULs survive.
function Invoke-GitRaw {
  param(
    [Parameter(Mandatory = $true)]
    [string[]] $GitArgs
  )
  foreach ($a in $GitArgs) {
    if ($a -match '^--output(=|$)') {
      throw "Refusing git argument that can write files: $a"
    }
  }
  $outFile = Join-Path ([System.IO.Path]::GetTempPath()) ('gitz-' + [guid]::NewGuid().ToString('N') + '.bin')
  $errFile = $outFile + '.err'
  try {
    # -FilePath (not -FileName): PS 5.1 Start-Process parameter name
    $p = Start-Process -FilePath 'git' -ArgumentList $GitArgs `
      -WorkingDirectory (Get-Location).Path `
      -RedirectStandardOutput $outFile `
      -RedirectStandardError $errFile `
      -Wait -PassThru -NoNewWindow
    $stderr = ''
    if (Test-Path -LiteralPath $errFile) {
      $stderr = [System.IO.File]::ReadAllText($errFile)
    }
    if ($p.ExitCode -ne 0) {
      $script:GitFailed = $true
      $msg = "git $($GitArgs -join ' ') exit=$($p.ExitCode) :: $($stderr.Trim())"
      $script:GitFailMessages.Add($msg) | Out-Null
      return ''
    }
    if (-not (Test-Path -LiteralPath $outFile)) { return '' }
    return [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($outFile))
  }
  finally {
    Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
  }
}

function Split-GitNulRecords {
  # Always return a flat string[] via ConvertTo-StringArray (never unary-comma nested).
  # PS 5.1 compatible: split on [char]0 - NOT `u{0} (PS 6+ only).
  param([string] $Raw)
  if ([string]::IsNullOrEmpty($Raw)) {
    return , ([string[]]@())
  }
  $list = New-Object System.Collections.Generic.List[string]
  foreach ($p in $Raw.Split([char]0)) {
    if ($null -ne $p -and $p.Length -gt 0) { $list.Add($p) | Out-Null }
  }
  return ConvertTo-StringArray ([string[]]$list.ToArray())
}

function ConvertTo-RepoSlashPath {
  param([string] $Path)
  if ([string]::IsNullOrEmpty($Path)) { return '' }
  return $Path.Replace('\', '/')
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

# Max untracked content scan size (plan 005).
$script:MaxUntrackedScanBytes = 1MB
$script:ScanSkipped = [System.Collections.Generic.List[string]]::new()

function Get-UntrackedPaths {
  # porcelain -z: records are "XY path\0" (no C-style quoting); renames have a second path\0.
  $raw = Invoke-GitRaw @('status', '--porcelain', '-z', '-uall')
  $parts = ConvertTo-StringArray (Split-GitNulRecords $raw)
  $paths = New-Object System.Collections.Generic.List[string]
  $i = 0
  while ($i -lt $parts.Count) {
    $rec = [string]$parts[$i]
    if ($rec.Length -lt 3) { $i++; continue }
    $xy = $rec.Substring(0, 2)
    $path = if ($rec.Length -gt 3 -and $rec[2] -eq ' ') { $rec.Substring(3) } else { $rec.Substring(2) }
    $path = ConvertTo-RepoSlashPath $path
    # Rename/copy: next NUL field is the other path - skip it for untracked listing.
    if ($xy -match '^[RC]') {
      $i += 2
      continue
    }
    if ($xy -eq '??' -and $path) {
      $paths.Add($path) | Out-Null
    }
    $i++
  }
  return ConvertTo-StringArray ([string[]]$paths.ToArray())
}

function Add-UntrackedPaths {
  param([System.Collections.Generic.HashSet[string]] $Set)
  foreach ($path in (ConvertTo-StringArray (Get-UntrackedPaths))) {
    if ($path) { [void]$Set.Add($path) }
  }
}

function Get-NameOnlyPathsZ {
  param([string[]] $GitArgs)
  $raw = Invoke-GitRaw $GitArgs
  $paths = New-Object System.Collections.Generic.List[string]
  foreach ($p in (ConvertTo-StringArray (Split-GitNulRecords $raw))) {
    $slash = ConvertTo-RepoSlashPath ([string]$p)
    if ($slash) { $paths.Add($slash) | Out-Null }
  }
  return ConvertTo-StringArray ([string[]]$paths.ToArray())
}

function Get-ChangedPaths {
  param([string] $BaseSha)
  $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

  if ([string]::IsNullOrWhiteSpace($BaseSha)) {
    foreach ($p in (Get-NameOnlyPathsZ @('diff', '--name-only', '-z'))) { [void]$set.Add($p) }
    foreach ($p in (Get-NameOnlyPathsZ @('diff', '--cached', '--name-only', '-z'))) { [void]$set.Add($p) }
  }
  else {
    foreach ($p in (Get-NameOnlyPathsZ @('diff', '--name-only', '-z', $BaseSha))) { [void]$set.Add($p) }
    foreach ($p in (Get-NameOnlyPathsZ @('diff', '--cached', '--name-only', '-z', $BaseSha))) { [void]$set.Add($p) }
  }
  # Always include untracked (owned_paths can escape via new files under any BaseRef mode).
  Add-UntrackedPaths -Set $set
  return @($set)
}

function Get-AddedDiffLines {
  param([string] $BaseSha)
  $chunks = New-Object System.Collections.Generic.List[string]
  # Patch text still uses line-oriented diffs (not -z); fine for content markers.
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
  # Untracked files: read contents for F07/stub, with 1MB size cap (plan 005).
  foreach ($path in (ConvertTo-StringArray (Get-UntrackedPaths))) {
    if (-not $path) { continue }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    try {
      $len = (Get-Item -LiteralPath $path).Length
      if ($len -gt $script:MaxUntrackedScanBytes) {
        $script:ScanSkipped.Add($path) | Out-Null
        continue
      }
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
  # name-status -z: "STATUS\0path\0" or rename "R100\0old\0new\0"
  $argSets = if ([string]::IsNullOrWhiteSpace($BaseSha)) {
    @(@('diff', '--name-status', '-z'), @('diff', '--cached', '--name-status', '-z'))
  }
  else {
    @(@('diff', '--name-status', '-z', $BaseSha), @('diff', '--cached', '--name-status', '-z', $BaseSha))
  }
  foreach ($gitArgs in $argSets) {
    $raw = Invoke-GitRaw $gitArgs
    # -z name-status: "D\0path\0", rename "R100\0old\0new\0", or copy "C100\0old\0new\0"
    # R and C both carry two paths (git diff-format raw output); mis-counting desyncs later records.
    $parts = ConvertTo-StringArray (Split-GitNulRecords $raw)
    $i = 0
    while ($i -lt $parts.Count) {
      $status = [string]$parts[$i]
      if ([string]::IsNullOrEmpty($status)) { $i++; continue }
      # Rename or copy: always consume three fields. Only rename can be an F07 test escape.
      if ($status -match '^[RC]' -and ($i + 2) -lt $parts.Count) {
        if ($status -match '^R') {
          $oldPath = ConvertTo-RepoSlashPath ([string]$parts[$i + 1])
          $newPath = ConvertTo-RepoSlashPath ([string]$parts[$i + 2])
          if ($oldPath -and $newPath) {
            if ((Test-IsTestLikePath $oldPath) -and -not (Test-IsTestLikePath $newPath)) {
              [void]$set.Add($oldPath)
            }
          }
        }
        $i += 3
        continue
      }
      if (($status.StartsWith('D') -or $status -eq 'D') -and ($i + 1) -lt $parts.Count) {
        $del = ConvertTo-RepoSlashPath ([string]$parts[$i + 1])
        if ($del) { [void]$set.Add($del) }
        $i += 2
        continue
      }
      # Other single-path statuses (A/M/...)
      $i += 2
    }
  }
  return @($set)
}

function Test-UnderOwnedPaths {
  param(
    [string] $Path,
    [string[]] $Owned
  )
  # Segment normalize (shared with lease-paths). Never TrimStart('.') - that strips ".agents".
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

  foreach ($skippedPath in @($script:ScanSkipped)) {
    $items.Add((Write-Item WARN 'scan' ("skipped {0} (size > 1MB)" -f $skippedPath))) | Out-Null
  }

  # 4. Test weakening (F07) - staged + unstaged
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
