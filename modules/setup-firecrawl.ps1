function Deploy-Firecrawl($Ctx) {
    Write-Step 'Firecrawl: CLI, скиллы и MCP'

    Write-Note 'Установка firecrawl CLI (npm global) ...'
    npm install -g firecrawl-cli 2>&1 | Select-Object -Last 2
    Refresh-Path
    if (-not (Test-Command firecrawl)) { Write-Warn 'firecrawl CLI не найден в PATH (проверь npm global bin).' }

    if (-not (Read-EnvKey 'FIRECRAWL_API_KEY')) {
        Write-Warn 'FIRECRAWL_API_KEY не задан — работаем keyless (лимитированный безлимит).'
        Write-Note 'Постоянный ключ: firecrawl-key.ps1 -Mode Init → открыть Authorize → -Mode Poll.'
    } else {
        Write-OK "FIRECRAWL_API_KEY задан (len $((Read-EnvKey 'FIRECRAWL_API_KEY').Length))."
    }

    $cli = Join-Path $Ctx.ToolDir 'tools'
    New-Item -ItemType Directory -Force -Path $cli | Out-Null
    if (Test-Path (Join-Path $cli 'firecrawl-key.ps1')) {
        Write-OK "firecrawl-key.ps1 (шим реестра) → $cli"
    } else {
        Write-Warn 'firecrawl-key.ps1 не найден — этап tools не выполнился?'
    }

    if (Test-Command firecrawl) {
        try {
            Write-Note 'firecrawl init --all --skip-auth --skip-agent ...'
            firecrawl init --all --skip-auth --skip-agent 2>&1 | Select-Object -Last 5
        } catch {
            Write-Warn 'firecrawl init не прошёл полностью (скиллы можно установить вручную: firecrawl init).'
        }
    } else {
        Write-Warn 'Скиллы firecrawl в opencode/.claude не установлены (CLI отсутствует).'
    }
}