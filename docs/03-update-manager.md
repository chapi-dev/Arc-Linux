# 03 – Azure Update Manager para Linux on Arc

## 1. Qué sustituye

| Hoy                                                       | Con Azure Update Manager (AUM)                |
|-----------------------------------------------------------|-----------------------------------------------|
| Conexión manual por SSH cada X días                       | Schedule declarativo, sin tocar el host       |
| `yum update -y` / `dnf update -y` / `apt upgrade -y` a mano | Maintenance Configuration ejecutada por AUM |
| Reboot decidido a ojo                                     | `rebootSetting = IfRequired` / `Always` / `Never` |
| Sin auditoría centralizada                                | Histórico en portal + Resource Graph + Log Analytics |
| Sin ventanas de mantenimiento                             | Maintenance windows con dynamic scope por tag |

## 2. Conceptos clave

- **Periodic assessment**: AUM evalúa cada **24 h** qué parches faltan en la
  máquina (no instala). Se activa por máquina (`patchSettings.assessmentMode = AutomaticByPlatform`).
- **Maintenance Configuration (MC)**: el "qué + cuándo + cómo" del patching
  (paquetes incluidos/excluidos, ventana, reboot).
- **Dynamic Scope**: query por tags/subscripciones/RGs que asocia máquinas a la MC. Se evalúa **en cada ejecución**, así que nuevas máquinas con los tags correctos entran solas.
- **One-time update**: ejecución puntual fuera de schedule (útil para emergencias / 0-day).

## 3. Diseño de anillos

| Ring | MC                                  | Cron / RRULE                          | Reboot       | Classifications                                  |
|------|-------------------------------------|---------------------------------------|--------------|--------------------------------------------------|
| R0   | `mc-linux-r0-weekly`                | `RRULE:FREQ=WEEKLY;BYDAY=TU;BYHOUR=22`| `IfRequired` | `Critical`, `Security`                           |
| R1   | `mc-linux-r1-weekly`                | `RRULE:FREQ=WEEKLY;BYDAY=TH;BYHOUR=22`| `IfRequired` | `Critical`, `Security`, `Other` (selectivo)      |
| R2   | `mc-linux-r2-biweekly`              | `RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=SA;BYHOUR=22` | `IfRequired` | `Critical`, `Security`, `Other`         |

Duración recomendada: **3h30** (mínimo de AUM es 1h30, máximo 3h55).

## 4. Crear una Maintenance Configuration (CLI)

```bash
LOC="westeurope"
RG="rg-arc-linux-prod"
MC="mc-linux-r0-weekly"

az maintenance configuration create \
  --resource-group $RG \
  --resource-name $MC \
  --location $LOC \
  --maintenance-scope "InGuestPatch" \
  --start-date-time "2026-07-07 22:00" \
  --time-zone "Romance Standard Time" \
  --duration "03:30" \
  --recur-every "1Week Tuesday" \
  --reboot-setting "IfRequired" \
  --extension-properties InGuestPatchMode="User" \
  --linux-parameters package-name-masks-to-exclude="kernel*,grub*" \
                    classifications-to-include="Critical Security"
```

> **Nota:** `kernel*` y `grub*` se excluyen en R0 hasta validar; se quitan
> de la exclusión en R1/R2.

## 5. Asociar máquinas por dynamic scope

```bash
az maintenance assignment create-or-update-dynamic-scope \
  --resource-group $RG \
  --resource-name $MC \
  --name "ds-linux-r0" \
  --subscriptions "<sub-id>" \
  --tags "ring=R0;aum=enabled;os=linux"
```

Equivalente declarativo en Bicep: ver `policy/initiatives/` (a generar).

## 6. Habilitar periodic assessment en cada máquina

Para **Arc-enabled servers** se hace via Azure Policy o por máquina:

```bash
az connectedmachine update \
  --resource-group $RG \
  --name <hostname> \
  --set properties.osProfile.linuxConfiguration.patchSettings.assessmentMode=AutomaticByPlatform \
        properties.osProfile.linuxConfiguration.patchSettings.patchMode=AutomaticByPlatform
```

`patchMode=AutomaticByPlatform` es obligatorio para que AUM gestione el
patching en lugar del agente nativo de la distro.

## 7. Visibilidad

- **Portal**: Update Manager → Update history.
- **Resource Graph**: ver `queries/resource-graph.kql`.
- **Log Analytics**: tabla `PatchAssessmentResources` y `PatchInstallationResources`.

Ejemplo: máquinas con parches críticos pendientes:

```kusto
patchassessmentresources
| where type =~ "microsoft.hybridcompute/machines/patchassessmentresults/softwarepatches"
| where properties.classifications has "Critical"
| where properties.installationState != "Installed"
| summarize pendientes=count() by tostring(properties.osType), tostring(split(id,'/')[8])
```

## 8. Rollback / mitigación

AUM **no** desinstala paquetes. Plan B:
- Mantener snapshots a nivel de disco (Azure Backup para Arc on-prem si aplica, o snapshots de almacenamiento).
- Para RHEL/Rocky/Alma: `dnf history rollback <id>` cuando el rollback es viable.
- Cláusula de exclusión rápida: añadir tag `aum=disabled` y la máquina sale del scope en la siguiente evaluación.

## 9. Coste

AUM **gratis** para máquinas Arc-enabled cuando se usan **MCs** y dynamic
scope. Lo que paga: ingesta en Log Analytics (opcional, ya cubierta por AMA).

## 10. Checklist de adopción

- [ ] Tag `aum=enabled` en máquinas onboarded.
- [ ] Tag `ring=R0|R1|R2` asignado.
- [ ] `patchMode=AutomaticByPlatform` y `assessmentMode=AutomaticByPlatform`.
- [ ] MC `mc-linux-r0-weekly` creada y validada en 2-3 máquinas piloto.
- [ ] Dynamic scope con query por tags.
- [ ] Workbook de seguimiento (ver `queries/`).
- [ ] Runbook de exclusión rápida (`aum=disabled`).
