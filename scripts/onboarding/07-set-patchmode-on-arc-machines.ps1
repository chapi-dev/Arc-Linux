<#
.SYNOPSIS
    Configura patchSettings.patchMode/assessmentMode = AutomaticByPlatform
    en todas las maquinas Arc Linux del RG cuyo tag aum == 'enabled'.

.DESCRIPTION
    En Azure Arc, el alias 'patchMode' no es modifiable via Azure Policy
    'Modify', por eso este script aplica el cambio via API directa con
    `az connectedmachine update`. Ejecutar desde el desktop del operator (no
    desde el host).

    Idempotente: solo cambia las maquinas que aun no estan configuradas.

.PARAMETER ResourceGroup
    RG donde estan las maquinas Arc.

.EXAMPLE
    pwsh -File scripts\onboarding\07-set-patchmode-on-arc-machines.ps1 -ResourceGroup rg-arc-linux-lab
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string] $ResourceGroup
)

$ErrorActionPreference = 'Continue'

Write-Host "Buscando maquinas Arc Linux con tag aum=enabled en $ResourceGroup ..." -ForegroundColor Cyan
$machines = az connectedmachine list -g $ResourceGroup --query "[?osName=='linux' && tags.aum=='enabled'].{name:name,patchMode:osProfile.linuxConfiguration.patchSettings.patchMode,assessmentMode:osProfile.linuxConfiguration.patchSettings.assessmentMode}" -o json | ConvertFrom-Json

if (-not $machines -or $machines.Count -eq 0) {
    Write-Host "No hay maquinas que cumplan filtro. Nada que hacer." -ForegroundColor Yellow
    return
}

foreach ($m in $machines) {
    if ($m.patchMode -eq 'AutomaticByPlatform' -and $m.assessmentMode -eq 'AutomaticByPlatform') {
        Write-Host "  SKIP $($m.name) (ya configurada)" -ForegroundColor Gray
        continue
    }
    Write-Host "  UPDATE $($m.name) ..." -ForegroundColor Cyan
    az connectedmachine update `
        -g $ResourceGroup -n $m.name `
        --set properties.osProfile.linuxConfiguration.patchSettings.assessmentMode=AutomaticByPlatform `
              properties.osProfile.linuxConfiguration.patchSettings.patchMode=AutomaticByPlatform | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host "    OK" -ForegroundColor Green } else { Write-Host "    FAIL" -ForegroundColor Red }
}

Write-Host ""
Write-Host "Estado final:" -ForegroundColor Yellow
az connectedmachine list -g $ResourceGroup --query "[?osName=='linux'].{name:name,patch:osProfile.linuxConfiguration.patchSettings.patchMode,assessment:osProfile.linuxConfiguration.patchSettings.assessmentMode,ring:tags.ring}" -o table
