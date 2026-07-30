#!/usr/bin/env bash
# =============================================================================
#  install-manager.sh  -  Instala/configura el MANAGER de Wazuh (AlsisGuard)
#                         en Ubuntu, de forma automatica.
# -----------------------------------------------------------------------------
#  Que hace:
#    1) Si Wazuh no esta instalado, ejecuta el instalador oficial "all-in-one"
#       (manager + indexer + dashboard) de Wazuh.
#    2) Aplica el ossec.conf y el local_rules.xml de AlsisGuard (los ficheros
#       que hay JUNTO a este script), haciendo copia de seguridad de los previos.
#    3) (Opcional) Anade tu IP de administracion a la lista blanca de respuesta
#       activa, para no auto-bloquearte del SSH.
#    4) Valida la configuracion y reinicia el manager.
#
#  USO (como root, en el servidor Ubuntu):
#    ./install-manager.sh [--admin-ip <IP>] [--vt-api-key <KEY>] [--skip-install]
#
#  Opciones:
#    --admin-ip <IP>     Anade <white_list>IP</white_list> a la respuesta activa
#                        (p. ej. tu IP de administracion, para no auto-bloquearte).
#    --vt-api-key <KEY>  Inyecta tu API key de VirusTotal en el ossec.conf
#                        (asi la clave NO viaja en el repositorio).
#    --skip-install      No instala Wazuh; solo aplica la configuracion.
#    -h, --help          Ayuda.
#
#  NOTA: las IPs propias del manager se anaden AUTOMATICAMENTE a la lista blanca,
#  de modo que la respuesta activa nunca pueda bloquear al propio servidor.
# =============================================================================

set -euo pipefail

# Instalacion NO interactiva (evita dialogos de apt/needrestart que cuelgan);
# el instalador oficial de Wazuh hereda estas variables.
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

ADMIN_IP=""
VT_API_KEY=""
SKIP_INSTALL=0

WAZUH_INSTALL_URL="https://packages.wazuh.com/4.x/wazuh-install.sh"
OSSEC_DIR="/var/ossec"
OSSEC_CONF="${OSSEC_DIR}/etc/ossec.conf"
RULES_FILE="${OSSEC_DIR}/etc/rules/local_rules.xml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { echo -e "[\e[36m*\e[0m] $*"; }
ok()   { echo -e "[\e[32m+\e[0m] $*"; }
warn() { echo -e "[\e[33m!\e[0m] $*"; }
err()  { echo -e "[\e[31mX\e[0m] $*" >&2; }
usage(){ sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --admin-ip)     ADMIN_IP="$2"; shift 2 ;;
        --vt-api-key)   VT_API_KEY="$2"; shift 2 ;;
        --skip-install) SKIP_INSTALL=1; shift ;;
        -h|--help)      usage ;;
        *) err "Opcion desconocida: $1"; exit 1 ;;
    esac
done

[[ $EUID -ne 0 ]] && { err "Debe ejecutarse como root."; exit 1; }

# Comprobar que los ficheros de configuracion estan junto al script
for f in ossec.conf local_rules.xml; do
    [[ -f "${SCRIPT_DIR}/${f}" ]] || { err "Falta ${SCRIPT_DIR}/${f}"; exit 1; }
done

manager_installed() { [[ -f "${OSSEC_DIR}/bin/wazuh-control" ]]; }

# -------- 1) Instalar Wazuh (all-in-one) si no esta --------
if manager_installed; then
    ok "Wazuh ya esta instalado; se aplicara solo la configuracion."
elif [[ $SKIP_INSTALL -eq 1 ]]; then
    err "Wazuh no esta instalado y se indico --skip-install. Aborto."
    exit 1
else
    log "Descargando el instalador oficial de Wazuh (all-in-one)..."
    tmp="$(mktemp -d)"
    curl -fsSL "$WAZUH_INSTALL_URL" -o "${tmp}/wazuh-install.sh"
    log "Instalando Wazuh (manager + indexer + dashboard). Puede tardar varios minutos..."
    # -a: all-in-one   -i: ignora el chequeo de hardware (util en VPS de 4 GB)
    bash "${tmp}/wazuh-install.sh" -a -i
    ok "Wazuh instalado."
    warn "Guarda las credenciales del dashboard que ha mostrado el instalador."
