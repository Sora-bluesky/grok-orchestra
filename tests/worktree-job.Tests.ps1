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
    "$err" | Should -Match 'already claimed|already exists|metadata exists'
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

  It 'cleanup -Force refuses tampered meta.path (repo root, sibling, .. escape) with zero deletion' {
    & $script:WtScript -Action new -JobId 'clntamp' -RepoRoot $script:Repo -LockDir $script:LockDir -SkipLog | Out-Null
    $metaPath = Join-Path $script:LockDir 'clntamp.worktree.json'
    $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $realWt = $meta.path
    Test-Path -LiteralPath $realWt | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $script:Repo 'src\app.ps1') | Should -BeTrue

    $sibling = Join-Path $TestDrive ("sibling-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $sibling | Out-Null
    Set-Content -LiteralPath (Join-Path $sibling 'keep.txt') -Value 'alive' -Encoding UTF8

    $escapePath = Join-Path $realWt '..\..\src'
    $cases = @(
      @{ Label = 'repo-root'; Path = $script:Repo },
      @{ Label = 'sibling'; Path = $sibling },
      @{ Label = 'dotdot-escape'; Path = $escapePath }
    )

    foreach ($c in $cases) {
      $m = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
      $m.path = $c.Path
      $m | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metaPath -Encoding UTF8

      $err = $null
      try {
        & $script:WtScript -Action cleanup -JobId 'clntamp' -RepoRoot $script:Repo -LockDir $script:LockDir -Force 2>&1 | Out-Null
      }
      catch { $err = $_ }
      $err | Should -Not -BeNullOrEmpty -Because "cleanup must refuse $($c.Label)"
      "$err" | Should -Match 'canonical L2 path|outside|Refusing|does not match'

      # Zero deletion of tampered targets and of the real worktree / main tree
      Test-Path -LiteralPath $script:Repo | Should -BeTrue
      Test-Path -LiteralPath (Join-Path $script:Repo 'src\app.ps1') | Should -BeTrue
      Test-Path -LiteralPath $realWt | Should -BeTrue
      Test-Path -LiteralPath (Join-Path $sibling 'keep.txt') | Should -BeTrue
    }

    # Restore path and prove normal cleanup still works
    $m2 = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $m2.path = $realWt
    $m2 | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metaPath -Encoding UTF8
    & $script:WtScript -Action cleanup -JobId 'clntamp' -RepoRoot $script:Repo -LockDir $script:LockDir -Force | Out-Null
    $LASTEXITCODE | Should -Be 0
  }

  It 'new refuses JobId reuse when wt/<Id> branch exists without metadata' {
    # Exclusive claim succeeds first; post-claim branch check refuses; owner rollback clears claim
    # and may delete the orphan branch (safe: claim owner, no concurrent new mid-flight).
    $sha = (git -C $script:Repo rev-parse HEAD).Trim()
    git -C $script:Repo branch 'wt/reuse1' $sha | Out-Null
    git -C $script:Repo show-ref --verify --quiet 'refs/heads/wt/reuse1'
    $LASTEXITCODE | Should -Be 0
    Test-Path -LiteralPath (Join-Path $script:LockDir 'reuse1.worktree.json') | Should -BeFalse

    $err = $null
    try {
      & $script:WtScript -Action new -JobId 'reuse1' -RepoRoot $script:Repo -LockDir $script:LockDir -SkipLog 2>&1 | Out-Null
    }
    catch { $err = $_ }
    $err | Should -Not -BeNullOrEmpty
    "$err" | Should -Match 'still exists'
    Test-Path -LiteralPath (Join-Path $script:LockDir 'reuse1.worktree.json') | Should -BeFalse
  }

  It 'same-JobId new after winner already owns claim refuses and does not destroy winner' {
    # Deterministic race: A already won (active worktree + branch + metadata).
    & $script:WtScript -Action new -JobId 'race1' -RepoRoot $script:Repo -LockDir $script:LockDir -SkipLog | Out-Null
    $metaPath = Join-Path $script:LockDir 'race1.worktree.json'
    $metaBefore = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $metaBefore.status | Should -Be 'active'
    $winnerPath = $metaBefore.path
    $marker = Join-Path $winnerPath 'WINNER_MARKER.txt'
    Set-Content -LiteralPath $marker -Value 'owned-by-A' -Encoding UTF8
    $branchShaBefore = (git -C $script:Repo rev-parse 'wt/race1').Trim()

    $err = $null
    try {
      & $script:WtScript -Action new -JobId 'race1' -RepoRoot $script:Repo -LockDir $script:LockDir -SkipLog 2>&1 | Out-Null
    }
    catch { $err = $_ }
    $err | Should -Not -BeNullOrEmpty
    "$err" | Should -Match 'already claimed|already exists|metadata exists'

    # Winner intact: dir, marker, branch, active metadata
    Test-Path -LiteralPath $winnerPath | Should -BeTrue
    Test-Path -LiteralPath $marker | Should -BeTrue
    (Get-Content -LiteralPath $marker -Raw).Trim() | Should -Be 'owned-by-A'
    git -C $script:Repo show-ref --verify --quiet 'refs/heads/wt/race1'
    $LASTEXITCODE | Should -Be 0
    (git -C $script:Repo rev-parse 'wt/race1').Trim() | Should -Be $branchShaBefore
    $metaAfter = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $metaAfter.status | Should -Be 'active'
    $metaAfter.path | Should -Be $winnerPath
  }

  It 'new rolls back orphan branch residue when worktree add fails after -b' {
    # Block path with a file so git worktree add may create branch then fail on populate,
    # or fail early — either way branch must not remain after the failed new.
    $blockParent = Join-Path $script:Repo '.agents\worktrees'
    New-Item -ItemType Directory -Force -Path $blockParent | Out-Null
    $blockPath = Join-Path $blockParent 'roll1'
    Set-Content -LiteralPath $blockPath -Value 'not-a-dir' -Encoding UTF8

    $err = $null
    try {
      & $script:WtScript -Action new -JobId 'roll1' -RepoRoot $script:Repo -LockDir $script:LockDir -SkipLog 2>&1 | Out-Null
    }
    catch { $err = $_ }
    $err | Should -Not -BeNullOrEmpty

    git -C $script:Repo show-ref --verify --quiet 'refs/heads/wt/roll1'
    $LASTEXITCODE | Should -Not -Be 0
    Test-Path -LiteralPath (Join-Path $script:LockDir 'roll1.worktree.json') | Should -BeFalse
  }

  It 'collect refuses detached HEAD in the worktree' {
    & $script:WtScript -Action new -JobId 'detach1' -RepoRoot $script:Repo -LockDir $script:LockDir -SkipLog | Out-Null
    $meta = Get-Content -LiteralPath (Join-Path $script:LockDir 'detach1.worktree.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    # Detach HEAD at current commit
    $head = (git -C $meta.path rev-parse HEAD).Trim()
    git -C $meta.path checkout --detach $head 2>$null | Out-Null

    $err = $null
    try {
      & $script:WtScript -Action collect -JobId 'detach1' -RepoRoot $script:Repo -LockDir $script:LockDir 2>&1 | Out-Null
    }
    catch { $err = $_ }
    $err | Should -Not -BeNullOrEmpty
    "$err" | Should -Match 'Detached|expected branch|symbolic-ref|not on expected'
  }
}

