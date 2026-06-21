# Arc-Linux — Azure Arc para servidores Linux

> Repositorio del **deep dive interno** para llevar la plataforma Linux
> (RHEL / CentOS / templates corporativos) al mismo modelo operativo que ya
> tenemos en Wintel sobre **Azure Arc-enabled Servers**: inventario, updates,
> antivirus y File Integrity Monitoring gestionados desde Azure.
>
> 🏆 **Lab end-to-end ejecutado el 2026-06-21/22 sobre RHEL 9.8.**
> Ver [`session/lab-execution-report.md`](session/lab-execution-report.md)
> para el informe ejecutivo con todas las capturas.

---

## 🧭 Cómo navegar este repo

| Si eres... | Empieza por... |
|---|---|
| **Cliente / decision maker** | [`session/lab-execution-report.md`](session/lab-execution-report.md) — informe ejecutivo con galería de capturas |
| **Operador que ejecuta el lab paso a paso** | [`session/walkthrough.md`](session/walkthrough.md) — guion bloque a bloque |
| **Arquitecto que quiere entender la solución** | [`docs/01-architecture.md`](docs/01-architecture.md) → [`docs/02-groups-and-tags.md`](docs/02-groups-and-tags.md) |
| **SRE que va a replicar en prod** | [`docs/07-lab-lessons-learned.md`](docs/07-lab-lessons-learned.md) primero, luego [`infra/`](infra/) |
| **Equipo de updates** | [`docs/03-update-manager.md`](docs/03-update-manager.md) |
| **Equipo de seguridad** | [`docs/04-defender-vs-trendmicro.md`](docs/04-defender-vs-trendmicro.md) |
| **Equipo de inventario** | [`docs/05-inventory.md`](docs/05-inventory.md) |
| **Equipo de identidades / onboarding masivo** | [`docs/06-onboarding-authentication.md`](docs/06-onboarding-authentication.md) |

---

## 1. Objetivo

| Tema       | Hoy                                | Mañana (con Arc)                                                       |
|------------|------------------------------------|------------------------------------------------------------------------|
| Updates    | Manual, cada X días                | **Azure Update Manager** + anillos + ventanas de mantenimiento         |
| Antivirus  | Trend Micro (agente propio)        | **Microsoft Defender for Servers (MDE.Linux)** vía extensión Arc       |
| FIM        | Sin FIM centralizado               | **File Integrity Monitoring** nativo en Defender for Servers P2 (MDE)  |
| Inventario | Manual, parcial en Azure Arc       | **Change Tracking + Inventory (AMA)** + **Azure Resource Graph**       |
| Grupos     | 3 grupos solo en Wintel            | Mismos 3 grupos extendidos a Linux                                     |

Los **3 grupos** existentes en Wintel se mantienen y se reaprovechan para Linux:

- `AZURE-ARC` → inventario base, agente Arc + AMA.
- `AZURE-ARC-UPDATE` → anillos de actualización (R0 pilot / R1 / R2 prod).
- `AZURE-ARC-DEFENDER` → onboarding de Microsoft Defender for Endpoint **+ File Integrity Monitoring (FIM)**.

La pertenencia a cada grupo se decide por **tags** (`ring=R0|R1|R2`,
`mdfc=enabled`, `os=linux`, …) y se asigna con **dynamic scope** de Azure
Update Manager + Azure Policy (`DeployIfNotExists`).

---

## 2. Estructura del repositorio

```
Arc-Linux/
├── README.md                          ← este archivo
├── docs/
│   ├── 01-architecture.md             ← componentes, agentes, red, RBAC
│   ├── 02-groups-and-tags.md          ← grupos AZURE-ARC*, taxonomía de tags
│   ├── 03-update-manager.md           ← Azure Update Manager + anillos (portal + CLI)
│   ├── 04-defender-vs-trendmicro.md   ← comparativa + plan de onboarding + FIM
│   ├── 05-inventory.md                ← Change Tracking + Inventory
│   ├── 06-onboarding-authentication.md ← Device code vs Service Principal (prod)
│   └── 07-lab-lessons-learned.md      ← Gotchas reales descubiertos en el lab
├── infra/                             ← Bicep (LAW + DCR + Maintenance Configs)
│   ├── README.md
│   ├── main.bicep
│   └── modules/{law,dcr,maintenance}.bicep
├── scripts/
│   ├── deploy/
│   │   ├── deploy.ps1                 ← orquesta RG + Bicep + Policies + SP + dynamic scopes
│   │   ├── rotate-sp.ps1              ← (re)crear SP cuando CAE bloquea
│   │   └── cleanup.ps1                ← borra todo
│   ├── lab/
│   │   ├── 01-create-linux-vm.ps1     ← crea VM de lab en Azure
│   │   ├── 02-deazure-vm.sh           ← "des-azuriza" la VM (simula on-prem)
│   │   └── reopen-ssh.ps1             ← reabre SSH cuando JIT bloquea
│   ├── onboarding/
│   │   ├── 03-create-sp-onboarding.ps1
│   │   ├── 04-azcmagent-connect.sh
│   │   └── 07-set-patchmode-on-arc-machines.ps1
│   ├── extensions/
│   │   ├── 05-install-ama.ps1
│   │   └── 06-install-mde-linux.ps1
│   └── validate/
│       └── 01-validate-fim-events.ps1 ← consulta KQL de eventos FIM en el LAW
├── policy/
│   └── initiatives/                   ← Azure Policy JSON
├── queries/
│   ├── inventory.kql
│   └── resource-graph.kql
└── session/
    ├── agenda.md                      ← agenda de la sesión 90-120 min
    ├── walkthrough.md                 ← guion paso a paso con capturas
    ├── lab-execution-report.md        ← informe ejecutivo del lab end-to-end + galería de capturas
    └── screenshots/                   ← capturas de cada paso + INDEX.md
```

