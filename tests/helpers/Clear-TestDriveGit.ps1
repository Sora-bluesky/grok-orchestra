#requires -Version 5.1
# Shared Pester helpers for suites that create git repos under $TestDrive.
# Git marks loose objects read-only on Windows; Pester 6 TestDrive teardown
# then fails with Access denied. Clear RO attrs and prune worktrees first.

function Clear-GitReadOnlyAttributes {
  param(
    [Parameter(Mandatory = $true)]
    [string] $Path
  )
  if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
  Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
    ForEach-Object {
      try { $_.Attributes = [System.IO.FileAttributes]::Normal } catch { }
    }
  try {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($item) { $item.Attributes = [System.IO.FileAttributes]::Normal }
  }
  catch { }
}

function Remove-TestGitWorktrees {
  param(
    [Parameter(Mandatory = $true)]
    [string] $RepoRoot
  )
  if (-not $RepoRoot -or -not (Test-Path -LiteralPath $RepoRoot)) { return }
  try {
    $list = & git -C $RepoRoot worktree list --porcelain 2>$null
    if ($LASTEXITCODE -ne 0) { return }
    foreach ($line in ($list -split "`r?`n")) {
      if ($line -match '^worktree (.+)$') {
        $p = $Matches[1]
        if ($p -and ($p -ne $RepoRoot)) {
          try { & git -C $RepoRoot worktree remove --force $p 2>$null | Out-Null } catch { }
        }
      }
    }
    try { & git -C $RepoRoot worktree prune 2>$null | Out-Null } catch { }
  }
  catch { }
}

function Clear-TestDriveAfterGit {
  param(
    [string] $RepoRoot = '',
    [string] $DriveRoot = ''
  )
  if ($RepoRoot) {
    Remove-TestGitWorktrees -RepoRoot $RepoRoot
    Clear-GitReadOnlyAttributes -Path $RepoRoot
  }
  if ($DriveRoot -and (Test-Path -LiteralPath $DriveRoot)) {
    Clear-GitReadOnlyAttributes -Path $DriveRoot
  }
  elseif ($TestDrive -and (Test-Path -LiteralPath $TestDrive)) {
    Clear-GitReadOnlyAttributes -Path $TestDrive
  }
}
