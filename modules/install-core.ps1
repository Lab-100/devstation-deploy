function Install-App {
    param(
        [hashtable]$App,
        [bool]$UseWinget
    )
    $already = $false
    if ($App.Check) {
        if ($App.Check -match '\.exe') {
            $already = (Test-Path (Join-Path $env:ProgramFiles "Docker\Docker\$($App.Check)")) -or
                       (Test-Path (Join-Path ${env:ProgramFiles(x86)} "Docker\Docker\$($App.Check)"))
        } else {
            $already = Test-Command $App.Check
        }
    }
    if ($already) { Write-OK "$($App.Id): уже установлено"; return }

    if ($UseWinget) {
        Write-Note "winget install $($App.Id) ..."
        winget install --id $App.Id --exact --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -eq 0) { Write-OK "$($App.Id): установлено"; return }
        Write-Warn "$($App.Id): winget вернул $LASTEXITCODE — пробую прямой загрузчик"
    }

    if (-not $App.DirectUrl) { Write-Fatal "$($App.Id): нет winget и нет прямого загрузчика" }
    Write-Note "$($App.Id): прямое скачивание $($App.DirectUrl)"
    $tmp = Join-Path $env:TEMP (Split-Path $App.DirectUrl -Leaf)
    Invoke-WebRequest -Uri $App.DirectUrl -OutFile $tmp -UseBasicParsing -TimeoutSec 600
    $argsList = if ($App.DirectArgs) { @($App.DirectArgs) } else { @() }
    $p = Start-Process -FilePath $tmp -ArgumentList $argsList -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) { Write-Warn "$($App.Id): установщик вернул код $($p.ExitCode)" }
}

function Deploy-InstallCore($Ctx) {
    Write-Step 'Установка базового набора (Git, pwsh7, Node LTS, Python, Ollama, gh, Docker Desktop)'

    if (-not (Test-Admin)) { Write-Fatal 'Установки требуют администратора. Запусти деплойер из админской консоли или без -NoElevate.' }

    $useWinget = Test-Command winget
    if ($useWinget) { Write-OK "winget: $((winget --version))" }
    else { Write-Warn 'winget не найден (App Installer отсутствует/сломан) — использую официальные прямые загрузчики.' }

    $apps = @(
        @{ Id = 'Microsoft.PowerShell'; Check = 'pwsh'; DirectUrl = 'https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/PowerShell-7.4.6-win-x64.msi'; DirectArgs = @('/quiet', '/norestart') },
        @{ Id = 'Git.Git'; Check = 'git'; DirectUrl = 'https://github.com/git-for-windows/git/releases/download/v2.45.2.windows.1/Git-2.45.2-64-bit.exe'; DirectArgs = @('/VERYSILENT', '/NORESTART', '/SP-') },
        @{ Id = 'OpenJS.NodeJS.LTS'; Check = 'node'; DirectUrl = 'https://nodejs.org/dist/v20.14.0/node-v20.14.0-x64.msi'; DirectArgs = @('/qn', '/norestart') },
        @{ Id = 'Python.Python.3.12'; Check = 'python'; DirectUrl = 'https://www.python.org/ftp/python/3.12.4/python-3.12.4-amd64.exe'; DirectArgs = @('/quiet', 'InstallAllUsers=1', 'PrependPath=1') },
        @{ Id = 'Ollama.Ollama'; Check = 'ollama'; DirectUrl = 'https://ollama.com/download/OllamaSetup.exe'; DirectArgs = @('/S') },
        @{ Id = 'GitHub.cli'; Check = 'gh'; DirectUrl = 'https://github.com/cli/cli/releases/download/v2.51.0/gh_2.51.0_windows_amd64.msi'; DirectArgs = @('/qn', '/norestart') },
        @{ Id = 'Docker.DockerDesktop'; Check = 'Docker Desktop.exe'; DirectUrl = 'https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe'; DirectArgs = @('install', '--quiet', '--accept-license') }
    )

    foreach ($app in $apps) {
        Install-App -App $app -UseWinget $useWinget
        Refresh-Path
    }

    if (-not (Test-Command node)) { Write-Fatal 'Node.js не установился — opencode не сможет.' }
    Write-Note 'npm global: opencode-ai ...'
    npm install -g opencode-ai 2>&1 | Select-Object -Last 2
    if ($LASTEXITCODE -ne 0) { Write-Warn 'npm install opencode-ai вернул ненулевой код' }
    Refresh-Path

    Write-OK 'Базовый набор установлен.'
    Write-Note "opencode: $((opencode --version 2>&1) -join '')"
}