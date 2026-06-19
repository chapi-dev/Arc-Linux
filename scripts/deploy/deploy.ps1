<#
.SYNOPSIS
    Despliega la infraestructura Arc-Linux en un RG nuevo de Azure.

.DESCRIPTION
    Orquesta:
      1. Crea el Resource Group.
      2. Despliega infra/main.bicep (LAW + DCR + 3 Maintenance Configurations).
      3. Crea o actualiza 3 policy definitions (AMA, MDE.Linux, AutomaticByPlatform).
      4. Asigna las policies al RG con system-assigned identity + rol minimo.
      5. Crea 3 dynamic scopes (uno por anillo) en las maintenance configurations.
      6. Crea el Service Principal de onboarding y guarda env vars en lab\lab.env.

    Modo idempotente: si los recursos ya existen, los reutiliza.

.PARAMETER ResourceGroup
    RG destino (default rg-arc-linux-lab).

.PARAMETER Location
    Region (default westeurope).

.PARAMETER SubscriptionId
    Subscription. Si se omite, usa la activa.

.PARAMETER NamePrefix
    Prefijo de nombres (default arc-linux-lab).

.PARAMETER SkipServicePrincipal
    No crear el Service Principal de onboarding (util si lo creas a mano luego).

.EXAMPLE
    pwsh -File scripts\deploy\deploy.ps1
    pwsh -File scripts\deploy\deploy.ps1 -ResourceGroup rg-arc-linux-lab -Location westeurope
#>
[CmdletBinding()]
param(
    [string] $ResourceGroup       = 'rg-arc-linux-lab',
    [string] $Location            = 'westeurope',
    [string] $SubscriptionId,
    [string] $NamePrefix          = 'arc-linux-lab',
    [string] $BaseStart           = '2026-07-07 22:00',
    [string] $TimeZone            = 'Romance Standard Time',
    [switch] $SkipServicePrincipal
)

$ErrorActionPreference = 'Stop'
function Step($msg) { Write-Host ""; Write-Host "===> $msg" -ForegroundColor Cyan }
function Info($msg) { Write-Host "    $msg" }
function Ok($msg)   { Write-Host "    OK  $msg" -ForegroundColor Green }

# --- 0) Resolver subscription ------------------------------------------------
if (-not $SubscriptionId) {
    $SubscriptionId = az account show --query id -o tsv
}
az account set --subscription $SubscriptionId | Out-Null
$tenantId = az account show --query tenantId -o tsv
$subName  = az account show --query name -o tsv

Step "Contexto Azure"
Info "Subscription : $subName ($SubscriptionId)"
Info "Tenant       : $tenantId"
Info "RG destino   : $ResourceGroup ($Location)"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')

# --- 1) RG --------------------------------------------------------------------
Step "Resource Group"
$rgExists = az group exists --name $ResourceGroup
if ($rgExists -eq 'true') {
    Info "RG $ResourceGroup ya existe, reutilizando"
} else {
    az group create --name $ResourceGroup --location $Location `
        --tags purpose=arc-linux managedBy=arc-linux-repo env=lab | Out-Null
    Ok "RG $ResourceGroup creado"
}

# --- 2) Bicep deployment ------------------------------------------------------
Step "Bicep deployment (LAW + DCR + MCs)"
$deploymentName = "arc-linux-$(Get-Date -Format 'yyyyMMddHHmmss')"
$bicepFile = Join-Path $repoRoot 'infra\main.bicep'

$deployResult = az deployment group create `
    --resource-group $ResourceGroup `
    --name $deploymentName `
    --template-file $bicepFile `
    --parameters location=$Location namePrefix=$NamePrefix baseStart="$BaseStart" timeZone="$TimeZone" `
    -o json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) { throw "Bicep deployment failed" }
$outs = $deployResult.properties.outputs
Ok "LAW : $($outs.lawName.value)"
Ok "DCR : $($outs.dcrName.value)"
Ok "MC R0: $($outs.mcR0Name.value)"
Ok "MC R1: $($outs.mcR1Name.value)"
Ok "MC R2: $($outs.mcR2Name.value)"

$mcR0Id = $outs.mcR0Id.value
$mcR1Id = $outs.mcR1Id.value
$mcR2Id = $outs.mcR2Id.value