---

## 3. Cómo usar este repo

### Quick-start (replicar el lab)

```powershell
# 1. Clonar y posicionarte
git clone https://github.com/chapi-dev/Arc-Linux.git
cd Arc-Linux

# 2. Desplegar la infra (LAW + DCR + MCs + policies + dynamic scopes)
pwsh -File scripts/deploy/deploy.ps1

# 3. Crear una VM de lab Linux en Azure (RHEL 9 o Ubuntu 22.04)
pwsh -File scripts/lab/01-create-linux-vm.ps1 -Os rhel9

# 4. "Des-azurizar" la VM (simular on-prem)
ssh azureuser@<ip> 'sudo bash -s' < scripts/lab/02-deazure-vm.sh

# 5. Onboarding a Arc (sigue el wizard del portal o usa el SP)
# Ver session/walkthrough.md bloque E.

# 6. Habilitar Defender for Servers Plan 2 + FIM en la sub.
# Ver session/walkthrough.md bloque H.

# 7. Validar todo
pwsh -File scripts/validate/01-validate-fim-events.ps1
```

### Lectura recomendada (orden)

1. `docs/01-architecture.md` — panorama general.
2. `docs/02-groups-and-tags.md` — taxonomía de tags y los 3 grupos.
3. `docs/03-update-manager.md` — Azure Update Manager + anillos (portal **y** CLI).
4. `docs/04-defender-vs-trendmicro.md` — comparativa MDE vs Trend, plan de migración, FIM.
5. `docs/05-inventory.md` — Change Tracking + Inventory + Resource Graph.
6. `docs/06-onboarding-authentication.md` — Device code vs SP para prod.
7. `docs/07-lab-lessons-learned.md` — gotchas descubiertos en el lab real.
8. `session/walkthrough.md` — guion paso a paso para la sesión.
9. `session/lab-execution-report.md` — informe ejecutivo del lab end-to-end con galería completa de capturas (1-pager extendido para responder al correo del cliente).

---

## 4. Pre-requisitos del lab

- Subscription de Azure (ya disponible).
- Permisos: `Owner` o `Contributor` + `User Access Administrator` en el RG del lab.
- Azure CLI ≥ 2.60, PowerShell 7, OpenSSH.
- Distribuciones para probar: **RHEL 9**, **Ubuntu 22.04** (proxy para "CentOS-like"
  ya que CentOS Linux 7 está EOL; usar **Rocky 9** o **AlmaLinux 9** como
  destino realista de migración).

---

## 5. Referencias oficiales

- [Connected Machine agent prerequisites](https://learn.microsoft.com/azure/azure-arc/servers/prerequisites)
- [Connect hybrid machines using a deployment script](https://learn.microsoft.com/azure/azure-arc/servers/onboard-service-principal)
- [Azure Update Manager overview](https://learn.microsoft.com/azure/update-manager/overview)
- [Dynamic scopes for maintenance configurations](https://learn.microsoft.com/azure/update-manager/manage-dynamic-scoping)
- [Microsoft Defender for Servers](https://learn.microsoft.com/azure/defender-for-cloud/plan-defender-for-servers)
- [Onboard Linux servers to MDE via Arc](https://learn.microsoft.com/azure/defender-for-cloud/enable-defender-for-endpoint)
- [Change Tracking and Inventory using AMA](https://learn.microsoft.com/azure/automation/change-tracking/overview-monitoring-agent)
- [Authentication options for Arc onboarding](docs/06-onboarding-authentication.md) (este repo)

---

## 6. Estado del trabajo

| Hito | Estado |
|---|---|
| Fase 1 — Repo + docs | ✅ |
| Fase 2 — Infra Bicep desplegada en `rg-arc-linux-lab` | ✅ |
| Fase 3 — Walkthrough lab con `lab-rhel9-01` (RHEL 9.8) | ✅ |
| Fase 4 — Validación end-to-end (incluye FIM events) | 🟡 día +1 |
| Fase 5 — Repetir flow con `lab-ubuntu22-01` (Ubuntu 22.04) | ⏳ pendiente |

Ver detalle completo en [`session/lab-execution-report.md`](session/lab-execution-report.md).

Modo de trabajo: **autopilot** (sin preguntas entre pasos salvo decisiones de
diseño que cambien dirección).
