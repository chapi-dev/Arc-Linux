# Arc-Linux – Deep Dive Azure Arc para Linux

> Repositorio de trabajo para el deep dive interno: llevar la plataforma Linux
> (RHEL / CentOS / templates corporativos) al mismo modelo operativo que ya
> tenemos en Wintel sobre **Azure Arc-enabled Servers**: inventario, updates y
> antivirus gestionados desde Azure.

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
│   ├── 03-update-manager.md           ← Azure Update Manager + anillos
│   ├── 04-defender-vs-trendmicro.md   ← comparativa + plan de onboarding
│   ├── 05-inventory.md                ← Change Tracking + Inventory
│   └── images/                        ← diagramas (a añadir)
├── scripts/
│   ├── lab/
│   │   ├── 01-create-linux-vm.ps1     ← crea VM de lab en Azure
│   │   └── 02-deazure-vm.sh           ← "des-azuriza" la VM (simula on-prem)
│   ├── onboarding/
│   │   ├── 03-create-sp-onboarding.ps1
│   │   └── 04-azcmagent-connect.sh
│   └── extensions/
│       ├── 05-install-ama.ps1
│       └── 06-install-mde-linux.ps1
├── policy/
│   └── initiatives/                   ← Azure Policy JSON
├── queries/
│   ├── inventory.kql
│   └── resource-graph.kql
└── session/
    └── agenda.md                      ← agenda de la sesión 90-120 min
```

---

## 3. Cómo usar este repo

1. Lee `docs/01-architecture.md` para el panorama general.
2. Decide tags y anillos en `docs/02-groups-and-tags.md`.
3. Levanta el lab siguiendo `scripts/lab/*` → `scripts/onboarding/*` → `scripts/extensions/*`.
4. Aplica policies de `policy/initiatives/`.
5. Valida inventario con las queries de `queries/`.
6. Lleva las decisiones abiertas a la sesión: `session/agenda.md`.

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

---

## 6. Estado del trabajo

Ver `plan.md` en el workspace de la sesión o la tabla `todos` del SQLite
operativo. Modo: **autopilot**.