fi

# -------- 2) Aplicar configuracion de AlsisGuard --------
ts="$(date +%Y%m%d-%H%M%S)"
if [[ -f "$OSSEC_CONF" ]]; then
    cp -a "$OSSEC_CONF" "${OSSEC_CONF}.bak.${ts}"
    ok "Copia de seguridad: ${OSSEC_CONF}.bak.${ts}"
fi
if [[ -f "$RULES_FILE" ]]; then
    cp -a "$RULES_FILE" "${RULES_FILE}.bak.${ts}"
    ok "Copia de seguridad: ${RULES_FILE}.bak.${ts}"
fi

mkdir -p "$(dirname "$RULES_FILE")"
install -m 0660 "${SCRIPT_DIR}/ossec.conf"      "$OSSEC_CONF"
install -m 0660 "${SCRIPT_DIR}/local_rules.xml" "$RULES_FILE"
chown wazuh:wazuh "$OSSEC_CONF" "$RULES_FILE" 2>/dev/null || true
ok "Configuracion de AlsisGuard aplicada."

# -------- 3) Inyectar API key de VirusTotal (opcional) --------
if [[ -n "$VT_API_KEY" ]]; then
    sed -i "s#<api_key>[^<]*</api_key>#<api_key>${VT_API_KEY}</api_key>#" "$OSSEC_CONF"
    ok "API key de VirusTotal inyectada."
elif grep -q "PON_AQUI_TU_API_KEY_DE_VIRUSTOTAL" "$OSSEC_CONF"; then
    warn "La API key de VirusTotal es un placeholder. Pásala con --vt-api-key <KEY>"
    warn "o edítala en ${OSSEC_CONF} (integración VirusTotal)."
fi

# -------- 4) Lista blanca: nunca bloquear al propio manager ni al admin --------
# Anade una IP a la lista blanca de respuesta activa (idempotente).
add_whitelist() {
    local ip="$1"
    [[ -z "$ip" || "$ip" == "127.0.0.1" ]] && return
    grep -q "<white_list>${ip}</white_list>" "$OSSEC_CONF" && return
    sed -i "s#\(<white_list>127.0.0.53</white_list>\)#\1\n    <white_list>${ip}</white_list>#" "$OSSEC_CONF"
    ok "Lista blanca (no bloquear): ${ip}"
}

log "Protegiendo las IPs del propio manager (no se podran bloquear)..."
# Todas las IPs locales del servidor
for ip in $(hostname -I 2>/dev/null); do add_whitelist "$ip"; done
# IP de la interfaz de salida por defecto
def_ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
add_whitelist "$def_ip"
# IP de administracion indicada
add_whitelist "$ADMIN_IP"

# -------- 4) Validar y reiniciar --------
log "Validando la configuracion..."
if "${OSSEC_DIR}/bin/wazuh-analysisd" -t; then
    ok "Configuracion valida."
else
    err "La validacion fallo. Se restauran las copias de seguridad."
    [[ -f "${OSSEC_CONF}.bak.${ts}" ]]  && cp -a "${OSSEC_CONF}.bak.${ts}"  "$OSSEC_CONF"
    [[ -f "${RULES_FILE}.bak.${ts}" ]]  && cp -a "${RULES_FILE}.bak.${ts}"  "$RULES_FILE"
    err "Revisa los mensajes de arriba. No se reinicio el manager."
    exit 1
fi

log "Reiniciando el manager de Wazuh..."
systemctl restart wazuh-manager

ok "Manager de Wazuh configurado y reiniciado."
echo
echo "  - Estado:   systemctl status wazuh-manager"
echo "  - Alertas:  tail -f ${OSSEC_DIR}/logs/alerts/alerts.json"
echo "  - Copias:   ${OSSEC_CONF}.bak.${ts} / ${RULES_FILE}.bak.${ts}"
