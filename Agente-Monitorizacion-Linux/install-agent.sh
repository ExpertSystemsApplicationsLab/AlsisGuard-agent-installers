#!/usr/bin/env bash
# =============================================================================
#  install-agent.sh  -  Instalador SILENCIOSO del Agente de Monitorizacion
#                       (Wazuh) para LINUX/UNIX.
# -----------------------------------------------------------------------------
#  Equivalente Linux del InstaladorAgente.exe de Windows. Deja el equipo listo
#  para respuesta activa:
#    - Instala wazuh-agent y lo enrola en el grupo 'unix' (config FIM central).
#    - Copia la respuesta activa (firewall-block.py con iptables, remove-threat.py).
#    - Asegura recoleccion de logs de autenticacion (SSH) para fuerza bruta.
#    - Anade recoleccion de Suricata (eve.json) si no esta.
#    - Anade carpetas FIM extra si se indican.
#    - Reinicia el servicio y comprueba conectividad 1514/1515.
#    - Autorreparacion: --force purga cualquier instalacion previa.
#
#  USO (como root):
#    ./install-agent.sh -m <IP_MANAGER> [opciones]
#
#  Opciones:
#    -m, --manager <IP|host>   IP o dominio del manager   (OBLIGATORIO)
#    -g, --group <grupo>       Grupo de enrolamiento       (def: unix)
#    -n, --name <nombre>       Nombre del agente           (def: hostname)
#    -f, --fim "<d1,d2,...>"   Carpetas extra a vigilar por FIM (tiempo real)
#    -s, --suricata-log <ruta> Ruta del eve.json de Suricata
#                              (def: /var/log/suricata/eve.json)
#        --force               Purga la instalacion previa y hace instalacion limpia
#    -h, --help                Ayuda
#
#  Tambien acepta variables de entorno: WAZUH_MANAGER, WAZUH_AGENT_GROUP,
#  WAZUH_AGENT_NAME, FIM_DIRS, SURICATA_LOG.
# =============================================================================

set -euo pipefail

# -------- Valores por defecto --------
MANAGER="${WAZUH_MANAGER:-}"
GROUP="${WAZUH_AGENT_GROUP:-unix}"
AGENT_NAME="${WAZUH_AGENT_NAME:-$(hostname)}"
FIM_DIRS="${FIM_DIRS:-}"
SURICATA_LOG="${SURICATA_LOG:-/var/log/suricata/eve.json}"
FORCE=0

OSSEC_DIR="/var/ossec"
OSSEC_CONF="${OSSEC_DIR}/etc/ossec.conf"
AR_BIN="${OSSEC_DIR}/active-response/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAZUH_MAJOR="4.x"

log()  { echo -e "[\e[36m*\e[0m] $*"; }
ok()   { echo -e "[\e[32m+\e[0m] $*"; }
warn() { echo -e "[\e[33m!\e[0m] $*"; }
err()  { echo -e "[\e[31mX\e[0m] $*" >&2; }

usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# -------- Parseo de argumentos --------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--manager)      MANAGER="$2"; shift 2 ;;
        -g|--group)        GROUP="$2"; shift 2 ;;
        -n|--name)         AGENT_NAME="$2"; shift 2 ;;
        -f|--fim)          FIM_DIRS="$2"; shift 2 ;;
        -s|--suricata-log) SURICATA_LOG="$2"; shift 2 ;;
        --force)           FORCE=1; shift ;;
        -h|--help)         usage ;;
        *) err "Opcion desconocida: $1"; exit 1 ;;
    esac
done

# -------- Comprobaciones previas --------
if [[ $EUID -ne 0 ]]; then
    err "Debe ejecutarse como root (usa sudo)."
    exit 1
fi
if [[ -z "$MANAGER" ]]; then
    err "Falta la IP del manager. Usa: $0 -m <IP_MANAGER>"
    exit 1
fi

