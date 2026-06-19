# 05 – Inventario Linux con Change Tracking + Inventory

## 1. Qué resolvemos

Hoy el inventario es **manual**, parcialmente visible "de rebote" porque las
máquinas aparecen en Azure Arc. Queremos:

- **Software instalado** (paquetes RPM/DEB) y versiones.
- **Servicios systemd** en ejecución.
- **Archivos críticos** que cambian (solapado con FIM, pero CT lo agrega).
- **Registry-equivalente** = `/etc` config files relevantes.
- **Daemons / puertos abiertos** (con extensión adicional).
- Todo **consultable por Resource Graph y KQL**, exportable, alertable.

## 2. Componente: Change Tracking & Inventory (CT&I) sobre AMA

| Antes (legacy)                                        | Hoy (recomendado)                                  |
|-------------------------------------------------------|----------------------------------------------------|
| Log Analytics Agent (MMA / OMS) + Automation account | **Azure Monitor Agent (AMA)** + **DCR**            |
| Solution `ChangeTracking` en Log Analytics            | Extensión `ChangeTracking-Linux` en cada máquina   |
| Configuración global en Automation account            | DCR (`Microsoft.Insights/dataCollectionRules`) por scope |

> MMA está **retirado**. Diseñamos directamente sobre AMA + DCR.

## 3. Despliegue por máquina Arc (manual / lab)

```bash
RG="rg-arc-linux-lab"
HOST="lab-rhel9-01"
LOC="westeurope"

# 1) AMA
az connectedmachine extension create \
  --resource-group $RG --machine-name $HOST --location $LOC \
  --name AzureMonitorLinuxAgent \
  --publisher Microsoft.Azure.Monitor \
  --type AzureMonitorLinuxAgent \
  --enable-auto-upgrade true

# 2) ChangeTracking-Linux
az connectedmachine extension create \
  --resource-group $RG --machine-name $HOST --location $LOC \
  --name ChangeTracking-Linux \
  --publisher Microsoft.Azure.ChangeTrackingAndInventory \
  --type ChangeTracking-Linux \
  --enable-auto-upgrade true
```

En producción se hace con **Azure Policy** `DeployIfNotExists` (un policy por
extensión) y un DCR asociado a la suscripción / RG.

## 4. Data Collection Rule (DCR) tipo

`dcr-linux-changetracking` con:

- **DataSources**: extensiones, daemons, archivos, software (packages).
- **Destinations**: `law-arc-linux-{region}`.
- **DataFlows**: a las tablas `ConfigurationChange` y `ConfigurationData`.

Bicep mínimo (esqueleto):

```bicep
resource dcr 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: 'dcr-linux-changetracking'
  location: location
  properties: {
    dataSources: {
      extensions: [
        {
          name: 'CTDataSource'
          extensionName: 'ChangeTracking-Linux'
          streams: [
            'Microsoft-ConfigurationChange'
            'Microsoft-ConfigurationChangeV2'
            'Microsoft-ConfigurationData'
          ]
          extensionSettings: {
            enableFiles: true
            enableSoftware: true
            enableRegistry: false   // no aplica a Linux
            enableServices: true
            enableInventory: true
            fileSettings: {
              fileCollectionFrequency: 900   // segundos
            }
            softwareSettings: {
              softwareCollectionFrequency: 1800
            }
            inventorySettings: {
              inventoryCollectionFrequency: 36000
            }
            servicesSettings: {
              serviceCollectionFrequency: 1800
            }
          }
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: lawId
          name: 'law'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-ConfigurationChange'
          'Microsoft-ConfigurationChangeV2'
          'Microsoft-ConfigurationData'
        ]
        destinations: [ 'law' ]
      }
    ]
  }
}
```

## 5. Consultas útiles

### Paquetes instalados por distro
```kusto
ConfigurationData
| where ConfigDataType == "Software"
| summarize hosts=dcount(Computer) by SoftwareName, CurrentVersion, SoftwareType
| order by hosts desc
```

### Cambios en archivos críticos últimas 24h
```kusto
ConfigurationChange
| where TimeGenerated > ago(24h)
| where ConfigChangeType == "Files"
| where FileSystemPath has_any ("/etc/ssh","/etc/sudoers","/etc/ld.so.preload","/etc/cron")
| project TimeGenerated, Computer, FileSystemPath, ChangeCategory, PreviousValue, NewValue
| order by TimeGenerated desc
```

### Servicios systemd que han cambiado de estado
```kusto
ConfigurationChange
| where ConfigChangeType == "Daemons"
| where SvcChangeType in ("State","Path")
| project TimeGenerated, Computer, SvcName, SvcState, SvcChangeType
| order by TimeGenerated desc
```

### Inventario "snapshot" actual de un host
```kusto
ConfigurationData
| where Computer == "lab-rhel9-01"
| summarize arg_max(TimeGenerated, *) by SoftwareName, ConfigDataType
| order by ConfigDataType, SoftwareName
```

## 6. Azure Resource Graph — vista plataforma

Inventario de **máquinas Arc** + tags + estado de agente, sin ir a LAW:

```kusto
Resources
| where type =~ 'microsoft.hybridcompute/machines'
| extend osType        = tostring(properties.osType),
         osName        = tostring(properties.osName),
         osVersion     = tostring(properties.osVersion),
         agentVersion  = tostring(properties.agentVersion),
         status        = tostring(properties.status),
         lastSeen      = todatetime(properties.lastStatusChange),
         ring          = tostring(tags.ring),
         env           = tostring(tags.env)
| where osType == 'linux'
| project name, resourceGroup, location, osName, osVersion, kernel=tostring(properties.osSku),
          agentVersion, status, lastSeen, ring, env, tags
| order by lastSeen desc
```

Más queries: `queries/resource-graph.kql` y `queries/inventory.kql`.

## 7. Solapamiento Inventory ↔ FIM

| Capacidad                                | CT&I                  | FIM (MDE)              | Decisión               |
|------------------------------------------|-----------------------|------------------------|------------------------|
| Software instalado (RPM/DEB)             | ✅                    | ❌                     | **CT&I**               |
| Servicios systemd                        | ✅                    | parcial                | **CT&I**               |
| Cambios en archivos críticos             | ✅ (con baseline)     | ✅ (con contexto + hash + proceso) | **FIM** (con MDE)  |
| Hash + proceso responsable               | ❌                    | ✅                     | **FIM**                |
| Alertas SOC                              | manual                | nativas en Defender    | **FIM**                |

No es duplicado: **CT&I es para Ops/Plataforma, FIM es para SecOps**.

## 8. Checklist de adopción

- [ ] AMA desplegado vía policy en todas las máquinas Arc.
- [ ] DCR `dcr-linux-changetracking` asociado.
- [ ] Workbook "Linux Inventory" publicado.
- [ ] Workbook "Changes last 7 days" publicado.
- [ ] Alertas KQL: cambios en `/etc/sudoers`, `authorized_keys` y `cron*` fuera de ventana.
- [ ] Export programado (Logic App) a CMDB.
