# 04 – Microsoft Defender for Servers (Linux) vs Trend Micro

## 1. TL;DR

| Capacidad                            | Trend Micro Deep Security / Apex One Server | Microsoft Defender for Servers P2 (MDE.Linux) |
|--------------------------------------|---------------------------------------------|------------------------------------------------|
| Antimalware on-access (real-time)    | Sí                                          | Sí (MDE EDR)                                   |
| EDR / behavioural detection          | Sí (limitado en Linux)                      | **Sí (MDE Linux EDR full)**                    |
| Web protection / network IPS         | Sí (IPS, módulo aparte)                     | Sí (Web Content Filtering, Network Protection) |
| **File Integrity Monitoring (FIM)**  | Sí (módulo Integrity Monitoring de DSM)     | **Sí — nativo en MDE, integrado en Defender for Cloud** |
| Vulnerability assessment             | Sí (módulo aparte, licenciado)              | **Sí — incluido (MDVM)**                       |
| Onboarding centralizado en Arc       | No nativo                                   | **Sí (extensión `MDE.Linux`)**                 |
| Integración con XDR / Sentinel       | Conector limitado                           | **Nativo (M365 Defender XDR + Sentinel)**      |
| Coste                                | Licencia por agente + módulos               | Plan 2: ~$15/srv/mes — todo incluido           |

> **Recomendación de partida**: piloto con **Defender for Servers Plan 2** en
> el anillo R0, convivencia controlada con Trend Micro durante 30-60 días,
> medir falsos positivos y rendimiento, y luego sustitución por host.

## 2. Planes Defender for Servers

| Plan   | Incluye                                                                 | Pensado para                       |
|--------|-------------------------------------------------------------------------|------------------------------------|
| Plan 1 | MDE for Servers (antimalware + EDR), licencia por host                  | Sólo EDR, sin FIM ni VA            |
| **Plan 2** | Todo lo de P1 + **FIM**, **MDVM**, **just-in-time VM access**, **adaptive app controls**, **regulatory compliance**, 500 MB de ingesta gratuita a Log Analytics por host/día | **Nuestro caso** |

Plan 2 se habilita a nivel de **suscripción** en
**Defender for Cloud → Environment settings → Plans → Servers**.

## 3. Onboarding de MDE.Linux vía Arc

Defender for Cloud, una vez habilitado Plan 1 o 2, instala automáticamente la
extensión `MDE.Linux` (publisher `Microsoft.Azure.AzureDefenderForServers`,
type `MDE.Linux`) en las máquinas Arc que tengan la integración activada.

### Manual (lab):
```bash
RG="rg-arc-linux-lab"
HOST="lab-rhel9-01"
LOC="westeurope"

az connectedmachine extension create \
  --resource-group $RG \
  --machine-name $HOST \
  --name "MDE.Linux" \
  --publisher "Microsoft.Azure.AzureDefenderForServers" \
  --type "MDE.Linux" \
  --location $LOC \
  --enable-auto-upgrade true \
  --settings '{"azureResourceId":"/subscriptions/<sub>/resourceGroups/'"$RG"'/providers/Microsoft.HybridCompute/machines/'"$HOST"'","forceReOnboarding":false,"vNextEnabled":"true"}'
```

### Verificación en el host:
```bash
mdatp health                    # estado del agente
mdatp health --field real_time_protection_enabled
mdatp health --field definitions_updated
mdatp threat list               # amenazas detectadas
```

### Distros soportadas por MDE.Linux (resumen)
RHEL 7.2+, 8.x, 9.x · CentOS 7.2+ · Rocky / Alma 8, 9 · Ubuntu 18.04 / 20.04 /
22.04 / 24.04 · SLES 12 SP5, 15 · Oracle Linux 7.2+, 8, 9 · Debian 10, 11, 12 ·
Amazon Linux 2, 2023 · Fedora 33-37.

> ⚠️ **CentOS 7 EOL** desde junio 2024. MDE sigue funcionando pero sin parches
> de SO — alinear con la migración a Rocky/Alma del doc de Update Manager.

## 4. File Integrity Monitoring (FIM) — sección estrella

