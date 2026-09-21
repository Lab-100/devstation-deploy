function Deploy-Opencode($Ctx) {
    Write-Step 'opencode: конфиги (ollama + локальные MCP + firecrawl), venv для local-llm'

    if (-not (Test-Command opencode)) { Write-Fatal 'opencode не в PATH — выполни install-core.' }
    Write-OK "opencode: $((opencode --version 2>&1) -join '')"

    New-Item -ItemType Directory -Force -Path $Ctx.ToolDir | Out-Null
    $mcpDir = Join-Path $Ctx.ToolDir 'mcp'
    New-Item -ItemType Directory -Force -Path $mcpDir | Out-Null

    if (-not (Test-Path (Join-Path $mcpDir 'llm_mcp_server.py'))) {
        # llm-mcp из реестра (этап tools): tools\llm-mcp\0.1.0\llm_mcp_server.py
        $linkedLlm = Join-Path $Ctx.ToolDir 'tools\llm-mcp'
        Write-Note "Копирую llm_mcp_server.py из $linkedLlm ..."
        Copy-Item (Join-Path $linkedLlm 'llm_mcp_server.py') $mcpDir -Force
    }
    $venv = Join-Path $mcpDir 'venv-llm'
    if (-not (Test-Path (Join-Path $venv 'Scripts\python.exe'))) {
        Write-Note 'Создаю venv для local-llm MCP ...'
        python -m venv $venv
    }
    if (Test-Path (Join-Path $venv 'Scripts\python.exe')) {
        $py = Join-Path $venv 'Scripts\python.exe'
        Write-Note 'pip install mcp ...'
        & $py -m pip --disable-pip-version-check install --quiet mcp 2>&1 | Select-Object -Last 2
        Write-OK "local-llm venv: $py"
    } else {
        Write-Warn 'venv для local-llm не создан.'
    }

    $haveKey = [bool](Read-EnvKey 'FIRECRAWL_API_KEY')

    $mcpConfig = [ordered]@{}
    if (Test-Path $py) {
        $mcpConfig['local-llm'] = [ordered]@{
            type = 'local'
            command = @($py, (Join-Path $mcpDir 'llm_mcp_server.py'))
            enabled = $true
        }
    }
    $mcpConfig['firecrawl-mcp'] = if ($haveKey) {
        [ordered]@{
            type = 'local'
            command = @('npx', '-y', 'firecrawl-mcp')
            environment = @{ FIRECRAWL_API_KEY = '{env:FIRECRAWL_API_KEY}' }
            enabled = $true
        }
    } else {
        [ordered]@{
            type = 'remote'
            url = 'https://mcp.firecrawl.dev/v2/mcp'
            enabled = $true
        }
    }

    $config = [ordered]@{
        provider = [ordered]@{
            ollama = [ordered]@{
                type = 'provider'
                baseUrl = 'http://localhost:11434/v1'
                models = [ordered]@{
                    '8b' = [ordered]@{ name = 'Hermes 3 8B'; model = 'hermes3:8b' }
                    '3b' = [ordered]@{ name = 'Hermes 3 3B'; model = 'hermes3:3b' }
                    '3b-cpu' = [ordered]@{ name = 'Hermes 3 3B CPU'; model = 'hermes3:3b-cpu' }
                }
                options = [ordered]@{ model = 'hermes3:3b' }
            }
        }
        mcp = $mcpConfig
    }

    $cfgPath = Join-Path $Ctx.WorkspaceDir 'opencode.json'
    if ((Test-Path $cfgPath) -and -not $Ctx.ForceOverwriteConfig) {
        Write-Warn "$cfgPath уже существует — не перезаписываю (флаг -ForceOverwriteConfig)."
    } else {
        New-Item -ItemType Directory -Force -Path $Ctx.WorkspaceDir | Out-Null
        $config | ConvertTo-Json -Depth 8 | Set-Content -Path $cfgPath -Encoding utf8
        Write-OK "opencode.json → $cfgPath"
    }

    $globalCfgDir = Join-Path $env:USERPROFILE '.config\opencode'
    New-Item -ItemType Directory -Force -Path $globalCfgDir | Out-Null
    $globalCfg = [ordered]@{
        mcp = [ordered]@{
            MCP_DOCKER = [ordered]@{
                type = 'local'
                command = @('docker', 'mcp', 'gateway', 'run', '--profile', 'dev_workflow')
                environment = @{ GITHUB_PERSONAL_ACCESS_TOKEN = '{env:GITHUB_PERSONAL_ACCESS_TOKEN}' }
                enabled = $true
            }
        }
    }
    $globalCfgPath = Join-Path $globalCfgDir 'opencode.json'
    $globalCfg | ConvertTo-Json -Depth 6 | Set-Content -Path $globalCfgPath -Encoding utf8
    Write-OK "Глобальный opencode.json (MCP_DOCKER) → $globalCfgPath"

    $agentsTemplate = Join-Path $Ctx.RepoRoot 'config\AGENTS.md.template'
    if ($agentsTemplate -and (Test-Path $agentsTemplate)) {
        $target = Join-Path $Ctx.WorkspaceDir 'AGENTS.md'
        if ((Test-Path $target) -and -not $Ctx.ForceOverwriteConfig) {
            Write-Warn "AGENTS.md уже есть — не перезаписываю."
        } else {
            Copy-Item $agentsTemplate $target -Force
            Write-OK "AGENTS.md → $target"
        }
    }
}