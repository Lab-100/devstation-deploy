function Deploy-Gordon($Ctx) {
    Write-Step 'Gordon (Docker Agent): конфиг агента и роутера провайдеров'

    $toolsDest = Join-Path $Ctx.ToolDir 'tools'
    New-Item -ItemType Directory -Force -Path $toolsDest | Out-Null
    foreach ($f in @('gordon.ps1', 'gordon-setup.ps1')) {
        $src = Join-Path $Ctx.RepoRoot "tools\$f"
        if (Test-Path $src) { Copy-Item $src (Join-Path $toolsDest $f) -Force }
    }
    $prov = Join-Path $Ctx.RepoRoot 'config\gordon-providers.json'
    if (Test-Path $prov) { Copy-Item $prov (Join-Path $Ctx.ToolDir 'gordon-providers.json') -Force }
    if (Test-Path (Join-Path $Ctx.RepoRoot 'tools\gordon.ps1')) { Write-OK "gordon.ps1/gordon-setup.ps1 + providers → $toolsDest" }

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
        & $setup 2>&1 | Out-String | Write-Note
    }
}