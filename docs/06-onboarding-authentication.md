# 06 – Onboarding authentication: Device Code vs Service Principal

> **Recomendación**: para **lab** y onboarding de **1 host puntual** es
> aceptable usar device code (más rápido).
> Para **producción**, **siempre** Service Principal (SP) con rol mínimo,
> rotación y almacenado en Key Vault.

## 1. Comparativa

| Aspecto                          | Device code (manual)                                  | Service Principal (recomendado en prod) |
|----------------------------------|--------------------------------------------------------|------------------------------------------|
| Necesita humano por VM           | Sí (un código en `microsoft.com/devicelogin`)         | No (no-interactivo)                      |
| Apto para automatización         | ❌                                                     | ✅ (ansible, packer, golden images)       |
| Identidad usada en Activity Log  | Tu usuario (`<OPERATOR>@…`)                            | El SP (`sp-arc-linux-onboarding`)        |
| Privilegio                       | El de tu usuario (Owner / GA en nuestro caso)         | **Mínimo**: `Azure Connected Machine Onboarding` |
| Rotación                         | N/A (depende de tu contraseña)                        | Rotable (`az ad sp credential reset`)    |
| Blast radius si fuga             | **Alto** (privilegios del usuario)                    | **Bajo** (solo onboarding en RG concreto)|
| Escalabilidad                    | 1 humano por host                                     | Miles de hosts sin intervención          |
| Auditoría                        | Sale en logs como acción humana                       | Identidad técnica clara                  |
| Conformidad (Compliance)         | Falla revisiones (cuentas privilegiadas en automation) | Cumple buenas prácticas Zero Trust       |

## 2. Cuándo usar cada uno

| Escenario                                  | Método             |
|--------------------------------------------|--------------------|
| 1 VM de lab, 1 demo, troubleshooting       | Device code        |
| Despliegue masivo (≥ 5 hosts)              | **Service Principal** |
| Pipeline CI/CD (Azure DevOps, GitHub Actions) | **Service Principal** |
| Golden image / cloud-init template         | **Service Principal** |
| Onboarding desde Ansible / SCCM-equiv      | **Service Principal** |
| MSP / multi-tenant                         | **Service Principal** |

## 3. Crear el Service Principal con mínimo privilegio

### 3.1 Opción A — Script ya en el repo

```powershell
cd <REPO_ROOT>
az logout ; az login          # browser interactivo
pwsh -File scripts\deploy\rotate-sp.ps1 -ResourceGroup rg-arc-linux-lab
```

El script:
- Borra el SP previo si existe (rotación limpia).
- Crea `sp-arc-linux-onboarding` con rol **`Azure Connected Machine Onboarding`**
  con scope = `/subscriptions/<sub>/resourceGroups/<rg>` (sólo ese RG).
- Caducidad del secreto: **1 año**.
- Guarda credenciales en `lab\lab.env` (gitignored).

### 3.2 Opción B — Pasos manuales (para entender qué hace)

```bash
# Variables
SUB_ID="<SUBSCRIPTION_ID>"
RG="rg-arc-linux-lab"
SP_NAME="sp-arc-linux-onboarding"

# 1) Crear el SP con rol minimo, scope = RG
az ad sp create-for-rbac \
  --name "$SP_NAME" \
  --role "Azure Connected Machine Onboarding" \
  --scopes "/subscriptions/$SUB_ID/resourceGroups/$RG" \
  --years 1
# OUTPUT (guardar TODO menos password en sitio publico):
# {
#   "appId":       "<APP_ID-GUID>",
#   "displayName": "sp-arc-linux-onboarding",
#   "password":    "<SECRET>           <-- solo se ve una vez",
#   "tenant":      "<TENANT-ID-GUID>"
# }
```

> **Importante:** el `password` solo se muestra **una vez**. Cópialo a Key
> Vault inmediatamente. Si lo pierdes, hay que rotarlo
> (`az ad sp credential reset --id <APP_ID>`).

### 3.3 ¿Qué incluye el rol `Azure Connected Machine Onboarding`?

ID del rol: `b64e21ea-ac4e-4cdf-9dc9-5b892992bee7`

Permisos efectivos:
- `Microsoft.HybridCompute/machines/write` (crear/registrar máquina)
- `Microsoft.HybridCompute/machines/extensions/write` (instalar extensiones)
- `Microsoft.GuestConfiguration/guestConfigurationAssignments/read`
- (y unos pocos `*/read` necesarios)

**No** permite:
- Borrar máquinas Arc (`delete`)
- Modificar nada fuera de Microsoft.HybridCompute / GuestConfiguration
- Crear policies, RBAC, network resources, etc.

