function Write-Step([string]$Message) { Write-Host "`n[STEP] $Message" -ForegroundColor Cyan }
function Write-OK([string]$Message) { Write-Host "  [OK] $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "  [!] $Message" -ForegroundColor Yellow }
function Write-Note([string]$Message) { Write-Host "      $Message" -ForegroundColor DarkGray }
function Write-Fatal([string]$Message) { Write-Host "  [X] $Message" -ForegroundColor Red; throw $Message }

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Online {
    try { Invoke-WebRequest -Uri 'https://api.github.com' -Method Head -TimeoutSec 12 -UseBasicParsing | Out-Null; return $true }
    catch { return $false }
}

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Get-BestDataDrive {
    $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
    $best = $disks | Where-Object { $_.DeviceID -ne 'C:' -and [double]$_.FreeSpace -ge 40GB } |
        Sort-Object { [double]$_.FreeSpace } -Descending | Select-Object -First 1
    if ($best) { return $best.DeviceID }
    $sys = $disks | Where-Object { $_.DeviceID -eq 'C:' } | Select-Object -First 1
    if ($sys -and [double]$sys.FreeSpace -ge 60GB) { return 'C:' }
    return ''
}

function Test-Command([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-Ok([string]$Command, [string]$Label) {
    Invoke-Expression $Command | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Fatal "$Label завершился с кодом $LASTEXITCODE" }
}

function Get-StatePath {
    return Join-Path $env:ProgramData 'devstation-deploy\state.json'
}

function Save-State($Ctx) {
    $dir = Split-Path (Get-StatePath) -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    @{
        version = 1
        workspaceDir = $Ctx.WorkspaceDir
        ollamaModelsDir = $Ctx.OllamaModelsDir
        rollbackRoot = $Ctx.RollbackRoot
        dataDrive = $Ctx.DataDrive
        owner = $Ctx.Owner
        pullQwen3 = $Ctx.PullQwen3
        setupGitHub = $Ctx.SetupGitHub
        done = @( @($Ctx.Done | Sort-Object -Unique | Where-Object { $_ }) | ForEach-Object { [string]$_ } )
        rebootRequired = $Ctx.RebootRequired
        updatedAt = (Get-Date -Format o)
    } | ConvertTo-Json -Depth 5 | Set-Content -Path (Get-StatePath) -Encoding utf8
}

function Load-State([hashtable]$DefaultCtx) {
    $p = Get-StatePath
    if (-not (Test-Path $p)) { return $DefaultCtx }
    try {
        $s = Get-Content $p -Raw | ConvertFrom-Json
    } catch { return $DefaultCtx }
    if (-not $s) { return $DefaultCtx }
    $DefaultCtx.WorkspaceDir = if ($s.workspaceDir) { $s.workspaceDir } else { $DefaultCtx.WorkspaceDir }
    $DefaultCtx.OllamaModelsDir = if ($s.ollamaModelsDir) { $s.ollamaModelsDir } else { $DefaultCtx.OllamaModelsDir }
    $DefaultCtx.RollbackRoot = if ($s.rollbackRoot) { $s.rollbackRoot } else { $DefaultCtx.RollbackRoot }
    $DefaultCtx.DataDrive = if ($s.dataDrive) { $s.dataDrive } else { $DefaultCtx.DataDrive }
    $DefaultCtx.Owner = if ($s.owner) { $s.owner } else { $DefaultCtx.Owner }
    $DefaultCtx.PullQwen3 = if ($null -ne $s.pullQwen3) { [bool]$s.pullQwen3 } else { $DefaultCtx.PullQwen3 }
    $DefaultCtx.SetupGitHub = if ($null -ne $s.setupGitHub) { [bool]$s.setupGitHub } else { $DefaultCtx.SetupGitHub }
    $DefaultCtx.Done = @( @($s.done) | Where-Object { $_ } | ForEach-Object { [string]$_ } )
    if ($s.rebootRequired) { $DefaultCtx.RebootRequired = $true }
    return $DefaultCtx
}

function Set-StageDone($Ctx, [string]$Stage, [hashtable]$State, [bool]$DoSave = $true) {
    $list = @($State.done) | Where-Object { $_ -and ($_ -ne $Stage) }
    $list = @($list)
    $list += $Stage
    $State.done = $list
    $Ctx.Done = @($list)
    if ($DoSave) { Save-State $Ctx }
}

function Read-EnvKey([string]$Name) {
    return [Environment]::GetEnvironmentVariable($Name, 'User')
}

function Set-UserEnv([string]$Name, [string]$Value) {
    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
    Set-Item -Path "env:$Name" -Value $Value
}

# Выбор OLLAMA_LLM_LIBRARY по реальному железу.
# Ловушка: при OLLAMA_LLM_LIBRARY=cpu_avx2 (или просто без него на старой карте)
# autodetect цепляет CUDA 13, а Maxwell/Pascal/Volta (compute capability < 7.5)
# поддержку в CUDA 13 потеряли — GPU молча не обнаруживается, всё уходит на CPU.
# Возвращает: 'cuda_v12' | '' (autodetect) | 'cpu_avx2'
function Get-OllamaLlmLibrary {
    $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if (-not $smi) { return 'cpu_avx2' }

    try {
        $csv = & nvidia-smi --query-gpu=name,compute_cap --format=csv,noheader 2>$null | Out-String
    } catch { $csv = '' }
    if (-not $csv.Trim()) { return 'cpu_avx2' }

    $best = $null
    foreach ($line in ($csv -split "`r?`n")) {
        $line = $line.Trim()
        if (-not $line) { continue }
        $parts = $line -split ','
        if ($parts.Count -lt 2) { continue }
        $name = $parts[0].Trim()
        $capRaw = $parts[1].Trim()
        # Целая часть CC: "6.1" -> 6, "8.6" -> 8, "12.0" -> 12.
        # Берём только целую часть строкой, а не [double]::TryParse:
        # в ru-RU культуре "6.1" не парсится (разделитель — запятая).
        $capMajorStr = ($capRaw -split '\.')[0].Trim()
        $capMajor = 0
        if (-not [int]::TryParse($capMajorStr, [ref]$capMajor)) { continue }
        if ($null -eq $best -or $capMajor -gt $best.CapMajor) {
            $best = [pscustomobject]@{ Name = $name; CapMajor = $capMajor; Cap = $capRaw }
        }
    }
    if ($null -eq $best) { return 'cpu_avx2' }

    if ($best.CapMajor -lt 7) {
        Write-Note "GPU: $($best.Name), CC $($best.Cap) (<7.5) -> OLLAMA_LLM_LIBRARY=cuda_v12 (CUDA 13 не поддерживает)"
        return 'cuda_v12'
    }

    Write-Note "GPU: $($best.Name), CC $($best.Cap) -> autodetect (OLLAMA_LLM_LIBRARY не задан)"
    return ''
}

# Каталог реестра считается валидным, если в нём есть _registry.json и latest.txt хотя бы
# одного инструмента (иначе это мусор от недокачанного архива).
function Test-RegistryDir([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $Path '_registry.json'))) { return $false }
    return ((Get-ChildItem -LiteralPath $Path -Filter 'latest.txt' -Recurse -ErrorAction SilentlyContinue |
            Measure-Object).Count -gt 0)
}

