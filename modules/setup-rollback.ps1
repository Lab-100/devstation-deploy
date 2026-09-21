function Deploy-Rollback($Ctx) {
    Write-Step 'Каталог откатов (rollback-catalog): git + (опц.) приватный репо'

    if (-not $Ctx.RollbackRoot) {
        $drive = if ($Ctx.OllamaModelsDir) { Split-Path (Split-Path $Ctx.OllamaModelsDir -Parent) -Qualifier } else { $Ctx.DataDrive }
        if (-not $drive -or $drive -eq 'C:') {
            $best = Get-BestDataDrive
            $drive = if ($best) { $best } else { Split-Path $Ctx.WorkspaceDir -Qualifier }
        }
        $Ctx.RollbackRoot = "$drive\rollback-catalog"
    }
    Write-OK "Корень каталога откатов: $($Ctx.RollbackRoot)"

    # backup-util уже развёрнут этапом tools (шим links через реестр).
    # Корень откатов фиксируем рядом: файл читается backup-util 0.2.x.
    $homeConf = Join-Path $env:USERPROFILE '.devstation\rollback-root.txt'
    New-Item -ItemType Directory -Force -Path (Split-Path $homeConf -Parent) | Out-Null
    Set-Content -Path $homeConf -Value $Ctx.RollbackRoot -Encoding ascii
    Write-OK "rollback-root.txt → $homeConf"

    New-Item -ItemType Directory -Force -Path $Ctx.RollbackRoot | Out-Null
    if (-not (Test-Path (Join-Path $Ctx.RollbackRoot '.git'))) {
        Push-Location $Ctx.RollbackRoot
        try {
            git init -q 2>&1 | Out-Null
            @'
changes/
*.log
.DS_Store
'@ | Set-Content -Path (Join-Path $Ctx.RollbackRoot '.gitignore') -Encoding utf8
            git add -A 2>&1 | Out-Null
            git -c user.name='devstation-deploy' -c user.email='deploy@local' commit -q -m 'init rollback-catalog' 2>&1 | Out-Null
            Write-OK 'Локальный git-каталог откатов инициализирован.'
        } finally { Pop-Location }
    } else {
        Write-OK 'Каталог откатов уже git-репозиторий.'
    }

    $toolsDest = Join-Path $Ctx.ToolDir 'tools'
    if (Test-Path (Join-Path $toolsDest 'backup-util.ps1')) {
        Write-OK "Инструмент откатов: $toolsDest\backup-util.ps1 (шим из реестра)"
    } else {
        Write-Warn 'backup-util.ps1 не найден — этап tools не выполнился?'
    }

    $ghOk = $false
    try { gh auth status 2>&1 | Out-Null; $ghOk = $true } catch { }
    if ($ghOk -and $Ctx.SetupGitHub) {
        Write-Note "Создаю приватный репо $($Ctx.Owner)/rollback-catalog ..."
        Push-Location $Ctx.RollbackRoot
        try {
            gh repo create "$($Ctx.Owner)/rollback-catalog" --private --source . --push 2>&1 | Out-String | Write-Note
        } finally { Pop-Location }
    }
}