Es el **rol más acotado** posible para Arc onboarding.

## 4. Guardado seguro del secret

### 4.1 Key Vault (recomendado)

```bash
KV_NAME="kv-arc-linux-prod"

# (Opcional) crear el KV
az keyvault create -n $KV_NAME -g $RG -l westeurope --enable-rbac-authorization true

# Subir el secreto
az keyvault secret set --vault-name $KV_NAME --name "ArcOnboardingSpSecret" --value "<SECRET>"

# Subir tambien el appId para no ir buscandolo
az keyvault secret set --vault-name $KV_NAME --name "ArcOnboardingSpAppId" --value "<APP_ID>"
```

Acceso desde el host de despliegue (no desde la VM que se onboarda):

```bash
ARC_SP_APP_ID=$(az keyvault secret show --vault-name $KV_NAME --name ArcOnboardingSpAppId --query value -o tsv)
ARC_SP_SECRET=$(az keyvault secret show --vault-name $KV_NAME --name ArcOnboardingSpSecret --query value -o tsv)
```

### 4.2 GitHub Actions / Azure DevOps

- **Federated credentials (OIDC)** sobre el mismo SP: no hay secret guardado en
  ningún sitio, GitHub firma un token JWT que Azure AD intercambia por uno
  válido. Configurar con:
  ```bash
  az ad app federated-credential create --id <APP_ID> --parameters '{
     "name":"github-actions",
     "issuer":"https://token.actions.githubusercontent.com",
     "subject":"repo:<org>/<repo>:ref:refs/heads/main",
     "audiences":["api://AzureADTokenExchange"]
  }'
  ```
- O secret estático en GitHub Encrypted Secrets / ADO Library.

## 5. Usar el SP desde la VM

Una vez tienes `ARC_SP_APP_ID`, `ARC_SP_SECRET`, `ARC_TENANT_ID`:

```bash
# Instalar agente
wget -q https://aka.ms/azcmagent -O /tmp/install_linux_azcmagent.sh
sudo bash /tmp/install_linux_azcmagent.sh

# Conectar con SP (no-interactivo)
sudo azcmagent connect \
  --service-principal-id     "$ARC_SP_APP_ID" \
  --service-principal-secret "$ARC_SP_SECRET" \
  --tenant-id                "$ARC_TENANT_ID" \
  --subscription-id          "$ARC_SUBSCRIPTION_ID" \
  --resource-group           "$ARC_RESOURCE_GROUP" \
  --location                 "$ARC_LOCATION" \
  --cloud                    "AzureCloud" \
  --tags                     "os=linux,osFamily=rhel,env=prod,ring=R0,..."
```

> Esto es exactamente lo que hace `scripts/onboarding/04-azcmagent-connect.sh`.

## 6. Rotación periódica (90 d recomendado)

```bash
# Rota el secret (caduca el anterior, genera nuevo)
az ad sp credential reset --id <APP_ID> --years 1
# Actualiza Key Vault con el nuevo password
```

Política sugerida:
- Cada 90 d rotación automática (Logic App / Function).
- Notificación 15 d antes de expirar.
- Si el SP no se ha usado en 180 d → **dispose**.

## 7. Distintos SP para distintos scopes

Si tienes varios anillos / entornos, mejor 1 SP por entorno con scope acotado:

| SP                              | Scope                                       |
|---------------------------------|---------------------------------------------|
| `sp-arc-linux-onboarding-prod`  | `/subscriptions/<sub-prod>/resourceGroups/rg-arc-linux-prod`  |
| `sp-arc-linux-onboarding-preprod`| `/subscriptions/<sub-preprod>/resourceGroups/rg-arc-linux-preprod`|
| `sp-arc-linux-onboarding-lab`   | `/subscriptions/<sub-dev>/resourceGroups/rg-arc-linux-lab`    |

Así si fuga uno, el blast radius es 1 RG.

## 8. Limpieza

```bash
# Borrar SP completamente (cuando ya no se use)
az ad sp delete --id <APP_ID>
az ad app delete --id <APP_ID>
```

El cleanup `scripts\deploy\cleanup.ps1` lo hace por defecto si pasa
`-KeepServicePrincipal:$false`.

---

## TL;DR

- **Lab**: device code (lo que estás haciendo en `lab-rhel9-01`). 1 VM, 1 click.
- **Prod**: SP con rol `Azure Connected Machine Onboarding`, scope RG, secret en Key Vault, rotación 90 d.
- Script ya listo: `scripts\deploy\rotate-sp.ps1`.
- Script de onboarding con SP ya listo: `scripts\onboarding\04-azcmagent-connect.sh`.
