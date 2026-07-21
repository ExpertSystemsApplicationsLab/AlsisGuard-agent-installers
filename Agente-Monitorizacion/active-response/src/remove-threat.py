# =============================================================================
# remove-threat.py  -  Active Response de Wazuh para AGENTES WINDOWS
# -----------------------------------------------------------------------------
# Borra el fichero que VirusTotal ha marcado como malicioso (regla 87105).
#
# En Windows el ejecutable de Active Response debe ser un .exe. Hay que
# COMPILAR este .py y dejarlo en:
#   C:\Program Files (x86)\ossec-agent\active-response\bin\remove-threat.exe
#
# Compilar (en una máquina Windows con Python + pyinstaller):
#   pip install pyinstaller
#   pyinstaller --onefile remove-threat.py
#   -> copiar dist\remove-threat.exe a la carpeta active-response\bin del agente
#
# Wazuh envía la alerta por STDIN en JSON. Extraemos syscheck.path y borramos.
# =============================================================================

import os
import sys
import json
from datetime import datetime

LOG_FILE = r"C:\Program Files (x86)\ossec-agent\active-response\active-responses.log"


def log(message):
    ts = datetime.now().strftime("%Y/%m/%d %H:%M:%S")
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"{ts} remove-threat.exe: {message}\n")
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
