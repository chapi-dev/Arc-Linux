#!/usr/bin/env bash
#
# 02-deazure-vm.sh
# ----------------
# Convierte una VM Linux que se ejecuta en Azure en una maquina que, desde el
# punto de vista de la red y del agente, parece on-prem. Esto permite probar
# el flujo de onboarding de Azure Arc como si fuera un servidor fisico.
#
# Lo que hace:
#   1) Detiene y desactiva el WALinuxAgent (waagent).
#   2) Desactiva cloud-init para los datasources Azure.
#   3) Bloquea con iptables/nftables el endpoint IMDS 169.254.169.254.
#   4) Limpia el cache de cloud-init.
#   5) Imprime un resumen.
#
# CONSIDERACIONES:
#   - SOLO PARA LAB. No usar en VMs productivas.
#   - Tras este script la VM YA NO SE puede gestionar via Azure VM agent
#     (extensions de Azure VM, reset de password, etc.).
#   - Como esta en Azure, sigue siendo facturada como VM. El truco es solo
#     para simular el path de Arc.
#
# Distribuciones soportadas:
#   - RHEL / Rocky / Alma 8, 9
#   - Ubuntu 20.04, 22.04, 24.04
#   - Debian 11, 12
#
# Uso:
#   sudo bash 02-deazure-vm.sh
#
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root (sudo bash $0)" >&2
    exit 1
fi

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "[$(ts)] $*"; }

log "Starting de-Azure procedure on $(hostname)"

# --- 1) Detectar distro -------------------------------------------------------
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    DISTRO="${ID,,}"
else
    DISTRO="unknown"
fi
log "Detected distro: $DISTRO"

# --- 2) WALinuxAgent (waagent) ------------------------------------------------
log "Stopping and disabling WALinuxAgent (waagent)"
if systemctl list-unit-files | grep -q '^waagent\.service'; then
    systemctl stop waagent || true
    systemctl disable waagent || true
    systemctl mask waagent || true
    log "waagent stopped, disabled and masked"
else
    log "waagent service not present, skipping"
fi

# --- 3) cloud-init Azure datasource ------------------------------------------
log "Disabling cloud-init Azure datasource"
mkdir -p /etc/cloud/cloud.cfg.d
cat > /etc/cloud/cloud.cfg.d/99_disable_azure.cfg <<'EOF'
# Lab override: pretend we are not on Azure
datasource_list: [ NoCloud, None ]
EOF
# tambien neutralizamos el datasource especifico si existe
rm -f /etc/cloud/cloud.cfg.d/90-azure*.cfg 2>/dev/null || true
log "cloud-init Azure datasource disabled"

# limpieza de caches para que el proximo arranque no se reidentifique como Azure
if command -v cloud-init >/dev/null 2>&1; then
    log "Cleaning cloud-init artifacts"
    cloud-init clean --logs || true
fi

# --- 4) Bloquear endpoint IMDS 169.254.169.254 -------------------------------
IMDS=169.254.169.254
log "Blocking access to IMDS $IMDS"
if command -v nft >/dev/null 2>&1; then
    nft add table inet deazure 2>/dev/null || true
    nft 'add chain inet deazure output { type filter hook output priority 0 ; }' 2>/dev/null || true
    nft add rule inet deazure output ip daddr $IMDS drop 2>/dev/null || true
    nft list table inet deazure | sed 's/^/    /'
elif command -v iptables >/dev/null 2>&1; then
    iptables -C OUTPUT -d $IMDS -j DROP 2>/dev/null || iptables -I OUTPUT -d $IMDS -j DROP
    # persistencia best-effort
    if [[ "$DISTRO" =~ ^(rhel|rocky|almalinux|centos|fedora|oracle)$ ]]; then
        if command -v iptables-save >/dev/null 2>&1; then
            iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
        fi
    elif [[ "$DISTRO" =~ ^(ubuntu|debian)$ ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent >/dev/null 2>&1 || true
        netfilter-persistent save 2>/dev/null || true
    fi
    iptables -L OUTPUT -n | grep $IMDS || true
else
    log "WARNING: neither nft nor iptables found; IMDS not blocked"
fi

# --- 5) Marcar la VM ----------------------------------------------------------
mkdir -p /etc/deazure
cat > /etc/deazure/info <<EOF
deazured_at = $(ts)
hostname    = $(hostname)
note        = Lab only. VM still billed as Azure VM, but de-identified for Arc onboarding.
EOF

# --- 6) Resumen --------------------------------------------------------------
log "=== de-Azure complete on $(hostname) ==="
log "Next: run scripts/onboarding/04-azcmagent-connect.sh"
log "If IMDS was reachable before, it should now be unreachable:"
( timeout 3 curl -s -H Metadata:true "http://169.254.169.254/metadata/instance?api-version=2021-02-01" >/dev/null && echo "  IMDS still reachable (unexpected)" ) \
    || echo "  IMDS unreachable (expected)"
