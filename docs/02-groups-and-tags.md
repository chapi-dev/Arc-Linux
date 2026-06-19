# 02 – Grupos AZURE-ARC* y taxonomía de tags

## 1. Filosofía

En Wintel ya tenemos **3 grupos**:

| Grupo                  | Propósito                                  |
|------------------------|--------------------------------------------|
| `AZURE-ARC`            | Inventario "sin más" (todo lo onboarded)   |
| `AZURE-ARC-UPDATE`     | Anillos de update                          |
| `AZURE-ARC-DEFENDER`   | Antivirus / EDR                            |

Decisión: **mantener los mismos nombres para Linux**, pero implementar la
"pertenencia a grupo" con **tags + dynamic scopes**, no con grupos estáticos
de Entra/AD ni AAD groups. Motivo: Azure Update Manager y Azure Policy
trabajan nativamente con **tags** y **resource graph queries**, no con grupos
externos.

## 2. Taxonomía de tags obligatoria

| Tag         | Valores permitidos                                  | Quién lo pone                  |
|-------------|-----------------------------------------------------|--------------------------------|
| `os`        | `linux` \| `windows`                                | Script de onboarding           |
| `osFamily`  | `rhel` \| `centos` \| `rocky` \| `alma` \| `ubuntu` \| `sles` \| `debian` \| `oracle` | Onboarding (autodetect) |
| `env`       | `prod` \| `preprod` \| `dev` \| `lab`               | Onboarding (parámetro)         |
| `ring`      | `R0` \| `R1` \| `R2` \| `none`                      | Onboarding + revisable         |
| `criticality` | `tier1` \| `tier2` \| `tier3`                     | CMDB / owner                   |
| `owner`     | `<team-alias>` (ej. `platform-linux`)               | CMDB / owner                   |
| `app`       | `<service-tag>` (ej. `sap-ecc`)                     | CMDB / owner                   |
| `mdfc`      | `enabled` \| `disabled` \| `exempt`                 | Seguridad                      |
| `aum`       | `enabled` \| `disabled` \| `exempt`                 | Patching                       |

> Cualquier máquina **sin** `ring` cae automáticamente en `none` y queda fuera
> de los schedules — postura segura por defecto.

## 3. Mapeo grupo → criterio (dynamic scope)

### 3.1 `AZURE-ARC`
Todas las máquinas con `Microsoft.HybridCompute/machines` en las
subscripciones objetivo. No hace falta tag; es el universo completo.

Query Resource Graph:
```kusto
Resources
| where type =~ 'microsoft.hybridcompute/machines'
```

### 3.2 `AZURE-ARC-UPDATE`
Máquinas con `aum == 'enabled'` **y** `ring in (R0,R1,R2)`.

```kusto
Resources
| where type =~ 'microsoft.hybridcompute/machines'
| where tags.aum == 'enabled'
| where tags.ring in ('R0','R1','R2')
```

Cada **ring** se asocia a su propia **Maintenance Configuration**:

| Ring | Población típica       | Ventana sugerida (TZ Europe/Madrid)            | Reboot      |
|------|------------------------|------------------------------------------------|-------------|
| R0   | Pilot (≤ 5 % parque)   | Martes 22:00 – 02:00 (semanal)                 | `IfRequired`|
| R1   | Preprod / no-críticos  | Jueves 22:00 – 04:00 (semanal)                 | `IfRequired`|
| R2   | Prod                   | Sábado 22:00 – 06:00 (semanal cada 2 semanas)  | `IfRequired`|

### 3.3 `AZURE-ARC-DEFENDER`
Máquinas con `mdfc == 'enabled'`.

```kusto
Resources
| where type =~ 'microsoft.hybridcompute/machines'
| where tags.mdfc == 'enabled'
```

Sobre estas, una **Azure Policy** `DeployIfNotExists` instala la extensión
`MDE.Linux` (publisher `Microsoft.Azure.AzureDefenderForServers`).

## 4. Cómo se materializa cada grupo

| Grupo                 | Mecanismo Azure                                                                 |
|-----------------------|---------------------------------------------------------------------------------|
| `AZURE-ARC`           | Vista en **Azure Resource Graph Explorer** + Workbook.                          |
| `AZURE-ARC-UPDATE`    | **Maintenance Configuration** + **Dynamic Scope** (tag query) por anillo.       |
| `AZURE-ARC-DEFENDER`  | **Azure Policy** `Configure Linux Arc machines to install MDE.Linux` con scope dinámico por tag. |

## 5. Cambios de anillo (governance)

- Cambiar `ring=R0 → R1` es un **PR en el repo de IaC** que actualiza el tag.
- Se aplica vía `az resource tag` o **Azure Policy** `Inherit a tag from the resource group`.
- Log de cambios queda en Activity Log + Git.

## 6. Tags como contrato

Estos tags pasan a ser **contrato** entre equipos:

- Plataforma garantiza que las máquinas se onboardan **con** todos los tags obligatorios.
- Seguridad consume `mdfc`.
- Operaciones consume `ring` y `aum`.
- FinOps consume `env`, `app`, `criticality`, `owner`.

Auditoría: **Azure Policy** `Require a tag on resources` para cada tag obligatorio.
