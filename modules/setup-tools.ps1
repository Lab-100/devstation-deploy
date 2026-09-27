function Deploy-Tools($Ctx) {
    Write-Step 'INVR-Tools: реестр (релиз scripts-tools) + локер + линки/шимы инструментов'

    $dest = Join-Path $Ctx.ToolDir 'tools'
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $tgtReg = Join-Path $dest 'registry'

    # 0. Манифест дистрибутива — источник правды по составу и версиям инструментов.
    $distManifestPath = Join-Path $Ctx.RepoRoot 'project.json'
    if (-not (Test-Path $distManifestPath)) { Write-Fatal "Нет манифеста дистрибутива: $distManifestPath" }
    $distManifest = Get-Content -LiteralPath $distManifestPath -Raw | ConvertFrom-Json
    $regRepo = if ($Ctx.RegistryRepo) { $Ctx.RegistryRepo } else { $distManifest.registry.repository }
    $regRef  = if ($Ctx.RegistryRef)  { $Ctx.RegistryRef }  else { $distManifest.registry.ref }
    $regOwner = if ($Ctx.Owner) { $Ctx.Owner } else { 'Lab-100' }
    if ($regRepo -notmatch "$regOwner/") { $regRepo = "$regOwner/$regRepo" }
    $regRepo = $regRepo -replace '^https://github\.com/', '' -replace '\.git$', ''

    # 1. Реестр: ставим/обновляем из релиза scripts-tools. Копии реестра в этом
    #    репозитории больше нет — единственный источник версий.
    $haveReg = Test-RegistryDir $tgtReg
    $needFetch = $Ctx.RegistrySource -or $Ctx.UpdateRegistry -or (-not $haveReg)

    if ($haveReg -and -not $needFetch) {
        Write-Note "Реестр уже развёрнут ($tgtReg) — использую как есть (обновление: -UpdateRegistry)."
    } else {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('invr-registry-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $srcReg = Get-RegistrySource -Ctx $Ctx -Repo $regRepo -Ref $regRef -TmpDir $tmp
            $stale = Join-Path $tmp 'stale'
            if (Test-Path $tgtReg) { Move-Item $tgtReg $stale -Force }
            New-Item -ItemType Directory -Force -Path $tgtReg | Out-Null
            Copy-Item (Join-Path $srcReg '*') $tgtReg -Recurse -Force
            Remove-Item $stale -Recurse -Force -ErrorAction SilentlyContinue
            Write-OK "Реестр → $tgtReg (источник: $regRepo@$regRef)"
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not (Test-RegistryDir $tgtReg)) { Write-Fatal "Реестр не развёрран: $tgtReg" }

    # 2. Локер берём из самого реестра (версия resolve-tools из latest.txt) —
    #    в дистрибутиве второй копии локера нет.
    $lokLatest = (Get-Content -LiteralPath (Join-Path $tgtReg 'resolve-tools\latest.txt') -Raw).Trim()
    $lokSrc = Join-Path $tgtReg "resolve-tools\$lokLatest\resolve-tools.ps1"
    if (-not (Test-Path $lokSrc)) { Write-Fatal "Нет локера в реестре: $lokSrc" }
    Copy-Item $lokSrc (Join-Path $dest 'resolve-tools.ps1') -Force
    Write-OK "Локер resolve-tools $lokLatest → $dest\resolve-tools.ps1"

    # 3. Манифест проекта (.devstation\project.json) — из манифеста дистрибутива.
    $toolsMap = [ordered]@{}
    foreach ($p in $distManifest.tools.PSObject.Properties) { $toolsMap[$p.Name] = $p.Value }
    $manifest = [ordered]@{
        schema = 'inrv.project/1'
        name   = 'devstation (localhost orchestrator tools)'
        tools  = $toolsMap
    }
    $mp = Join-Path $Ctx.ToolDir 'project.json'
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $mp -Encoding utf8
    Write-OK "Манифест ($($toolsMap.Count) инструментов) → $mp"

    # 4. Линковка: junction tools\<tool> → registry\<tool>\<latest> + плоские шимы *.ps1.
    #    Шимы кладём рядом с реестром ($dest), а не уровнем выше: тогда переносимый
    #    шим находит реестр как $PSScriptRoot\registry.
    Write-Note 'Линковка инструментов (resolve-tools link -GenerateShims) ...'
    & pwsh -NoProfile -NoLogo -File (Join-Path $dest 'resolve-tools.ps1') link `
        -Project $Ctx.ToolDir -Registry $tgtReg -ShimRoot $dest -GenerateShims 2>&1 | Out-String | Write-Note

    $missing = @()
    foreach ($must in @('backup-util.ps1', 'gordon.ps1', 'resolve-tools.ps1', 'mcp-watchdog.ps1',
                        'opencode-status.ps1', 'opencode-plugins-install.ps1', 'opencode-restart.ps1')) {
        if (-not (Test-Path (Join-Path $dest $must))) { $missing += $must }
    }
    if ($missing.Count) {
        Write-Warn ("Линковка не создала шимов: " + ($missing -join ', ') + ' — проверь диапазоны в project.json и версии в реестре.')
    } else {
        Write-OK 'Инструменты залинкованы (tools\<tool> → registry, tools\*.ps1 — шимы).'
    }

    # 5. cmd-шимы мониторов (генерируются инсталлером плагинов, переносимые %~dp0).
    #    -Force обязателен: без него установщик требует уже существующий каталог
    #    плагинов, падает и cmd-шимы не создаются вовсе.
    $plgShim = Join-Path $dest 'opencode-plugins-install.ps1'
    if (Test-Path $plgShim) {
        # Каталог-пробник временный и НЕ junction: tools\<tool> — это линк в
        # реестр, и копирование плагинов «сам в себя» падает.
        $probe = Join-Path $dest '.cmd-shim-probe'
        try {
            & pwsh -NoProfile -NoLogo -File $plgShim `
                -PluginsDir $probe -ShimsDir $dest -Force 2>&1 | Out-String | Write-Note
        } finally {
            Remove-Item -LiteralPath $probe -Recurse -Force -ErrorAction SilentlyContinue
        }
        $cmds = @(Get-ChildItem -LiteralPath $dest -Filter *.cmd -File -ErrorAction SilentlyContinue)
        if ($cmds.Count) {
            Write-OK "cmd-шимы мониторов → $dest\*.cmd ($($cmds.Name -join ', '))"
        } else {
            Write-Warn 'cmd-шимы мониторов не созданы — см. вывод установщика плагинов выше.'
        }
    } else {
        Write-Warn "Нет шима установщика плагинов ($plgShim) — cmd-шимы не созданы."
    }

    $Ctx.InvrToolsReady = $true
}
