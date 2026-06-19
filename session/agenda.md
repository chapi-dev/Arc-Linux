# Agenda – Sesión Deep Dive Azure Arc para Linux

**Duración:** 90 – 120 min
**Audiencia:** Plataforma (Wintel + Linux), Seguridad, Operaciones, Patching
**Pre-lectura obligatoria:** `README.md` + `docs/01-architecture.md`
**Pre-lectura recomendada:** `docs/02-groups-and-tags.md`, `docs/04-defender-vs-trendmicro.md` (sección FIM)

---

## 0. Apertura · 5 min
- Recap: por qué pasamos de updates / antivirus / inventario manuales a Arc.
- Recordatorio: en Wintel ya funciona con `AZURE-ARC`, `AZURE-ARC-UPDATE`, `AZURE-ARC-DEFENDER`.
- Objetivo de la sesión: cerrar **decisiones**, no descubrir tecnología.

## 1. Arquitectura objetivo · 10 min
- Diagrama de `docs/01-architecture.md`.
- Componentes: Connected Machine Agent + extensiones (AMA, MDE.Linux, ChangeTracking).
- Endpoints de red obligatorios (`*.his.arc.azure.com`, `management.azure.com`, …).
- ¿Hace falta **Azure Arc Private Link Scope** sobre ExpressRoute? **Decisión pendiente.**

## 2. Grupos AZURE-ARC* y tags · 15 min
- Reuso de los 3 grupos como en Wintel.
- Implementación con **tags + dynamic scope**, no AAD groups.
- Taxonomía obligatoria: `os`, `osFamily`, `env`, `ring`, `criticality`, `owner`, `app`, `mdfc`, `aum`.
- **Decisión:** lista final de tags obligatorios + responsable de cada tag.
- **Decisión:** quién mete las máquinas en `ring=R0` (pilot).

## 3. Update Manager · 20 min
- Sustituye `yum/apt manual` por **AUM** + **Maintenance Configurations** + **dynamic scope**.
- Periodic assessment + `patchMode=AutomaticByPlatform`.
- Anillos R0/R1/R2 con ventanas tipo (ver `docs/03-update-manager.md`).
- Exclusión inicial de `kernel*` y `grub*` en R0.
- **Decisión:** número exacto de anillos y ventanas (cron por anillo).
- **Decisión:** approval gate entre R0 → R1 (manual / automático tras N horas sin alertas).
- **Decisión:** quién es owner de cada anillo.
- **Decisión:** estrategia de rollback (snapshots, `dnf history`, exclusión rápida con `aum=disabled`).

## 4. Defender for Servers + FIM · 25 min
- Comparativa rápida con **Trend Micro** (tabla en `docs/04`).
- Onboarding vía extensión `MDE.Linux` (publisher `Microsoft.Azure.AzureDefenderForServers`).
- **File Integrity Monitoring (FIM)** — bloque dedicado:
  - Generaciones: legacy MMA → AMA-bridge → **MDE nativo (target)**.
  - Paths recomendados (`/etc/sudoers`, `authorized_keys`, `ld.so.preload`, systemd, cron, boot, …).
  - Eventos: hash anterior/nuevo, proceso responsable, cadena padre.
  - Integración: Defender for Cloud → M365 Defender XDR → Sentinel.
- **Decisión:** Defender for Servers **Plan 1 vs Plan 2**. (FIM requiere **Plan 2**.)
- **Decisión:** plan de coexistencia / desinstalación de Trend Micro (4 fases sugeridas en `docs/04`).
- **Decisión:** workspace destino y región para los logs de FIM.
- **Decisión:** lista de paths corporativos custom a incluir en FIM (drivers `/opt/<app>/*`, etc.).

## 5. Inventario · 10 min
- AMA + extensión `ChangeTracking-Linux` + DCR única reutilizable.
- Solapamiento con FIM: **CT&I es Ops/Plataforma, FIM es SecOps** — coexisten, no compiten.
- Workbooks y queries (`queries/inventory.kql`).
- **Decisión:** workspace único o uno por entorno (prod/preprod/lab).
- **Decisión:** ¿exportamos inventario a CMDB? (Logic App, frecuencia).

## 6. Demo / Lab · 15 min
Recorrido rápido por `scripts/`:
1. `lab/01-create-linux-vm.ps1` → VM RHEL 9 en Azure.
2. `lab/02-deazure-vm.sh` → para waagent, deshabilita cloud-init Azure, bloquea IMDS.
3. `onboarding/03-create-sp-onboarding.ps1` → SP con rol mínimo.
4. `onboarding/04-azcmagent-connect.sh` → host se registra como `Microsoft.HybridCompute/machines`.
5. `extensions/05-install-ama.ps1` + `06-install-mde-linux.ps1`.
6. Resource Graph: `queries/resource-graph.kql` muestra la VM con tags.

## 7. Roadmap propuesto · 5 min
| Semana | Hito                                                                 |
|--------|----------------------------------------------------------------------|
| S0     | Aprobación de decisiones de esta sesión                              |
| S1     | Lab end-to-end con 1 RHEL + 1 Ubuntu + 1 Rocky                       |
| S2     | Plan 2 Defender activo en sub piloto + FIM con paths target          |
| S3-S4  | R0 pilot (5-10 hosts reales) con AUM + MDE + FIM                     |
| S5-S8  | R1 preprod, KPIs, ajustes                                            |
| S9-S12 | R2 prod por oleadas + desinstalación de Trend Micro                  |

## 8. Decisiones a cerrar (resumen) · 5 min
1. Arc Private Link Scope: **sí / no**.
2. Defender plan: **P1 / P2** (FIM requiere P2).
3. Anillos: número, ventanas, owner, gates.
4. Workspace LAW: único o multi.
5. Tags obligatorios y dueños.
6. Plan de salida de Trend Micro (fases y métricas Go/No-Go).
7. Paths corporativos a añadir a FIM.

## 9. Q&A · 5 min

---

### Acta automática
Tras la sesión, registrar acuerdos en `session/decisions.md` (a crear) y abrir
un PR en este repo actualizando los docs afectados.
