<#
.SYNOPSIS
    Consulta eventos FIM y Change Tracking en el LAW del lab.

.DESCRIPTION
    Lanza queries KQL sobre el workspace law-arc-linux-lab para validar que
    los cambios preparados en lab-rhel9-01 han llegado:
      - touch /etc/passwd
      - modify /etc/ssh/sshd_config
      - create /etc/ssh/sshd_config.bak
      - create /etc/lab-arc-demo/config.txt
      - create /usr/local/bin/lab-fake-binary

    Esperar 30-90 min tras los cambios para que ChangeTracking-Linux propague.

.PARAMETER ResourceGroup
    RG del workspace. Default: rg-arc-linux-lab.

.PARAMETER WorkspaceName
    Nombre del LAW. Default: law-arc-linux-lab.

.PARAMETER LookbackHours
    Ventana hacia atras para buscar eventos. Default: 24h.

.EXAMPLE
    pwsh -File scripts\validate\01-validate-fim-events.ps1

.EXAMPLE
    pwsh -File scripts\validate\01-validate-fim-events.ps1 -LookbackHours 4
#>
[CmdletBinding()]
param(
    [string] $ResourceGroup  = 'rg-arc-linux-lab',
    [string] $WorkspaceName  = 'law-arc-linux-lab',
    [int]    $LookbackHours  = 24,
    [string] $Computer       = 'lab-rhel9-01'
)

$ErrorActionPreference = 'Stop'

# Workspace ID
Write-Host "==> Resolviendo workspace $WorkspaceName ..." -ForegroundColor Cyan
$wsId = az monitor log-analytics workspace show `
    --resource-group $ResourceGroup `
    --workspace-name $WorkspaceName `
    --query customerId -o tsv 2>$null

if (-not $wsId) {
    Write-Host "ERROR: workspace no encontrado." -ForegroundColor Red
    exit 1
}
Write-Host "    Workspace customerId: $wsId" -ForegroundColor Gray

# 1. ChangeTracking-Linux extension status
Write-Host "`n==> Verificando extension ChangeTracking-Linux..." -ForegroundColor Cyan
$sub = az account show --query id -o tsv
$extUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$ResourceGroup/providers/Microsoft.HybridCompute/machines/$Computer/extensions?api-version=2024-07-10"
$exts = az rest --method GET --uri $extUri --query "value[?contains(name, 'ChangeTracking')].{name:name,state:properties.provisioningState,version:properties.typeHandlerVersion}" -o json | ConvertFrom-Json

if (-not $exts) {
    Write-Host "  WARN: ChangeTracking-Linux extension NO instalada todavia." -ForegroundColor Yellow
    Write-Host "        Defender for Cloud la desplegara cuando la policy se evalue." -ForegroundColor Yellow
    Write-Host "        Forzar evaluacion: az policy state trigger-scan --resource-group $ResourceGroup --no-wait" -ForegroundColor Yellow
} else {
    foreach ($e in $exts) {
        Write-Host "  $($e.name): $($e.state) (version $($e.version))" -ForegroundColor Green
    }
}

# 2. Queries KQL
$queries = @(
    @{
        Title = "[A] Resumen de cambios ConfigurationChange en ${LookbackHours}h"
        Q = @"
ConfigurationChange
| where TimeGenerated > ago(${LookbackHours}h)
| where Computer == '$Computer'
| summarize Count=count() by ConfigChangeType, bin(TimeGenerated, 1h)
| order by TimeGenerated desc
"@
    },
    @{
        Title = "[B] Cambios en /etc/passwd, /etc/shadow, /etc/sudoers"
        Q = @"
ConfigurationChange
| where TimeGenerated > ago(${LookbackHours}h)
| where Computer == '$Computer'
| where FileSystemPath in~ ('/etc/passwd','/etc/shadow','/etc/sudoers','/etc/group','/etc/gshadow')
| project TimeGenerated, FileSystemPath, ChangeCategory, FieldsChanged, PreviousValue, NewValue
| order by TimeGenerated desc
"@
    },
    @{
        Title = "[C] Cambios en sshd_config"
        Q = @"
ConfigurationChange
| where TimeGenerated > ago(${LookbackHours}h)
| where Computer == '$Computer'
| where FileSystemPath startswith '/etc/ssh/'
| project TimeGenerated, FileSystemPath, ChangeCategory, FieldsChanged
| order by TimeGenerated desc
"@
    },
    @{
        Title = "[D] Cualquier cambio en /etc/lab-arc-demo (regla custom FIM)"
        Q = @"
ConfigurationChange
| where TimeGenerated > ago(${LookbackHours}h)
| where Computer == '$Computer'
| where FileSystemPath startswith '/etc/lab-arc-demo/'
| project TimeGenerated, FileSystemPath, ChangeCategory, FieldsChanged
| order by TimeGenerated desc
"@
    },
    @{
        Title = "[E] Software/packages installed (Change Tracking + Inventory)"
        Q = @"
ConfigurationData
| where TimeGenerated > ago(${LookbackHours}h)
| where Computer == '$Computer'
| where ConfigDataType == 'Software'
| summarize count() by SoftwareName, SoftwareType
| order by SoftwareName asc
| take 20
"@
    },
    @{
        Title = "[F] Daemons/services state on the host"
        Q = @"
ConfigurationData
| where TimeGenerated > ago(${LookbackHours}h)
| where Computer == '$Computer'
| where ConfigDataType == 'Daemons'
| project TimeGenerated, Daemon = SvcName, State = SvcState, RunLevels = SvcStartupName
| order by Daemon asc
| take 20
"@
    },
    @{
        Title = "[G] Threats detected by MDE (Defender events)"
        Q = @"
DeviceFileEvents
| where TimeGenerated > ago(${LookbackHours}h)
| where DeviceName has '$Computer'
| where InitiatingProcessFileName has_any('mdatp','wdavdaemon')
| project TimeGenerated, ActionType, FileName, FolderPath, SHA256
| order by TimeGenerated desc
| take 20
"@
    }
)

foreach ($q in $queries) {
    Write-Host "`n==> $($q.Title)" -ForegroundColor Cyan
    Write-Host $q.Q -ForegroundColor DarkGray
    try {
        $res = az monitor log-analytics query --workspace $wsId --analytics-query $q.Q -o json 2>$null | ConvertFrom-Json
        if (-not $res -or $res.Count -eq 0) {
            Write-Host "  (sin resultados aun)" -ForegroundColor Yellow
        } else {
            $res | Format-Table -AutoSize | Out-String -Width 200
        }
    } catch {
        Write-Host "  ERROR ejecutando query: $_" -ForegroundColor Red
    }
}

Write-Host "`n==> Validacion completada." -ForegroundColor Green
Write-Host "Si todas las queries devuelven '(sin resultados aun)', espera 30-60 min mas:" -ForegroundColor Gray
Write-Host "  - ChangeTracking-Linux extension necesita instalarse" -ForegroundColor Gray
Write-Host "  - Tras instalarse, primer reporte tarda ~15-30 min" -ForegroundColor Gray
Write-Host "  - Eventos llegan al LAW con latencia adicional de 5-15 min" -ForegroundColor Gray
