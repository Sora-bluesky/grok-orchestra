#requires -Version 5.1
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'verify-job.ps1' {
  BeforeAll {
    $script:OrchestraRoot = Split-Path $PSScriptRoot -Parent
    $script:VerifyScript = Join-Path $script:OrchestraRoot 'scripts\verify-job.ps1'
  }

  BeforeEach {
    $script:Repo = Join-Path $TestDrive ("repo-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:Repo | Out-Null
    Push-Location $script:Repo
    git init -q | Out-Null
    git config user.email 'test@example.com'
    git config user.name 'Test'
    # Seed a tracked test file and non-test file
    New-Item -ItemType Directory -Force -Path (Join-Path $script:Repo 'tests') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $script:Repo 'src') | Out-Null
    Set-Content -LiteralPath (Join-Path $script:Repo 'tests\Sample.Tests.ps1') -Value '# sample test' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $script:Repo 'src\app.ps1') -Value '# app' -Encoding UTF8
    git add -A
    git commit -qm 'seed'
  }

  AfterEach {
    Pop-Location
  }

  It 'passes on clean tree with -SkipLog' {
    $output = & $script:VerifyScript -JobId 'x' -SkipLog -RepoRoot $script:Repo *>&1
    $LASTEXITCODE | Should -Be 0
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'verify-job: PASS'
  }

  It 'fails when changed path escapes OwnedPaths' {
    Set-Content -LiteralPath (Join-Path $script:Repo 'src\app.ps1') -Value '# app changed' -Encoding UTF8
    $output = & $script:VerifyScript -JobId 'x' -SkipLog -RepoRoot $script:Repo -OwnedPaths @('docs') *>&1
    $LASTEXITCODE | Should -Be 1
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'outside owned_paths'
  }

  It 'fails on unstaged test file deletion' {
    Remove-Item -LiteralPath (Join-Path $script:Repo 'tests\Sample.Tests.ps1') -Force
    $output = & $script:VerifyScript -JobId 'x' -SkipLog -RepoRoot $script:Repo *>&1
    $LASTEXITCODE | Should -Be 1
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'f07:tests'
  }

  It 'fails on staged test file deletion' {
    git rm -q 'tests/Sample.Tests.ps1'
    $output = & $script:VerifyScript -JobId 'x' -SkipLog -RepoRoot $script:Repo *>&1
    $LASTEXITCODE | Should -Be 1
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'f07:tests'
  }

  It 'allows test deletion with -AcceptTestChanges' {
    Remove-Item -LiteralPath (Join-Path $script:Repo 'tests\Sample.Tests.ps1') -Force
    $output = & $script:VerifyScript -JobId 'x' -SkipLog -RepoRoot $script:Repo -AcceptTestChanges *>&1
    $LASTEXITCODE | Should -Be 0
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'verify-job: PASS'
  }

  It 'warns on TODO stub in added lines but still passes' {
    Set-Content -LiteralPath (Join-Path $script:Repo 'src\app.ps1') -Value "# TODO: implement later`n# app" -Encoding UTF8
    $output = & $script:VerifyScript -JobId 'x' -SkipLog -RepoRoot $script:Repo *>&1
    $LASTEXITCODE | Should -Be 0
    $text = ($output | ForEach-Object { "$_" } | Out-String)
    $text | Should -Match '\[WARN\] stub'
    $text | Should -Match 'verify-job: PASS'
  }

  It 'fails on invalid BaseRef instead of false PASS' {
    $output = & $script:VerifyScript -JobId 'x' -SkipLog -RepoRoot $script:Repo -BaseRef 'definitely-not-a-ref-xyz' *>&1
    $LASTEXITCODE | Should -Be 1
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'verify-job: FAIL'
  }

  It 'rejects option-shaped BaseRef (injection guard)' {
    $output = & $script:VerifyScript -JobId 'x' -SkipLog -RepoRoot $script:Repo -BaseRef '--output=/tmp/x' *>&1
    $LASTEXITCODE | Should -Be 1
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'git option|BaseRef'
  }

  It 'fails when untracked path escapes OwnedPaths' {
    Set-Content -LiteralPath (Join-Path $script:Repo 'outside.txt') -Value 'leak' -Encoding UTF8
    $output = & $script:VerifyScript -JobId 'x' -SkipLog -RepoRoot $script:Repo -OwnedPaths @('src') *>&1
    $LASTEXITCODE | Should -Be 1
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'outside owned_paths'
  }
}
