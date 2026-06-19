# Infra – Bicep para Arc-Linux

Despliegue Bicep a **scope de Resource Group** que crea:

| Recurso                                                  | Nombre                                |
|----------------------------------------------------------|---------------------------------------|
| Log Analytics Workspace                                  | `law-arc-linux-lab`                   |
| Data Collection Rule (syslog only)                       | `dcr-arc-linux-lab-syslog`            |
| Maintenance Configuration – R0 (Tue, weekly)             | `mc-arc-linux-lab-r0-weekly`          |
| Maintenance Configuration – R1 (Thu, weekly)             | `mc-arc-linux-lab-r1-weekly`          |
| Maintenance Configuration – R2 (Sat, biweekly)           | `mc-arc-linux-lab-r2-biweekly`        |

Adicionalmente `scripts/deploy/deploy.ps1` crea:

| Recurso                                                                                | Scope        |
|----------------------------------------------------------------------------------------|--------------|
| Policy definition `arc-linux-deploy-ama` (DeployIfNotExists)                           | Subscription |
| Policy definition `arc-linux-deploy-mde` (DeployIfNotExists, requiere tag `mdfc=enabled`) | Subscription |
| Policy definition `arc-linux-patchmode-auto` (**AuditIfNotExists**, ver nota)          | Subscription |
| Policy assignments (`assign-ama`, `assign-mde`, `assign-patchmode`) + MI + roles       | RG           |
| Dynamic scopes `ds-arc-linux-r{0,1,2}` (tag query `ring=Rx + aum=enabled`)             | MC           |
| Service Principal `sp-arc-linux-onboarding` (rol mínimo) — si CAE lo permite           | RG           |

## Cómo desplegar

```powershell
# Login y selección de subscription
az login
az account set --subscription <SUBSCRIPTION_ID>

# Orquestación completa (RG nuevo + Bicep + policies + dynamic scopes + SP)
pwsh -File scripts\deploy\deploy.ps1

# Parámetros opcionales
pwsh -File scripts\deploy\deploy.ps1 `
    -ResourceGroup rg-arc-linux-lab `
    -Location westeurope `
    -NamePrefix arc-linux-lab `
    -BaseStart "2026-07-07 22:00" `
    -TimeZone "Romance Standard Time"
```

## Cómo limpiar

```powershell
pwsh -File scripts\deploy\cleanup.ps1 -ResourceGroup rg-arc-linux-lab -Confirm:$true
```

## Validar Bicep sin desplegar

```powershell
az bicep build --file infra\main.bicep --stdout > $null
az deployment group what-if `
    --resource-group rg-arc-linux-lab `
    --template-file infra\main.bicep
```

## Lo que NO crea (de momento)

- **Defender for Servers Plan 2** en la sub: requiere decisión de coste
  (~$15/host/mes). Habilitar manualmente cuando se pruebe MDE.Linux:
  ```bash
  az security pricing create -n VirtualMachines --tier Standard --subplan P2
  ```
- **DCR associations (DCRA)**: se crean al onboardar cada máquina, no antes.
- **Tablas custom de Change Tracking** en el LAW: se generan al instalar la
  extensión `ChangeTracking-Linux` sobre la primera máquina (Microsoft crea
  las tablas + DCR automáticamente como parte del flujo de la solución).
- **VMs / Arc-enabled servers**: se crean con `scripts/lab/`.

## Notas técnicas relevantes

- **`patchmode-auto` es `AuditIfNotExists`, no `Modify`.** En Azure Arc el
  alias `Microsoft.HybridCompute/machines/osProfile.linuxConfiguration.patchSettings.patchMode`
  no es modificable via Azure Policy. Aplica el cambio con:
  ```powershell
  pwsh -File scripts/onboarding/07-set-patchmode-on-arc-machines.ps1 -ResourceGroup rg-arc-linux-lab
  ```
- **Service Principal y CAE**: si tu tenant tiene **Continuous Access
  Evaluation** activa, `az ad sp create-for-rbac` puede devolver
  `TokenCreatedWithOutdatedPolicies` y el deploy.ps1 dejará el SP sin
  crear. Refresca tu sesión y ejecuta:
  ```powershell
  az logout ; az login
  pwsh -File scripts/deploy/rotate-sp.ps1 -ResourceGroup rg-arc-linux-lab
  ```