### 4.1 ¿Qué es?

FIM monitoriza **cambios** (create, modify, delete, rename, attribute change)
en **archivos y directorios críticos** del sistema y alerta cuando ocurren
fuera de procesos legítimos. Es un control compensatorio clave para:

- **PCI-DSS req. 11.5** — monitorización de integridad de archivos.
- **HIPAA, ISO 27001 A.12.4, NIST 800-53 SI-7**.
- Detección temprana de **persistencia** de atacantes (cron, systemd, ld.so.preload).
- Auditoría de **shadow IT** y cambios fuera de pipeline.

### 4.2 Implementaciones — IMPORTANTE: hay dos generaciones

| Generación        | Agente                                | Estado                                                                |
|-------------------|----------------------------------------|-----------------------------------------------------------------------|
| **Legacy**        | Microsoft Monitoring Agent (MMA / OMS) | **Deprecated**. Retirado con la deprecación de MMA en Defender for Cloud |
| **Intermedio**    | Azure Monitor Agent (AMA)             | Modo puente, **siendo retirado** a favor de la versión nativa MDE     |
| **Actual / target** | **Microsoft Defender for Endpoint (MDE.Linux)** | **Recomendado** — FIM corre dentro del propio motor MDE          |

> 🟢 **Diseñar directamente sobre la versión MDE.** Evita el path AMA-only de
> FIM (que Microsoft está retirando) y unifica antivirus + EDR + FIM en **un
> único agente** = `mdatp`.

### 4.3 Habilitar FIM (MDE based) en Defender for Cloud

1. Portal → **Defender for Cloud** → **Environment settings** → selecciona la
   suscripción → **Defender plans**.
2. En **Servers** plan 2, abre **Settings**.
3. Componente **File Integrity Monitoring** → **On**.
4. Configura el **Log Analytics workspace** de destino (ingesta del audit log
   FIM, los primeros 500 MB/host/día gratis con P2).
5. Define la **Workspace configuration** (qué paths se monitorizan).

### 4.4 Paths recomendados para Linux

| Categoría             | Path                                                   | Por qué                                                 |
|-----------------------|--------------------------------------------------------|----------------------------------------------------------|
| Binarios del sistema  | `/bin`, `/sbin`, `/usr/bin`, `/usr/sbin`, `/usr/local/bin`, `/usr/local/sbin` | Cambios sin paquete = sospechoso              |
| Librerías             | `/lib`, `/lib64`, `/usr/lib`, `/usr/lib64`             | Hijacking de librerías compartidas                       |
| Cargador dinámico     | `/etc/ld.so.preload`, `/etc/ld.so.conf`, `/etc/ld.so.conf.d/*` | Vector clásico de persistencia (rootkits)        |
| Configuración OS      | `/etc/passwd`, `/etc/shadow`, `/etc/group`, `/etc/sudoers`, `/etc/sudoers.d/*` | Privilege escalation                       |
| SSH                   | `/etc/ssh/sshd_config`, `/root/.ssh/authorized_keys`, `/home/*/.ssh/authorized_keys` | Backdoor accounts                        |
| systemd / cron        | `/etc/systemd/system/*`, `/etc/cron.*`, `/var/spool/cron/*`, `/etc/crontab` | Persistencia                                |
| Boot                  | `/boot`, `/boot/grub2`, `/etc/default/grub`            | Bootkit                                                  |
| Hooks de paquetería   | `/etc/yum.repos.d/*`, `/etc/apt/sources.list.d/*`      | Cadena de suministro                                     |
| Custom corporativo    | `/opt/<app>/conf`, `/etc/<app>/*`                      | Compliance del negocio                                   |

> **No** monitorizar `/var/log/*`, `/tmp`, `/proc`, `/sys`, `/dev`: cambian
> permanentemente y generan ruido + coste de ingesta.

### 4.5 ¿Qué información captura cada evento FIM?

- Timestamp UTC, hostname, agente.
- Path completo, tipo de cambio (`Create | Modify | Delete | Rename`).
- Hash anterior / nuevo (SHA-256).
- Tamaño, owner, permisos antes/después.
- Proceso responsable (pid, exe, command line, user).
- Cadena de proceso padre (útil para distinguir `dnf` vs ataque manual).

