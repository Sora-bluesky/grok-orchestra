#requires -Version 5.1
<#
.SYNOPSIS
  L2 git worktree lifecycle: new / collect / cleanup.
  collect never merges, rebases, cherry-picks, or mutates main HEAD (F10).

.PARAMETER Action
  new | collect | cleanup

.PARAMETER JobId
  Safe single path segment (letters, digits, hyphen, underscore).

.PARAMETER BaseRef
  Base commit for new (default: HEAD). Resolved to a full SHA before use.

.PARAMETER OwnedPaths
  Optional repo-relative prefixes stored in L2 metadata and passed to collect verify.

.PARAMETER SkipLog
  new: set log_required=false (Grok-direct worktrees).

.PARAMETER Force
  cleanup: allow removing a dirty worktree. Never deletes branch wt/<JobId>.

.PARAMETER RepoRoot
  Control-plane repository root (default: parent of scripts/).

.PARAMETER LockDir
  Override locks directory (default: <RepoRoot>/.agents/locks).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('new', 'collect', 'cleanup')]
  [string] $Action,

  [Parameter(Mandatory = $true)]
  [string] $JobId,

  [string] $BaseRef = '',

  [string[]] $OwnedPaths = @(),

  [switch] $SkipLog,

  [switch] $Force,

  [string] $RepoRoot = '',

  [string] $LockDir = ''
)

$ErrorActionPreference = 'Stop'

