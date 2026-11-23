# devstation-deploy installer (bootstrap).
# Скачивает дистрибутив из публичного GitHub (codeload-архив по тегу/ветке,
# БЕЗ gh и без авторизации) или из локального zip и запускает deploy.ps1.
# Инсталлер однофайловый, версия не привязана к дистрибутиву.
# Использование:
#   pwsh install.ps1                          # последний релиз, иначе ветка main
#   pwsh install.ps1 -Tag v0.3.5              # конкретный тег
#   pwsh install.ps1 -Ref main                # конкретная ветка
#   pwsh install.ps1 -Force                   # принудительно скачать свежий дистрибутив
#   pwsh install.ps1 -SourceZip .\dist.zip    # локальный дистрибутив (всегда свежий)
#   pwsh install.ps1 -CheckOnly / -DryRun / -Resume ...   # проброс флагов в deploy.ps1
# Флаги deploy.ps1 передаются как есть: -PullQwen3, -SetupGitHub, -Owner, -WorkspaceDir, ...
[CmdletBinding()]
param(
    [string]$Tag = '',
    [string]$Ref = '',
    [string]$SourceZip = '',
    [switch]$Force,
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

# Загрузка с резервным каналом: встроенный Invoke-WebRequest на этой машине
# может не пройти перенаправление GitHub на хранилище активов; curl.exe идёт
# следующим и устраняет проблему без изменения адреса.
function Invoke-Download {
    param([string]$Uri, [string]$OutFile)
    try {
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile -TimeoutSec 300 -UseBasicParsing
        return
    } catch {
        Write-Host "Встроенная загрузка не сработала ($($_.Exception.Message)); пробую curl.exe ..." -ForegroundColor DarkGray
    }
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl) { throw "Не удалось скачать ${Uri}: нет рабочего curl.exe" }
    & $curl.Source -fL --retry 3 --connect-timeout 30 --max-time 300 -o $OutFile $Uri
    if ($LASTEXITCODE -ne 0) { throw "curl.exe не смог скачать $Uri (код $LASTEXITCODE)" }
}

# 1. Получение/подготовка дистрибутива
$haveSource = Test-Path $deploy
# Без флагов локальная копия переиспользуется (офлайн-режим). Явный -Force или
# -SourceZip означает, что берём свежий дистрибутив, а не старый кэш.
if ($haveSource -and ($Force -or $SourceZip)) {
    Write-Host "Обновляю локальную копию дистрибутива в $dest ..."
    Remove-Item -LiteralPath $dest -Recurse -Force
    $haveSource = $false
}
if (-not $haveSource) {
    $zip = $SourceZip
    if (-not $zip) {
        # GitHub требует авторизацию для gh release download, а codeload отдаёт
        # полный исходник публично и без gh — поэтому качаем архив репозитория.
        $ref = $Ref
        if (-not $ref) {
            $ref = $Tag
            if (-not $ref) {
                try {
                    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" `
                        -Headers @{ 'User-Agent' = 'devstation-deploy-installer' } -TimeoutSec 30
                    $ref = $rel.tag_name
                    Write-Host "Последний релиз: $ref"
                } catch {
                    Write-Host "Не удалось определить последний релиз ($($_.Exception.Message)); беру ветку main." -ForegroundColor DarkGray
                    $ref = 'main'
                }
            }
        }
        $isTag = $ref -match '^v\d'
        $kind = if ($isTag) { 'tags' } else { 'heads' }
        $url = "https://codeload.github.com/$Repo/zip/refs/$kind/$ref"
        Write-Host "Скачиваю дистрибутив $Repo@$ref ..."
        $tmp = Join-Path $env:TEMP "devstation-deploy-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        $zip = Join-Path $tmp 'dist.zip'
        try {
            Invoke-Download -Uri $url -OutFile $zip
        } catch {
            Write-Host "Скачивание не удалось ($($_.Exception.Message)). Проверь интернет или укажи -SourceZip." -ForegroundColor Red
            exit 1
        }
        if (-not (Test-Path $zip) -or (Get-Item $zip).Length -lt 1024) {
            Write-Host 'Архив пуст или повреждён.' -ForegroundColor Red
            exit 1
        }
    }
    Write-Host "Распаковываю в $dest ..."
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    # codeload отдаёт единый корневой каталог (например devstation-deploy-0.3.5),
    # поэтому разворачиваем во временный каталог и поднимаем содержимое на уровень $dest.
    $stage = Join-Path $env:TEMP "devstation-deploy-stage-$([guid]::NewGuid().ToString('N'))"
    Expand-Archive -LiteralPath $zip -DestinationPath $stage -Force
    $root = Get-ChildItem -LiteralPath $stage -Directory | Select-Object -First 1
    if (-not $root) { Write-Host 'Архив пуст.' -ForegroundColor Red; exit 1 }
    Copy-Item -Path (Join-Path $root.FullName '*') -Destination $dest -Recurse -Force
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path $deploy)) { Write-Host 'В архиве нет deploy.ps1 (неверный архив).' -ForegroundColor Red; exit 1 }
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
