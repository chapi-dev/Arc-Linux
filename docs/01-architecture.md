# 01 – Arquitectura Azure Arc para Linux

## 1. Componentes

```
┌─────────────────────────────────────────────────────────────────┐
│                         Azure (control plane)                   │
│                                                                 │
│  ┌──────────────┐  ┌─────────────────┐  ┌────────────────────┐  │
│  │ Azure Arc    │  │ Azure Update    │  │ Microsoft Defender │  │
│  │ for Servers  │  │ Manager (AUM)   │  │ for Cloud / MDE    │  │
│  └──────┬───────┘  └────────┬────────┘  └─────────┬──────────┘  │
│         │                   │                     │             │
│  ┌──────┴────────────────── ┴──────── ┌───────────┴──────────┐  │
│  │ Log Analytics Workspace (DCRs)     │ Azure Resource Graph │  │
│  │   + Azure Monitor (AMA)            │ + Azure Policy       │  │
│  └────────────────────────────────────┴──────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
               ▲                                ▲
               │ HTTPS / 443                    │ HTTPS / 443
               │                                │
        ┌──────┴──────────────────────────────────────┐
        │           Servidor Linux (on-prem o Azure   │
        │           "des-azurizado" en lab)           │
        │                                             │
        │  ┌───────────────────────────────────────┐  │
        │  │ Connected Machine Agent (azcmagent)   │  │
        │  │   - himds  (manage identity service)  │  │
        │  │   - gc_arc_service (guest config)     │  │
        │  │   - extension manager                 │  │
        │  └─────────┬─────────────────────────────┘  │
        │            │                                │
        │  ┌─────────┴────────────────────────────┐   │
        │  │ Extensiones                          │   │
        │  │  - AzureMonitorLinuxAgent (AMA)      │   │
        │  │  - MDE.Linux (Defender)              │   │
        │  │  - ChangeTracking-Linux              │   │
        │  │  - CustomScript (puntual)            │   │
        │  └──────────────────────────────────────┘   │
        └─────────────────────────────────────────────┘
```

## 2. Agentes y servicios en el host

| Servicio (systemd)             | Procedencia                | Función                                          |
|--------------------------------|----------------------------|--------------------------------------------------|
| `himds.service`                | Connected Machine Agent    | Identidad gestionada (managed identity) del host |
| `gcad.service`                 | Connected Machine Agent    | Guest Configuration (compliance)                 |
| `extd.service`                 | Connected Machine Agent    | Extension manager                                |
| `azuremonitoragent`            | Extensión AMA              | Telemetría a Log Analytics (DCR)                 |
| `mdatp`                        | Extensión MDE.Linux        | EDR / antivirus Defender for Endpoint            |

> Equivalente Wintel: `himds.exe`, `gc_service.exe`, `gc_arc_service.exe`,
> `MonAgentCore.exe` (AMA), `MsSense.exe` (MDE).

## 3. Distribuciones Linux soportadas

