<#
.SYNOPSIS
    Crea el Service Principal sp-arc-linux-onboarding y refresca lab\lab.env.

.DESCRIPTION
    Pensado para ejecutarse manualmente desde un host con sesion `az login`
    fresca (e interactiva si tu tenant tiene CAE activado, que invalida
    tokens cacheados al hacer operaciones contra Graph).

    Si el deploy automatico fallo el paso del SP con error
    "TokenCreatedWithOutdatedPolicies", ejecuta:

        az logout
        az login
        pwsh -File scripts\deploy\rotate-sp.ps1

.PARAMETER ResourceGroup
    RG sobre el que el SP tendra rol 'Azure Connected Machine Onboarding'.

.EXAMPLE
    pwsh -File scripts\deploy\rotate-sp.ps1 -ResourceGroup rg-arc-linux-lab
#>
[CmdletBinding()]
param(
    [string] $ResourceGroup = 'rg-arc-linux-lab',
    [string] $SpName        = 'sp-arc-linux-onboarding',
    [string] $SubscriptionId
)

$ErrorActionPreference = 'Stop'

if (-not $SubscriptionId) { $SubscriptionId = az account show --query id -o tsv }
az account set --subscription $SubscriptionId | Out-Null
$tenantId = az account show --query tenantId -o tsv
$rgScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup"

Write-Host "Creando / rotando $SpName ..." -ForegroundColor Cyan
$existing = az ad sp list --display-name $SpName --query "[0].appId" -o tsv 2>$null
if ($existing) {
    Write-Host "Borrando SP existente $existing para rotar secreto..." -ForegroundColor Yellow
    az ad sp delete --id $existing 2>$null
    az ad app delete --id $existing 2>$null
    Start-Sleep -Seconds 10
}

$sp = az ad sp create-for-rbac `
    --name $SpName `
    --role "Azure Connected Machine Onboarding" `
    --scopes $rgScope `
    --years 1 `
    -o json | ConvertFrom-Json

if (-not $sp.appId) { throw "No se obtuvo appId. Token CAE expirado, ejecuta 'az logout && az login' y reintenta." }

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$envFile  = Join-Path $repoRoot 'lab\lab.env'

@"
# Regenerado por scripts/deploy/rotate-sp.ps1 el $(Get-Date -Format 's')
export ARC_TENANT_ID=$tenantId
export ARC_SUBSCRIPTION_ID=$SubscriptionId
export ARC_RESOURCE_GROUP=$ResourceGroup
export ARC_LOCATION=westeurope
export ARC_SP_APP_ID=$($sp.appId)
export ARC_SP_SECRET=$($sp.password)
export ARC_TAG_ENV=lab
export ARC_TAG_RING=R0
export ARC_TAG_OWNER=platform-linux
export ARC_TAG_APP=none
export ARC_TAG_MDFC=enabled
export ARC_TAG_AUM=enabled
"@ | Set-Content $envFile -Encoding utf8

Write-Host ""
Write-Host "OK Service Principal listo." -ForegroundColor Green
Write-Host "    appId   : $($sp.appId)"
Write-Host "    secret  : ${env:none}(guardado en $envFile)"
Write-Host ""
Write-Host "Para onboardar una maquina linux desde tu desktop:"
Write-Host "    scp lab\lab.env <user>@<host>:~/lab.env"
Write-Host "    ssh <user>@<host>"
Write-Host "      source ~/lab.env"
Write-Host "      sudo -E bash 04-azcmagent-connect.sh"
