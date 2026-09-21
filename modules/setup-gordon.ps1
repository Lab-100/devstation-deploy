function Deploy-Gordon($Ctx) {
    Write-Step 'Gordon (Docker Agent): конфиг агента и роутера провайдеров'

    $toolsDest = Join-Path $Ctx.ToolDir 'tools'
    New-Item -ItemType Directory -Force -Path $toolsDest | Out-Null

    # Инструменты gordon уже залинкованы этапом tools (tools\gordon.ps1, gordon-setup.ps1 —
    # шимы на реестр). Провайдеры копируем в конфиг себя (gordon 0.2.x ищет их сама).
    $prov = Join-Path $Ctx.RepoRoot 'config\gordon-providers.json'
    if (Test-Path $prov) {
        $provDest = Join-Path $Ctx.ToolDir 'gordon-providers.json'
        Copy-Item $prov $provDest -Force
        Write-OK "gordon-providers.json → $provDest"
    }
    if (Test-Path (Join-Path $toolsDest 'gordon.ps1')) { Write-OK "gordon.ps1 (шим реестра) → $toolsDest" }
    else { Write-Warn 'gordon.ps1 не найден — этап tools не выполнился?' }

    $agentsDir = Join-Path $env:USERPROFILE '.agents'
    New-Item -ItemType Directory -Force -Path $agentsDir | Out-Null
    $gordonYaml = Join-Path $agentsDir 'gordon.yaml'
    if (-not (Test-Path $gordonYaml)) {
        Copy-Item (Join-Path $Ctx.RepoRoot 'config\gordon.yaml.template') $gordonYaml -Force
        Write-OK "gordon.yaml → $gordonYaml (модель по умолчанию: smollm2)"
    } else {
        Write-OK "gordon.yaml уже есть: $gordonYaml"
    }

    $setup = Join-Path $toolsDest 'gordon-setup.ps1'
    if (Test-Path $setup) {
        Write-Note 'Запускаю gordon-setup.ps1 (линки плагинов, Model Runner, локальная модель) ...'
        & pwsh -NoProfile -NoLogo -File $setup 2>&1 | Out-String | Write-Note
    }
}