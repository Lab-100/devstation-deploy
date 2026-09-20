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