# --- 3) Policy definitions ----------------------------------------------------
Step "Policy definitions (sub-scope)"
$policyDir = Join-Path $repoRoot 'policy\initiatives'
$defs = @(
    @{ Name='arc-linux-deploy-ama';       File='deploy-ama-on-arc-linux.json'   ; DisplayName='[Arc-Linux] Deploy AMA on Linux Arc' }
    @{ Name='arc-linux-deploy-mde';       File='deploy-mde-on-arc-linux.json'   ; DisplayName='[Arc-Linux] Deploy MDE.Linux when mdfc=enabled' }
    @{ Name='arc-linux-patchmode-auto';   File='set-patchmode-automatic.json'   ; DisplayName='[Arc-Linux] Set patchMode=AutomaticByPlatform' }
)
foreach ($def in $defs) {
    $path = Join-Path $policyDir $def.File
    $tmpRules = New-TemporaryFile
    try {
        $json = Get-Content $path -Raw | ConvertFrom-Json
        $json.properties.policyRule | ConvertTo-Json -Depth 100 | Set-Content $tmpRules.FullName -Encoding utf8
        $tmpParams = New-TemporaryFile
        $json.properties.parameters | ConvertTo-Json -Depth 100 | Set-Content $tmpParams.FullName -Encoding utf8
        az policy definition create `
            --name $def.Name `
            --display-name $def.DisplayName `
            --description $json.properties.description `
            --rules $tmpRules.FullName `
            --params $tmpParams.FullName `
            --mode $json.properties.mode `
            --subscription $SubscriptionId | Out-Null
        Ok "Policy def: $($def.Name)"
    } finally {
        Remove-Item $tmpRules.FullName -ErrorAction SilentlyContinue
        if ($tmpParams) { Remove-Item $tmpParams.FullName -ErrorAction SilentlyContinue }
    }
}

# --- 4) Policy assignments al RG ---------------------------------------------
Step "Policy assignments (scope RG)"
$rgScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup"
$contribRole = 'b24988ac-6180-42a0-ab88-20f7382dd24c'   # Contributor
$logAnaContribRole = '92aaf0da-9dab-42b6-94a3-d43ce8d16293' # Log Analytics Contributor
$assignments = @(
    @{ Name='assign-ama-arc-linux';      Def='arc-linux-deploy-ama';     Roles=@($contribRole, $logAnaContribRole) }
    @{ Name='assign-mde-arc-linux';      Def='arc-linux-deploy-mde';     Roles=@($contribRole) }
    @{ Name='assign-patchmode-arc-linux';Def='arc-linux-patchmode-auto'; Roles=@() }   # AuditIfNotExists no necesita MI con roles
)
foreach ($a in $assignments) {
    $defId = "/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/policyDefinitions/$($a.Def)"
    $exists = az policy assignment show --name $a.Name --scope $rgScope 2>$null
    if ($exists) {
        Info "Assignment $($a.Name) ya existe; saltando creacion"
    } else {
        az policy assignment create `
            --name $a.Name `
            --display-name $a.Name `
            --policy $defId `
            --scope $rgScope `
            --location $Location `
            --mi-system-assigned | Out-Null
        Ok "Assignment creado: $($a.Name)"
    }
    # Sleep para que la MI se propague
    Start-Sleep -Seconds 10
    $principalId = az policy assignment show --name $a.Name --scope $rgScope --query identity.principalId -o tsv
    if (-not $principalId) { Write-Warning "No se obtuvo principalId de $($a.Name)"; continue }
    foreach ($r in $a.Roles) {
        $alreadyAssigned = az role assignment list --assignee $principalId --scope $rgScope --role $r --query "[0].id" -o tsv 2>$null
        if (-not $alreadyAssigned) {
            az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal `
                --role $r --scope $rgScope | Out-Null
            Ok "Rol $r asignado a MI de $($a.Name)"
        } else {
            Info "Rol $r ya asignado a MI de $($a.Name)"
        }
    }
}

# --- 5) Dynamic scopes en las MCs --------------------------------------------
Step "Dynamic scopes en Maintenance Configurations"
function Ensure-DynamicScope {
    param($McResourceGroup, $McName, $ScopeName, $Ring, $SubId)
    $body = @{
        properties = @{
            filter = @{
                osTypes      = @('Linux')
                resourceTypes= @('Microsoft.HybridCompute/machines')
                locations    = @()
                resourceGroups = @()
                tagSettings = @{
                    tags = @{
                        ring = @($Ring)
                        aum  = @('enabled')
                    }
                    filterOperator = 'All'
                }
            }
        }
    } | ConvertTo-Json -Depth 10
    $tmp = New-TemporaryFile
    Set-Content $tmp.FullName $body -Encoding utf8
    $uri = "/subscriptions/$SubId/resourceGroups/$McResourceGroup/providers/Microsoft.Maintenance/configurationAssignments/$ScopeName" + "?api-version=2023-04-01"
    # configurationAssignments con filter dinamico = dynamic scope
    $payload = @{
        location = $Location
        properties = @{
            maintenanceConfigurationId = "/subscriptions/$SubId/resourceGroups/$McResourceGroup/providers/Microsoft.Maintenance/maintenanceConfigurations/$McName"
            filter = @{
                osTypes      = @('Linux')
                resourceTypes= @('Microsoft.HybridCompute/machines')
                locations    = @()
                resourceGroups = @()
                tagSettings = @{
                    tags = @{
                        ring = @($Ring)
                        aum  = @('enabled')
                    }
                    filterOperator = 'All'
                }
            }
        }
    } | ConvertTo-Json -Depth 10
    Set-Content $tmp.FullName $payload -Encoding utf8
    az rest --method PUT --uri "https://management.azure.com$uri" --body "@$($tmp.FullName)" | Out-Null
    Remove-Item $tmp.FullName -ErrorAction SilentlyContinue
}