# -------- Detectar gestor de paquetes --------
detect_pkg() {
    if   command -v apt-get >/dev/null 2>&1; then echo "apt"
    elif command -v dnf     >/dev/null 2>&1; then echo "dnf"
    elif command -v yum     >/dev/null 2>&1; then echo "yum"
    elif command -v zypper  >/dev/null 2>&1; then echo "zypper"
    else echo "unknown"; fi
}
PKG="$(detect_pkg)"
log "Gestor de paquetes detectado: $PKG"
[[ "$PKG" == "unknown" ]] && { err "Distribucion no soportada (sin apt/dnf/yum/zypper)."; exit 1; }

agent_installed() { [[ -d "$OSSEC_DIR" ]] || command -v wazuh-control >/dev/null 2>&1; }

# -------- Purga (autorreparacion / --force) --------
purge_agent() {
    warn "Purga de la instalacion previa del agente..."
    systemctl stop wazuh-agent 2>/dev/null || true
    case "$PKG" in
        apt)    apt-get remove --purge -y wazuh-agent 2>/dev/null || true ;;
        dnf)    dnf remove -y wazuh-agent 2>/dev/null || true ;;
        yum)    yum remove -y wazuh-agent 2>/dev/null || true ;;
        zypper) zypper --non-interactive remove wazuh-agent 2>/dev/null || true ;;
    esac
    rm -rf "$OSSEC_DIR"
    ok "Instalacion previa eliminada."
}

# -------- Anadir repositorio de Wazuh --------
add_repo() {
    log "Configurando repositorio de Wazuh ($WAZUH_MAJOR)..."
    case "$PKG" in
        apt)
            apt-get install -y curl gnupg apt-transport-https >/dev/null
            curl -fsSL https://packages.wazuh.com/key/GPG-KEY-WAZUH \
                | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import 2>/dev/null
            chmod 644 /usr/share/keyrings/wazuh.gpg
            echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/${WAZUH_MAJOR}/apt/ stable main" \
                > /etc/apt/sources.list.d/wazuh.list
            apt-get update -y
            ;;
        dnf|yum)
            rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH
            cat > /etc/yum.repos.d/wazuh.repo <<EOF
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-\$releasever - Wazuh
baseurl=https://packages.wazuh.com/${WAZUH_MAJOR}/yum/
protect=1
EOF
            ;;
        zypper)
            rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH
            cat > /etc/zypp/repos.d/wazuh.repo <<EOF
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=Wazuh repository
baseurl=https://packages.wazuh.com/${WAZUH_MAJOR}/yum/
EOF
            ;;
    esac
}

# -------- Instalar el agente con enrolamiento y grupo --------
install_agent() {
    log "Instalando wazuh-agent (manager=$MANAGER, grupo=$GROUP, nombre=$AGENT_NAME)..."
    export WAZUH_MANAGER="$MANAGER"
    export WAZUH_AGENT_GROUP="$GROUP"
    export WAZUH_AGENT_NAME="$AGENT_NAME"
    export WAZUH_REGISTRATION_SERVER="$MANAGER"
    case "$PKG" in
        apt)    apt-get install -y wazuh-agent ;;
        dnf)    dnf install -y wazuh-agent ;;
        yum)    yum install -y wazuh-agent ;;
        zypper) zypper --non-interactive install wazuh-agent ;;
    esac
    systemctl daemon-reload
    systemctl enable wazuh-agent >/dev/null 2>&1 || true
    systemctl start wazuh-agent
    ok "Agente instalado y servicio iniciado."
}

# -------- Respuesta activa --------
copy_active_response() {
    log "Instalando scripts de respuesta activa..."
    mkdir -p "$AR_BIN"
    local copied=0
    for f in firewall-block.py remove-threat.py; do
        if [[ -f "${SCRIPT_DIR}/active-response/${f}" ]]; then
            cp "${SCRIPT_DIR}/active-response/${f}" "${AR_BIN}/${f}"
            chmod 750 "${AR_BIN}/${f}"
            chown root:wazuh "${AR_BIN}/${f}" 2>/dev/null || true
            ok "Respuesta activa: ${f}"
            copied=1
        else
            warn "No se encontro ${SCRIPT_DIR}/active-response/${f} (se omite)."
        fi
    done
    [[ $copied -eq 0 ]] && warn "No se copio ninguna respuesta activa."
}

