function Deploy-Rollback($Ctx) {
    Write-Step 'Каталог откатов (rollback-catalog): инструмент + git + (опц.) приватный репо'

    if (-not $Ctx.RollbackRoot) {
        $drive = if ($Ctx.OllamaModelsDir) { Split-Path (Split-Path $Ctx.OllamaModelsDir -Parent) -Qualifier } else { $Ctx.DataDrive }
        if (-not $drive -or $drive -eq 'C:') {
            $best = Get-BestDataDrive
            $drive = if ($best) { $best } else { Split-Path $Ctx.WorkspaceDir -Qualifier }
        }
        $Ctx.RollbackRoot = "$drive\rollback-catalog"
    }
    Write-OK "Корень каталога откатов: $($Ctx.RollbackRoot)"

    $toolsDest = Join-Path $Ctx.ToolDir 'tools'
    New-Item -ItemType Directory -Force -Path $toolsDest | Out-Null
    Copy-Item (Join-Path $Ctx.RepoRoot 'tools\backup-util.ps1') (Join-Path $toolsDest 'backup-util.ps1') -Force
    Set-Content -Path (Join-Path $toolsDest 'rollback-root.txt') -Value $Ctx.RollbackRoot -Encoding ascii
    Write-OK "backup-util.ps1 + rollback-root.txt → $toolsDest"

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