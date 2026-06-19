#!/usr/bin/env bash
#
# 04-azcmagent-connect.sh
# -----------------------
# Instala el Connected Machine Agent (azcmagent) y conecta el host a Azure Arc
# usando un Service Principal con rol "Azure Connected Machine Onboarding".
#
# REQUIERE estas variables exportadas (las imprime 03-create-sp-onboarding.ps1):
#   ARC_TENANT_ID
#   ARC_SUBSCRIPTION_ID
#   ARC_RESOURCE_GROUP
#   ARC_LOCATION              (ej. westeurope)
#   ARC_SP_APP_ID
#   ARC_SP_SECRET
#
# Tags opcionales (puedes sobreescribir):
#   ARC_TAG_ENV=lab
#   ARC_TAG_RING=R0
#   ARC_TAG_OWNER=platform-linux
#   ARC_TAG_APP=none
#   ARC_TAG_MDFC=enabled
#   ARC_TAG_AUM=enabled
#   ARC_TAG_CRITICALITY=tier3
#
# Uso:
#   sudo -E bash 04-azcmagent-connect.sh
#
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root with sudo -E (to preserve env vars)" >&2
    exit 1
fi

req() {
    if [[ -z "${!1:-}" ]]; then
        echo "Missing required env var: $1" >&2
        exit 1
    fi
}
for v in ARC_TENANT_ID ARC_SUBSCRIPTION_ID ARC_RESOURCE_GROUP ARC_LOCATION ARC_SP_APP_ID ARC_SP_SECRET; do
    req "$v"
done

ARC_TAG_ENV="${ARC_TAG_ENV:-lab}"
ARC_TAG_RING="${ARC_TAG_RING:-R0}"
ARC_TAG_OWNER="${ARC_TAG_OWNER:-platform-linux}"
ARC_TAG_APP="${ARC_TAG_APP:-none}"
ARC_TAG_MDFC="${ARC_TAG_MDFC:-enabled}"
ARC_TAG_AUM="${ARC_TAG_AUM:-enabled}"
ARC_TAG_CRITICALITY="${ARC_TAG_CRITICALITY:-tier3}"

# Detectar osFamily para tag
. /etc/os-release
case "${ID,,}" in
    rhel)         OSF=rhel ;;
    centos)       OSF=centos ;;
    rocky)        OSF=rocky ;;
    almalinux)    OSF=alma ;;
    ubuntu)       OSF=ubuntu ;;
    debian)       OSF=debian ;;
    sles)         OSF=sles ;;
    opensuse*)    OSF=sles ;;
    ol|oraclelinux) OSF=oracle ;;
    *)            OSF=unknown ;;
esac
echo "Detected osFamily: $OSF"

# 1) Instalar agente
if ! command -v azcmagent >/dev/null 2>&1; then
    echo "Installing Connected Machine agent..."
    # Script oficial Microsoft, descarga e instala paquete adecuado
    wget -q https://aka.ms/azcmagent -O /tmp/install_linux_azcmagent.sh
    bash /tmp/install_linux_azcmagent.sh
fi

azcmagent version

# 2) Connect
TAGS="os=linux,osFamily=$OSF,env=$ARC_TAG_ENV,ring=$ARC_TAG_RING,owner=$ARC_TAG_OWNER,app=$ARC_TAG_APP,mdfc=$ARC_TAG_MDFC,aum=$ARC_TAG_AUM,criticality=$ARC_TAG_CRITICALITY,managedBy=arc-linux-repo"

echo "Connecting to Azure Arc..."
azcmagent connect \
    --service-principal-id "$ARC_SP_APP_ID" \
    --service-principal-secret "$ARC_SP_SECRET" \
    --tenant-id "$ARC_TENANT_ID" \
    --subscription-id "$ARC_SUBSCRIPTION_ID" \
    --resource-group "$ARC_RESOURCE_GROUP" \
    --location "$ARC_LOCATION" \
    --cloud "AzureCloud" \
    --tags "$TAGS"

echo ""
echo "=== Agent status ==="
azcmagent show
echo ""
echo "Resource path in Azure:"
echo "  /subscriptions/$ARC_SUBSCRIPTION_ID/resourceGroups/$ARC_RESOURCE_GROUP/providers/Microsoft.HybridCompute/machines/$(hostname)"
echo ""
echo "Next: install extensions from scripts/extensions/"
