#requires -Version 5.1
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'install.ps1' {
  BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    $script:InstallScript = Join-Path $script:RepoRoot 'scripts\install.ps1'
  }

  BeforeEach {
    $script:Target = Join-Path $TestDrive ("app-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:Target | Out-Null
  }

  It 'installs layout into empty target' {
    & $script:InstallScript -Target $script:Target
    $LASTEXITCODE | Should -Be 0

    (Join-Path $script:Target 'AGENTS.md') | Should -Exist
    (Join-Path $script:Target 'scripts\delegate-codex.ps1') | Should -Exist
    (Join-Path $script:Target 'scripts\lease-paths.ps1') | Should -Exist
    (Join-Path $script:Target 'scripts\check.ps1') | Should -Exist
    (Join-Path $script:Target 'scripts\verify-job.ps1') | Should -Exist
    (Join-Path $script:Target 'scripts\lib\path-normalize.ps1') | Should -Exist
    (Join-Path $script:Target '.agents\STATE.example.md') | Should -Exist
    (Join-Path $script:Target '.agents\docs\packets\smoke-001.prompt.txt') | Should -Exist
    (Join-Path $script:Target '.gitignore') | Should -Exist
    (Test-Path -LiteralPath (Join-Path $script:Target '.agents\STATE.md')) | Should -BeFalse
  }

  It 'is idempotent on second run (skips, no byte change without -Force)' {
    & $script:InstallScript -Target $script:Target | Out-Null
    $sample = Join-Path $script:Target 'scripts\delegate-codex.ps1'
    # Mutate so a silent overwrite would change content (hash would diverge).
    Set-Content -LiteralPath $sample -Value 'MUTATED-BY-TEST-DO-NOT-OVERWRITE' -Encoding UTF8
    $before = Get-FileHash -LiteralPath $sample -Algorithm SHA256

    $output = & $script:InstallScript -Target $script:Target *>&1
    $LASTEXITCODE | Should -Be 0
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match '\[skip\]'

    $after = Get-FileHash -LiteralPath $sample -Algorithm SHA256
    $after.Hash | Should -Be $before.Hash
    (Get-Content -LiteralPath $sample -Raw).Trim() | Should -Be 'MUTATED-BY-TEST-DO-NOT-OVERWRITE'
  }

  It 'does not overwrite existing AGENTS.md; writes AGENTS.grok-orchestra.md' {
    $agents = Join-Path $script:Target 'AGENTS.md'
    Set-Content -LiteralPath $agents -Value 'app-owned-agents' -Encoding UTF8
    & $script:InstallScript -Target $script:Target | Out-Null
    $LASTEXITCODE | Should -Be 0

    (Get-Content -LiteralPath $agents -Raw).Trim() | Should -Be 'app-owned-agents'
    (Join-Path $script:Target 'AGENTS.grok-orchestra.md') | Should -Exist
  }

  It 'appends orchestra gitignore block only once' {
    $gi = Join-Path $script:Target '.gitignore'
    $prefix = "node_modules/`r`n# app-owned-marker-keep`r`n"
    [System.IO.File]::WriteAllText($gi, $prefix, (New-Object System.Text.UTF8Encoding $false))
    & $script:InstallScript -Target $script:Target | Out-Null
    $once = [System.IO.File]::ReadAllText($gi)
    ($once -split 'grok-orchestra begin').Count | Should -Be 2
    $once.StartsWith($prefix.TrimEnd("`r", "`n").Substring(0, 12)) | Should -BeTrue
    $once | Should -Match 'app-owned-marker-keep'

    & $script:InstallScript -Target $script:Target | Out-Null
    $twice = [System.IO.File]::ReadAllText($gi)
    ($twice -split 'grok-orchestra begin').Count | Should -Be 2
    $twice | Should -Match 'app-owned-marker-keep'
  }

  It 'does not copy .agents/worktrees content' {
    $wt = Join-Path $script:RepoRoot '.agents\worktrees\_install_test_sentinel'
    New-Item -ItemType Directory -Force -Path $wt | Out-Null
    $sentinel = Join-Path $wt 'should-not-copy.txt'
    Set-Content -LiteralPath $sentinel -Value 'secret-worktree' -Encoding UTF8
    try {
      & $script:InstallScript -Target $script:Target | Out-Null
      $leaked = Join-Path $script:Target '.agents\worktrees\_install_test_sentinel\should-not-copy.txt'
      (Test-Path -LiteralPath $leaked) | Should -BeFalse
    }
    finally {
      Remove-Item -LiteralPath $wt -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  It 'DryRun writes nothing' {
    $before = @(Get-ChildItem -LiteralPath $script:Target -Force -Recurse -ErrorAction SilentlyContinue)
    $before.Count | Should -Be 0
    & $script:InstallScript -Target $script:Target -DryRun | Out-Null
    $LASTEXITCODE | Should -Be 0
    $after = @(Get-ChildItem -LiteralPath $script:Target -Force -Recurse -ErrorAction SilentlyContinue)
    $after.Count | Should -Be 0
  }

  It 'rejects Target equal to this repository' {
    $err = $null
    try {
      & $script:InstallScript -Target $script:RepoRoot 2>&1 | Out-Null
    }
    catch {
      $err = $_
    }
    $err | Should -Not -BeNullOrEmpty
    "$err" | Should -Match 'must not be this repository'
  }

  It 'generated smoke packet does not reference fixtures/sample.txt' {
    & $script:InstallScript -Target $script:Target | Out-Null
    $smoke = Get-Content -LiteralPath (Join-Path $script:Target '.agents\docs\packets\smoke-001.prompt.txt') -Raw
    $smoke | Should -Not -Match 'fixtures/sample\.txt'
    $smoke | Should -Match 'TODO\(target-app\)'
    # Source smoke must not have been bulk-copied as the only content
    $smoke | Should -Not -Match 'fixtures/sample.txt for clarity for a new contributor to grok-orchestra'
  }

  It 'does not copy dogfooding plan-*.prompt.txt packets' {
    & $script:InstallScript -Target $script:Target | Out-Null
    $packets = Join-Path $script:Target '.agents\docs\packets'
    (Test-Path -LiteralPath (Join-Path $packets 'smoke-001.prompt.txt')) | Should -BeTrue
    @(Get-ChildItem -LiteralPath $packets -Filter 'plan-*.prompt.txt' -ErrorAction SilentlyContinue).Count | Should -Be 0
  }
}
