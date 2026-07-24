# =============================================================================
# netsh-block.py  -  Active Response de Wazuh para AGENTES WINDOWS  (v3)
# -----------------------------------------------------------------------------
# Banea/desbanea en el firewall de Windows la IP de un ataque de autenticación
# (fuerza bruta) sea cual sea el vector: SMB, RDP, WinRM (evento 4625) o SSH
# (OpenSSH, canal OpenSSH/Operational).
#
# Extrae la IP en este orden:
#   1. data.srcip
#   2. data.win.eventdata.ipAddress            (4625: SMB/RDP/WinRM/local)
#   3. regex "from <IP> port" en el mensaje    (OpenSSH de Windows)
#
# Además escribe el log en el formato JSON que decodifica el manager (para que
# el baneo aparezca como alerta en el dashboard) e inyecta data.srcip.
#
# Compilar:  pip install pyinstaller ; pyinstaller --onefile netsh-block.py
#   -> copiar dist\netsh-block.exe a active-response\bin
# =============================================================================

import sys
import re
import json
import subprocess
from datetime import datetime

LOG_FILE = r"C:\Program Files (x86)\ossec-agent\active-response\active-responses.log"
PROGRAM = "active-response/bin/netsh-block.exe"
WHITELIST = {"127.0.0.1", "::1", "-"}

# "Failed password for user from 192.168.1.90 port 55000 ssh2"
IP_FROM_RE = re.compile(r"from\s+(\d{1,3}(?:\.\d{1,3}){3})\s+port", re.IGNORECASE)
IP_ANY_RE = re.compile(r"\b(\d{1,3}(?:\.\d{1,3}){3})\b")


def write_log(line):
    ts = datetime.now().strftime("%Y/%m/%d %H:%M:%S")
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(f"{ts} {line}\n")
    except Exception:
        pass


def get_ip(alert):
    data = alert.get("data", {})
    # 1) srcip directo
    ip = data.get("srcip")
    if ip and ip not in WHITELIST:
        return ip
    # 2) evento 4625 (SMB/RDP/WinRM/local)
    ip = data.get("win", {}).get("eventdata", {}).get("ipAddress")
    if ip and ip not in WHITELIST:
        return ip
    # 3) OpenSSH de Windows: extraer del mensaje
    msg = data.get("win", {}).get("system", {}).get("message", "") or ""
    m = IP_FROM_RE.search(msg)
    if m:
        return m.group(1)
    m = IP_ANY_RE.search(msg)
    if m:
        return m.group(1)
    return None


def emit_json(msg, ip, action):
    params = msg.setdefault("parameters", {})
    alert = params.setdefault("alert", {})
    data = alert.setdefault("data", {})
    data["srcip"] = ip
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
