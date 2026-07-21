#!/usr/bin/env python3
# =============================================================================
# remove-threat.py  -  Active Response de Wazuh para AGENTES LINUX
# -----------------------------------------------------------------------------
# Borra el fichero que VirusTotal ha marcado como malicioso (regla 87105).
# Equivalente Linux del remove-threat.py de Windows (misma logica, rutas Linux).
#
# Debe estar en:  /var/ossec/active-response/bin/remove-threat.py
#   (con permiso de ejecucion, propietario root:wazuh)
#
# Wazuh envia la alerta por STDIN en JSON. Extraemos syscheck.path y borramos.
# =============================================================================

import os
import sys
import json
from datetime import datetime

LOG_FILE = "/var/ossec/logs/active-responses.log"


def log(message):
    ts = datetime.now().strftime("%Y/%m/%d %H:%M:%S")
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"{ts} remove-threat.py: {message}\n")
    except Exception:
        pass


def main():
    raw = sys.stdin.readline()
    try:
        data = json.loads(raw)
    except Exception as e:
        log(f"ERROR parseando JSON de entrada: {e}")
        sys.exit(1)

    command = data.get("command", "")
    alert = data.get("parameters", {}).get("alert", {})

    # La ruta puede venir en syscheck.path o en el bloque virustotal
    filename = (
        alert.get("syscheck", {}).get("path")
        or alert.get("data", {}).get("virustotal", {}).get("source", {}).get("file")
    )

    if command == "add":
        if filename and os.path.isfile(filename):
            try:
                os.remove(filename)
                log(f"eliminado fichero malicioso: {filename}")
            except Exception as e:
                log(f"ERROR al eliminar {filename}: {e}")
        else:
            log(f"fichero no encontrado o ruta vacia: '{filename}'")

    sys.exit(0)


if __name__ == "__main__":
    main()
