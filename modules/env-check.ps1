function Deploy-EnvCheck($Ctx) {
    Write-Step 'Проверка окружения (Windows 10/11, RAM, диски, winget, сеть)'

    $os = Get-CimInstance Win32_OperatingSystem
    $ver = [Version]$os.Version
    $okOs = $ver.Major -eq 10 -and $ver.Build -ge 19045
    Write-Note "OS: $($os.Caption) (версия $($os.Version))"
    if (-not $okOs) { Write-Warn 'Поддерживается Windows 10 22H2+ (build >= 19045) или Windows 11' }

    $ram = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
    $ramGB = [math]::Round($ram / 1GB, 1)
    Write-Note "RAM: $ramGB ГБ (требуется >= 16)"
    if ($ramGB -lt 16) { if ($Ctx.ForceHardware) { Write-Warn 'RAM < 16 ГБ — продолжаем с -ForceHardware' } else { Write-Warn 'RAM < 16 ГБ — не гарантируется бесперебойная работа' } }

    $gpu = Get-CimInstance Win32_VideoController | Select-Object -First 1
    Write-Note "GPU: $($gpu.Name)"
    if ($gpu.Name -match 'NVIDIA|RTX|GTX' ) { Write-Note 'CUDA-обвязки НЕ ставятся: конфигурация CPU-first (как на референсной машине).' }

    foreach ($drive in Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3") {
        Write-Note "Диск $($drive.DeviceID): свободно $([math]::Round([double]$drive.FreeSpace/1GB,1)) ГБ"
    }
    $data = Get-BestDataDrive
    if ($data) { Write-OK "Не-системный диск для данных: $data" } else { Write-Warn 'Свободного места >= 40 ГБ вне C: не найдено — будем использовать C:' }

    if (Test-Command winget) {
        try { Write-OK "winget: $((winget --version))" } catch { Write-OK 'winget найден (версия недоступна)' }
    }
    else { Write-Warn 'winget не найден. Нужно: Параметры → Приложения → Дополнительные возможности → установить Installer (App Installer), либо run: winget --self-update после ручной установки App Installer из Microsoft Store.' }

    if (-not (Test-Admin)) { Write-Warn 'Текущая сессия НЕ администратор — установки потребуют UAC (деплойер перезапустит себя).' }

    if (Test-Online) { Write-OK 'Интернет доступен (api.github.com отвечает).' }
    else { Write-Fatal 'Нет интернета — прерываю. Требуется сеть для пакетов, моделей и конфигураций.' }

    if (Test-Command pwsh) { Write-OK "pwsh: $($PSVersionTable.PSVersion)" }

    $missing = @()
    if (-not (Test-Command pwsh)) { $missing += 'PowerShell 7' }
    if (-not (Test-Command winget)) { $missing += 'winget (App Installer)' }
    if (-not (Test-Online)) { $missing += 'сеть' }
    if (-not $okOs) { $missing += 'поддерживаемую ОС' }
    if (-not $data) { $missing += 'место на диске' }
    if ($missing.Count) {
        Write-Warn "Нерешённые требования: $($missing -join ', ')"
    } else {
        Write-OK 'Окружение готово к установке.'
    }
}