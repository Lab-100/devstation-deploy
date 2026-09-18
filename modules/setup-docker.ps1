function Deploy-DockerInstall($Ctx) {
    Write-Step 'Docker Desktop: подготовка (WSL2, установка)'

    $wslStatus = $null
    try { $wslStatus = & wsl.exe --status 2>&1 | Out-String } catch { }
    if ($wslStatus -match 'не установлена|not installed|No installed distributions|WSL.*requires a reboot') {
        Write-Warn 'WSL2 отсутствует/пребывает в неполном состоянии.'
        if (-not (Test-Admin)) { Write-Fatal 'Для включения WSL нужен администратор.' }
        Write-Note 'Запускаю: wsl --install --no-distribution'
        & wsl.exe --install --no-distribution 2>&1 | Out-String | Write-Note
        $Ctx.RebootRequired = $true
        Write-OK 'WSL2 инициировано. Требуется перезагрузка — после неё запусти deploy.ps1 -Resume (продолжим с docker-setup).'
    } else {
        Write-OK "WSL в порядке ($(($wslStatus -split "`n")[0]))"
    }

    $ddExe = Join-Path ${env:ProgramFiles} 'Docker\Docker\Docker Desktop.exe'
    $ddExe86 = Join-Path ${env:ProgramFiles(x86)} 'Docker\Docker\Docker Desktop.exe'
    if (-not (Test-Path $ddExe) -and -not (Test-Path $ddExe86)) {
        if (-not (Test-Command winget)) { Write-Fatal 'winget отсутствует.' }
        Write-Note 'Устанавливаю Docker Desktop ...'
        winget install --id Docker.DockerDesktop --exact --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) { Write-Warn "Docker Desktop: winget вернул $LASTEXITCODE" }
    } else {
        Write-OK 'Docker Desktop уже установлен.'
    }
}

function Deploy-DockerSetup($Ctx) {
    Write-Step 'Docker: запуск движка, плагины Гордона, Model Runner, профиль MCP'

    $dd = @((Join-Path ${env:ProgramFiles} 'Docker\Docker\Docker Desktop.exe'), (Join-Path ${env:ProgramFiles(x86)} 'Docker\Docker\Docker Desktop.exe')) |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $dd) { Write-Fatal 'Docker Desktop не установлен — выполни docker-install.' }
    if (-not (Get-Process 'Docker Desktop' -ErrorAction SilentlyContinue)) {
        Write-Note 'Запускаю Docker Desktop ...'
        Start-Process $dd
    }

    $ready = $false
    for ($i = 0; $i -lt 40 -and -not $ready; $i++) {
        Start-Sleep -Seconds 6
        try {
            $v = & docker version --format '{{.Server.Version}}' 2>&1 | Out-String
            if ($v -match '\d+\.\d+\.\d+') { $ready = $true; Write-OK "Docker engine: $($v.Trim())" }
        } catch { }
        if (-not $ready -and $i % 5 -eq 4) { Write-Note "Ожидаю движок Docker (${i}/40)... " }
    }
    if (-not $ready) { Write-Warn 'Движок Docker не поднялся за ~4 мин. Проверь: WSL2 включено? Параметры Docker → Use WSL 2 based engine?' }

    if ($ready) {
        $plugins = @('docker-agent.exe', 'docker-model.exe', 'docker-ai.exe', 'docker-mcp.exe')
        foreach ($src in @((Join-Path ${env:ProgramFiles} 'Docker\Docker\resources\cli-plugins'), (Join-Path ${env:ProgramFiles(x86)} 'Docker\Docker\resources\cli-plugins'))) {
            if (-not (Test-Path $src)) { continue }
            foreach ($p in $plugins) {
                $s = Join-Path $src $p
                $d = Join-Path "$env:USERPROFILE\.docker\cli-plugins" $p
                if (-not (Test-Path $s)) { continue }
                if (Test-Path $d) { continue }
                New-Item -ItemType Directory -Force -Path (Split-Path $d) | Out-Null
                try { New-Item -ItemType SymbolicLink -Path $d -Target $s | Out-Null; Write-OK "Плагин $p (ссылка)" }
                catch { Copy-Item $s $d -Force; Write-OK "Плагин $p (копия)" }
            }
        }
        Refresh-Path

        Write-Note 'Model Runner: enable + pull моделей ...'
        try { docker model list 2>&1 | Out-Null } catch { }
        docker model pull ai/smollm2 2>&1 | Select-Object -Last 1
        if ($Ctx.PullQwen3) { docker model pull ai/qwen3 2>&1 | Select-Object -Last 1 }
        else { Write-Note 'ai/qwen3 пропущен (только smollm2). Для большой модели: pwsh gordon-setup.ps1' }
        Write-OK "Model Runner: $((docker model list 2>&1 | Out-String).Trim())"

        $profileFile = Join-Path $Ctx.RepoRoot 'config\docker-mcp\dev_workflow.yaml'
        if (Test-Path $profileFile) {
            Write-Note 'Импорт профиля dev_workflow (github-official, memory, puppeteer) ...'
            docker mcp profile import $profileFile 2>&1 | Out-String | Write-Note
            docker mcp profile list 2>&1 | Out-String | Write-Note
        }
    }

    $ghOk = $false
    try { gh auth status 2>&1 | Out-Null | Out-Null; $ghOk = $true } catch { }
    if (-not $ghOk -and (Read-EnvKey 'GITHUB_PERSONAL_ACCESS_TOKEN')) {
        Write-Note 'Настраиваю gh по GITHUB_PERSONAL_ACCESS_TOKEN ...'
        [Environment]::GetEnvironmentVariable('GITHUB_PERSONAL_ACCESS_TOKEN', 'User') | gh auth login --with-token
        $ghOk = $LASTEXITCODE -eq 0
    }
    if ($ghOk) { Write-OK "gh авторизован: $((gh api user --jq .login 2>&1))" }
    else { Write-Warn 'gh не авторизован. Один раз выполни: gh auth login (device-flow), затем для приватных репо деплоя всё пойдёт само.' }
}