Azure Arc soporta oficialmente (lista no exhaustiva, ver [docs oficiales](https://learn.microsoft.com/azure/azure-arc/servers/prerequisites#supported-operating-systems)):

- **Red Hat Enterprise Linux** 7, 8, 9 (incluido Arm64 en 8/9 para algunas features).
- **CentOS Linux** 7 (EOL — solo modo "best effort"; planear migración).
- **Rocky Linux** 8, 9 y **AlmaLinux** 8, 9 (sustitutos de CentOS).
- **Ubuntu** 18.04, 20.04, 22.04, 24.04.
- **SUSE Linux Enterprise Server** 12 SP5, 15.
- **Oracle Linux** 7, 8, 9.
- **Debian** 10, 11, 12.
- **Amazon Linux** 2, 2023.

Arquitectura: **x86-64** soportada plenamente; **Arm64** parcial. **32-bit no soportado.**

> ⚠️ Para los "templates" corporativos: validar que `systemd`, `openssl`,
> `glibc` y `python3` cumplen los mínimos del agente.

## 4. Requisitos de red (salida HTTPS/443)

El agente necesita resolver y conectar contra estos endpoints (Azure Public Cloud):

| Endpoint                                              | Servicio                                  |
|-------------------------------------------------------|-------------------------------------------|
| `management.azure.com`                                | ARM (control plane)                       |
| `login.microsoftonline.com`                           | Azure AD / Entra ID (auth)                |
| `login.windows.net`                                   | Azure AD (auth alternativo)               |
| `*.his.arc.azure.com`                                 | Hybrid Identity Service                   |
| `*.guestconfiguration.azure.com`                      | Guest Configuration (compliance/policy)   |
| `agentserviceapi.guestconfiguration.azure.com`        | Reporte de extensiones                    |
| `*.servicebus.windows.net`                            | Notificaciones extensiones                |
| `*.blob.core.windows.net`                             | Descarga de binarios de extensión         |
| `pas.windows.net`                                     | SSH / RBAC sobre Arc                      |
| `*.waconazure.com`                                    | Windows Admin Center (si se usa)          |

Alternativas:
- **Azure Arc Private Link Scope** para tráfico privado por ExpressRoute / VPN.
- **HTTP/HTTPS proxy** (`azcmagent config set proxy.url`).

Referencia: [networking requirements](https://learn.microsoft.com/azure/azure-arc/servers/network-requirements).

## 5. RBAC mínimo

| Rol                                       | Asignado a                                  | Para qué                                       |
|-------------------------------------------|---------------------------------------------|------------------------------------------------|
| `Azure Connected Machine Onboarding`      | Service Principal de onboarding             | Registrar nuevos hosts (acción única).         |
| `Azure Connected Machine Resource Administrator` | Equipo de plataforma                | Gestionar recursos `Microsoft.HybridCompute`.  |
| `Monitoring Contributor`                  | Equipo de Ops                               | DCR, AMA, alertas.                             |
| `Security Admin` / `Security Reader`      | Equipo de Seguridad                         | Defender for Cloud.                            |
| `Update Manager Contributor` (custom)     | Equipo de Patching                          | Maintenance configurations, schedules.         |

Principio: **service principal solo para onboarding**, después rota o vence.
Resto vía grupos de Entra ID + PIM.

## 6. Modelo lógico para Linux

```
Subscription
└── Resource Group: rg-arc-linux-{env}
    ├── Connected Machines (Microsoft.HybridCompute/machines)
    │     tags: os=linux, ring=R0|R1|R2, env=prod|preprod|lab,
    │           owner=<team>, mdfc=enabled, app=<service>
    ├── Maintenance Configurations
    │     - mc-linux-r0-weekly-tue-22h
    │     - mc-linux-r1-weekly-thu-22h
    │     - mc-linux-r2-weekly-sat-22h
    ├── Data Collection Rules (DCR)
    │     - dcr-linux-inventory
    │     - dcr-linux-syslog
    └── Log Analytics Workspace: law-arc-linux-{region}
```

## 7. Flujo de onboarding (resumen)

1. Crear **Service Principal** con rol `Azure Connected Machine Onboarding`.
2. Ejecutar en el host `install_linux_azcmagent.sh`.
3. `azcmagent connect --service-principal-id … --tenant-id … --subscription-id … --resource-group … --location … --tags "os=linux,ring=R0,…"`.
4. La máquina aparece en Azure como `Microsoft.HybridCompute/machines`.
5. **Azure Policy** detecta tag `mdfc=enabled` / `ring=*` y dispara
   `DeployIfNotExists` de las extensiones (AMA, MDE.Linux, ChangeTracking).
6. **Maintenance Configuration** con dynamic scope toma la máquina por tags.

Detalle paso a paso: `docs/02-groups-and-tags.md` y scripts de `scripts/`.
