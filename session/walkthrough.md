# Walkthrough lab Arc-Linux — Guion paso a paso para capturas

> Fechas de ejecución: 2026-06-21 → 2026-06-22
> Subscription: `<SUBSCRIPTION_NAME>` (`<SUBSCRIPTION_ID>`)
> RG: `rg-arc-linux-lab` (westeurope)
> Tenant: `<TENANT_ID>`
> Operator: <OPERATOR>
>
> **Convención**: cada paso es una captura sugerida. 📸 = lo que enseñar.
>
> 📊 **Para ver el resultado del lab con todas las capturas embebidas**:
> [`lab-execution-report.md`](lab-execution-report.md).

---

## Inventario del lab (ya creado)

| Recurso          | Nombre / Valor                                                                  |
|------------------|---------------------------------------------------------------------------------|
| Resource group   | `rg-arc-linux-lab`                                                              |
| Workspace LAW    | `law-arc-linux-lab`                                                             |
| DCR              | `dcr-arc-linux-lab-syslog`                                                      |
| MC anillo R0     | `mc-arc-linux-lab-r0-weekly` (Tue 22:00, excl. `kernel*` `grub*`)               |
| MC anillo R1     | `mc-arc-linux-lab-r1-weekly` (Thu 22:00)                                        |
| MC anillo R2     | `mc-arc-linux-lab-r2-biweekly` (Sat 22:00 cada 2 sem)                           |
| Dynamic scopes   | `ds-arc-linux-r0` / `r1` / `r2` (filter `ring=Rx + aum=enabled`)                |
| Policy assigns   | `assign-ama-arc-linux`, `assign-mde-arc-linux`, `assign-patchmode-arc-linux`    |
| VM RHEL 9.8      | `lab-rhel9-01` — pública `<RHEL_IP>` — usuario `azureuser`                  |
| VM Ubuntu 22.04  | `lab-ubuntu22-01` — pública `<UBUNTU_IP>` — usuario `azureuser`               |

---

# 🟦 BLOQUE A — Tour de la infra desplegada (portal)

