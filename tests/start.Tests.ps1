# Tests for start.ps1, run against the fake docker in tests/bin (see tests/run.sh).
BeforeAll {
    $env:PATH = (Join-Path $PSScriptRoot 'bin') + [IO.Path]::PathSeparator + $env:PATH

    # Runs start.ps1 from / in a scratch copy of the repo.
    function Invoke-Start([string]$EnvFile, [string]$FailOn = '') {
        $work = (New-Item -ItemType Directory (Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid()))).FullName
        Copy-Item (Join-Path $PSScriptRoot '..' 'start.ps1') $work
        Set-Content (Join-Path $work '.env') $EnvFile
        $env:FAKE_DOCKER_LOG = Join-Path $work 'calls.log'
        $env:FAKE_DOCKER_FAIL = $FailOn
        Push-Location /
        try { pwsh -NoProfile -File (Join-Path $work 'start.ps1') *> (Join-Path $work 'out') }
        finally { Pop-Location }
        [pscustomobject]@{
            Dir   = $work
            Exit  = $LASTEXITCODE
            Calls = @(Get-Content $env:FAKE_DOCKER_LOG -ErrorAction SilentlyContinue)
        }
    }
}

Describe 'start.ps1' {
    It 'logs in with the token on stdin, then pulls and starts' {
        $r = Invoke-Start 'PROOFARC_PULL_TOKEN=ghp_test=123'
        $r.Calls | Should -Be @(
            "$($r.Dir) | login ghcr.io -u proofarc --password-stdin"
            "$($r.Dir) | compose pull"
            "$($r.Dir) | compose up -d")
        (Get-Content "$($r.Dir)/calls.log.stdin" -Raw).Trim() | Should -Be 'ghp_test=123'
        $r.Exit | Should -Be 0
    }

    It 'skips login when the token is empty' {
        $r = Invoke-Start 'PROOFARC_PULL_TOKEN='
        $r.Calls | Should -Be @("$($r.Dir) | compose pull", "$($r.Dir) | compose up -d")
        $r.Exit | Should -Be 0
    }

    It 'skips login when the token key is missing' {
        $r = Invoke-Start 'PROOFARC_URL=https://example.test'
        $r.Calls | Should -Be @("$($r.Dir) | compose pull", "$($r.Dir) | compose up -d")
    }

    It 'stops before pulling when login fails' {
        $r = Invoke-Start 'PROOFARC_PULL_TOKEN=bad' 'login ghcr.io -u proofarc --password-stdin'
        $r.Calls | Should -Be @("$($r.Dir) | login ghcr.io -u proofarc --password-stdin")
        $r.Exit | Should -Not -Be 0
    }

    It 'does not start when pull fails' {
        $r = Invoke-Start 'PROOFARC_PULL_TOKEN=' 'compose pull'
        $r.Calls | Should -Be @("$($r.Dir) | compose pull")
        $r.Exit | Should -Not -Be 0
    }
}
