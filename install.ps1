# devstation-deploy installer (bootstrap).
# Скачивает дистрибутив из GitHub Release (через gh) или из локального zip
# и запускает deploy.ps1. Инсталлер однофайловый, версия не привязана к дистрибу.
# Использование:
#   pwsh install.ps1                          # последний Release (нужен gh auth)
#   pwsh install.ps1 -Tag v0.2.0              # конкретный тег
#   pwsh install.ps1 -SourceZip .\v0.2.0.zip  # локальный дистрибутив
#   pwsh install.ps1 -CheckOnly / -DryRun / -Resume ...   # проброс флагов в deploy.ps1
# Флаги deploy.ps1 передаются как есть: -PullQwen3, -SetupGitHub, -Owner, -WorkspaceDir, ...
[CmdletBinding()]
param(
    [string]$Tag = '',
    [string]$SourceZip = '',
    [string]$Repo = 'Lab-100/devstation-deploy',
    [switch]$CheckOnly,
    [switch]$DryRun,
    [switch]$Resume,
    [switch]$NoElevate,
    [string]$WorkspaceDir = '',
    [string]$OllamaModelsDir = '',
    [string]$RollbackRoot = '',
    [string]$Owner = '',
    [switch]$PullQwen3,
    [switch]$SetupGitHub,
    [switch]$SmokeGordon,
    [switch]$ForceOverwriteConfig
)
$ErrorActionPreference = 'Stop'

$dest = Join-Path $env:LOCALAPPDATA 'devstation-deploy'
$deploy = Join-Path $dest 'deploy.ps1'

# 1. Получение/подготовка дистрибутива
$haveSource = Test-Path $deploy
if (-not $haveSource) {
    $zip = $SourceZip
    if (-not $zip) {
        $gh = Join-Path (Get-Command gh -ErrorAction SilentlyContinue).Source ''
        if (-not $gh) {
            Write-Host 'gh не найден. Установи GitHub CLI (winget install GitHub.cli) или используй -SourceZip.' -ForegroundColor Red
            exit 1
        }
        Write-Host "Скачиваю дистрибутив $Repo@$($Tag -replace '^$','latest') ..."
        $tmp = Join-Path $env:TEMP "devstation-deploy-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        $tagArgs = @('release', 'download', '--repo', $Repo, '--pattern', '*.zip')
        if ($Tag) { $tagArgs += '--tag', $Tag }
        $dl = gh @tagArgs --dir $tmp 2>&1
        if ($LASTEXITCODE -ne 0) { Write-Host "Скачивание не удалось: $dl" -ForegroundColor Red; exit 1 }
        $zip = Get-ChildItem $tmp -Filter '*.zip' | Select-Object -First 1 -ExpandProperty FullName
        if (-not $zip) { Write-Host 'В релизе нет zip-архива.' -ForegroundColor Red; exit 1 }
    }
    Write-Host "Распаковываю в $dest ..."
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force
    if (-not (Test-Path $deploy)) { Write-Host 'В архиве нет deploy.ps1 (неверный zip).' -ForegroundColor Red; exit 1 }
}

# 2. Требуется PowerShell 7 у нас самих
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'Требуется PowerShell 7.' -ForegroundColor Red; exit 1 }

# 3. Проброс флагов
$args2 = @()
if ($CheckOnly) { $args2 += '-CheckOnly' }
if ($DryRun) { $args2 += '-DryRun' }
if ($Resume) { $args2 += '-Resume' }
if ($NoElevate) { $args2 += '-NoElevate' }
if ($WorkspaceDir) { $args2 += '-WorkspaceDir', $WorkspaceDir }
if ($OllamaModelsDir) { $args2 += '-OllamaModelsDir', $OllamaModelsDir }
if ($RollbackRoot) { $args2 += '-RollbackRoot', $RollbackRoot }
if ($Owner) { $args2 += '-Owner', $Owner }
if ($PullQwen3) { $args2 += '-PullQwen3' }
if ($SetupGitHub) { $args2 += '-SetupGitHub' }
if ($SmokeGordon) { $args2 += '-SmokeGordon' }
if ($ForceOverwriteConfig) { $args2 += '-ForceOverwriteConfig' }

Write-Host "Запускаю deploy.ps1 $($args2 -join ' ')"
& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $deploy @args2
exit $LASTEXITCODE