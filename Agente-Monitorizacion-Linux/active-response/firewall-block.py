#!/usr/bin/env python3
# =============================================================================
# firewall-block.py  -  Active Response de Wazuh para AGENTES LINUX
# -----------------------------------------------------------------------------
# Equivalente Linux de netsh-block.py (Windows). Bloquea/desbloquea en el
# firewall (iptables) la IP de un ataque de fuerza bruta, leyendo la IP de
# data.srcip (o data.win.eventdata.ipAddress).
#
# Ademas escribe en active-responses.log una linea en el MISMO formato JSON que
# usan los active-response de serie de Wazuh, inyectando data.srcip, para que el
# manager la decodifique y el bloqueo aparezca como alerta buscable.
#
# Debe estar en:  /var/ossec/active-response/bin/firewall-block.py
#   (con permiso de ejecucion, propietario root:wazuh)
# =============================================================================

import sys
import json
import subprocess
from datetime import datetime

LOG_FILE = "/var/ossec/logs/active-responses.log"
PROGRAM = "active-response/bin/firewall-block.py"

# IPs que nunca se deben bloquear
WHITELIST = {"127.0.0.1", "::1", "-"}


def write_log(line):
    ts = datetime.now().strftime("%Y/%m/%d %H:%M:%S")
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(f"{ts} {line}\n")
    except Exception:
        pass


def get_ip(alert):
    data = alert.get("data", {})
    return (
        data.get("srcip")
        or data.get("win", {}).get("eventdata", {}).get("ipAddress")
    )


def is_ipv6(ip):
    return ":" in ip


def emit_json(msg, ip, action):
    """Escribe la linea en formato JSON que el manager decodifica como alerta."""
    params = msg.setdefault("parameters", {})
    alert = params.setdefault("alert", {})
    data = alert.setdefault("data", {})
    data["srcip"] = ip
    params["program"] = PROGRAM
    msg["command"] = action
    write_log(f"{PROGRAM}: {json.dumps(msg, ensure_ascii=False)}")


def run_fw(action_flag, ip):
    """action_flag: '-I' para bloquear, '-D' para desbloquear."""
    tool = "ip6tables" if is_ipv6(ip) else "iptables"
    subprocess.run(
        [tool, action_flag, "INPUT", "-s", ip, "-j", "DROP"],
        check=False,
    )


def main():
    raw = sys.stdin.readline()
    try:
        msg = json.loads(raw)
    except Exception as e:
        write_log(f"{PROGRAM}: ERROR parseando JSON: {e}")
        sys.exit(1)

    command = msg.get("command", "")
    alert = msg.get("parameters", {}).get("alert", {})
    ip = get_ip(alert)

    if not ip or ip in WHITELIST:
        write_log(f"{PROGRAM}: IP no valida o en whitelist: {ip}")
        sys.exit(0)

    if command == "add":
        run_fw("-I", ip)
        emit_json(msg, ip, "add")
    elif command == "delete":
        run_fw("-D", ip)
        emit_json(msg, ip, "delete")

    sys.exit(0)


if __name__ == "__main__":
    main()