function Get-ControlRoot {
  if ($RepoRoot) { return (Resolve-Path -LiteralPath $RepoRoot).Path }
  return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Assert-SafeJobId {
  param([string] $Id)
  if ([string]::IsNullOrWhiteSpace($Id)) {
    throw 'JobId is required.'
  }
  if ($Id -match '[\\/]' -or $Id -eq '.' -or $Id -eq '..') {
    throw "JobId must be a single safe path segment (no separators / . / ..): '$Id'"
  }
  if ($Id -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') {
    throw ("JobId must match ^[A-Za-z0-9][A-Za-z0-9_-]*`$ : '{0}'" -f $Id)
  }
}

function Get-Git {
  param(
    [string] $WorkDir,
    [string[]] $GitArgs
  )
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $output = & git -C $WorkDir @GitArgs 2>&1
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  $text = ($output | ForEach-Object { "$_" }) -join [Environment]::NewLine
  if ($code -ne 0) {
    throw ("git -C '{0}' {1} failed (exit {2}): {3}" -f $WorkDir, ($GitArgs -join ' '), $code, $text)
  }
  return $text
}

function Resolve-CommitSha {
  param(
    [string] $WorkDir,
    [string] $Ref
  )
  if ([string]::IsNullOrWhiteSpace($Ref)) {
    throw 'BaseRef resolved empty.'
  }
  if ($Ref.StartsWith('-')) {
    throw "BaseRef must not start with '-': '$Ref'"
  }
  $sha = (Get-Git -WorkDir $WorkDir -GitArgs @('rev-parse', '--verify', "$Ref^{commit}")).Trim()
  if ($sha -notmatch '^[0-9a-f]{40}$') {
    throw "BaseRef did not resolve to a 40-char SHA: '$Ref' -> '$sha'"
  }
  return $sha
}

function Get-MetaPath {
  param(
    [string] $Locks,
    [string] $Id
  )
  return (Join-Path $Locks ("{0}.worktree.json" -f $Id))
}

function Read-Meta {
  param([string] $Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "L2 metadata not found: $Path"
  }
  try {
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
  }
  catch {
    throw "Invalid L2 metadata JSON: $Path — $($_.Exception.Message)"
  }
}

function Write-Meta {
  param(
    [string] $Path,
    [hashtable] $Meta
  )
  $dir = Split-Path -Parent $Path
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $Meta | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Test-JobIdCollision {
  param(
    [string] $Locks,
    [string] $Id
  )
  if (-not (Test-Path -LiteralPath $Locks)) { return }
  $target = "{0}.worktree.json" -f $Id
  foreach ($f in Get-ChildItem -LiteralPath $Locks -Filter '*.worktree.json' -File -ErrorAction SilentlyContinue) {
    if ($f.Name -ceq $target) { continue }
    if ($f.Name -ieq $target) {
      throw "JobId case-collision with existing metadata: $($f.Name)"
    }
  }
}

function Get-RegisteredWorktreePath {
  param(
    [string] $ControlRoot,
    [string] $Branch
  )
  $porcelain = Get-Git -WorkDir $ControlRoot -GitArgs @('worktree', 'list', '--porcelain')
  $currentPath = $null
  $currentBranch = $null
  foreach ($line in ($porcelain -split "`r?`n")) {
    if ($line -match '^worktree (.+)$') {
      if ($currentPath -and $currentBranch -eq $Branch) {
        return $currentPath
      }
      $currentPath = $Matches[1]
      $currentBranch = $null
    }
    elseif ($line -match '^branch refs/heads/(.+)$') {
      $currentBranch = $Matches[1]
    }
    elseif ($line -eq '') {
      if ($currentPath -and $currentBranch -eq $Branch) {
        return $currentPath
      }
      $currentPath = $null
      $currentBranch = $null
    }
  }
  if ($currentPath -and $currentBranch -eq $Branch) {
    return $currentPath
  }
  return $null
}

function Test-WorktreeDirty {
  param([string] $WorktreePath)
  $status = Get-Git -WorkDir $WorktreePath -GitArgs @('status', '--porcelain')
  return -not [string]::IsNullOrWhiteSpace($status)
}

function Assert-WorktreeIdentity {
  param(
    [string] $ControlRoot,
    [object] $Meta,
    [string] $ExpectedJobId
  )
  $metaJob = [string]$Meta.job_id
  if ($metaJob -cne $ExpectedJobId) {
    throw "Metadata job_id '$metaJob' does not match requested JobId '$ExpectedJobId'."
  }
  $expectedBranch = "wt/$ExpectedJobId"
  $branch = [string]$Meta.branch
  if ($branch -cne $expectedBranch) {
    throw "Metadata branch '$branch' does not match expected '$expectedBranch'."
  }
  $expectedPath = Join-Path (Join-Path $ControlRoot '.agents\worktrees') $ExpectedJobId
  $metaPath = [string]$Meta.path
  if (-not (Test-Path -LiteralPath $metaPath)) {
    throw "Worktree directory missing: $metaPath"
  }
  if (-not (Test-Path -LiteralPath $expectedPath)) {
    throw "Expected worktree path missing: $expectedPath"
  }
  $resolvedMeta = (Resolve-Path -LiteralPath $metaPath).Path
  $resolvedExpected = (Resolve-Path -LiteralPath $expectedPath).Path
  if ($resolvedMeta -ne $resolvedExpected) {
    throw "Metadata path is not the canonical L2 path. metadata=$resolvedMeta expected=$resolvedExpected"
  }
  $registered = Get-RegisteredWorktreePath -ControlRoot $ControlRoot -Branch $branch
  if (-not $registered) {
    throw "Branch '$branch' is not registered as a git worktree."
  }
  $resolvedReg = (Resolve-Path -LiteralPath $registered).Path
  if ($resolvedReg -ne $resolvedMeta) {
    throw "Worktree path mismatch. metadata=$resolvedMeta registered=$resolvedReg"
  }
  $headSym = (Get-Git -WorkDir $resolvedMeta -GitArgs @('symbolic-ref', '-q', 'HEAD')).Trim()
  $expectedRef = "refs/heads/$branch"
  if ($headSym -ne $expectedRef) {
    throw "Worktree HEAD is not on expected branch (got '$headSym', expected '$expectedRef'). Detached or wrong branch."
  }
  return $resolvedMeta
}

function Invoke-New {
  param(
    [string] $ControlRoot,
    [string] $Locks,
    [string] $Id,
    [string] $Base,
    [string[]] $Owned,
    [bool] $LogRequired
  )

  Assert-SafeJobId -Id $Id
  Test-JobIdCollision -Locks $Locks -Id $Id

  $metaPath = Get-MetaPath -Locks $Locks -Id $Id
  if (Test-Path -LiteralPath $metaPath) {
    $existing = Read-Meta -Path $metaPath
    if ([string]$existing.status -eq 'active') {
      throw "Active L2 worktree already exists for JobId='$Id' ($metaPath)."
    }
    throw "L2 metadata already exists for JobId='$Id' (status=$($existing.status)). Remove or use a new JobId."
  }

  $branch = "wt/$Id"
  # Refuse reuse while branch still exists (cleanup leaves branch as evidence)
  $branchCheck = & git -C $ControlRoot show-ref --verify --quiet "refs/heads/$branch" 2>$null
  if ($LASTEXITCODE -eq 0) {
    throw "Branch '$branch' still exists. Choose a new JobId or delete the branch manually after merge."
  }

  $baseSha = if ([string]::IsNullOrWhiteSpace($Base)) {
    Resolve-CommitSha -WorkDir $ControlRoot -Ref 'HEAD'
  }
  else {
    Resolve-CommitSha -WorkDir $ControlRoot -Ref $Base
  }

  $wtParent = Join-Path $ControlRoot '.agents\worktrees'
  New-Item -ItemType Directory -Force -Path $wtParent | Out-Null
  $wtPath = Join-Path $wtParent $Id
  if (Test-Path -LiteralPath $wtPath) {
    throw "Worktree directory already exists: $wtPath"
  }

  $createdWorktree = $false
  try {
    Get-Git -WorkDir $ControlRoot -GitArgs @('worktree', 'add', '-b', $branch, $wtPath, $baseSha) | Out-Null
    $createdWorktree = $true
    $resolvedPath = (Resolve-Path -LiteralPath $wtPath).Path
    $now = Get-Date -Format o
    $meta = @{
      schema_version = 1
      job_id         = $Id
      path           = $resolvedPath
      branch         = $branch
      base_sha       = $baseSha
      status         = 'active'
      owned_paths    = @($Owned)
      log_required   = $LogRequired
      created_at     = $now
      updated_at     = $now
    }
    Write-Meta -Path $metaPath -Meta $meta
    # Machine-readable single line for delegate parsing
    Write-Output ("path={0};branch={1};base_sha={2};status=active" -f $resolvedPath, $branch, $baseSha)
  }
  catch {
    if ($createdWorktree -and (Test-Path -LiteralPath $wtPath)) {
      try { & git -C $ControlRoot worktree remove --force $wtPath 2>$null | Out-Null } catch { }
      try { & git -C $ControlRoot branch -D $branch 2>$null | Out-Null } catch { }
    }
    if (Test-Path -LiteralPath $metaPath) {
      Remove-Item -LiteralPath $metaPath -Force -ErrorAction SilentlyContinue
    }
    throw
  }
}

function Invoke-Collect {
  param(
    [string] $ControlRoot,
    [string] $Locks,
    [string] $Id
  )

  Assert-SafeJobId -Id $Id
  $metaPath = Get-MetaPath -Locks $Locks -Id $Id
  $meta = Read-Meta -Path $metaPath
  if ([string]$meta.status -ne 'active' -and [string]$meta.status -ne 'collected') {
    throw "Cannot collect JobId='$Id' with status=$($meta.status)"
  }

  $wtPath = Assert-WorktreeIdentity -ControlRoot $ControlRoot -Meta $meta -ExpectedJobId $Id
  if (Test-WorktreeDirty -WorktreePath $wtPath) {
    throw "Worktree is dirty (uncommitted changes). Commit in the worktree or discard before collect: $wtPath"
  }

  $baseSha = [string]$meta.base_sha
  $branch = [string]$meta.branch
  $owned = @()
  if ($meta.owned_paths) { $owned = @($meta.owned_paths | ForEach-Object { [string]$_ }) }
  $logRequired = $true
  if ($null -ne $meta.log_required) { $logRequired = [bool]$meta.log_required }

  $verifyScript = Join-Path $PSScriptRoot 'verify-job.ps1'
  $verifyArgs = @{
    JobId    = $Id
    RepoRoot = $wtPath
    BaseRef  = $baseSha
  }
  if ($owned.Count -gt 0) { $verifyArgs['OwnedPaths'] = $owned }
  if (-not $logRequired) { $verifyArgs['SkipLog'] = $true }

  Write-Host "worktree-job collect: running verify-job on worktree $wtPath (base=$baseSha)"
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $verifyOut = & $verifyScript @verifyArgs 2>&1
  $verifyCode = $LASTEXITCODE
  $ErrorActionPreference = $prevEap
  $verifyText = ($verifyOut | ForEach-Object { "$_" }) -join [Environment]::NewLine
  Write-Host $verifyText

  $diffText = Get-Git -WorkDir $ControlRoot -GitArgs @('diff', "$baseSha..$branch", '--stat')
  Write-Host "--- git diff $baseSha..$branch --stat ---"
  Write-Host $diffText

  $meta.status = 'collected'
  $meta.updated_at = Get-Date -Format o
  # ConvertFrom-Json object → rewrite via hashtable-like properties
  $updated = @{
    schema_version = [int]$meta.schema_version
    job_id         = [string]$meta.job_id
    path           = [string]$meta.path
    branch         = [string]$meta.branch
    base_sha       = [string]$meta.base_sha
    status         = 'collected'
    owned_paths    = $owned
    log_required   = $logRequired
    created_at     = [string]$meta.created_at
    updated_at     = [string]$meta.updated_at
  }
  Write-Meta -Path $metaPath -Meta $updated

  Write-Host ''
  Write-Host '=== Operator next actions (F10: collect does NOT merge) ==='
  Write-Host ("  git merge --no-ff {0}" -f $branch)
  Write-Host ("  # or open a PR from {0}" -f $branch)
  Write-Host ("  # then: worktree-job.ps1 -Action cleanup -JobId {0}" -f $Id)

  if ($verifyCode -ne 0) {
    Write-Host 'worktree-job collect: VERIFY FAIL (main HEAD unchanged; no merge performed)'
    exit 1
  }
  Write-Host 'worktree-job collect: VERIFY PASS (main HEAD unchanged; no merge performed)'
  exit 0
}

function Invoke-Cleanup {
  param(
    [string] $ControlRoot,
    [string] $Locks,
    [string] $Id,
    [bool] $ForceRemove
  )

  Assert-SafeJobId -Id $Id
  $metaPath = Get-MetaPath -Locks $Locks -Id $Id
  $meta = Read-Meta -Path $metaPath
  $wtPath = [string]$meta.path
  $branch = [string]$meta.branch

  if (Test-Path -LiteralPath $wtPath) {
    $resolved = (Resolve-Path -LiteralPath $wtPath).Path
    if (Test-WorktreeDirty -WorktreePath $resolved) {
      if (-not $ForceRemove) {
        throw "Worktree is dirty. Re-run with -Force to remove, or commit/discard changes first: $resolved"
      }
    }
    # Prefer registered path; fall back to force remove by path
    try {
      if ($ForceRemove) {
        Get-Git -WorkDir $ControlRoot -GitArgs @('worktree', 'remove', '--force', $resolved) | Out-Null
      }
      else {
        Get-Git -WorkDir $ControlRoot -GitArgs @('worktree', 'remove', $resolved) | Out-Null
      }
    }
    catch {
      if ($ForceRemove) {
        # Last resort for tests / half-registered trees
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
        try { Get-Git -WorkDir $ControlRoot -GitArgs @('worktree', 'prune') | Out-Null } catch { }
      }
      else {
        throw
      }
    }
  }

  $owned = @()
  if ($meta.owned_paths) { $owned = @($meta.owned_paths | ForEach-Object { [string]$_ }) }
  $logRequired = $true
  if ($null -ne $meta.log_required) { $logRequired = [bool]$meta.log_required }
  $updated = @{
    schema_version = [int]$meta.schema_version
    job_id         = [string]$meta.job_id
    path           = [string]$meta.path
    branch         = $branch
    base_sha       = [string]$meta.base_sha
    status         = 'removed'
    owned_paths    = $owned
    log_required   = $logRequired
    created_at     = [string]$meta.created_at
    updated_at     = (Get-Date -Format o)
  }
  Write-Meta -Path $metaPath -Meta $updated
  Write-Host ("worktree-job cleanup: removed worktree for {0}; branch {1} retained (Operator deletes manually)." -f $Id, $branch)
}

# --- main ---
$control = Get-ControlRoot
if ([string]::IsNullOrWhiteSpace($LockDir)) {
  $LockDir = Join-Path $control '.agents\locks'
}
New-Item -ItemType Directory -Force -Path $LockDir | Out-Null

switch ($Action) {
  'new' {
    $logReq = -not $SkipLog.IsPresent
    Invoke-New -ControlRoot $control -Locks $LockDir -Id $JobId -Base $BaseRef -Owned $OwnedPaths -LogRequired $logReq
  }
  'collect' {
    Invoke-Collect -ControlRoot $control -Locks $LockDir -Id $JobId
  }
  'cleanup' {
    Invoke-Cleanup -ControlRoot $control -Locks $LockDir -Id $JobId -ForceRemove:$Force
  }
}