### Paso A1 · Resource group y vista general
**Portal:** [https://portal.azure.com](https://portal.azure.com) → `Resource groups` → `rg-arc-linux-lab` → **Overview**.

📸 La parrilla de recursos con los 7 nombres (LAW, DCR, 3 MCs, 2 VMs) y la columna `Tags`.

### Paso A2 · Log Analytics Workspace
Click en `law-arc-linux-lab` → **Overview** y luego **Settings → Workspace summary**.

📸 Página de Overview con `Pricing tier = Pay-as-you-go`, retention 30 d y cap 5 GB/día.

### Paso A3 · Maintenance Configurations (los 3 anillos)
**Portal → All services → Azure Update Manager → Machines / Maintenance configurations** (o directo: `https://portal.azure.com/#view/Microsoft_Azure_Automation/UpdateCenterMenuBlade/~/maintenanceconfigurations`).
Filtra por subscription y verás los 3 MCs.

📸 Lista de las 3 MCs con su recurrencia (Tuesday, Thursday, Saturday).
📸 Entra a `mc-arc-linux-lab-r0-weekly` → **Properties** → pestaña *Updates* (verás `Critical` + `Security`, exclusión `kernel*`, `grub*`) → pestaña *Dynamic scopes* (verás `ds-arc-linux-r0` con filter `ring=R0 + aum=enabled`).

### Paso A4 · Azure Policy assignments
**Portal → Policy → Compliance** filtrando por scope `rg-arc-linux-lab`.

📸 Listado con `assign-ama-arc-linux`, `assign-mde-arc-linux`, `assign-patchmode-arc-linux`.
📸 Click en `assign-ama-arc-linux` → **Assigned identities** muestra la MI generada y su rol asignado en el RG.

---

# 🟩 BLOQUE B — Las VMs Linux (Azure VM tradicional)
## 3 minutos · 2 capturas

### Paso B1 · Las 2 VMs en el RG
**Portal → `rg-arc-linux-lab` → Virtual machines** o desde `Resource groups`.

📸 Listado con `lab-rhel9-01` y `lab-ubuntu22-01`, ambas `Running`.

### Paso B2 · Verifica SSH desde tu máquina
Abre PowerShell o tu terminal local:

```powershell
ssh azureuser@<RHEL_IP>    # RHEL
# Esperado: PRETTY_NAME="Red Hat Enterprise Linux 9.8 (Plow)"

ssh azureuser@<UBUNTU_IP>    # Ubuntu
# Esperado: PRETTY_NAME="Ubuntu 22.04.5 LTS"
```

📸 Terminal con ambos prompts confirmando hostname + distro.

---

# 🟧 BLOQUE C — Crear el Service Principal de onboarding
## 2 minutos · 1 captura

> ⚠️ **Solo necesario para producción / despliegues masivos.** Para 1-2 VMs de
> lab puedes saltarte este bloque y usar **device code** desde el portal
> (Azure Arc → Machines → Add → **Authenticate machines manually**).
>
> Ver justificación completa en [`docs/06-onboarding-authentication.md`](../docs/06-onboarding-authentication.md):
> comparativa, rotación, Key Vault, federated credentials.

> El SP falló al crearse automáticamente por CAE del tenant. Tienes que
> refrescar tu sesión.

### Paso C1 · Refresca tu login y rota el SP

En **PowerShell local** (en la carpeta del repo):

```powershell
cd <REPO_ROOT>
az logout
az login                                                            # abre browser → completa login
pwsh -File scripts\deploy\rotate-sp.ps1 -ResourceGroup rg-arc-linux-lab
```

Esperado: imprime `OK Service Principal listo` con `appId` y guarda
credenciales en `lab\lab.env`.

📸 Salida con `appId` (no captures el secret).

---

# 🟥 BLOQUE D — "De-azurizar" la VM RHEL
## 5 minutos · 2 capturas

> Aquí simulamos que la VM es on-prem para que Arc la trate como tal.

### Paso D0 · Foto del "antes" (estado VM Azure pura)

Conéctate y ejecuta los 3 comandos:
```bash
ssh azureuser@<RHEL_IP>
# Una vez dentro:
hostnamectl
sudo systemctl status waagent --no-pager | head -5
curl -s -H Metadata:true "http://169.254.169.254/metadata/instance?api-version=2021-02-01" | head -c 300 ; echo
```

Lo esperado **ahora** (antes del de-azure):
- `hostnamectl` → `Virtualization: microsoft`, `Hardware Vendor: Microsoft Corporation`, `Firmware: Hyper-V UEFI`.
- `waagent` → `active (running)`.
- `curl IMDS` → JSON con metadatos de la VM.

📸 Capturas: `D0a-rhel-hostnamectl-before.png` ✅, `D0b-rhel-waagent-before.png`, `D0c-rhel-imds-before.png`.

### Paso D1 · Copia el script y ejecútalo

```powershell
cd <REPO_ROOT>
scp scripts\lab\02-deazure-vm.sh azureuser@<RHEL_IP>:~
ssh azureuser@<RHEL_IP> 'sudo bash ~/02-deazure-vm.sh'
```

Lo que hace:
- Para y deshabilita `waagent`.
- Neutraliza cloud-init Azure datasource.
- Bloquea con `nft/iptables` el endpoint IMDS `169.254.169.254`.
- Marca la VM en `/etc/deazure/info`.

📸 Salida final con `=== de-Azure complete on lab-rhel9-01 ===` y la línea
   `IMDS unreachable (expected)`.

### Paso D2 · (Opcional) Verifica que ya no responde IMDS
```powershell
ssh azureuser@<RHEL_IP> 'curl -s -m 3 -H Metadata:true http://169.254.169.254/metadata/instance?api-version=2021-02-01 ; echo "exit=$?"'
```

📸 Resultado con timeout / exit no-cero, confirmando IMDS bloqueado.

---

# 🟪 BLOQUE E — Onboarding de la RHEL en Azure Arc
## 5 minutos · 3 capturas

### Paso E1 · Carga las credenciales del SP en la VM

> 💡 **Para producción usar siempre SP** con rol mínimo (ver
> `docs/06-onboarding-authentication.md`). Para el lab puedes saltarte el SP
> y usar **device code** desde el wizard del portal
> (**Azure Arc → Machines → Add → Authenticate machines manually**).

```powershell
# Sube tu archivo lab.env (creado en bloque C) a la VM
scp lab\lab.env azureuser@<RHEL_IP>:~/lab.env
```

### Paso E2 · Conecta el host a Arc

Copia el script de onboarding y ejecútalo:
```powershell
scp scripts\onboarding\04-azcmagent-connect.sh azureuser@<RHEL_IP>:~
ssh azureuser@<RHEL_IP>
# Ya dentro de la VM:
source ~/lab.env
sudo -E bash ~/04-azcmagent-connect.sh
```

Lo que hace:
- Descarga e instala el `azcmagent` (`Connected Machine Agent`).
- Hace `azcmagent connect` con tu SP, sub, RG, location y los tags
  `os=linux, osFamily=rhel, env=lab, ring=R0, owner=platform-linux,
  app=none, mdfc=enabled, aum=enabled, criticality=tier3`.

📸 La salida con `azcmagent show` mostrando `Agent Status: Connected`.

### Paso E3 · Ver el host en Azure Arc (portal)

**Portal → Azure Arc → Machines** (o
`https://portal.azure.com/#view/Microsoft_Azure_HybridCompute/AzureArcCenterBlade/~/overview`).

📸 La VM `lab-rhel9-01` aparece como **Connected** con tipo de recurso
`Microsoft.HybridCompute/machines`.

📸 Click en la VM → **Overview**: muestra IP del agente, OS, kernel, agentVersion, todos los tags.

---

# 🟦 BLOQUE F — Policies disparan las extensiones
## 10–15 minutos de espera · 3 capturas

Las **Azure Policies** `DeployIfNotExists` evalúan el RG cada ~10–15 min y
deberían instalar solas las extensiones AMA y MDE.Linux.

### Paso F1 · Forzar evaluación
Para no esperar:

```powershell
az policy state trigger-scan --resource-group rg-arc-linux-lab --no-wait
```

### Paso F2 · Comprobar compliance
**Portal → Policy → Compliance** → escoge `assign-ama-arc-linux`.

📸 Estado de la VM: pasará de **Non-compliant** a **Compliant** cuando
la extensión esté desplegada (5–15 min).

### Paso F3 · Listar extensiones en la VM Arc
```powershell
az connectedmachine extension list -g rg-arc-linux-lab --machine-name lab-rhel9-01 -o table
```

📸 Debe aparecer `AzureMonitorLinuxAgent` con `provisioningState=Succeeded`.

> **MDE.Linux** sólo se instala si **Defender for Servers Plan 1/2** está
> activo en la sub. Si no lo está, la policy queda *Non-compliant* — es lo
> esperado hasta el bloque H.

---

# 🟩 BLOQUE G — Aplicar `patchMode=AutomaticByPlatform`
## 2-3 minutos · 1-2 capturas

### G1 · Vía portal (recomendado para 1-pocos hosts) ⭐

1. Portal → busca arriba **"Azure Update Manager"**.
2. Menú izquierdo: **Manage → Machines**.
3. Filtra `Subscription = <SUBSCRIPTION_NAME>`, `Resource group = rg-arc-linux-lab`.
4. Marca la checkbox de `lab-rhel9-01`.
5. Botón **Update settings** (arriba).
6. En el panel:
   - **Periodic assessment** → **Enable**.
   - **Patch orchestration** → **Customer Managed Schedules**.
7. **Save**. Tras 10-30 s ya aparece configurada.

📸 `G1a-portal-aum-update-settings.png` (el panel Change update settings).
📸 `G1b-portal-aum-machine-configured.png` (lista mostrando "Customer Managed Schedules").

### G2 · Vía script (alternativa para masa)

Si tienes muchas máquinas (o quieres automatizarlo en pipeline / golden image):

```powershell
pwsh -File scripts\onboarding\07-set-patchmode-on-arc-machines.ps1 -ResourceGroup rg-arc-linux-lab
```

Recorre todas las Arc Linux con `aum=enabled` y aplica los modos. Idempotente.

📸 `G2-patchmode-script-output.png` (tabla final del script).

---

# 🟧 BLOQUE H — (Opcional pero recomendado) Defender Plan 2 + FIM
## 5 minutos · 3 capturas

> **Cuidado**: esto activa facturación (~$15/host/mes en la sub).

### Paso H1 · Habilitar Plan 2 a nivel sub
**Portal → Microsoft Defender for Cloud → Environment settings → tu suscripción → Defender plans → Servers → Settings**.

Cambia a **Plan 2** y guarda.

📸 La pantalla con Plan 2 activo y los componentes (Endpoint protection, FIM, VA, etc.) en **On**.

### Paso H2 · Activar FIM
En la misma página de Servers Plan 2 → componente **File Integrity
Monitoring** → click **Edit configuration** → selecciona el workspace
`law-arc-linux-lab` → revisa la lista de paths recomendados (puedes añadir
los `/opt/<app>/conf` corporativos).

📸 Pantalla de configuración FIM con workspace asociado.

### Paso H3 · Comprobar MDE.Linux desplegada
Tras 5-10 min:
```powershell
az connectedmachine extension list -g rg-arc-linux-lab --machine-name lab-rhel9-01 -o table
ssh azureuser@<RHEL_IP> 'sudo mdatp health --field real_time_protection_enabled'
```

📸 Salida con `MDE.Linux` provisioning Succeeded y `mdatp health` = `true`.

---

# 🟪 BLOQUE I — Repetir con Ubuntu (para mostrar multi-distro)
## 10 minutos · 2 capturas

Repite los bloques D y E con la VM Ubuntu, cambiando IP y opcionalmente el
tag de anillo (`ARC_TAG_RING=R1`) para ver que el dynamic scope correcto la
recoge.

```powershell
scp scripts\lab\02-deazure-vm.sh azureuser@<UBUNTU_IP>:~
ssh azureuser@<UBUNTU_IP> 'sudo bash ~/02-deazure-vm.sh'

scp lab\lab.env scripts\onboarding\04-azcmagent-connect.sh azureuser@<UBUNTU_IP>:~
ssh azureuser@<UBUNTU_IP>
source ~/lab.env
export ARC_TAG_RING=R1                       # opcional: pone Ubuntu en anillo R1
sudo -E bash ~/04-azcmagent-connect.sh
```

📸 Portal → Azure Arc → Machines: ahora dos hosts, uno por distro.
📸 Maintenance Configuration R1 → Dynamic scope `ds-arc-linux-r1`:
   pestaña *Machines* muestra `lab-ubuntu22-01` evaluada como dentro de
   scope.

---

# 🟦 BLOQUE J — Vistas finales / Resource Graph
## 5 minutos · 3 capturas

**Portal → Azure Resource Graph Explorer**

### Paso J1 · Inventario completo
Pega esto:
```kusto
Resources
| where type =~ 'microsoft.hybridcompute/machines'
| extend osType=tostring(properties.osType),
         osName=tostring(properties.osName),
         agent=tostring(properties.agentVersion),
         status=tostring(properties.status),
         ring=tostring(tags.ring),
         mdfc=tostring(tags.mdfc),
         aum=tostring(tags.aum)
| project name, resourceGroup, osType, osName, agent, status, ring, mdfc, aum
| order by name asc
```

📸 La tabla con tus 2 hosts Arc, sus tags y estado.

### Paso J2 · Extensiones desplegadas por los policies
```kusto
Resources
| where type =~ 'microsoft.hybridcompute/machines/extensions'
| extend machine = tostring(split(id, '/')[8]),
         extType = tostring(properties.type),
         state = tostring(properties.provisioningState)
| project machine, extType, state, publisher=tostring(properties.publisher)
| order by machine, extType
```

📸 Filas con `AzureMonitorLinuxAgent` (y `MDE.Linux` si activaste H).

### Paso J3 · Drift: máquinas Linux sin AMA
Útil para mostrar la query que detecta lagunas:
```kusto
Resources
| where type =~ 'microsoft.hybridcompute/machines'
| where tostring(properties.osType) =~ 'linux'
| project machineId=id, name
| join kind=leftouter (
    Resources
    | where type =~ 'microsoft.hybridcompute/machines/extensions'
    | where tostring(properties.type) == 'AzureMonitorLinuxAgent'
    | extend machineId = strcat_array(array_slice(split(id,'/'),0,8), '/')
    | project machineId, hasAMA=true
) on machineId
| where isnull(hasAMA)
| project name
```

📸 Resultado vacío (significa que la policy ya las cubrió todas).

---

# 🟥 BLOQUE K — Cleanup al terminar
## 1 minuto

Para no dejar coste corriendo:
```powershell
pwsh -File scripts\deploy\cleanup.ps1 -ResourceGroup rg-arc-linux-lab -Confirm:$true
```

Esto borra: policy assignments + policy defs + SP + RG entero (LAW, DCR, MCs, dynamic scopes, VMs, NSGs).

---

## Checklist final de capturas (24 fotos sugeridas)

- [ ] A1 RG overview
- [ ] A2 LAW overview
- [ ] A3a Lista de Maintenance Configurations
- [ ] A3b MC R0 + dynamic scope ds-arc-linux-r0
- [ ] A4a Lista de policy assignments
- [ ] A4b Detalle assign-ama-arc-linux + MI
- [ ] B1 Lista de VMs running
- [ ] B2 Terminal `ssh hostname` ambas distros
- [ ] C1 Salida rotate-sp.ps1 con appId
- [ ] D1 Salida 02-deazure-vm.sh RHEL
- [ ] D2 curl IMDS bloqueado
- [ ] E2 azcmagent show Connected
- [ ] E3a Azure Arc → Machines listing
- [ ] E3b Detalle de lab-rhel9-01 (overview con tags)
- [ ] F2 Compliance state
- [ ] F3 Extensiones listadas en CLI
- [ ] G   Tabla final patchMode
- [ ] H1 Defender Plan 2 activo
- [ ] H2 Configuración FIM
- [ ] H3 MDE.Linux Succeeded + mdatp health
- [ ] I1 Portal con 2 hosts Arc
- [ ] I2 ds-arc-linux-r1 con Ubuntu dentro
- [ ] J1 Resource Graph inventario
- [ ] J2 Resource Graph extensiones
