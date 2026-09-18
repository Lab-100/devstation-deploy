function Deploy-InstallCore($Ctx) {
    Write-Step 'Установка базового набора (Git, pwsh7, Node LTS, Python, Ollama, gh, Docker Desktop)'

    if (-not (Test-Command winget)) { Write-Fatal 'winget отсутствует — см. шаг env-check.' }
    if (-not (Test-Admin)) { Write-Fatal 'Установки требуют администратора. Запусти деплойер из админской консоли или без -NoElevate.' }

    $apps = @(
        @{ Id = 'Microsoft.PowerShell'; Check = 'pwsh' },
        @{ Id = 'Git.Git'; Check = 'git' },
        @{ Id = 'OpenJS.NodeJS.LTS'; Check = 'node' },
        @{ Id = 'Python.Python.3.12'; Check = 'python' },
        @{ Id = 'Ollama.Ollama'; Check = 'ollama' },
        @{ Id = 'GitHub.cli'; Check = 'gh' },
        @{ Id = 'Docker.DockerDesktop'; Check = 'Docker Desktop.exe' }
    )

    foreach ($app in $apps) {
        $already = $false
        if ($app.Check) {
            if ($app.Check -match '\.exe') { $already = Test-Path (Join-Path $env:ProgramFiles "Docker\Docker\$($app.Check)") -or (Test-Path (Join-Path ${env:ProgramFiles(x86)} "Docker\Docker\$($app.Check)")) }
            else { $already = Test-Command $app.Check }
        }
        if ($already) { Write-OK "$($app.Id): уже установлено" ; continue }
        Write-Note "winget install $($app.Id) ..."
        winget install --id $app.Id --exact --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) { Write-Warn "$($app.Id): winget вернул $LASTEXITCODE (возможно уже стоит / требуется перевод к себе)" }
    }
    Refresh-Path

    if (-not (Test-Command node)) { Write-Fatal 'Node.js не установился — opencode не сможет.' }
    Write-Note 'npm global: opencode-ai ...'
    npm install -g opencode-ai 2>&1 | Select-Object -Last 2
    if ($LASTEXITCODE -ne 0) { Write-Warn 'npm install opencode-ai вернул ненулевой код' }
    Refresh-Path

    Write-OK 'Базовый набор установлен.'
    Write-Note "opencode: $((opencode --version 2>&1) -join '')"
}