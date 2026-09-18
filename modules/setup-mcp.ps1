function Deploy-Mcp($Ctx) {
    Write-Step 'MCP: глобальный opencode.json (MCP_DOCKER) и профиль dev_workflow'

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
    $p = Join-Path $globalCfgDir 'opencode.json'
    $globalCfg | ConvertTo-Json -Depth 6 | Set-Content -Path $p -Encoding utf8
    Write-OK "Глобальный opencode.json → $p"

    if (Test-Command docker) {
        $profiles = (docker mcp profile list 2>&1 | Out-String)
        if ($profiles -match 'dev_workflow') {
            Write-OK 'Профиль dev_workflow импортирован.'
        } else {
            $file = Join-Path $Ctx.RepoRoot 'config\docker-mcp\dev_workflow.yaml'
            if (Test-Path $file) {
                Write-Note 'Импортирую профиль dev_workflow ...'
                docker mcp profile import $file 2>&1 | Out-String | Write-Note
            } else {
                Write-Warn 'dev_workflow.yaml не найден — профиль не импортирован.'
            }
        }
    } else {
        Write-Warn 'docker CLI недоступен — глобальный MCP_DOCKER не заработает до поднятия Docker.'
    }
}