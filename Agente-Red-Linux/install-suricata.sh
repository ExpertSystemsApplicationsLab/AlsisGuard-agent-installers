#!/usr/bin/env bash
# =============================================================================
#  install-suricata.sh  -  Instalador SILENCIOSO del Agente de Red (Suricata)
#                          para LINUX/UNIX.
# -----------------------------------------------------------------------------
#  Equivalente Linux del InstaladorAgenteRed.exe de Windows.
#    - Instala Suricata (IDS) y descarga el conjunto de reglas.
#    - Lo configura sobre la interfaz de red indicada (o la de la ruta por defecto).
#    - Deja el eve.json en /var/log/suricata/eve.json.
#    - Engancha la recoleccion al Agente de Monitorizacion (Wazuh) ya instalado,
#      que es quien pertenece al grupo 'unix' y reenvia al manager.
#
#  REQUISITO: el Agente de Monitorizacion (wazuh-agent) debe estar ya instalado
#  (ejecuta antes install-agent.sh).
#
#  USO (como root):
#    ./install-suricata.sh [opciones]
#
#  Opciones:
#    -i, --interface <iface>   Interfaz a monitorizar (def: la de la ruta por defecto)
#    -H, --home-net <cidr>     Red interna, p. ej. "192.168.0.0/16" (def: auto)
#    -s, --suricata-log <ruta> Ruta del eve.json (def: /var/log/suricata/eve.json)
#        --no-wazuh-hook       No tocar la config del agente Wazuh
#    -h, --help                Ayuda
#
#  Variables de entorno equivalentes: IFACE, HOME_NET, SURICATA_LOG.
# =============================================================================

set -euo pipefail

# Instalacion NO interactiva (evita dialogos de apt/needrestart que cuelgan).
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

IFACE="${IFACE:-}"
HOME_NET="${HOME_NET:-}"
SURICATA_LOG="${SURICATA_LOG:-/var/log/suricata/eve.json}"
WAZUH_HOOK=1

SURICATA_YAML="/etc/suricata/suricata.yaml"
OSSEC_CONF="/var/ossec/etc/ossec.conf"

log()  { echo -e "[\e[36m*\e[0m] $*"; }
ok()   { echo -e "[\e[32m+\e[0m] $*"; }
warn() { echo -e "[\e[33m!\e[0m] $*"; }
err()  { echo -e "[\e[31mX\e[0m] $*" >&2; }
usage(){ sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--interface)    IFACE="$2"; shift 2 ;;
        -H|--home-net)     HOME_NET="$2"; shift 2 ;;
        -s|--suricata-log) SURICATA_LOG="$2"; shift 2 ;;
        --no-wazuh-hook)   WAZUH_HOOK=0; shift ;;
        -h|--help)         usage ;;
        *) err "Opcion desconocida: $1"; exit 1 ;;
    esac
done

[[ $EUID -ne 0 ]] && { err "Debe ejecutarse como root (usa sudo)."; exit 1; }

# -------- Interfaz por defecto si no se indica --------
if [[ -z "$IFACE" ]]; then
    IFACE="$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')"
    [[ -z "$IFACE" ]] && { err "No se pudo detectar la interfaz de red. Indica una con -i."; exit 1; }
fi
log "Interfaz a monitorizar: $IFACE"

# -------- HOME_NET automatica si no se indica --------
if [[ -z "$HOME_NET" ]]; then
    HOME_NET="$(ip -o -f inet addr show "$IFACE" 2>/dev/null | awk '{print $4}' | head -n1)"
    [[ -z "$HOME_NET" ]] && HOME_NET="192.168.0.0/16"
fi
log "HOME_NET: $HOME_NET"

# -------- Detectar gestor de paquetes --------
if   command -v apt-get >/dev/null 2>&1; then PKG="apt"
elif command -v dnf     >/dev/null 2>&1; then PKG="dnf"
elif command -v yum     >/dev/null 2>&1; then PKG="yum"
elif command -v zypper  >/dev/null 2>&1; then PKG="zypper"
else err "Distribucion no soportada."; exit 1; fi
log "Gestor de paquetes: $PKG"

