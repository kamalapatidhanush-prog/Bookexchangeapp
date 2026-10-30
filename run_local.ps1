param(
    [switch]$ApiOnly
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
$pythonPath = Join-Path $repoRoot '.venv\Scripts\python.exe'
if (-not (Test-Path $pythonPath)) {
    $pythonCommand = Get-Command python -ErrorAction Stop
    $pythonPath = $pythonCommand.Source
}

if ([string]::IsNullOrWhiteSpace($env:API_TOKEN_SECRET)) {
    $secretDirectory = Join-Path $env:LOCALAPPDATA 'LeafAndLore'
    $secretPath = Join-Path $secretDirectory 'api-token-secret'
    if (-not (Test-Path $secretPath)) {
        New-Item -ItemType Directory -Path $secretDirectory -Force | Out-Null
        $secret = & $pythonPath -c "import secrets; print(secrets.token_urlsafe(48))"
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not generate the local API signing secret.'
        }
        [System.IO.File]::WriteAllText($secretPath, $secret.Trim())
    }
    $env:API_TOKEN_SECRET = (Get-Content -Raw $secretPath).Trim()
}

if ($env:API_TOKEN_SECRET.Trim().Length -lt 32) {
    throw 'API_TOKEN_SECRET must contain at least 32 characters.'
}

$apiPort = 8081
if (-not [string]::IsNullOrWhiteSpace($env:API_PORT)) {
    if (-not [int]::TryParse($env:API_PORT, [ref]$apiPort) -or $apiPort -lt 1 -or $apiPort -gt 65535) {
        throw 'API_PORT must be a valid TCP port between 1 and 65535.'
    }
}
$env:API_PORT = "$apiPort"
$apiUri = "http://127.0.0.1:$apiPort/health"
$apiProcess = $null
$apiReady = $false

try {
    try {
        $health = Invoke-RestMethod -Uri $apiUri -TimeoutSec 2
        $apiReady = $health.status -eq 'ok'
    }
    catch {
        $apiReady = $false
    }

    if ($apiReady) {
        Write-Host "Leaf & Lore API is already healthy on port $apiPort."
    }
    else {
        Write-Host 'Starting the Leaf & Lore API...'
        $apiProcess = Start-Process `
            -FilePath $pythonPath `
            -ArgumentList @('api/server.py') `
            -WorkingDirectory $repoRoot `
            -NoNewWindow `
            -PassThru

        $deadline = [DateTime]::UtcNow.AddSeconds(60)
        do {
            if ($apiProcess.HasExited) {
                throw "The API exited with code $($apiProcess.ExitCode). Review the server output above."
            }

            try {
                $health = Invoke-RestMethod -Uri $apiUri -TimeoutSec 2
                $apiReady = $health.status -eq 'ok'
            }
            catch {
                $apiReady = $false
            }

            if (-not $apiReady) {
                Start-Sleep -Milliseconds 500
            }
        } while (-not $apiReady -and [DateTime]::UtcNow -lt $deadline)

        if (-not $apiReady) {
            throw 'The API did not become healthy within 60 seconds.'
        }
        Write-Host 'Leaf & Lore API is healthy.'
    }

    if ($ApiOnly) {
        if ($apiProcess) {
            Wait-Process -Id $apiProcess.Id
        }
    }
    else {
        Write-Host "Starting Leaf & Lore in Chrome (API port $apiPort). Press Ctrl+C to stop."
        Push-Location $repoRoot
        try {
            & flutter run -d chrome "--dart-define=API_BASE_URL=http://127.0.0.1:$apiPort"
            if ($LASTEXITCODE -ne 0) {
                throw "Flutter exited with code $LASTEXITCODE."
            }
        }
        finally {
            Pop-Location
        }
    }
}
finally {
    if ($apiProcess -and -not $apiProcess.HasExited) {
        Stop-Process -Id $apiProcess.Id
    }
}
