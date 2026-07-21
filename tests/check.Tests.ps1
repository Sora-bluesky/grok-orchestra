#requires -Version 5.1
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'check.ps1' {
  BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    $script:CheckScript = Join-Path $script:RepoRoot 'scripts\check.ps1'
  }

  BeforeEach {
    $script:TestLockDir = Join-Path $TestDrive ("locks-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:TestLockDir | Out-Null
  }

  It 'clean locks report OK/WARN only and exit 0' {
    $output = & $script:CheckScript -LockDir $script:TestLockDir -RepoRoot $script:RepoRoot *>&1
    $LASTEXITCODE | Should -Be 0
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Not -Match '\[FAIL\]'
  }

  It 'detects stale write-job.lock without -Fix' {
    $lockPath = Join-Path $script:TestLockDir 'write-job.lock'
    @"
job_id=dead-job
type=implement
started=2026-01-01T00:00:00
pid=999999
"@ | Set-Content -LiteralPath $lockPath -Encoding UTF8

    $output = & $script:CheckScript -LockDir $script:TestLockDir -RepoRoot $script:RepoRoot *>&1
    $LASTEXITCODE | Should -Be 0
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'stale pid=999999'
    Test-Path -LiteralPath $lockPath | Should -BeTrue
  }

  It 'removes stale write-job.lock with -Fix' {
    $lockPath = Join-Path $script:TestLockDir 'write-job.lock'
    @"
job_id=dead-job
type=implement
started=2026-01-01T00:00:00
pid=999999
"@ | Set-Content -LiteralPath $lockPath -Encoding UTF8

    $output = & $script:CheckScript -LockDir $script:TestLockDir -RepoRoot $script:RepoRoot -Fix *>&1
    $LASTEXITCODE | Should -Be 0
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'removed'
    Test-Path -LiteralPath $lockPath | Should -BeFalse
  }

  It 'does not auto-remove legacy lock without pid=' {
    $lockPath = Join-Path $script:TestLockDir 'write-job.lock'
    @"
job_id=legacy
type=implement
started=2026-01-01T00:00:00
"@ | Set-Content -LiteralPath $lockPath -Encoding UTF8

    $output = & $script:CheckScript -LockDir $script:TestLockDir -RepoRoot $script:RepoRoot -Fix *>&1
    $LASTEXITCODE | Should -Be 0
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'legacy lock without pid='
    Test-Path -LiteralPath $lockPath | Should -BeTrue
  }

  It 'marks orphan running lease as stale with -Fix' {
    $leasePath = Join-Path $script:TestLockDir 'orphan.lease.json'
    @{
      job_id      = 'orphan'
      owned_paths = @('src')
      status      = 'running'
      acquired_at = '2026-01-01T00:00:00'
    } | ConvertTo-Json | Set-Content -LiteralPath $leasePath -Encoding UTF8

    $output = & $script:CheckScript -LockDir $script:TestLockDir -RepoRoot $script:RepoRoot -Fix *>&1
    $LASTEXITCODE | Should -Be 0
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'status=stale'
    $lease = Get-Content -LiteralPath $leasePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $lease.status | Should -Be 'stale'
  }
}
