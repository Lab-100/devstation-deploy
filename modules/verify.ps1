function Deploy-Verify($Ctx) {
    Write-Step 'Итоговая проверка развёртывания'

    $report = @()
    $ok = $true

    $checks = @(
        @{ Name = 'pwsh 7'; Test = { Test-Command pwsh } },
        @{ Name = 'git'; Test = { Test-Command git } },
        @{ Name = 'node'; Test = { Test-Command node } },
        @{ Name = 'ollama (CLI)'; Test = { Test-Command ollama } },
        @{ Name = 'gh (CLI)'; Test = { Test-Command gh } },
        @{ Name = 'opencode (CLI)'; Test = { Test-Command opencode } },
        @{ Name = 'firecrawl (CLI)'; Test = { Test-Command firecrawl } }
    )
    foreach ($c in $checks) {
        $r = & $c.Test
        $report += [pscustomobject]@{ Check = $c.Name; OK = $r; Info = '' }
        if (-not $r) { $ok = $false; Write-Warn "$($c.Name): не найден" }
        else { Write-OK "$($c.Name): есть" }
    }

    try {
        $v = Invoke-RestMethod -Uri 'http://localhost:11434/api/version' -TimeoutSec 5
        $report += [pscustomobject]@{ Check = 'ollama API'; OK = $true; Info = "v$($v.version)" }
        Write-OK "ollama API: $($v.version)"
        $tags = (ollama list 2>&1 | Out-String)
        foreach ($m in @('hermes3:3b', 'hermes3:8b', 'hermes3:3b-cpu')) {
            $has = $tags -match [regex]::Escape($m)
            $report += [pscustomobject]@{ Check = "model $m"; OK = $has; Info = '' }
            if ($has) { Write-OK "Модель ${m}: есть" } else { $ok = $false; Write-Warn "Модель ${m}: нет" }
        }
    } catch {
        $report += [pscustomobject]@{ Check = 'ollama API'; OK = $false; Info = 'не отвечает' }
        Write-Warn 'ollama API не отвечает — запусти ollama-server.cmd.'
        $ok = $false
    }

    try {
        $dv = (docker version --format '{{.Server.Version}}' 2>&1 | Out-String).Trim()
        $report += [pscustomobject]@{ Check = 'docker engine'; OK = [bool]($dv -match '\d'); Info = $dv }
        if ($dv -match '\d') { Write-OK "docker engine: $dv" } else { $ok = $false; Write-Warn "docker engine: $dv" }
        $mr = (docker model list 2>&1 | Out-String)
        if ($mr -match 'smollm2') { Write-OK 'Model Runner + smollm2: есть' }
        else { $ok = $false; Write-Warn 'Model Runner: smollm2 не найден' }
    } catch {
        Write-Warn 'docker engine/Model Runner недоступны (проверь Docker Desktop).'
        $ok = $false
    }

    foreach ($f in @(
        (Join-Path $Ctx.WorkspaceDir 'opencode.json'),
        (Join-Path $env:USERPROFILE '.config\opencode\opencode.json'),
        (Join-Path $Ctx.ToolDir 'mcp\venv-llm\Scripts\python.exe'),
        (Join-Path $Ctx.ToolDir 'tools\backup-util.ps1'),
        (Join-Path $env:USERPROFILE '.agents\gordon.yaml'),
        (Join-Path $env:USERPROFILE '.docker\cli-plugins\docker-agent.exe')
    )) {
        $p = Test-Path $f
        $report += [pscustomobject]@{ Check = "file $(Split-Path $f -Leaf)"; OK = $p; Info = $f }
        if ($p) { Write-OK "Артефакт: $f" } else { $ok = $false; Write-Warn "Нет файла: $f" }
    }

    if ($Ctx.RollbackRoot -and (Test-Path $Ctx.RollbackRoot)) {
        Write-OK "Каталог откатов: $($Ctx.RollbackRoot)"
    } else {
        $ok = $false; Write-Warn 'Каталог откатов не создан.'
    }

    if ($Ctx.SmokeGordon -and (Test-Command pwsh)) {
        Write-Note 'Смоук-тест Гордона (может занять время) ...'
        & pwsh (Join-Path $Ctx.ToolDir 'tools\gordon.ps1') -Prompt 'Ответь только OK' 2>&1 | Out-String | Write-Note
    }

    $reportDir = Join-Path $env:ProgramData 'devstation-deploy'
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
    $report | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $reportDir 'verify-report.json') -Encoding utf8

    if ($ok) {
        Write-Step 'ВСЁ ГОТОВО: инфраструктура развёрнута и проверена.'
    } else {
        Write-Step 'ЕСТЬ НЕЗАКРЫТЫЕ ПУНКТЫ — см. report выше.'
        exit 1
    }
}