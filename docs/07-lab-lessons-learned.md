# 07 — Lecciones aprendidas del lab

> Compilación de **gotchas reales** descubiertos durante el deploy y onboarding
> del lab (2026-06-21 → 2026-06-22). Léelo antes de replicar en producción.

## Índice

1. [JIT VM Access bloquea SSH custom](#1-jit-vm-access-bloquea-ssh-custom)
2. [Scripts .sh con CRLF rompen bash](#2-scripts-sh-con-crlf-rompen-bash)
3. [RHEL PAYG en Azure y RHUI](#3-rhel-payg-en-azure-y-rhui)
4. [Bicep CLI en Windows con `--outfile NUL`](#4-bicep-cli-en-windows-con---outfile-nul)
5. [Azure CLI `application-insights` extension rota](#5-azure-cli-application-insights-extension-rota)
6. [AUM bulk panel y Arc-enabled servers](#6-aum-bulk-panel-y-arc-enabled-servers)
7. [MDE.Linux Network Protection y release ring](#7-mdelinux-network-protection-y-release-ring)
8. [MDE en passive mode por defecto](#8-mde-en-passive-mode-por-defecto)
9. [Policy Modify no funciona con `patchMode` en Arc](#9-policy-modify-no-funciona-con-patchmode-en-arc)
10. [DCR Change Tracking necesita la extensión primero](#10-dcr-change-tracking-necesita-la-extensión-primero)

---

## 1. JIT VM Access bloquea SSH custom

**Síntoma**: `ssh -i <key> azureuser@<ip>` da `Connection timed out`. El NSG
muestra una regla `DenyAll:22` con prioridad 4096 que sustituyó tu allow custom.

**Causa**: Microsoft Defender for Cloud → **Just-In-Time VM Access** está
habilitado en la sub. Al onboardar la VM aplica reglas default-deny en el NSG
para forzar el flujo "request access" temporal.

**Workaround (lab)**: añadir una regla allow custom con prioridad **<4096**.

```powershell
pwsh -File scripts\lab\reopen-ssh.ps1
```

Crea/refresca `allow-ssh-mine` (priority 1000) con tu IP pública actual en
todos los NSGs del RG. Re-ejecutar cuando tu ISP rote la IP o JIT vuelva a
limpiar las reglas custom.

**Producción**: no abrir SSH al mundo. Usar **Azure Bastion** o JIT con su
flujo de "request access" temporal. Para Arc-enabled servers (on-prem), el
problema no existe — JIT solo aplica a Azure VMs nativas.

---

## 2. Scripts .sh con CRLF rompen bash

**Síntoma**: `./02-deazure-vm.sh` falla con:
```
set: invalid option name pipefail
./02-deazure-vm.sh: line 2: $'\r': command not found
```

**Causa**: el repo se clonó desde Windows y los `.sh` están con line endings
CRLF. Bash en Linux no los entiende.

**Workaround**: convertir a LF en el host Linux o forzar LF en git.

```bash
# En el host Linux
sed -i 's/\r$//' scripts/lab/02-deazure-vm.sh

# O usar dos2unix
dos2unix scripts/lab/02-deazure-vm.sh
```

**Mejor solución**: añadir `.gitattributes` a la raíz del repo para que git
fuerce LF en `.sh` independientemente del SO:

```gitattributes
*.sh text eol=lf
*.ps1 text eol=crlf
*.bicep text eol=lf
```

Ya está aplicado en este repo.

---

## 3. RHEL PAYG en Azure y RHUI

**Síntoma**: cualquier `dnf <cmd>` muestra:
```
Updating Subscription Management repositories.
Unable to read consumer identity
This system is not registered with an entitlement server. You can use subscription-manager to register.
```

**Causa**: RHEL PAYG en Azure no usa Red Hat Subscription Manager. Usa
**RHUI** (Red Hat Update Infrastructure) gestionado por Azure. Los mensajes
son normales y **no impiden** que dnf instale paquetes.

**Acción**: ignorar el warning. Si quieres silenciarlo:

```bash
sudo subscription-manager config --rhsm.manage_repos=0
```

**Producción**: si la imagen es BYOS (Bring Your Own Subscription), sí hay
que registrar con `subscription-manager register --username ... --password ...`.
En PAYG no.

---

## 4. Bicep CLI en Windows con `--outfile NUL`

**Síntoma**: validar Bicep con `az bicep build --file foo.bicep --outfile NUL`
falla con:
```
System.IO.IOException: Unsupported Windows DOS device path.
   at Bicep.IO.Abstraction.IOUri.FromFilePath(String filePath)
```

**Causa**: Bicep CLI no soporta `NUL` como path en Windows (a partir de la
versión 0.39.x).

**Workaround**: usar `--stdout` y redirigir.

```powershell
az bicep build --file infra/modules/dcr.bicep --stdout > $null
```

---

## 5. Azure CLI `application-insights` extension rota

**Síntoma**: comandos de Azure CLI fallan con:
```
PermissionError: [WinError 5] Access is denied:
'C:\Users\<u>\.azure\cliextensions\application-insights\application_insights-1.2.3.dist-info'
```

Afecta a:
- `az graph query`
- `az connectedmachine update`
- `az maintenance ...`
- Cualquier comando que cargue todas las extensions al arrancar.

**Causa**: actualización de la extension dejó archivos bloqueados/corruptos.

**Workaround 1 — usar `az rest` directo** (lo más rápido):
```powershell
$uri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.HybridCompute/machines/$m`?api-version=2024-07-10"
az rest --method GET --uri $uri
```

**Workaround 2 — reinstalar la extension**:
```powershell
az extension remove --name application-insights
az extension add    --name application-insights
```

A veces el remove también falla por permisos. Borrar a mano el folder y
reinstalar:
```powershell
Remove-Item "$env:USERPROFILE\.azure\cliextensions\application-insights" -Recurse -Force
az extension add --name application-insights
```

---

## 6. AUM bulk panel y Arc-enabled servers

**Síntoma**: en `Azure Update Manager → Machines → Update settings` (bulk),
para máquinas Arc-enabled la columna **Patch orchestration** sale en gris
con `Not available`. El aviso dice:

> *"Patch orchestration is not applicable to Arc-enabled servers. To schedule
> updates on Azure machines, please change patch orchestration to 'Customer
> Managed Schedules'..."*

**Causa**: el bulk panel solo configura `patchMode` para Azure VMs nativas.
En Arc el equivalente está en otro alias y no es modificable desde ese panel.

**Workaround**:

**A) Por VM individual (portal)**: `Azure Update Manager → Machines → click
sobre la VM → Update settings` (dentro del recurso, no el bulk). Ahí sí
aparece **Patch orchestration** activo.

**B) Por API (cuando hay muchas VMs)**:
```powershell
$uri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.HybridCompute/machines/$m`?api-version=2024-07-10"
$body = @{
  properties = @{
    osProfile = @{
      linuxConfiguration = @{
        patchSettings = @{
          patchMode = "AutomaticByPlatform"
          assessmentMode = "AutomaticByPlatform"
        }
      }
    }
  }
} | ConvertTo-Json -Depth 10 -Compress
az rest --method PATCH --uri $uri --body $body --headers "Content-Type=application/json"
```

O el script idempotente:
```powershell
pwsh -File scripts\onboarding\07-set-patchmode-on-arc-machines.ps1 -ResourceGroup rg-arc-linux-lab
```

> Nota: el bulk panel **sí permite** activar `Periodic assessment` en lote
> para Arc. Solo Patch orchestration está limitado.

---

## 7. MDE.Linux Network Protection y release ring

**Síntoma**: después de:
```bash
sudo mdatp config network-protection enforcement-level --value audit
```

`mdatp health` reporta:
```
healthy: false
health_issues: ["Network Protection cannot start due to unsupported release ring"]
network_protection_status: "enablement_failed_due_to_edr_capabilities"
```

**Causa**: Network Protection en MDE.Linux requiere **release_ring=Insider-Fast**.
En `Production` (el default y recomendado para prod) no arranca.

**Workaround para prod**: dejar Network Protection desactivado.
```bash
sudo mdatp config network-protection enforcement-level --value disabled
sudo mdatp health --field healthy   # debe ser true
```

**Si necesitas Network Protection** (no recomendado en prod por ser preview):
```bash
sudo mdatp edr early-preview enable
sudo systemctl restart mdatp
```

Ref: <https://learn.microsoft.com/en-us/defender-endpoint/network-protection-linux>

---

## 8. MDE en passive mode por defecto

**Síntoma**: tras desplegar MDE.Linux via Defender for Cloud, `mdatp health`
muestra:
```
passive_mode_enabled: true
real_time_protection_enabled: false
engine_load_status: "Engine not loaded"
```

**Causa**: Microsoft despliega MDE.Linux en **passive mode** por defecto para
coexistir con otros AVs (típico cuando todavía hay Trend Micro / Symantec /
McAfee / ESET en el host). En passive mode MDE **informa pero no bloquea**.

**Para pasar a active mode (sustituir el AV existente)**:
```bash
sudo mdatp config passive-mode --value disabled
sudo mdatp config real-time-protection --value enabled
sudo mdatp config behavior-monitoring --value enabled
sudo mdatp definitions update
sudo mdatp health
```

Esperado:
```
passive_mode_enabled: false
real_time_protection_enabled: true
engine_load_status: "Engine load succeeded"
behavior_monitoring: enabled
```

**Producción**: **siempre** desinstalar el AV anterior (Trend Micro) **antes**
de activar active mode. Tener dos AVs activos a la vez puede causar:
- Falsos positivos cruzados
- Cuarentena en duelo por el mismo fichero
- Performance hit del 30%+ en I/O

Orden recomendado:
1. Onboard a Arc + MDE en passive mode (convivencia).
2. Validar MDE funciona (cobertura, telemetría, alerts en M365 Defender).
3. Plan de migración por anillos: desinstalar Trend Micro + pasar MDE a active.
4. Periodo de observación.

---

## 9. Policy Modify no funciona con `patchMode` en Arc

**Síntoma**: al asignar una policy con efecto `Modify` que intenta poner
`patchMode = AutomaticByPlatform` sobre máquinas Arc, falla:
```
Modify operation 'addOrReplace' is not supported on field
'Microsoft.HybridCompute/machines/osProfile.linuxConfiguration.patchSettings.patchMode'
```

**Causa**: el alias de policy para esa propiedad **no está marcado como
modifiable** en Arc (`Microsoft.HybridCompute`). Solo es queryable
(`AuditIfNotExists`).

**Workaround**: usar `AuditIfNotExists` para detectar, + script externo para
remediar (no `DeployIfNotExists` ni `Modify`):

```json
{
  "if": {
    "field": "type",
    "equals": "Microsoft.HybridCompute/machines"
  },
  "then": {
    "effect": "AuditIfNotExists",
    "details": {
      "type": "Microsoft.HybridCompute/machines",
      "name": "[field('name')]",
      "existenceCondition": {
        "field": "Microsoft.HybridCompute/machines/osProfile.linuxConfiguration.patchSettings.patchMode",
        "equals": "AutomaticByPlatform"
      }
    }
  }
}
```

El script `scripts/onboarding/07-set-patchmode-on-arc-machines.ps1` (o el
workaround `az rest` del punto 6) hacen la remediación.

**Esto puede cambiar en el futuro** cuando Microsoft marque el alias como
modifiable. Verificar periódicamente.

---

## 10. DCR Change Tracking necesita la extensión primero

**Síntoma**: al desplegar un DCR con `dataSources` apuntando a las tablas
`Microsoft-ConfigurationChange*`, la validación de Azure Resource Manager
falla con `InvalidStreamName` o las tablas no aparecen en el LAW.

**Causa**: las tablas custom de Change Tracking
(`Microsoft-ConfigurationChange`, `Microsoft-ConfigurationChangeV2`,
`Microsoft-ConfigurationData`) **no existen en el LAW hasta que la
extensión `ChangeTracking-Linux` se haya desplegado al menos una vez** en
alguna VM apuntando a ese workspace.

**Workaround**: en una primera pasada de Bicep, dejar el DCR con sólo syslog
(o sólo perfCounters), desplegar la extensión `ChangeTracking-Linux` en una
VM cualquiera para que cree las tablas, y luego en una segunda pasada
ampliar el DCR con los streams `Microsoft-ConfigurationChange*`.

Alternativa más rápida: dejar que Defender for Cloud se encargue del DCR
de FIM cuando habilites FIM en el plan (`Settings → File Integrity
Monitoring → Workspace`). Es lo que se ha hecho en este lab.

El DCR de syslog se ha mantenido aparte (`dcr-arc-linux-lab-syslog`) para
recolectar `auth`, `daemon`, `kern`, `local0-7` independientemente.
