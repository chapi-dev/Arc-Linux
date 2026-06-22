<#
.SYNOPSIS
    Reabre el puerto 22 en los NSGs del lab a tu IP publica actual.

.DESCRIPTION
    Detecta tu IP publica via api.ipify.org y crea/actualiza la regla
    'allow-ssh-mine' (priority 1000) en los NSGs de las VMs de lab,
    sobreescribiendo cualquier IP previa. Util cuando tu ISP rota la IP o
    cuando JIT de Defender for Cloud borra reglas custom.

.EXAMPLE
    pwsh -File scripts\lab\reopen-ssh.ps1
#>
[CmdletBinding()]
param(
    [string] $ResourceGroup = 'rg-arc-linux-lab',
    [string[]] $NsgNames    = @('lab-rhel9-01-nsg','lab-ubuntu22-01-nsg')
)

$ErrorActionPreference = 'Stop'

$myIp = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 5)
Write-Host "Tu IP publica actual: $myIp" -ForegroundColor Cyan

foreach ($nsg in $NsgNames) {
    Write-Host "=> $nsg" -ForegroundColor Cyan
    az network nsg rule delete -g $ResourceGroup --nsg-name $nsg -n allow-ssh-mine 2>$null | Out-Null
    az network nsg rule create -g $ResourceGroup --nsg-name $nsg -n allow-ssh-mine `
        --priority 1000 --access Allow --direction Inbound --protocol Tcp `
        --source-address-prefixes $myIp --source-port-ranges '*' `
        --destination-port-ranges 22 --destination-address-prefixes '*' `
        --description "Lab manual SSH allow from operator IP (overrides JIT default-deny)" | Out-Null
    Write-Host "   OK regla allow-ssh-mine apuntando a $myIp" -ForegroundColor Green
}

Write-Host "`nIntenta de nuevo:" -ForegroundColor Yellow
Write-Host "  ssh -i `$HOME\.ssh\id_rsa azureuser@<RHEL_IP>"
Write-Host "  ssh -i `$HOME\.ssh\id_rsa azureuser@<UBUNTU_IP>"
