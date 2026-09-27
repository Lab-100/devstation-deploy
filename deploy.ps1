# devstation-deploy — авторазвёртывание локальной AI-инфраструктуры Windows.
# Использование:
#   pwsh deploy.ps1 -CheckOnly                              # только проверка готовности
#   pwsh deploy.ps1 -DryRun                                 # план без изменений
#   pwsh deploy.ps1                                         # полный деплой (с UAC)
#   pwsh deploy.ps1 -Resume                                 # продолжить после перезагрузки
#   pwsh deploy.ps1 -Stage docker-install                   # отдельный этап
# Флаги: -PullQwen3, -SetupGitHub, -SmokeGordon, -WorkspaceDir, -OllamaModelsDir,
#        -RegistrySource, -RegistryRepo, -RegistryRef, -UpdateRegistry,
#        -RollbackRoot, -Owner, -ForceHardware, -ForceOverwriteConfig, -NoElevate
[CmdletBinding()]
param(
    [ValidateSet('all', 'env-check', 'install-core', 'ollama', 'docker-install',
        'docker-setup', 'tools', 'firecrawl', 'opencode', 'mcp', 'rollback',
        'gordon', 'startup', 'verify')]
    [string]$Stage = 'all',
    [switch]$Resume,
    [switch]$CheckOnly,
    [switch]$DryRun,
    [switch]$NoElevate,
    [switch]$PullQwen3,
    [switch]$SetupGitHub,
    [switch]$SmokeGordon,
    [switch]$ForceHardware,
    [switch]$ForceOverwriteConfig,
    [string]$WorkspaceDir = '',
    [string]$OllamaModelsDir = '',
    [string]$RollbackRoot = '',
    [string]$Owner = 'Lab-100',
    [string]$RegistrySource = '',
    [string]$RegistryRepo = '',
    [string]$RegistryRef = '',
    [switch]$UpdateRegistry
)
$ErrorActionPreference = 'Stop'
$Script:DeployVersion = '0.3.2'

# Рабочий каталог (куда кладутся opencode.json и AGENTS.md) по умолчанию не
# привязан к конкретной машине: переменная окружения DEVSTATION_WORKSPACE,
# затем существующий каталог оркестрации, затем корень этого репозитория.
if (-not $WorkspaceDir) {
    $WorkspaceDir = if ($env:DEVSTATION_WORKSPACE) { $env:DEVSTATION_WORKSPACE }
                    elseif (Test-Path -LiteralPath 'C:\Scripts\AGENTS.md') { 'C:\Scripts' }
                    else { Split-Path -Parent $PSCommandPath }
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host 'Требуется PowerShell 7. Пытаюсь установить/перезапустить ...' -ForegroundColor Yellow
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwsh -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        winget install --id Microsoft.PowerShell --exact --silent --accept-package-agreements --accept-source-agreements
    }
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) {
        $argb = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
        foreach ($k in $PSBoundParameters.Keys) {
            $v = $PSBoundParameters[$k]
            if ($v -is [switch]) { if ($v) { $argb += ("-" + $k) } }
            elseif ($v) { $argb += ("-" + $k); $argb += [string]$v }
        }
        Start-Process ($pwsh.Source) -Wait -ArgumentList $argb
        exit $LASTEXITCODE
    }
    Write-Host 'PowerShell 7 не установлен и не установился автоматически. Установи его (winget install Microsoft.PowerShell) и повтори.' -ForegroundColor Red
    exit 1
}

$components = [ordered]@{
    'env-check'    = { param($c) Deploy-EnvCheck $c }
    'install-core' = { param($c) Deploy-InstallCore $c }
    'ollama'       = { param($c) Deploy-Ollama $c }
    'docker-install' = { param($c) Deploy-DockerInstall $c }
    'docker-setup' = { param($c) Deploy-DockerSetup $c }
    'tools'        = { param($c) Deploy-Tools $c }
    'firecrawl'    = { param($c) Deploy-Firecrawl $c }
    'opencode'     = { param($c) Deploy-Opencode $c }
    'mcp'          = { param($c) Deploy-Mcp $c }
    'rollback'     = { param($c) Deploy-Rollback $c }
    'gordon'       = { param($c) Deploy-Gordon $c }
    'startup'      = { param($c) Deploy-Startup $c }
    'verify'       = { param($c) Deploy-Verify $c }
}

$moduleDir = Join-Path $PSScriptRoot 'modules'
foreach ($m in (Get-ChildItem $moduleDir -Filter '*.ps1')) { . $m.FullName }

$defaults = [ordered]@{
    WorkspaceDir = $WorkspaceDir
    OllamaModelsDir = $OllamaModelsDir
    RollbackRoot = $RollbackRoot
    DataDrive = ''
    Owner = $Owner
    RegistrySource = $RegistrySource
    RegistryRepo = $RegistryRepo
    RegistryRef = $RegistryRef
    UpdateRegistry = $UpdateRegistry
    PullQwen3 = $PullQwen3
    SetupGitHub = $SetupGitHub
    ForceHardware = $ForceHardware
    ForceOverwriteConfig = $ForceOverwriteConfig
    SmokeGordon = $SmokeGordon
    # Корень развёртывания: DEVSTATION_ROOT (удобно для стендов и проверок),
    # иначе обычный %USERPROFILE%\.devstation.
    ToolDir = if ($env:DEVSTATION_ROOT) { $env:DEVSTATION_ROOT }
              else { Join-Path $env:USERPROFILE '.devstation' }
    RepoRoot = $PSScriptRoot
    Done = @()
    RebootRequired = $false
}
$Ctx = Load-State $defaults

