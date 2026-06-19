<#
.SYNOPSIS
    Instala Azure Monitor Agent (AMA) + ChangeTracking-Linux en una maquina Arc.

.EXAMPLE
    ./05-install-ama.ps1 -ResourceGroup rg-arc-linux-lab -MachineName lab-rhel9-01
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string] $ResourceGroup,
    [Parameter(Mandatory=$true)] [string] $MachineName,
    [string] $Location = 'westeurope'
)

$ErrorActionPreference = 'Stop'

Write-Host "Installing AzureMonitorLinuxAgent on $MachineName..." -ForegroundColor Cyan
az connectedmachine extension create `
    --resource-group $ResourceGroup `
    --machine-name $MachineName `
    --location $Location `
    --name AzureMonitorLinuxAgent `
    --publisher Microsoft.Azure.Monitor `
    --type AzureMonitorLinuxAgent `
    --enable-auto-upgrade true | Out-Null

Write-Host "Installing ChangeTracking-Linux on $MachineName..." -ForegroundColor Cyan
az connectedmachine extension create `
    --resource-group $ResourceGroup `
    --machine-name $MachineName `
    --location $Location `
    --name ChangeTracking-Linux `
    --publisher Microsoft.Azure.ChangeTrackingAndInventory `
    --type ChangeTracking-Linux `
    --enable-auto-upgrade true | Out-Null

Write-Host "Done. Verify with:" -ForegroundColor Green
Write-Host "  az connectedmachine extension list -g $ResourceGroup --machine-name $MachineName -o table"
