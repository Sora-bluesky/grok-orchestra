#requires -Version 5.1
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'delegate-codex.ps1 Prompt Contract gate' {
  BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    $script:DelegateScript = Join-Path $script:RepoRoot 'scripts\delegate-codex.ps1'
    $script:SmokePacket = Join-Path $script:RepoRoot '.agents\docs\packets\smoke-001.prompt.txt'

    # Isolate from real codex: empty APPDATA hides npm codex.js; PATH fake fails if exec is reached.
    $script:OrigPath = $env:PATH
    $script:OrigAppData = $env:APPDATA
    $fakeBin = Join-Path $TestDrive 'fake-bin'
    New-Item -ItemType Directory -Force -Path $fakeBin | Out-Null
    $fakeCmd = Join-Path $fakeBin 'codex.cmd'
    @(
      '@echo off'
      'echo codex must not be invoked by unit tests 1>&2'
      'exit /b 99'
    ) | Set-Content -LiteralPath $fakeCmd -Encoding ASCII
    $fakeAppData = Join-Path $TestDrive 'appdata'
    New-Item -ItemType Directory -Force -Path $fakeAppData | Out-Null
    $env:APPDATA = $fakeAppData
    $env:PATH = "$fakeBin;$env:PATH"
  }

  AfterAll {
    if ($null -ne $script:OrigPath) { $env:PATH = $script:OrigPath }
    if ($null -ne $script:OrigAppData) { $env:APPDATA = $script:OrigAppData }
  }

  BeforeEach {
    $script:TempDir = Join-Path $TestDrive 'packets'
    New-Item -ItemType Directory -Force -Path $script:TempDir | Out-Null
  }

  It 'rejects prompt missing a required heading with incomplete message' {
    $promptPath = Join-Path $script:TempDir 'missing-heading.prompt.txt'
    # Intentionally omit ## Constraints
    @'
## Objective
Smoke test incomplete contract.

## Relevant files
- AGENTS.md

## Acceptance checks
- none

## Output format
## TL;DR
'@ | Set-Content -LiteralPath $promptPath -Encoding UTF8

    $err = $null
    try {
      & $script:DelegateScript -JobId 'test-missing-contract' -Type review -PromptFile $promptPath 2>&1 | Out-Null
    }
    catch {
      $err = $_
    }
    $err | Should -Not -BeNullOrEmpty
    $msg = "$err"
    $msg | Should -Match 'Prompt Contract incomplete'
    $msg | Should -Match '## Constraints'
    $msg | Should -Not -Match 'codex must not be invoked'
  }

  It 'rejects missing PromptFile with not found message' {
    $missingPath = Join-Path $script:TempDir 'does-not-exist.prompt.txt'
    $err = $null
    try {
      & $script:DelegateScript -JobId 'test-missing-file' -Type review -PromptFile $missingPath 2>&1 | Out-Null
    }
    catch {
      $err = $_
    }
    $err | Should -Not -BeNullOrEmpty
    "$err" | Should -Match 'Prompt file not found'
  }

  It 'complete smoke packet passes Test-PromptContract (missing headings empty)' {
    # Indirect check of the same required-heading set as Test-PromptContract in the script,
    # without invoking codex exec (plan 001 allows this for case 3).
    $text = Get-Content -LiteralPath $script:SmokePacket -Raw -Encoding UTF8
    $required = @('## Objective', '## Constraints', '## Relevant files', '## Acceptance checks', '## Output format')
    $missing = @()
    foreach ($h in $required) {
      if ($text -notmatch [regex]::Escape($h)) { $missing += $h }
    }
    $missing | Should -BeNullOrEmpty
  }
}
