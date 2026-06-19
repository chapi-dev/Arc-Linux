<#
.SYNOPSIS
    Instala la extension MDE.Linux (Microsoft Defender for Endpoint) en una maquina Arc.

.DESCRIPTION
    En produccion, lo normal es activar Defender for Servers Plan 2 a nivel de
    suscripcion y dejar que Defender for Cloud despliegue la extension. Este
    script es para lab / despliegue manual puntual.

.EXAMPLE
    ./06-install-mde-linux.ps1 -ResourceGroup rg-arc-linux-lab -MachineName lab-rhel9-01
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string] $ResourceGroup,
    [Parameter(Mandatory=$true)] [string] $MachineName,
    [string] $Location = 'westeurope'
)

$ErrorActionPreference = 'Stop'

$subscriptionId = az account show --query id -o tsv
$azureResourceId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.HybridCompute/machines/$MachineName"

$settings = @{
    azureResourceId   = $azureResourceId
    forceReOnboarding = $false
    vNextEnabled      = "true"
} | ConvertTo-Json -Compress

Write-Host "Installing MDE.Linux extension on $MachineName..." -ForegroundColor Cyan
az connectedmachine extension create `
    --resource-group $ResourceGroup `
    --machine-name $MachineName `
    --location $Location `
    --name "MDE.Linux" `
    --publisher "Microsoft.Azure.AzureDefenderForServers" `
    --type "MDE.Linux" `
    --enable-auto-upgrade true `
    --settings $settings | Out-Null

Write-Host ""
Write-Host "Done. To verify on the host run:" -ForegroundColor Green
Write-Host "  ssh user@host 'sudo mdatp health'"
Write-Host "  ssh user@host 'sudo mdatp health --field real_time_protection_enabled'"