Describe 'check.ps1 L2 worktree stale detection' {
  BeforeAll {
    $script:OrchestraRoot = Split-Path $PSScriptRoot -Parent
    $script:CheckScript = Join-Path $script:OrchestraRoot 'scripts\check.ps1'
    $script:WtScript = Join-Path $script:OrchestraRoot 'scripts\worktree-job.ps1'
  }

  BeforeEach {
    $script:TestLockDir = Join-Path $TestDrive ("locks-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:TestLockDir | Out-Null
  }

  It 'clears stale status=creating claim with -Fix when no dir and no branch' {
    $metaPath = Join-Path $script:TestLockDir 'staleclaim.worktree.json'
    @{
      schema_version = 1
      job_id         = 'staleclaim'
      path           = (Join-Path $TestDrive 'no-such-wt')
      branch         = 'wt/staleclaim'
      base_sha       = '0000000000000000000000000000000000000000'
      status         = 'creating'
      owned_paths    = @()
      log_required   = $false
      created_at     = '2026-01-01T00:00:00Z'
      updated_at     = '2026-01-01T00:00:00Z'
    } | ConvertTo-Json | Set-Content -LiteralPath $metaPath -Encoding UTF8

    $out1 = & $script:CheckScript -LockDir $script:TestLockDir -RepoRoot $script:OrchestraRoot -SkipToolCheck *>&1
    ($out1 | ForEach-Object { "$_" } | Out-String) | Should -Match 'stale claim|status=creating'
    Test-Path -LiteralPath $metaPath | Should -BeTrue

    $out2 = & $script:CheckScript -LockDir $script:TestLockDir -RepoRoot $script:OrchestraRoot -SkipToolCheck -Fix *>&1
    ($out2 | ForEach-Object { "$_" } | Out-String) | Should -Match 'claim file removed'
    Test-Path -LiteralPath $metaPath | Should -BeFalse
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

  It 'live worktree reports OK with -Fix and does not rewrite status to stale' {
    $repo = Join-Path $TestDrive ("live-repo-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $repo | Out-Null
    git -C $repo init -q | Out-Null
    git -C $repo config user.email 'test@example.com'
    git -C $repo config user.name 'Test'
    # Minimal SSOT so check.ps1 does not FAIL on layout (only L2 line is under test)
    @(
      'AGENTS.md',
      '.agents\INDEX.md',
      '.agents\docs\failure-modes.md',
      'scripts\delegate-codex.ps1',
      'scripts\lease-paths.ps1',
      '.gitignore'
    ) | ForEach-Object {
      $p = Join-Path $repo $_
      New-Item -ItemType Directory -Force -Path (Split-Path $p -Parent) | Out-Null
      Set-Content -LiteralPath $p -Value 'stub' -Encoding UTF8
    }
    # gitignore patterns required by check.ps1
    @(
      '.agents/locks/*.lease.json',
      '.agents/locks/*.worktree.json',
      '.agents/logs/codex/*.last.txt'
    ) | Set-Content -LiteralPath (Join-Path $repo '.gitignore') -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $repo 'f.txt') -Value 'x' -Encoding UTF8
    git -C $repo add -A | Out-Null
    git -C $repo commit -qm 'seed' | Out-Null
    $lockDir = Join-Path $repo '.agents\locks'
    New-Item -ItemType Directory -Force -Path $lockDir | Out-Null

    try {
      & $script:WtScript -Action new -JobId 'liveok' -RepoRoot $repo -LockDir $lockDir -SkipLog | Out-Null
      $metaPath = Join-Path $lockDir 'liveok.worktree.json'
      $metaBefore = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
      $metaBefore.status | Should -Be 'active'

      $output = & $script:CheckScript -LockDir $lockDir -RepoRoot $repo -SkipToolCheck -Fix *>&1
      $code = $LASTEXITCODE
      $text = ($output | ForEach-Object { "$_" } | Out-String)
      $code | Should -Be 0 -Because $text
      $text | Should -Match 'worktree:liveok'
      $text | Should -Match 'dir\+branch\+registration OK'
      $text | Should -Not -Match 'marked status=stale'

      $metaAfter = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
      $metaAfter.status | Should -Be 'active'
    }
    finally {
      try {
        $list = git -C $repo worktree list --porcelain 2>$null
        foreach ($line in ($list -split "`r?`n")) {
          if ($line -match '^worktree (.+)$') {
            $p = $Matches[1]
            if ($p -ne $repo) { git -C $repo worktree remove --force $p 2>$null | Out-Null }
          }
        }
      }
      catch { }
    }
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