### 4.6 Consulta KQL de eventos FIM

```kusto
// Cambios en archivos críticos en las últimas 24h, agrupados por host y path
MDEFileIntegrityEvents       // tabla cuando FIM corre sobre MDE
| where TimeGenerated > ago(24h)
| where FileName in~ ('passwd','shadow','sudoers','authorized_keys','sshd_config')
   or FolderPath has_any ('/etc/ld.so.preload','/etc/systemd/system','/etc/cron')
| summarize cambios=count(), procesos=make_set(InitiatingProcessFileName), ultimos=max(TimeGenerated)
            by DeviceName, FolderPath, FileName, ActionType
| order by cambios desc
```

> Si tu workspace aún usa la versión AMA, la tabla equivalente es
> `ConfigurationChange` (tipo `Files`) y `ConfigurationData`. Migrar a MDE.

### 4.7 Alertas

Defender for Cloud genera alertas tipo:
- *Suspicious modification to a SSH authorized keys file.*
- *Modification of system file outside package manager context.*
- *Changes to bootloader files detected.*

Severidad y reglas configurables en **Defender for Cloud → Security alerts**.
Integrar con **Sentinel** (`SecurityAlert` table) y/o crear **automation
rules** que abran ticket en ServiceNow / Jira.

### 4.8 Convivencia con Trend Micro Integrity Monitoring

Durante la transición:
- **Coexistir** Trend IM + Defender FIM **es seguro** (son lectores, no
  bloqueantes), pero duplica ruido.
- Recomendación: **silenciar reglas de IM en Trend** para los paths que
  asume Defender FIM, comparar 2-3 semanas, decidir.

## 5. Exclusiones / compatibilidad

| Componente               | Exclusiones típicas en Linux                                          |
|--------------------------|------------------------------------------------------------------------|
| Antimalware on-access    | DB engines (Oracle datafiles, PostgreSQL `base/`, MariaDB datadir)    |
| Antimalware              | Volúmenes NFS de backup masivos                                       |
| FIM                      | Logs de aplicación que rotan rápido                                   |

Configurar `mdatp exclusion` para AV y la **workspace configuration** para FIM.

## 6. Performance

Datos públicos de MS en RHEL/Ubuntu modernos:
- CPU steady-state: < 3 % en cargas típicas.
- RAM: 200–400 MB residentes.
- Impacto en I/O secuencial: < 5 % con exclusiones bien hechas.

> ⚠️ En hosts con **bases de datos** o **journaling intensivo**, validar con
> `mdatp diagnostic real-time-protection-statistics` antes y después.

## 7. Convivencia / sustitución de Trend Micro

| Fase | Duración | Acción                                                                                          |
|------|----------|------------------------------------------------------------------------------------------------|
| 0    | 1 sem    | Lab: 1 RHEL + 1 Ubuntu con MDE + FIM activos, Trend desinstalado                                |
| 1    | 2 sem    | R0 pilot (5 hosts) con MDE+FIM, Trend en modo "monitor only"                                    |
| 2    | 4 sem    | R1 preprod con ambos productos. Comparar tickets / FPs / consumo                                |
| 3    | 1 sem    | Decisión Go/No-Go (KPIs en `session/agenda.md`)                                                 |
| 4    | 4-6 sem  | Despliegue progresivo a R2 prod + **desinstalación de Trend** ring por ring                     |

## 8. Checklist de adopción

- [ ] Plan 2 habilitado en la subscription objetivo.
- [ ] Tag `mdfc=enabled` en máquinas objetivo.
- [ ] Azure Policy `DeployIfNotExists` para extensión MDE.Linux.
- [ ] **FIM (versión MDE)** activado y workspace asociado.
- [ ] Lista de paths corporativos custom revisada y añadida.
- [ ] Exclusiones de AV para DB / NFS revisadas.
- [ ] Conector Sentinel `Defender for Cloud` activo.
- [ ] Plan de desinstalación de Trend documentado.
