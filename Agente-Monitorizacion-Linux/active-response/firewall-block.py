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

import re
import sys
import json
import subprocess
from datetime import datetime

LOG_FILE = "/var/ossec/logs/active-responses.log"
PROGRAM = "active-response/bin/firewall-block.py"

# Duracion POR DEFECTO del bloqueo en SEGUNDOS. El propio script programa el
# desbloqueo, asi la IP SIEMPRE se libera pasado este tiempo (aunque reinicies el
# agente o lo lances a mano). Pon 0 para bloqueo permanente (solo manual).
# Se puede sobreescribir por invocacion pasando los segundos como argumento
# (parameters.extra_args, es decir "arguments" en la API). Ej: arguments:["120"].
BLOCK_SECONDS = 40

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


def _fw_tool(ip):
    return "ip6tables" if is_ipv6(ip) else "iptables"


def valid_ip(ip):
    """Valida el formato de la IP (evita inyeccion en el proceso programado)."""
    return bool(re.match(r'^[0-9A-Fa-f:.]{3,45}$', ip or ''))


def get_seconds(msg):
    """Duracion del bloqueo: usa el argumento pasado en la invocacion
    (parameters.extra_args / 'arguments' de la API) si es un numero; si no,
    usa BLOCK_SECONDS por defecto."""
    args = msg.get("parameters", {}).get("extra_args") or []
    for a in args:
        try:
            return int(str(a).strip())
        except (ValueError, TypeError):
            continue
    return BLOCK_SECONDS


def schedule_unblock(ip, seconds):
    """Programa el desbloqueo dentro de 'seconds' segundos con un proceso PROPIO,
    independiente de Wazuh y que sobrevive a reinicios del agente. Garantiza que
    el bloqueo caduque siempre pasado el tiempo establecido."""
    if seconds <= 0 or not valid_ip(ip):
        return
    tool = _fw_tool(ip)
    cmd = ("sleep %d; for i in $(seq 1 20); do "
           "%s -D INPUT -s %s -j DROP 2>/dev/null || break; done") % (int(seconds), tool, ip)
    try:
        subprocess.Popen(
            ["nohup", "bash", "-c", cmd],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        write_log("%s: desbloqueo programado para %s en %ds" % (PROGRAM, ip, int(seconds)))
    except Exception as e:
        write_log("%s: no se pudo programar el desbloqueo de %s: %s" % (PROGRAM, ip, e))


def unblock(ip):
    """Quita TODAS las reglas DROP de esa IP (por si hubiera duplicadas)."""
    tool = _fw_tool(ip)
    for _ in range(20):
        r = subprocess.run(
            [tool, "-D", "INPUT", "-s", ip, "-j", "DROP"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if r.returncode != 0:
            break


def block(ip):
    """Bloquea la IP dejando UNA sola regla (limpia duplicados antes)."""
    unblock(ip)
    tool = _fw_tool(ip)
    subprocess.run([tool, "-I", "INPUT", "-s", ip, "-j", "DROP"], check=False)


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
        block(ip)
        schedule_unblock(ip, get_seconds(msg))   # caduca solo pasados los segundos (arg o BLOCK_SECONDS)
        emit_json(msg, ip, "add")
    elif command == "delete":
        unblock(ip)
        emit_json(msg, ip, "delete")

    sys.exit(0)


if __name__ == "__main__":
    main()
