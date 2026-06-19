<#
.SYNOPSIS
    Crea una VM Linux en Azure para usarla como lab de Azure Arc.

.DESCRIPTION
    Provisiona una VM (RHEL 9 por defecto), su NIC, NSG, IP publica y SSH key.
    La VM se crea con tag lifecycle=lab para localizarla / borrarla facilmente.

    Pensada para que despues se "des-azurice" con scripts/lab/02-deazure-vm.sh
    y se conecte a Azure Arc como si fuera on-prem.

.PARAMETER ResourceGroup
    RG donde se crea la VM (se crea si no existe).

.PARAMETER Location
    Region de Azure (default westeurope).

.PARAMETER VmName
    Nombre de la VM (default lab-rhel9-01).

.PARAMETER Image
    Imagen URN (default RedHat:RHEL:9-lvm-gen2:latest).
    Otras: 'Canonical:ubuntu-24_04-lts:server:latest', 'Erockyenterprisesoftwarefoundationinc1653071250513:rockylinux-9:rockylinux-9:latest'

.PARAMETER Size
    Tamano de VM (default Standard_B2s).

.PARAMETER AdminUsername
    Usuario SSH (default azureuser).

.PARAMETER SshKeyPath
    Ruta a la clave SSH publica (default $HOME\.ssh\id_rsa.pub).

.PARAMETER MyPublicIp
    IP publica del operador para abrir SSH 22 solo a esa IP. Si no se pasa, se intenta detectar.

.EXAMPLE
    ./01-create-linux-vm.ps1 -ResourceGroup rg-arc-linux-lab -VmName lab-rhel9-01

.NOTES
    Requiere Azure CLI con login activo (az login) y subscripcion seleccionada (az account set --subscription ...).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string] $ResourceGroup,
    [string] $Location       = 'westeurope',
    [string] $VmName         = 'lab-rhel9-01',
    [string] $Image          = 'RedHat:RHEL:9-lvm-gen2:latest',
    [string] $Size           = 'Standard_B2s',
    [string] $AdminUsername  = 'azureuser',
    [string] $SshKeyPath     = (Join-Path $HOME '.ssh\id_rsa.pub'),
    [string] $MyPublicIp     = $null
)

$ErrorActionPreference = 'Stop'

function Require-Tool($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "Tool '$name' is required but not on PATH."
    }
}

Require-Tool az

if (-not (Test-Path $SshKeyPath)) {
    throw "SSH public key not found at $SshKeyPath. Run ssh-keygen first or pass -SshKeyPath."
}

if (-not $MyPublicIp) {
    Write-Host "Detecting your public IP..." -ForegroundColor Cyan
    try { $MyPublicIp = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 5) } catch {
        throw "Could not auto-detect public IP. Pass -MyPublicIp explicitly."
    }
}
Write-Host "Using public IP $MyPublicIp for SSH allow-list" -ForegroundColor Cyan

Write-Host "Creating resource group $ResourceGroup in $Location..." -ForegroundColor Cyan
az group create --name $ResourceGroup --location $Location --tags lifecycle=lab purpose=arc-linux | Out-Null

$nsgName = "$VmName-nsg"
Write-Host "Creating NSG $nsgName..." -ForegroundColor Cyan
az network nsg create -g $ResourceGroup -n $nsgName -l $Location | Out-Null
az network nsg rule create -g $ResourceGroup --nsg-name $nsgName -n allow-ssh `
    --priority 1000 --access Allow --protocol Tcp --direction Inbound `
    --source-address-prefixes $MyPublicIp --source-port-ranges '*' `
    --destination-port-ranges 22 --destination-address-prefixes '*' | Out-Null

Write-Host "Creating VM $VmName ($Size) with image $Image ..." -ForegroundColor Cyan
az vm create `
    --resource-group $ResourceGroup `
    --name $VmName `
    --location $Location `
    --image $Image `
    --size $Size `
    --admin-username $AdminUsername `
    --ssh-key-values "$SshKeyPath" `
    --nsg $nsgName `
    --public-ip-sku Standard `
    --storage-sku StandardSSD_LRS `
    --os-disk-size-gb 64 `
    --tags lifecycle=lab purpose=arc-linux os=linux env=lab ring=R0 owner=platform-linux `
    | Out-Null

$publicIp = az vm show -d -g $ResourceGroup -n $VmName --query publicIps -o tsv

Write-Host ""
Write-Host "=== VM ready ===" -ForegroundColor Green
Write-Host "Hostname    : $VmName"
Write-Host "Public IP   : $publicIp"
Write-Host "SSH         : ssh ${AdminUsername}@${publicIp}"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. scp ./02-deazure-vm.sh ${AdminUsername}@${publicIp}:~"
Write-Host "  2. ssh ${AdminUsername}@${publicIp} 'sudo bash ~/02-deazure-vm.sh'"
Write-Host "  3. Use ./04-azcmagent-connect.sh on the VM to onboard to Arc"
