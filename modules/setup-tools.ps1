function Deploy-Tools($Ctx) {
    Write-Step 'INVR-Tools: реестр + локер + линки/шимы инструментов'

    $dest = Join-Path $Ctx.ToolDir 'tools'
    New-Item -ItemType Directory -Force -Path $dest | Out-Null

    # 1. Реестр-снимок (доставляется с дистрибутивом devstation-deploy).
    $srcReg = Join-Path $Ctx.RepoRoot 'tools\registry'
    if (-not (Test-Path $srcReg)) { Write-Fatal "Нет реестра-снимка в дистрибутиве: $srcReg" }
    $tgtReg = Join-Path $dest 'registry'
    New-Item -ItemType Directory -Force -Path $tgtReg | Out-Null
    Copy-Item (Join-Path $srcReg '*') $tgtReg -Recurse -Force
    Write-OK "Реестр-снимок → $tgtReg"

    # 2. Bootstrap локера.
    $srcLok = Join-Path $Ctx.RepoRoot 'tools\resolve-tools.ps1'
    if (-not (Test-Path $srcLok)) { Write-Fatal "Нет локера в дистрибутиве: $srcLok" }
    Copy-Item $srcLok (Join-Path $dest 'resolve-tools.ps1') -Force
    Write-OK "Локер → $dest\resolve-tools.ps1"

    # 3. Манифест проекта (.devstation\project.json) со списком инструментов.
    $manifest = [ordered]@{
        schema = 'inrv.project/1'
        name   = 'devstation (localhost orchestrator tools)'
        tools  = [ordered]@{
            'resolve-tools' = '0.2.x'
            'backup-util'   = '0.2.x'
            'gordon'        = '0.2.x'
            'firecrawl-key' = '0.2.x'
            'vmdisk'        = '0.2.x'
            'doc-extract'   = '0.2.x'
            'ai-provider-check' = '0.2.x'
            'llm-mcp'       = '0.1.x'
        }
    }
    $mp = Join-Path $Ctx.ToolDir 'project.json'
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $mp -Encoding utf8
    Write-OK "Манифест → $mp"

    # 4. Линковка: junction tools\<tool> → registry\<tool>\<latest> + плоские шимы *.ps1.
    Write-Note 'Линковка инструментов (resolve-tools link -GenerateShims) ...'
    & pwsh -NoProfile -NoLogo -File (Join-Path $dest 'resolve-tools.ps1') link `
        -Project $Ctx.ToolDir -Registry $tgtReg -GenerateShims 2>&1 | Out-String | Write-Note

    if (-not (Test-Path (Join-Path $dest 'backup-util.ps1'))) {
        Write-Warn 'Линковка не создала шимов — проверь манифест/версии.'
    } else {
        Write-OK 'Инструменты залинкованы (tools\<tool> → registry, tools\*.ps1 — шимы).'
    }

    $Ctx.InvrToolsReady = $true
}