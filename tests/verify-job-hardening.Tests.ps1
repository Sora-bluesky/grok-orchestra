#requires -Version 5.1
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'verify-job.ps1 hardening (plan 005)' {
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
    New-Item -ItemType Directory -Force -Path (Join-Path $script:Repo 'src') | Out-Null
    Set-Content -LiteralPath (Join-Path $script:Repo 'src\app.ps1') -Value '# app' -Encoding UTF8
    git add -A
    git commit -qm 'seed'
  }

  AfterEach {
    Pop-Location
  }

  It 'treats non-ASCII untracked path as outside OwnedPaths (no quote mangling)' {
    # U+00E9 Latin small letter e with acute
    $name = ([char]0x00E9).ToString() + '.Tests.ps1'
    Set-Content -LiteralPath (Join-Path $script:Repo $name) -Value '# test' -Encoding UTF8
    $output = & $script:VerifyScript -JobId 'x' -SkipLog -RepoRoot $script:Repo -OwnedPaths @('src') *>&1
    $LASTEXITCODE | Should -Be 1
    $text = ($output | ForEach-Object { "$_" } | Out-String)
    $text | Should -Match 'outside owned_paths'
    # Path should appear with the accented character, not C-style octal quotes
    $text | Should -Not -Match '\\\\303'
  }

  It 'treats leading-space filename as a real path outside OwnedPaths' {
    $spaced = Join-Path $script:Repo ' leading-space.txt'
    Set-Content -LiteralPath $spaced -Value 'x' -Encoding UTF8
    $output = & $script:VerifyScript -JobId 'x' -SkipLog -RepoRoot $script:Repo -OwnedPaths @('src') *>&1
    $LASTEXITCODE | Should -Be 1
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'outside owned_paths'
  }

  It 'skips untracked content scan over 1MB with WARN and still PASS' {
    $big = Join-Path $script:Repo 'big-untracked.bin'
    $fs = [System.IO.File]::Open($big, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    try {
      $fs.SetLength(2MB)
    }
    finally {
      $fs.Dispose()
    }
    $output = & $script:VerifyScript -JobId 'x' -SkipLog -RepoRoot $script:Repo *>&1
    $LASTEXITCODE | Should -Be 0
    $text = ($output | ForEach-Object { "$_" } | Out-String)
    $text | Should -Match '\[WARN\] scan'
    $text | Should -Match 'size > 1MB'
    $text | Should -Match 'verify-job: PASS'
  }

  It 'still fails F07 when a copy (C) record precedes a test-file deletion' {
    # Regression: name-status -z copy records are three fields; treating C like single-path
    # desyncs the parser and can drop a following D of a test file (Codex P2 on PR #17).
    New-Item -ItemType Directory -Force -Path (Join-Path $script:Repo 'tests') | Out-Null
    $payload = (1..80 | ForEach-Object { "line $_ unique-copy-payload-for-similarity" }) -join "`n"
    Set-Content -LiteralPath (Join-Path $script:Repo 'src\seed-copy.ps1') -Value $payload -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $script:Repo 'tests\Doomed.Tests.ps1') -Value '# doomed test' -Encoding UTF8
    git add -A
    git commit -qm 'seed-for-copy'
    git config diff.renames copies
    Copy-Item -LiteralPath (Join-Path $script:Repo 'src\seed-copy.ps1') -Destination (Join-Path $script:Repo 'src\seed-copy-2.ps1')
    Remove-Item -LiteralPath (Join-Path $script:Repo 'tests\Doomed.Tests.ps1') -Force
    git add -A
    $output = & $script:VerifyScript -JobId 'x' -SkipLog -RepoRoot $script:Repo *>&1
    $LASTEXITCODE | Should -Be 1
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'f07:tests'
  }
}

Describe 'path-normalize preserves segment whitespace' {
  BeforeAll {
    . (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\lib\path-normalize.ps1')
  }

  It 'keeps leading space in a filename segment' {
    $n = ConvertTo-NormalizedRepoPath -Path ' leading.txt'
    $n | Should -Be ' leading.txt'
  }

  It 'keeps .agents and does not collapse leading-dot segments' {
    ConvertTo-NormalizedRepoPath -Path '.agents/config' | Should -Be '.agents/config'
  }
}

Describe 'install.ps1 junction self-target (plan 005)' {
  BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    $script:InstallScript = Join-Path $script:RepoRoot 'scripts\install.ps1'
  }

  It 'rejects junction alias of the repository root' {
    $juncParent = Join-Path $TestDrive 'junc-parent'
    New-Item -ItemType Directory -Force -Path $juncParent | Out-Null
    $junc = Join-Path $juncParent 'repo-link'
    $created = $false
    try {
      New-Item -ItemType Junction -Path $junc -Target $script:RepoRoot -ErrorAction Stop | Out-Null
      $created = $true
    }
    catch {
      Set-ItResult -Skipped -Because "Junction creation not available in this environment: $($_.Exception.Message)"
      return
    }

    if ($created) {
      $err = $null
      try {
        & $script:InstallScript -Target $junc 2>&1 | Out-Null
      }
      catch {
        $err = $_
      }
      $err | Should -Not -BeNullOrEmpty
      "$err" | Should -Match 'must not be this repository'
    }
  }
}
