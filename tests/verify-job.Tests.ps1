#requires -Version 5.1
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'verify-job.ps1' {
  BeforeAll {
    . (Join-Path $PSScriptRoot 'helpers\Clear-TestDriveGit.ps1')
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
    try { Pop-Location } catch { }
    Clear-TestDriveAfterGit -RepoRoot $script:Repo -DriveRoot $TestDrive
  }

  AfterAll {
    Clear-TestDriveAfterGit -DriveRoot $TestDrive
  }

  It 'passes on clean tree with -SkipLog' {
    $output = & $script:VerifyScript -JobId 'x' -SkipLog -RepoRoot $script:Repo *>&1
    $LASTEXITCODE | Should -Be 0
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'verify-job: PASS'
  }

  It 'restores caller PWD after PASS and FAIL' {
    $caller = Join-Path $TestDrive ("caller-pwd-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $caller | Out-Null
    Push-Location $caller
    try {
      $beforePass = (Get-Location).Path
      & $script:VerifyScript -JobId 'pwd-pass' -SkipLog -RepoRoot $script:Repo *>$null
      $LASTEXITCODE | Should -Be 0
      (Get-Location).Path | Should -Be $beforePass

      # Force FAIL via OwnedPaths escape
      Set-Content -LiteralPath (Join-Path $script:Repo 'src\app.ps1') -Value '# changed' -Encoding UTF8
      $beforeFail = (Get-Location).Path
      & $script:VerifyScript -JobId 'pwd-fail' -SkipLog -RepoRoot $script:Repo -OwnedPaths @('docs') *>$null
      $LASTEXITCODE | Should -Be 1
      (Get-Location).Path | Should -Be $beforeFail
    }
    finally {
      Pop-Location
    }
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

  It 'resolves BaseRef HEAD to a full 40-char SHA' {
    $output = & $script:VerifyScript -JobId 'x' -SkipLog -RepoRoot $script:Repo -BaseRef 'HEAD' *>&1
    $LASTEXITCODE | Should -Be 0
    $text = ($output | ForEach-Object { "$_" } | Out-String)
    $text | Should -Match 'git:baseref: resolved to [0-9a-fA-F]{40}'
    if ($text -match 'resolved to ([0-9a-fA-F]+)') {
      $Matches[1].Length | Should -Be 40
    }
    else {
      throw 'resolved SHA not found in verify-job output'
    }
  }

  It 'fails on untracked test file containing it.skip' {
    Set-Content -LiteralPath (Join-Path $script:Repo 'tests\New.Tests.ps1') -Value "it.skip('pending', () => {})" -Encoding UTF8
    $output = & $script:VerifyScript -JobId 'x' -SkipLog -RepoRoot $script:Repo *>&1
    $LASTEXITCODE | Should -Be 1
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'f07:tests'
  }

  It 'keeps leading-dot .agents under OwnedPaths .agents' {
    New-Item -ItemType Directory -Force -Path (Join-Path $script:Repo '.agents') | Out-Null
    Set-Content -LiteralPath (Join-Path $script:Repo '.agents\config.txt') -Value 'seed' -Encoding UTF8
    git add -A
    git commit -qm 'seed-agents'
    Set-Content -LiteralPath (Join-Path $script:Repo '.agents\config.txt') -Value 'changed' -Encoding UTF8
    $output = & $script:VerifyScript -JobId 'x' -SkipLog -RepoRoot $script:Repo -OwnedPaths @('.agents') *>&1
    $LASTEXITCODE | Should -Be 0
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'verify-job: PASS'
  }

  It 'does not treat OwnedPaths agents as covering .agents paths' {
    New-Item -ItemType Directory -Force -Path (Join-Path $script:Repo '.agents') | Out-Null
    Set-Content -LiteralPath (Join-Path $script:Repo '.agents\secret.txt') -Value 'seed' -Encoding UTF8
    git add -A
    git commit -qm 'seed-dot-agents'
    Set-Content -LiteralPath (Join-Path $script:Repo '.agents\secret.txt') -Value 'leaked' -Encoding UTF8
    $output = & $script:VerifyScript -JobId 'x' -SkipLog -RepoRoot $script:Repo -OwnedPaths @('agents') *>&1
    $LASTEXITCODE | Should -Be 1
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'outside owned_paths'
  }

  It 'fails when test file is renamed out of tests/' {
    git mv 'tests/Sample.Tests.ps1' 'src/Sample.ps1'
    $output = & $script:VerifyScript -JobId 'x' -SkipLog -RepoRoot $script:Repo *>&1
    $LASTEXITCODE | Should -Be 1
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'f07:tests'
  }
}
