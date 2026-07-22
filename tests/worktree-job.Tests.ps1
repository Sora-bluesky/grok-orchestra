#requires -Version 5.1
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'worktree-job.ps1' {
  BeforeAll {
    $script:OrchestraRoot = Split-Path $PSScriptRoot -Parent
    $script:WtScript = Join-Path $script:OrchestraRoot 'scripts\worktree-job.ps1'
  }

  BeforeEach {
    $script:Repo = Join-Path $TestDrive ("repo-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:Repo | Out-Null
    Push-Location $script:Repo
    git init -q | Out-Null
    git config user.email 'test@example.com'
    git config user.name 'Test'
    New-Item -ItemType Directory -Force -Path (Join-Path $script:Repo 'src') | Out-Null
    Set-Content -LiteralPath (Join-Path $script:Repo 'src\app.ps1') -Value '# app' -Encoding UTF8
    git add -A
    git commit -qm 'seed'
    $script:BaseSha = (git rev-parse HEAD).Trim()
    $script:LockDir = Join-Path $script:Repo '.agents\locks'
    New-Item -ItemType Directory -Force -Path $script:LockDir | Out-Null
  }

  AfterEach {
    # Best-effort cleanup of worktrees so TestDrive can be removed
    try {
      $list = git -C $script:Repo worktree list --porcelain 2>$null
      foreach ($line in ($list -split "`r?`n")) {
        if ($line -match '^worktree (.+)$') {
          $p = $Matches[1]
          if ($p -ne $script:Repo) {
            git -C $script:Repo worktree remove --force $p 2>$null | Out-Null
          }
        }
      }
      git -C $script:Repo worktree prune 2>$null | Out-Null
    }
    catch { }
    Pop-Location
  }

  It 'new creates worktree, branch, and metadata; emits machine-readable path line' {
    $out = & $script:WtScript -Action new -JobId 'jobA' -RepoRoot $script:Repo -LockDir $script:LockDir -SkipLog 2>&1
    $LASTEXITCODE | Should -Be 0
    $text = ($out | ForEach-Object { "$_" }) -join "`n"
    $text | Should -Match 'path='
    $text | Should -Match 'branch=wt/jobA'
    $text | Should -Match ('base_sha=' + $script:BaseSha)

    $metaPath = Join-Path $script:LockDir 'jobA.worktree.json'
    Test-Path -LiteralPath $metaPath | Should -BeTrue
    $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $meta.status | Should -Be 'active'
    $meta.schema_version | Should -Be 1
    $meta.log_required | Should -BeFalse
    $meta.base_sha | Should -Be $script:BaseSha
    Test-Path -LiteralPath $meta.path | Should -BeTrue
    git -C $script:Repo show-ref --verify --quiet 'refs/heads/wt/jobA'
    $LASTEXITCODE | Should -Be 0
  }

  It 'new refuses duplicate JobId while active' {
    & $script:WtScript -Action new -JobId 'dup1' -RepoRoot $script:Repo -LockDir $script:LockDir -SkipLog | Out-Null
    $err = $null
    try {
      & $script:WtScript -Action new -JobId 'dup1' -RepoRoot $script:Repo -LockDir $script:LockDir -SkipLog 2>&1 | Out-Null
    }
    catch { $err = $_ }
    $err | Should -Not -BeNullOrEmpty
    "$err" | Should -Match 'already exists'
  }

  It 'new rejects unsafe JobId' {
    $err = $null
    try {
      & $script:WtScript -Action new -JobId '../evil' -RepoRoot $script:Repo -LockDir $script:LockDir -SkipLog 2>&1 | Out-Null
    }
    catch { $err = $_ }
    $err | Should -Not -BeNullOrEmpty
    "$err" | Should -Match 'JobId'
  }

  It 'cleanup refuses dirty worktree without -Force; succeeds when clean; keeps branch' {
    & $script:WtScript -Action new -JobId 'clean1' -RepoRoot $script:Repo -LockDir $script:LockDir -SkipLog | Out-Null
    $meta = Get-Content -LiteralPath (Join-Path $script:LockDir 'clean1.worktree.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Set-Content -LiteralPath (Join-Path $meta.path 'src\app.ps1') -Value '# dirty' -Encoding UTF8

    $err = $null
    try {
      & $script:WtScript -Action cleanup -JobId 'clean1' -RepoRoot $script:Repo -LockDir $script:LockDir 2>&1 | Out-Null
    }
    catch { $err = $_ }
    $err | Should -Not -BeNullOrEmpty
    "$err" | Should -Match 'dirty'

    # Force remove dirty
    & $script:WtScript -Action cleanup -JobId 'clean1' -RepoRoot $script:Repo -LockDir $script:LockDir -Force | Out-Null
    $LASTEXITCODE | Should -Be 0
    $meta2 = Get-Content -LiteralPath (Join-Path $script:LockDir 'clean1.worktree.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $meta2.status | Should -Be 'removed'
    git -C $script:Repo show-ref --verify --quiet 'refs/heads/wt/clean1'
    $LASTEXITCODE | Should -Be 0  # branch retained
  }

  It 'collect shows diff, refuses dirty, never changes main HEAD' {
    & $script:WtScript -Action new -JobId 'col1' -RepoRoot $script:Repo -LockDir $script:LockDir -SkipLog | Out-Null
    $meta = Get-Content -LiteralPath (Join-Path $script:LockDir 'col1.worktree.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $mainHeadBefore = (git -C $script:Repo rev-parse HEAD).Trim()

    # dirty refuse
    Set-Content -LiteralPath (Join-Path $meta.path 'src\app.ps1') -Value '# uncommitted' -Encoding UTF8
    $err = $null
    try {
      & $script:WtScript -Action collect -JobId 'col1' -RepoRoot $script:Repo -LockDir $script:LockDir 2>&1 | Out-Null
    }
    catch { $err = $_ }
    $err | Should -Not -BeNullOrEmpty
    "$err" | Should -Match 'dirty'

    # commit in worktree and collect
    Set-Content -LiteralPath (Join-Path $meta.path 'src\app.ps1') -Value '# committed change' -Encoding UTF8
    git -C $meta.path add -A | Out-Null
    git -C $meta.path commit -qm 'wt change' | Out-Null

    # Write-Host output is not reliably captured; assert side effects (F10 + status)
    & $script:WtScript -Action collect -JobId 'col1' -RepoRoot $script:Repo -LockDir $script:LockDir *>$null
    $LASTEXITCODE | Should -Be 0

    $mainHeadAfter = (git -C $script:Repo rev-parse HEAD).Trim()
    $mainHeadAfter | Should -Be $mainHeadBefore

    # No merge in progress / no staged index changes on main (untracked .agents/locks is OK)
    Test-Path -LiteralPath (Join-Path $script:Repo '.git\MERGE_HEAD') | Should -BeFalse
    $staged = @(git -C $script:Repo diff --cached --name-only)
    @($staged | Where-Object { $_ }).Count | Should -Be 0

    $metaAfter = Get-Content -LiteralPath (Join-Path $script:LockDir 'col1.worktree.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $metaAfter.status | Should -Be 'collected'

    # wt branch advanced; main still at pre-collect HEAD
    $wtHead = (git -C $script:Repo rev-parse 'wt/col1').Trim()
    $wtHead | Should -Not -Be $mainHeadBefore
  }

  It 'collect does not merge even when verify would pass (HEAD identity assertion)' {
    & $script:WtScript -Action new -JobId 'nomrg' -RepoRoot $script:Repo -LockDir $script:LockDir -SkipLog | Out-Null
    $meta = Get-Content -LiteralPath (Join-Path $script:LockDir 'nomrg.worktree.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $before = (git -C $script:Repo rev-parse HEAD).Trim()
    Set-Content -LiteralPath (Join-Path $meta.path 'src\app.ps1') -Value '# v2' -Encoding UTF8
    git -C $meta.path add src/app.ps1 | Out-Null
    git -C $meta.path commit -qm 'v2' | Out-Null
    $wtHead = (git -C $meta.path rev-parse HEAD).Trim()
    $wtHead | Should -Not -Be $before

    & $script:WtScript -Action collect -JobId 'nomrg' -RepoRoot $script:Repo -LockDir $script:LockDir | Out-Null
    (git -C $script:Repo rev-parse HEAD).Trim() | Should -Be $before
    # wtHead must not be an ancestor of the pre-collect main tip (not merged)
    git -C $script:Repo merge-base --is-ancestor $wtHead $before 2>$null
    $LASTEXITCODE | Should -Not -Be 0
  }

  It 'collect rejects metadata whose path is not the canonical L2 worktree' {
    & $script:WtScript -Action new -JobId 'tamper1' -RepoRoot $script:Repo -LockDir $script:LockDir -SkipLog | Out-Null
    $metaPath = Join-Path $script:LockDir 'tamper1.worktree.json'
    $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    # Point path at control root (must not become collect target)
    $meta.path = $script:Repo
    $meta | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metaPath -Encoding UTF8
    $err = $null
    try {
      & $script:WtScript -Action collect -JobId 'tamper1' -RepoRoot $script:Repo -LockDir $script:LockDir 2>&1 | Out-Null
    }
    catch { $err = $_ }
    $err | Should -Not -BeNullOrEmpty
    "$err" | Should -Match 'canonical L2 path|path mismatch|does not match'
  }
}

Describe 'check.ps1 L2 worktree stale detection' {
  BeforeAll {
    $script:OrchestraRoot = Split-Path $PSScriptRoot -Parent
    $script:CheckScript = Join-Path $script:OrchestraRoot 'scripts\check.ps1'
  }

  BeforeEach {
    $script:TestLockDir = Join-Path $TestDrive ("locks-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:TestLockDir | Out-Null
  }

  It 'warns when active worktree directory is missing; -Fix marks stale' {
    $metaPath = Join-Path $script:TestLockDir 'gone.worktree.json'
    @{
      schema_version = 1
      job_id         = 'gone'
      path           = (Join-Path $TestDrive 'does-not-exist-wt')
      branch         = 'wt/gone'
      base_sha       = '0000000000000000000000000000000000000000'
      status         = 'active'
      owned_paths    = @()
      log_required   = $false
      created_at     = '2026-01-01T00:00:00Z'
      updated_at     = '2026-01-01T00:00:00Z'
    } | ConvertTo-Json | Set-Content -LiteralPath $metaPath -Encoding UTF8

    $output = & $script:CheckScript -LockDir $script:TestLockDir -RepoRoot $script:OrchestraRoot -SkipToolCheck *>&1
    $LASTEXITCODE | Should -Be 0
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'worktree:gone'
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'directory missing'

    $output2 = & $script:CheckScript -LockDir $script:TestLockDir -RepoRoot $script:OrchestraRoot -SkipToolCheck -Fix *>&1
    ($output2 | ForEach-Object { "$_" } | Out-String) | Should -Match 'status=stale'
    $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $meta.status | Should -Be 'stale'
  }
}

Describe 'delegate-codex.ps1 -Worktree skips L0 lock' {
  BeforeAll {
    $script:OrchestraRoot = Split-Path $PSScriptRoot -Parent
    $script:DelegateScript = Join-Path $script:OrchestraRoot 'scripts\delegate-codex.ps1'
    $script:OrigPath = $env:PATH
    $script:OrigAppData = $env:APPDATA
  }

  AfterAll {
    if ($null -ne $script:OrigPath) { $env:PATH = $script:OrigPath }
    if ($null -ne $script:OrigAppData) { $env:APPDATA = $script:OrigAppData }
  }

  BeforeEach {
    $script:Repo = Join-Path $TestDrive ("drepo-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:Repo | Out-Null
    # Minimal scripts shim: real worktree-job via absolute path is used from PSScriptRoot fallback
    New-Item -ItemType Directory -Force -Path (Join-Path $script:Repo 'scripts') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $script:Repo '.agents\docs\packets') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $script:Repo '.agents\locks') | Out-Null
    git -C $script:Repo init -q | Out-Null
    git -C $script:Repo config user.email 'test@example.com'
    git -C $script:Repo config user.name 'Test'
    Set-Content -LiteralPath (Join-Path $script:Repo 'README.md') -Value 'seed' -Encoding UTF8
    git -C $script:Repo add -A | Out-Null
    git -C $script:Repo commit -qm 'seed' | Out-Null

    $prompt = Join-Path $script:Repo '.agents\docs\packets\t.prompt.txt'
    @'
## Objective
Test L2 skip lock.

## Constraints
- none

## Relevant files
- README.md

## Acceptance checks
- none

## Output format
## TL;DR
'@ | Set-Content -LiteralPath $prompt -Encoding UTF8
    $script:PromptPath = $prompt

    # Fake codex that writes -o file and exits 0
    $fakeBin = Join-Path $TestDrive ("fake-codex-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $fakeBin | Out-Null
    $fakeCmd = Join-Path $fakeBin 'codex.cmd'
    @(
      '@echo off'
      'setlocal EnableDelayedExpansion'
      'set OUT='
      ':loop'
      'if "%~1"=="" goto run'
      'if /I "%~1"=="-o" ('
      '  set OUT=%~2'
      '  shift'
      '  shift'
      '  goto loop'
      ')'
      'shift'
      'goto loop'
      ':run'
      'if defined OUT ('
      '  echo fake-codex-ok> "!OUT!"'
      ')'
      'echo fake-codex-ok'
      'exit /b 0'
    ) | Set-Content -LiteralPath $fakeCmd -Encoding ASCII
    $fakeAppData = Join-Path $TestDrive ("appdata-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $fakeAppData | Out-Null
    $env:APPDATA = $fakeAppData
    $env:PATH = "$fakeBin;$script:OrigPath"

    $script:LockPath = Join-Path $script:Repo '.agents\locks\write-job.lock'
  }

  AfterEach {
    try {
      $list = git -C $script:Repo worktree list --porcelain 2>$null
      foreach ($line in ($list -split "`r?`n")) {
        if ($line -match '^worktree (.+)$') {
          $p = $Matches[1]
          if ($p -ne $script:Repo) {
            git -C $script:Repo worktree remove --force $p 2>$null | Out-Null
          }
        }
      }
    }
    catch { }
  }

  It 'implement -Worktree does not create main-tree write-job.lock' {
    $err = $null
    try {
      & $script:DelegateScript -JobId 'l2job1' -Type implement -PromptFile $script:PromptPath -RepoRoot $script:Repo -Worktree -OwnedPaths @('src') 2>&1 | Out-Null
    }
    catch {
      $err = $_
    }
    $err | Should -BeNullOrEmpty
    $LASTEXITCODE | Should -Be 0
    Test-Path -LiteralPath $script:LockPath | Should -BeFalse
    # L1 lease must not appear on control root
    $leases = @(Get-ChildItem -LiteralPath (Join-Path $script:Repo '.agents\locks') -Filter '*.lease.json' -ErrorAction SilentlyContinue)
    $leases.Count | Should -Be 0
    $meta = Join-Path $script:Repo '.agents\locks\l2job1.worktree.json'
    Test-Path -LiteralPath $meta | Should -BeTrue
    $m = Get-Content -LiteralPath $meta -Raw -Encoding UTF8 | ConvertFrom-Json
    $m.status | Should -Be 'active'
    $m.log_required | Should -BeTrue
    # fake codex wrote last log under worktree
    $log = Join-Path $m.path ".agents\logs\codex\l2job1.last.txt"
    Test-Path -LiteralPath $log | Should -BeTrue
  }
}