# -------- Instalar Suricata --------
log "Instalando Suricata..."
case "$PKG" in
    apt)
        apt-get update -y
        apt-get install -y software-properties-common >/dev/null 2>&1 || true
        add-apt-repository -y ppa:oisf/suricata-stable >/dev/null 2>&1 || warn "PPA de OISF no disponible; se usa el paquete de la distro."
        apt-get update -y
        apt-get install -y suricata jq
        ;;
    dnf)
        dnf install -y epel-release >/dev/null 2>&1 || true
        dnf install -y suricata jq
        ;;
    yum)
        yum install -y epel-release >/dev/null 2>&1 || true
        yum install -y suricata jq
        ;;
    zypper)
        zypper --non-interactive install suricata jq
        ;;
esac
ok "Suricata instalado: $(suricata -V 2>/dev/null | head -n1)"

# -------- Configurar interfaz y HOME_NET --------
if [[ -f "$SURICATA_YAML" ]]; then
    cp -n "$SURICATA_YAML" "${SURICATA_YAML}.bak" 2>/dev/null || true
    # Interfaz en la primera entrada de af-packet
    sed -i "0,/- interface:.*/s//- interface: ${IFACE}/" "$SURICATA_YAML"
    # HOME_NET
    sed -i -E "s#(HOME_NET:\s*).*#\1\"[${HOME_NET}]\"#" "$SURICATA_YAML"
    ok "suricata.yaml configurado (interfaz=$IFACE, HOME_NET=$HOME_NET)."
else
    warn "No se encontro $SURICATA_YAML; revisa la instalacion de Suricata."
fi

# En Debian/Ubuntu, fijar interfaz y modo en /etc/default/suricata
if [[ -f /etc/default/suricata ]]; then
    sed -i "s/^IFACE=.*/IFACE=${IFACE}/" /etc/default/suricata 2>/dev/null || true
    sed -i "s/^LISTENMODE=.*/LISTENMODE=af-packet/" /etc/default/suricata 2>/dev/null || true
fi

# -------- Descargar reglas --------
log "Descargando conjunto de reglas (suricata-update)..."
if command -v suricata-update >/dev/null 2>&1; then
    suricata-update >/dev/null 2>&1 || warn "suricata-update fallo; Suricata usara las reglas por defecto."
    ok "Reglas actualizadas."
else
    warn "suricata-update no disponible; se usan las reglas por defecto."
fi

# -------- Validar y arrancar --------
log "Validando configuracion de Suricata..."
suricata -T -c "$SURICATA_YAML" >/dev/null 2>&1 && ok "Configuracion valida." || warn "La validacion dio avisos; revisa 'suricata -T -c $SURICATA_YAML -v'."

systemctl enable suricata >/dev/null 2>&1 || true
systemctl restart suricata
ok "Servicio Suricata iniciado sobre $IFACE."

# -------- Enganchar la recoleccion al agente Wazuh --------
if [[ $WAZUH_HOOK -eq 1 ]]; then
    if [[ -f "$OSSEC_CONF" ]]; then
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
            systemctl restart wazuh-agent 2>/dev/null || warn "No se pudo reiniciar wazuh-agent."
        else
            log "ossec.conf: Suricata ya presente (no se duplica)."
        fi
    else
        warn "No se encontro el Agente de Monitorizacion ($OSSEC_CONF)."
        warn "Instala primero install-agent.sh; los eventos de Suricata no llegaran al manager sin el."
    fi
fi

echo
ok "Agente de Red (Suricata) instalado y monitorizando ${IFACE}."
echo "  - Log de eventos: ${SURICATA_LOG}"
echo "  - Estado:         systemctl status suricata"
echo "  - Alertas:        jq 'select(.event_type==\"alert\")' ${SURICATA_LOG}"
