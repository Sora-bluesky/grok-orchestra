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
    $before = Get-FileHash -LiteralPath $sample -Algorithm SHA256
    $mtime = (Get-Item -LiteralPath $sample).LastWriteTimeUtc

    Start-Sleep -Milliseconds 50
    $output = & $script:InstallScript -Target $script:Target *>&1
    $LASTEXITCODE | Should -Be 0
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match '\[skip\]'

    $after = Get-FileHash -LiteralPath $sample -Algorithm SHA256
    $after.Hash | Should -Be $before.Hash
    (Get-Item -LiteralPath $sample).LastWriteTimeUtc | Should -Be $mtime
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
    Set-Content -LiteralPath $gi -Value "node_modules/`n" -Encoding UTF8
    & $script:InstallScript -Target $script:Target | Out-Null
    $once = Get-Content -LiteralPath $gi -Raw
    ($once -split 'grok-orchestra begin').Count | Should -Be 2

    & $script:InstallScript -Target $script:Target | Out-Null
    $twice = Get-Content -LiteralPath $gi -Raw
    ($twice -split 'grok-orchestra begin').Count | Should -Be 2
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
}
