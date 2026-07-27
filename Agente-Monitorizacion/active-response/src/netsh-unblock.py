# =============================================================================
# netsh-unblock.py  -  Active Response de Wazuh para AGENTES WINDOWS
# -----------------------------------------------------------------------------
# DESBLOQUEA (borra) una regla de firewall creada por netsh-block, es decir,
# levanta un baneo temporal antes de que expire. Pensado para invocarse BAJO
# DEMANDA desde el manager / tu panel (API PUT /active-response), pasándole la IP.
#
# De dónde saca la IP a desbloquear (en este orden):
#   1. parameters.extra_args[0]      <- lo que envía el panel por la API
#   2. parameters.alert.data.srcip   <- por si viene en la alerta
#
# Escribe el log en formato JSON (decodificable por el manager) para que el
# desbloqueo aparezca como alerta en el dashboard.
#
# Compilar:  pip install pyinstaller ; pyinstaller --onefile netsh-unblock.py
#   -> copiar dist\netsh-unblock.exe a:
#      C:\Program Files (x86)\ossec-agent\active-response\bin\netsh-unblock.exe
# =============================================================================

import sys
import json
import subprocess
from datetime import datetime

LOG_FILE = r"C:\Program Files (x86)\ossec-agent\active-response\active-responses.log"
PROGRAM = "active-response/bin/netsh-unblock.exe"


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

    # En invocación bajo demanda por API, Wazuh manda command="add".
    # Aceptamos add o delete: en ambos casos el objetivo es LEVANTAR el baneo.
    if command in ("add", "delete"):
        rule_name = f"WAZUH-AR-BLOCK-{ip}"
        subprocess.run(
            ["netsh", "advfirewall", "firewall", "delete", "rule",
             f"name={rule_name}"],
            check=False,
        )
        write_log(f"{PROGRAM}: IP desbloqueada manualmente: {ip}")
        emit_json(msg, ip)

    sys.exit(0)


if __name__ == "__main__":
    main()