if ($Ctx.DataDrive -eq '') {
    $best = Get-BestDataDrive
    $Ctx.DataDrive = if ($best) { $best } else { 'C:' }
}

$plan = if ($Stage -eq 'all') { @($components.Keys) } else { @($Stage) }

Write-Host "`n=== devstation-deploy $Script:DeployVersion ===" -ForegroundColor Cyan
Write-Host "Рабочий каталог: $($Ctx.WorkspaceDir)"
Write-Host "Шаблон: >=16 ГБ RAM, CPU-only, WSL2 для Docker, локальные модели Ollama+ModelRunner"

if ($DryRun) {
    Write-Host "`nРежим DryRun — только план:" -ForegroundColor Yellow
    Deploy-EnvCheck $Ctx
    Write-Host "План: $($plan -join ' → ')" -ForegroundColor Cyan
    Write-Host 'Изменения НЕ применялись.' -ForegroundColor Yellow
    exit 0
}

if ($CheckOnly) {
    Write-Host "`nРежим CheckOnly:" -ForegroundColor Yellow
    Deploy-EnvCheck $Ctx
    $matrix = @('pwsh','git','node','python','ollama','gh','docker','firecrawl','opencode')
    foreach ($c in $matrix) {
        $has = Test-Command $c
        Write-Host ("  {0,-12} {1}" -f $c, $(if ($has) { 'OK' } else { '—' }))
    }
    if (Test-Path (Join-Path $Ctx.ToolDir 'mcp\venv-llm\Scripts\python.exe')) { Write-Host '  venv-llm     OK' }
    exit 0
}

$needsAdmin = $plan -contains 'all' -or $plan -contains 'install-core' -or $plan -contains 'ollama' -or
    $plan -contains 'docker-install' -or $plan -contains 'docker-setup'
if ($needsAdmin -and -not (Test-Admin) -and -not $NoElevate) {
    Write-Host 'Нужны права администратора. Перезапускаю деплойер с UAC ...' -ForegroundColor Yellow
    $argb = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'deploy.ps1'))
    if ($Stage -ne 'all') { $argb += '-Stage', $Stage }
    foreach ($s in @('Resume','PullQwen3','SetupGitHub','SmokeGordon','ForceHardware','ForceOverwriteConfig')) {
        if (Get-Variable -Name $s -ValueOnly -ErrorAction SilentlyContinue) { $argb += "-$s" }
    }
    # -WorkspaceDir передаём только если он задан явно: иначе дочерний процесс
    # вычислит тот же дефолт сам (та же переменная окружения и тот же путь).
    if ($PSBoundParameters.ContainsKey('WorkspaceDir') -and $WorkspaceDir) { $argb += '-WorkspaceDir', $WorkspaceDir }
    if ($OllamaModelsDir) { $argb += '-OllamaModelsDir', $OllamaModelsDir }
    if ($RollbackRoot) { $argb += '-RollbackRoot', $RollbackRoot }
    if ($Owner -ne 'Lab-100') { $argb += '-Owner', $Owner }
    if ($RegistrySource) { $argb += '-RegistrySource', $RegistrySource }
    if ($RegistryRepo) { $argb += '-RegistryRepo', $RegistryRepo }
    if ($RegistryRef) { $argb += '-RegistryRef', $RegistryRef }
    if ($UpdateRegistry) { $argb += '-UpdateRegistry' }
    Start-Process pwsh -Verb RunAs -Wait -ArgumentList $argb
    exit $LASTEXITCODE
}

$first = $true
foreach ($stage in $plan) {
    if ($first) { $first = $false }
    if ($Resume -and ($Ctx.Done -contains $stage)) {
        Write-Host "[skip] этап $stage уже выполнен (Resume)" -ForegroundColor DarkGray
        continue
    }
    try {
        & $components[$stage] $Ctx
        if ($stage -eq 'docker-install' -and $Ctx.RebootRequired) {
            Set-StageDone $Ctx 'docker-install' $Ctx
            Write-Host "`n=== Перезагрузи систему, затем: pwsh deploy.ps1 -Resume ===" -ForegroundColor Yellow
            exit 0
        }
        Set-StageDone $Ctx $stage $Ctx
    } catch {
        Write-Host "`n[FAIL] Этап ${stage}: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Состояние сохранено. После исправления: pwsh deploy.ps1 -Resume" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "`n=== Деплой завершён (этапы: $($Ctx.Done -join ', ')) ===" -ForegroundColor Cyan
Write-Host 'Дальше вручную (однократно):' -ForegroundColor DarkGray
Write-Host '  • gh auth login         — если gh не авторизован' -ForegroundColor DarkGray
Write-Host '  • FIRECRAWL_API_KEY    — firecrawl-key.ps1 -Mode Init/Poll (опционально, keyless работает)' -ForegroundColor DarkGray
Write-Host "  • зайди в $($Ctx.WorkspaceDir) и вызови opencode" -ForegroundColor DarkGray
Write-Host "Состояние: $(Get-StatePath)" -ForegroundColor DarkGray
