function Deploy-Startup($Ctx) {
    Write-Step 'Автозапуск при старте Windows (ollama-сервер, Docker Desktop)'

    $startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
    New-Item -ItemType Directory -Force -Path $startup | Out-Null

    $serverCmd = Join-Path $Ctx.ToolDir 'ollama-server.cmd'
    if (Test-Path $serverCmd) {
        $lnk = Join-Path $startup 'ollama-server.cmd'
        if (-not (Test-Path $lnk)) { Copy-Item $serverCmd $lnk -Force }
        Write-OK "Ollama-сервер: $lnk"
    }

    $dd = @((Join-Path ${env:ProgramFiles} 'Docker\Docker\Docker Desktop.exe'), (Join-Path ${env:ProgramFiles(x86)} 'Docker\Docker\Docker Desktop.exe')) |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($dd) {
        $ws = New-Object -ComObject WScript.Shell
        $lnk = Join-Path $startup 'Docker Desktop.lnk'
        if (-not (Test-Path $lnk)) {
            $sc = $ws.CreateShortcut($lnk)
            $sc.TargetPath = $dd
            $sc.WorkingDirectory = Split-Path $dd -Parent
            $sc.Save()
        }
        Write-OK "Docker Desktop: $lnk"
    }
}