try {
    Ensure-DynamicScope -McResourceGroup $ResourceGroup -McName $outs.mcR0Name.value -ScopeName 'ds-arc-linux-r0' -Ring 'R0' -SubId $SubscriptionId
    Ok "Dynamic scope ds-arc-linux-r0 -> MC R0"
    Ensure-DynamicScope -McResourceGroup $ResourceGroup -McName $outs.mcR1Name.value -ScopeName 'ds-arc-linux-r1' -Ring 'R1' -SubId $SubscriptionId
    Ok "Dynamic scope ds-arc-linux-r1 -> MC R1"
    Ensure-DynamicScope -McResourceGroup $ResourceGroup -McName $outs.mcR2Name.value -ScopeName 'ds-arc-linux-r2' -Ring 'R2' -SubId $SubscriptionId
    Ok "Dynamic scope ds-arc-linux-r2 -> MC R2"
} catch {
    Write-Warning "Fallo creando dynamic scopes ($_). Puedes crearlos a mano con 'az maintenance assignment create-or-update-dynamic-scope'."
}

# --- 6) Service Principal de onboarding --------------------------------------
if (-not $SkipServicePrincipal) {
    Step "Service Principal de onboarding"
    $spName = 'sp-arc-linux-onboarding'
    $existing = az ad sp list --display-name $spName --query "[0].appId" -o tsv 2>$null
    if ($existing) {
        Info "SP $spName ya existe (appId=$existing). No se rota el secreto."
        $spAppId = $existing
        $spSecret = '<reuse-existing>'
    } else {
        $sp = az ad sp create-for-rbac `
            --name $spName `
            --role "Azure Connected Machine Onboarding" `
            --scopes $rgScope `
            --years 1 `
            -o json | ConvertFrom-Json
        $spAppId  = $sp.appId
        $spSecret = $sp.password
        Ok "SP creado (appId=$spAppId)"
    }

    $labDir = Join-Path $repoRoot 'lab'
    $envFile = Join-Path $labDir 'lab.env'
    @"
# Generado por scripts/deploy/deploy.ps1 el $(Get-Date -Format 's')
export ARC_TENANT_ID=$tenantId
export ARC_SUBSCRIPTION_ID=$SubscriptionId
export ARC_RESOURCE_GROUP=$ResourceGroup
export ARC_LOCATION=$Location
export ARC_SP_APP_ID=$spAppId
export ARC_SP_SECRET=$spSecret
export ARC_TAG_ENV=lab
export ARC_TAG_RING=R0
export ARC_TAG_OWNER=platform-linux
export ARC_TAG_APP=none
export ARC_TAG_MDFC=enabled
export ARC_TAG_AUM=enabled
"@ | Set-Content $envFile -Encoding utf8
    Ok "Env vars guardadas en $envFile (gitignored)"
}

# --- 7) Resumen final --------------------------------------------------------
Step "Resumen"
Write-Host ""
Write-Host "Recursos en $ResourceGroup :" -ForegroundColor Yellow
az resource list -g $ResourceGroup --query "[].{name:name,type:type,location:location}" -o table

Write-Host ""
Write-Host "Policy assignments en RG:" -ForegroundColor Yellow
az policy assignment list --scope $rgScope --query "[].{name:name,policy:policyDefinitionId}" -o table

Write-Host ""
Write-Host "Siguiente paso (cuando quieras hacer el onboarding del lab):" -ForegroundColor Cyan
Write-Host "  pwsh -File scripts/lab/01-create-linux-vm.ps1 -ResourceGroup $ResourceGroup"
Write-Host "  scp scripts/lab/02-deazure-vm.sh <user>@<ip>:~"
Write-Host "  ssh ... 'sudo bash 02-deazure-vm.sh'"
Write-Host "  source lab/lab.env ; ssh ... 'sudo -E bash 04-azcmagent-connect.sh'"
