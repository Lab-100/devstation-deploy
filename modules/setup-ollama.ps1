function Deploy-Ollama($Ctx) {
    Write-Step 'Ollama: кофигурация CPU-first и локальные модели'

    if (-not (Test-Command ollama)) { Write-Fatal 'ollama не в PATH. Сначала install-core.' }

    if (-not $Ctx.OllamaModelsDir) {
        $drive = if ($Ctx.DataDrive) { $Ctx.DataDrive } else { Get-BestDataDrive }
        if (-not $drive) { $drive = 'C:' }
        $Ctx.OllamaModelsDir = "$drive\OllamaModels"
    }
    New-Item -ItemType Directory -Force -Path $Ctx.OllamaModelsDir | Out-Null
    Write-OK "Каталог моделей: $($Ctx.OllamaModelsDir)"

    Set-UserEnv 'OLLAMA_MODELS' $Ctx.OllamaModelsDir
    Set-UserEnv 'OLLAMA_LLM_LIBRARY' 'cpu_avx2'
    Set-UserEnv 'OLLAMA_CONTEXT_LENGTH' '16384'
    Set-UserEnv 'OLLAMA_KV_CACHE_TYPE' 'q4_0'
    Set-UserEnv 'OLLAMA_NUM_PARALLEL' '1'
    Set-UserEnv 'OLLAMA_MAX_LOADED_MODELS' '1'
    Set-UserEnv 'OLLAMA_KEEP_ALIVE' '30m'

    $toolDir = $Ctx.ToolDir
    New-Item -ItemType Directory -Force -Path $toolDir | Out-Null
    $serverCmd = Join-Path $toolDir 'ollama-server.cmd'
    $exe = (Get-Command ollama).Source
    @"
@echo off
set OLLAMA_LLM_LIBRARY=cpu_avx2
set OLLAMA_CONTEXT_LENGTH=16384
set OLLAMA_KV_CACHE_TYPE=q4_0
set OLLAMA_MODELS=$($Ctx.OllamaModelsDir)
set OLLAMA_NUM_PARALLEL=1
set OLLAMA_MAX_LOADED_MODELS=1
set OLLAMA_KEEP_ALIVE=30m
start "" /b "$exe" serve
"@ | Set-Content -Path $serverCmd -Encoding ascii
    Write-OK "Серверный скрипт: $serverCmd"

    $up = $false
    try {
        $r = Invoke-RestMethod -Uri 'http://localhost:11434/api/version' -TimeoutSec 4
        $up = $true
        Write-OK "Ollama уже запущен: $($r.version)"
    } catch { }

    if (-not $up) {
        Write-Note 'Запускаю ollama serve ...'
        Start-Process -FilePath $exe -ArgumentList 'serve' -WindowStyle Hidden
        Start-Sleep -Seconds 6
        try {
            $r = Invoke-RestMethod -Uri 'http://localhost:11434/api/version' -TimeoutSec 8
            Write-OK "Ollama поднят: $($r.version)"
        } catch { Write-Warn 'Не удалось подтвердить запуск ollama serve (проверь вручную).' }
    }

    foreach ($m in @('hermes3:3b', 'hermes3:8b', 'hermes3:3b-cpu')) {
        Write-Note "ollama pull $m ..."
        ollama pull $m 2>&1 | Select-Object -Last 1
    }

    $tags = (ollama list 2>&1 | Out-String)
    foreach ($m in @('hermes3:3b', 'hermes3:8b', 'hermes3:3b-cpu')) {
        if ($tags -match [regex]::Escape($m)) { Write-OK "Модель $m на месте." }
        else { Write-Warn "Модель $m не найдена — повтори pull позже." }
    }
}