# Приводит скачанный/разло��енный каталог к виду «каталог реестра» (внутри _registry.json).
function Resolve-RegistryRoot([string]$Path) {
    if (Test-RegistryDir $Path) { return $Path }
    foreach ($cand in @((Join-Path $Path 'tools\registry'), (Join-Path $Path 'registry'))) {
        if (Test-RegistryDir $cand) { return $cand }
    }
    $inner = Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue
    foreach ($d in $inner) {
        $r = Resolve-RegistryRoot $d.FullName
        if ($r) { return $r }
    }
    return $null
}

function Expand-Archive-To([string]$Archive, [string]$DestDir) {
    New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
    $tar = (Get-Command tar -ErrorAction SilentlyContinue)
    if ($tar) {
        & $tar.Source -xzf $Archive -C $DestDir
        if ($LASTEXITCODE -ne 0) { Write-Fatal "tar не распаковал $Archive (код $LASTEXITCODE)" }
        return
    }
    Write-Fatal 'Нет tar.exe в системе — распакуй реестр вручную и укажи -RegistrySource <путь>.'
}

# Источник реестра INVR-Tools: приоритет 1) -RegistrySource (каталог/архив),
# 2) скачивание архива scripts-tools (Lab-100/scripts-tools) с GitHub.
# Возвращает путь к каталогу реестра (внутри _registry.json).
function Get-RegistrySource($Ctx, [string]$Repo, [string]$Ref, [string]$TmpDir) {
    if ($Ctx.RegistrySource) {
        $src = $Ctx.RegistrySource
        if (Test-Path -LiteralPath $src -PathType Container) {
            $root = Resolve-RegistryRoot $src
            if (-not $root) { Write-Fatal "-RegistrySource: в каталоге $src не найден реестр (_registry.json)." }
            return $root
        }
        if (Test-Path -LiteralPath $src -PathType Leaf) {
            $ex = Join-Path $TmpDir 'unpack'
            Expand-Archive-To $src $ex
            $root = Resolve-RegistryRoot $ex
            if (-not $root) { Write-Fatal "-RegistrySource: в архиве $src не найден реестр." }
            return $root
        }
        Write-Fatal "-RegistrySource: путь не существует: $src"
    }

    if (-not (Test-Online)) { Write-Fatal 'Нет сети и не задан -RegistrySource — реестр скачать нельзя.' }
    $url = "https://codeload.github.com/$Repo/tar.gz/refs/heads/$Ref"
    $arc = Join-Path $TmpDir 'registry.tar.gz'
    Write-Note "Скачиваю реестр: $url"
    try {
        Invoke-WebRequest -Uri $url -OutFile $arc -UseBasicParsing -TimeoutSec 120
    } catch {
        Write-Fatal "Не скачался реестр $Repo@$Ref : $($_.Exception.Message). Укажи -RegistrySource <путь>."
    }
    $ex = Join-Path $TmpDir 'unpack'
    Expand-Archive-To $arc $ex
    $root = Resolve-RegistryRoot $ex
    if (-not $root) { Write-Fatal "В архиве $Repo@$Ref не найден реестр (ожидался _registry.json)." }
    return $root
}