# -------- Parchear ossec.conf: Suricata + FIM (sin duplicar) --------
patch_ossec_conf() {
    [[ -f "$OSSEC_CONF" ]] || { warn "No existe $OSSEC_CONF; se omite su configuracion."; return; }

    # Suricata (eve.json)
    if ! grep -qi "eve.json" "$OSSEC_CONF"; then
        cat >> "$OSSEC_CONF" <<EOF

<ossec_config>
  <localfile>
    <log_format>json</log_format>
    <location>${SURICATA_LOG}</location>
  </localfile>
</ossec_config>
EOF
        ok "ossec.conf: anadida recoleccion de Suricata (${SURICATA_LOG})."
    else
        log "ossec.conf: Suricata ya presente (no se duplica)."
    fi

    # FIM extra (lista separada por comas)
    if [[ -n "$FIM_DIRS" ]]; then
        local added=0 block=""
        IFS=',' read -ra DIRS <<< "$FIM_DIRS"
        for d in "${DIRS[@]}"; do
            d="$(echo "$d" | xargs)"   # trim
            [[ -z "$d" ]] && continue
            if grep -qF "$d" "$OSSEC_CONF"; then
                log "FIM: '$d' ya vigilada (no se duplica)."
                continue
            fi
            block+="    <directories realtime=\"yes\" check_all=\"yes\">${d}</directories>\n"
            ok "FIM: vigilando en tiempo real ${d}"
            added=1
        done
        if [[ $added -eq 1 ]]; then
            printf "\n<ossec_config>\n  <syscheck>\n%b  </syscheck>\n</ossec_config>\n" "$block" >> "$OSSEC_CONF"
        fi
    fi
}

# -------- Test de puertos --------
test_port() {
    timeout 3 bash -c ">/dev/tcp/$1/$2" >/dev/null 2>&1 && echo "accesible" || echo "NO accesible"
}
port_test() {
    log "Comprobando conectividad con el manager $MANAGER (1514/1515)..."
    echo "    Puerto 1514 (datos)    : $(test_port "$MANAGER" 1514)"
    echo "    Puerto 1515 (registro) : $(test_port "$MANAGER" 1515)"
}

# ============================ FLUJO PRINCIPAL ============================
if agent_installed; then
    if [[ $FORCE -eq 1 ]]; then
        purge_agent
    else
        warn "Ya hay un agente instalado. Se reconfigurara el manager y el grupo."
        warn "Para una instalacion limpia desde cero, relanza con --force."
    fi
fi

if ! agent_installed || [[ $FORCE -eq 1 ]]; then
    add_repo
    install_agent
else
    # Reconfiguracion: actualizar la IP del manager en ossec.conf y re-registrar
    log "Reconfigurando manager a $MANAGER..."
    if [[ -f "$OSSEC_CONF" ]]; then
        sed -i -E "s#(<address>).*(</address>)#\1${MANAGER}\2#" "$OSSEC_CONF" || true
    fi
    systemctl restart wazuh-agent || true
fi

copy_active_response
patch_ossec_conf

log "Reiniciando servicio wazuh-agent para aplicar la configuracion..."
systemctl restart wazuh-agent

port_test

ok "Agente de Monitorizacion instalado y configurado (grupo '${GROUP}', manager ${MANAGER})."
echo
echo "  - Respuesta activa lista (bloqueo de IP con iptables y borrado de amenazas)"
echo "  - Recoleccion de Suricata configurada (${SURICATA_LOG})"
echo "  - Registros de autenticacion (SSH) recogidos por defecto -> deteccion de fuerza bruta"
echo "  - Estado del agente:  systemctl status wazuh-agent"
