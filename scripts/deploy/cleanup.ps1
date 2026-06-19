<#
.SYNOPSIS
    Borra TODA la infra creada por deploy.ps1.

.DESCRIPTION
    1. Elimina policy assignments del RG.
    2. Elimina role assignments asociados a las MI de las policies.
    3. Elimina policy definitions a nivel sub.
    4. Borra el Service Principal de onboarding.
    5. Borra el Resource Group entero.

.EXAMPLE
    pwsh -File scripts\deploy\cleanup.ps1 -ResourceGroup rg-arc-linux-lab -Confirm:$true
#>
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
    [string] $ResourceGroup = 'rg-arc-linux-lab',
    [string] $SubscriptionId,
    [switch] $KeepServicePrincipal
)

$ErrorActionPreference = 'Continue'

if (-not $SubscriptionId) { $SubscriptionId = az account show --query id -o tsv }
az account set --subscription $SubscriptionId | Out-Null
$rgScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup"

if (-not $PSCmdlet.ShouldProcess("RG $ResourceGroup + SP + policies", "DELETE")) { return }

Write-Host "Removing policy assignments..." -ForegroundColor Cyan
foreach ($name in @('assign-ama-arc-linux','assign-mde-arc-linux','assign-patchmode-arc-linux')) {
    az policy assignment delete --name $name --scope $rgScope 2>$null
}

Write-Host "Removing policy definitions (sub scope)..." -ForegroundColor Cyan
foreach ($name in @('arc-linux-deploy-ama','arc-linux-deploy-mde','arc-linux-patchmode-auto')) {
    az policy definition delete --name $name --subscription $SubscriptionId 2>$null
}

if (-not $KeepServicePrincipal) {
    Write-Host "Removing Service Principal sp-arc-linux-onboarding..." -ForegroundColor Cyan
    $appId = az ad sp list --display-name sp-arc-linux-onboarding --query "[0].appId" -o tsv 2>$null
    if ($appId) { az ad sp delete --id $appId 2>$null; az ad app delete --id $appId 2>$null }
}

Write-Host "Deleting resource group $ResourceGroup ..." -ForegroundColor Cyan
az group delete --name $ResourceGroup --yes --no-wait

Write-Host "Cleanup launched (RG deletion in background)." -ForegroundColor Green
