#!/usr/bin/env python3
# =============================================================================
# firewall-unblock.py  -  Active Response de Wazuh para AGENTES LINUX
# -----------------------------------------------------------------------------
# Equivalente Linux de netsh-unblock.py (Windows). DESBLOQUEA una IP borrando la
# regla DROP de iptables/ip6tables creada por firewall-block.py, es decir, levanta
# un baneo antes de que expire. Pensado para invocarse BAJO DEMANDA desde el
# manager / tu panel (API PUT /active-response), pasandole la IP.
#
# De donde saca la IP a desbloquear (en este orden):
#   1. parameters.extra_args[0]      <- lo que envia el panel por la API
#   2. parameters.alert.data.srcip   <- por si viene en la alerta
#
# Escribe el log en formato JSON (decodificable por el manager) para que el
# desbloqueo aparezca como alerta en el dashboard.
#
# Debe estar en:  /var/ossec/active-response/bin/firewall-unblock.py
#   (con permiso de ejecucion, propietario root:wazuh)
# =============================================================================

import sys
import json
import subprocess
from datetime import datetime

LOG_FILE = "/var/ossec/logs/active-responses.log"
PROGRAM = "active-response/bin/firewall-unblock.py"


def write_log(line):
    ts = datetime.now().strftime("%Y/%m/%d %H:%M:%S")
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(f"{ts} {line}\n")
    except Exception:
        pass


def get_ip(msg):
    params = msg.get("parameters", {})
    # 1) argumento pasado por la API
    args = params.get("extra_args") or []
    if args:
        return str(args[0]).strip()
    # 2) srcip de la alerta
    return params.get("alert", {}).get("data", {}).get("srcip")


def is_ipv6(ip):
    return ":" in ip


def unblock(ip):
    """Borra TODAS las reglas DROP para esa IP (por si hay duplicadas)."""
    tool = "ip6tables" if is_ipv6(ip) else "iptables"
    removed = 0
    # iptables -D falla cuando ya no queda ninguna regla que coincida.
    for _ in range(20):
        r = subprocess.run(
            [tool, "-D", "INPUT", "-s", ip, "-j", "DROP"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if r.returncode != 0:
            break
        removed += 1
    return removed


def emit_json(msg, ip):
    params = msg.setdefault("parameters", {})
    alert = params.setdefault("alert", {})
    data = alert.setdefault("data", {})
    data["srcip"] = ip
    params["program"] = PROGRAM
    write_log(f"{PROGRAM}: {json.dumps(msg, ensure_ascii=False)}")


def main():
    raw = sys.stdin.readline()
    try:
        msg = json.loads(raw)
    except Exception as e:
        write_log(f"{PROGRAM}: ERROR parseando JSON: {e}")
        sys.exit(1)

    command = msg.get("command", "")
    ip = get_ip(msg)

    if not ip:
        write_log(f"{PROGRAM}: no se indico IP a desbloquear")
        sys.exit(0)

    # En invocacion bajo demanda por API, Wazuh manda command="add".
    # Aceptamos add o delete: en ambos casos el objetivo es LEVANTAR el baneo.
    if command in ("add", "delete"):
        n = unblock(ip)
        write_log(f"{PROGRAM}: IP desbloqueada manualmente: {ip} (reglas borradas: {n})")
        emit_json(msg, ip)

    sys.exit(0)


if __name__ == "__main__":
    main()
