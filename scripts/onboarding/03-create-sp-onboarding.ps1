<#
.SYNOPSIS
    Crea el Service Principal usado para onboarding masivo de Linux en Azure Arc.

.DESCRIPTION
    Aplica el principio de privilegio minimo: solo el rol
    'Azure Connected Machine Onboarding' al RG destino.

    El secreto se imprime una sola vez. Guardalo en Key Vault y configura
    rotacion (recomendado 90 dias).

.PARAMETER ResourceGroup
    RG donde las maquinas Arc se registraran.

.PARAMETER SpName
    Nombre del SP (default sp-arc-linux-onboarding).

.PARAMETER SubscriptionId
    Subscription destino. Si se omite, usa la activa.

.EXAMPLE
    ./03-create-sp-onboarding.ps1 -ResourceGroup rg-arc-linux-lab
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string] $ResourceGroup,
    [string] $SpName         = 'sp-arc-linux-onboarding',
    [string] $SubscriptionId = (az account show --query id -o tsv)
)

$ErrorActionPreference = 'Stop'

Write-Host "Subscription : $SubscriptionId"
Write-Host "Resource Grp : $ResourceGroup"
Write-Host "SP name      : $SpName"

$scope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup"

Write-Host "Creating service principal..." -ForegroundColor Cyan
$sp = az ad sp create-for-rbac `
    --name $SpName `
    --role "Azure Connected Machine Onboarding" `
    --scopes $scope `
    --years 1 `
    -o json | ConvertFrom-Json

$tenantId = (az account show --query tenantId -o tsv)

Write-Host ""
Write-Host "=== Save these values securely (Key Vault recommended) ===" -ForegroundColor Yellow
Write-Host "tenantId       : $tenantId"
Write-Host "subscriptionId : $SubscriptionId"
Write-Host "resourceGroup  : $ResourceGroup"
Write-Host "appId          : $($sp.appId)"
Write-Host "displayName    : $($sp.displayName)"
Write-Host "password       : $($sp.password)    <-- shown only this time"
Write-Host ""
Write-Host "On the Linux host, export these env vars before running 04-azcmagent-connect.sh:" -ForegroundColor Cyan
@"
export ARC_TENANT_ID=$tenantId
export ARC_SUBSCRIPTION_ID=$SubscriptionId
export ARC_RESOURCE_GROUP=$ResourceGroup
export ARC_LOCATION=westeurope
export ARC_SP_APP_ID=$($sp.appId)
export ARC_SP_SECRET=$($sp.password)
"@
