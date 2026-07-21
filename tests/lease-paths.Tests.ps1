#requires -Version 5.1
#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'lease-paths.ps1' {
  BeforeAll {
    $script:LeaseScript = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\lease-paths.ps1'

    function script:Invoke-Lease {
      param(
        [Parameter(Mandatory)]
        [ValidateSet('acquire', 'check', 'release')]
        [string] $Action,
        [string] $JobId = '',
        [string[]] $OwnedPaths = @(),
        [string] $Type = ''
      )
      $params = @{
        Action  = $Action
        LockDir = $script:TestLockDir
      }
      if ($JobId) { $params.JobId = $JobId }
      if ($OwnedPaths.Count -gt 0) { $params.OwnedPaths = $OwnedPaths }
      if ($Type) { $params.Type = $Type }

      & $script:LeaseScript @params
    }
  }

  BeforeEach {
    # Unique dir per test so leftover lease files cannot cross-contaminate
    $script:TestLockDir = Join-Path $TestDrive ("locks-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $script:TestLockDir | Out-Null
  }

  It 'acquire creates lease json with status running' {
    Invoke-Lease -Action acquire -JobId 'job-a' -OwnedPaths @('src')
    $leasePath = Join-Path $script:TestLockDir 'job-a.lease.json'
    $leasePath | Should -Exist
    $lease = Get-Content -LiteralPath $leasePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $lease.status | Should -Be 'running'
    $lease.job_id | Should -Be 'job-a'
    @($lease.owned_paths) | Should -Contain 'src'
  }

  It 'double acquire on same path throws lease overlap' {
    Invoke-Lease -Action acquire -JobId 'job-a' -OwnedPaths @('src')
    {
      Invoke-Lease -Action acquire -JobId 'job-b' -OwnedPaths @('src')
    } | Should -Throw -ExpectedMessage '*lease overlap*'
  }

  It 'prefix overlap check exits 1 for src vs src/lib' {
    Invoke-Lease -Action acquire -JobId 'job-a' -OwnedPaths @('src')
    # Write-Host goes to host/information stream; capture all streams for message assert
    $output = & $script:LeaseScript -Action check -OwnedPaths @('src/lib') -LockDir $script:TestLockDir *>&1
    $LASTEXITCODE | Should -Be 1
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'overlap'
  }

  It 'boundary non-overlap check exits 0 for src vs src2' {
    Invoke-Lease -Action acquire -JobId 'job-a' -OwnedPaths @('src')
    $output = & $script:LeaseScript -Action check -OwnedPaths @('src2') -LockDir $script:TestLockDir *>&1
    $LASTEXITCODE | Should -Be 0
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'lease check: free'
  }

  It 'release sets status released and allows re-acquire' {
    Invoke-Lease -Action acquire -JobId 'job-a' -OwnedPaths @('src')
    Invoke-Lease -Action release -JobId 'job-a'
    $leasePath = Join-Path $script:TestLockDir 'job-a.lease.json'
    $lease = Get-Content -LiteralPath $leasePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $lease.status | Should -Be 'released'

    Invoke-Lease -Action acquire -JobId 'job-b' -OwnedPaths @('src')
    $leaseB = Get-Content -LiteralPath (Join-Path $script:TestLockDir 'job-b.lease.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $leaseB.status | Should -Be 'running'
  }

  It 'absolute path throws must be repo-relative' {
    {
      Invoke-Lease -Action check -OwnedPaths @('C:\Windows\System32')
    } | Should -Throw -ExpectedMessage '*must be repo-relative*'
  }

  It '../escape path throws must stay inside the repository' {
    {
      Invoke-Lease -Action check -OwnedPaths @('../escape')
    } | Should -Throw -ExpectedMessage '*must stay inside the repository*'
  }

  It 'mid-path .. segment throws must stay inside the repository' {
    {
      Invoke-Lease -Action check -OwnedPaths @('src/../escape')
    } | Should -Throw -ExpectedMessage '*must stay inside the repository*'
  }

  It 'leading-dot path .agents is accepted as repo-relative' {
    $output = & $script:LeaseScript -Action check -OwnedPaths @('.agents/locks') -LockDir $script:TestLockDir *>&1
    $LASTEXITCODE | Should -Be 0
    ($output | ForEach-Object { "$_" } | Out-String) | Should -Match 'lease check: free'
  }
}
