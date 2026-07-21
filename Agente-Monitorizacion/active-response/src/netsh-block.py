# =============================================================================
# netsh-block.py  -  Active Response de Wazuh para AGENTES WINDOWS  (v2)
# -----------------------------------------------------------------------------
# Bloquea/desbloquea en el firewall de Windows la IP de un ataque de fuerza
# bruta (logon fallido), leyendo la IP de data.win.eventdata.ipAddress.
#
# NOVEDAD v2: además de bloquear, escribe en active-responses.log una línea en
# el MISMO formato JSON que usan los active-response de serie de Wazuh, e inyecta
# el campo data.srcip. Así el manager la decodifica (decoder ar_log_json) y el
# bloqueo aparece como ALERTA buscable/filtrable en el dashboard.
#
# Compilar a .exe:
#   pip install pyinstaller
#   pyinstaller --onefile netsh-block.py
#   -> copiar dist\netsh-block.exe a:
#      C:\Program Files (x86)\ossec-agent\active-response\bin\netsh-block.exe
# =============================================================================

import sys
import json
import subprocess
from datetime import datetime

LOG_FILE = r"C:\Program Files (x86)\ossec-agent\active-response\active-responses.log"
PROGRAM = "active-response/bin/netsh-block.exe"

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


def emit_json(msg, ip, action):
    """Escribe la línea en formato JSON que el manager decodifica como alerta."""
    params = msg.setdefault("parameters", {})
    alert = params.setdefault("alert", {})
    data = alert.setdefault("data", {})
    data["srcip"] = ip            # <-- inyectamos srcip para que sea buscable
    params["program"] = PROGRAM
    msg["command"] = action
    write_log(f"{PROGRAM}: {json.dumps(msg, ensure_ascii=False)}")


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

    rule_name = f"WAZUH-AR-BLOCK-{ip}"

    if command == "add":
        subprocess.run(
            ["netsh", "advfirewall", "firewall", "add", "rule",
             f"name={rule_name}", "dir=in", "action=block", f"remoteip={ip}"],
            check=False,
        )
        emit_json(msg, ip, "add")
    elif command == "delete":
        subprocess.run(
            ["netsh", "advfirewall", "firewall", "delete", "rule",
             f"name={rule_name}"],
            check=False,
        )
        emit_json(msg, ip, "delete")

    sys.exit(0)


if __name__ == "__main__":
    main()
