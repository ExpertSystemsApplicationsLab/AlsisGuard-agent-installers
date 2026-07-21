# AgentInstaller — Instaladores de agentes (AlsisGuard)

Conjunto de instaladores `.exe` con marca propia para desplegar los agentes de
AlsisGuard en equipos **Windows**. Este repositorio contiene **dos instaladores
independientes**, cada uno en su carpeta:

| Carpeta | Instalador | Qué despliega |
|---|---|---|
| `Agente-Monitorizacion/` | Agente de Monitorización | Vigila el **equipo** (registros del sistema, integridad de ficheros, vulnerabilidades, cumplimiento). Se conecta al **sistema central** de AlsisGuard. |
| `Agente-Red/` | Agente de Red | Vigila el **tráfico de red** del equipo (detección de intrusiones/IDS) y envía sus hallazgos al Agente de Monitorización, que los reenvía al sistema central. |

Ambos comparten estilo visual, marca editable y el mismo flujo de
compilación/firma. Este README cubre **todo el ciclo**: compilar, firmar,
personalizar, instalar y resolver problemas.

Cada agente está disponible en **dos versiones**: **Windows** (instalador `.exe`
con ventana, carpetas `Agente-Monitorizacion/` y `Agente-Red/`) y **Linux/UNIX**
(script `.sh` silencioso, carpetas `Agente-Monitorizacion-Linux/` y
`Agente-Red-Linux/`). En Linux los agentes se enrolan en el grupo **`unix`**
(ver sección 6.3).

---

## 1. Conceptos básicos

- El **Agente de Monitorización** es la base: se instala primero y es quien
  mantiene la conexión con el **sistema central** (donde se recogen, analizan y
  visualizan los eventos). Necesita la **IP o dominio del sistema central**.
- El **Agente de Red** es un complemento: analiza el tráfico de la interfaz de
  red elegida y **se apoya en el Agente de Monitorización** ya instalado para
  hacer llegar sus alertas al sistema central. No sustituye al de monitorización.
- Orden recomendado de despliegue en un equipo: **1)** Agente de Monitorización
  → **2)** Agente de Red.
- Alcance del Agente de Red: analiza **solo el tráfico del equipo donde se
  instala**. Para cubrir toda una red haría falta situar el sensor en un punto de
  concentración de tráfico (puerto espejo/SPAN, TAP o el firewall perimetral);
  eso queda fuera de estos instaladores.

---

## 2. Requisitos

**Equipo donde se COMPILA el `.exe`** (una sola vez, quien prepara los instaladores):

- Windows 10/11 (incluye el compilador de .NET Framework `csc.exe` y `tar`).
- No hace falta Visual Studio (se compila con `build.ps1`). Opcionalmente puede
  abrirse `Instalador.sln`.
- **Solo para el Agente de Monitorización:** Python + PyInstaller
  (`pip install pyinstaller`), necesarios para compilar los scripts de respuesta
  activa (`active-response\src\*.py`) a `.exe`. Si no están, `build.ps1` avisa y
  genera el instalador sin respuesta activa.

**Equipo DESTINO donde se ejecuta el instalador:**

- Windows 10/11 o Windows Server.
- Permisos de **Administrador** (los instaladores lo exigen por UAC).
- Agente de Monitorización: puede instalarse **sin internet** (su instalador va
  embebido en el `.exe`).
- Agente de Red: **requiere conexión a internet** (descarga sus componentes y el
  conjunto de reglas en el momento de instalar).

---

## 3. Compilar los instaladores

En un PC con Windows, dentro de **cada** carpeta:

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1
```

Resultado:

- `Agente-Monitorizacion\dist\InstaladorAgente.exe`
- `Agente-Red\dist\InstaladorAgenteRed.exe`

`build.ps1` localiza el compilador de Windows, embebe los recursos (marca, logo y
—en el caso del Agente de Red— el script de instalación) y genera el `.exe`. Si
prefieres Visual Studio, abre `Instalador.sln` y compila en modo *Release*.

---

## 4. Firmar los `.exe` (quitar el aviso "Editor desconocido")

Windows muestra "Editor desconocido" mientras el `.exe` no esté firmado. Para uso
interno, dentro de cada carpeta y en **PowerShell como Administrador**:

```powershell
powershell -ExecutionPolicy Bypass -File sign.ps1
```

Crea (una vez) un certificado autofirmado **ESALab**, confía en él en ESTE equipo
y firma el `.exe`. A partir de ahí el aviso mostrará **ESALab** en este equipo.

Para que **otros** equipos también lo reconozcan sin aviso, instala en ellos el
certificado `ESALab.cer` que genera el script (a mano o por GPO en un dominio):

```powershell
Import-Certificate -FilePath ESALab.cer -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath ESALab.cer -CertStoreLocation Cert:\LocalMachine\TrustedPublisher
```

> Para que **cualquier** equipo (incluidos externos) confíe sin instalar nada,
> haría falta un certificado de firma de código **de pago** (OV/EV) emitido a la
> empresa por una autoridad certificadora.

---

## 5. Personalizar la marca (sin recompilar)

Junto a cada `.exe` (en `dist\`) quedan dos archivos editables y redistribuibles:

- **`branding.json`** — textos y colores.
- **`logo.png`** — logo (PNG horizontal, fondo transparente, ~320×120 px).

Campos de `branding.json`:

| Campo | Para qué sirve |
|---|---|
| `companyName` | Nombre de empresa (cabecera). |
| `productTitle` | Título de la ventana. |
| `subtitle` | Texto secundario bajo el nombre. |
| `primaryColor` / `accentColor` / `headerColor` | Colores en hexadecimal. |
| `supportText` | Texto de pie (p. ej. datos de soporte). |
| `logoFile` | Nombre del archivo de logo. |
| `defaultManagerIp` / `lockManagerIp` | *(Solo Agente de Monitorización)* IP del sistema central precargada, y si se bloquea para que el usuario no la cambie. |
| `agentGroup` | *(Solo Agente de Monitorización)* Grupo de enrolamiento para recibir la configuración FIM centralizada del manager. Por defecto `windows`. |
| `suricataEveLog` | *(Solo Agente de Monitorización)* Ruta del `eve.json` de Suricata que recolecta el agente. |

Si estos archivos no están junto al `.exe`, se usan los valores y el logo
**embebidos por defecto**.

---

## 6. Usar los instaladores (en el equipo destino)

### 6.1 Agente de Monitorización

1. Clic derecho en `InstaladorAgente.exe` → **Ejecutar como administrador**.
2. Escribir la **IP o dominio del sistema central**.
3. (Opcional) Ajustar el **nombre del equipo/agente** (por defecto, el del equipo).
4. (Opcional) Marcar **"Vigilar carpetas extra con FIM"** y escribir una carpeta
   por línea (se vigilan en tiempo real).
5. Pulsar **Instalar y configurar agente**. El progreso se muestra en la ventana.

Además de instalar el agente, deja el equipo **listo para respuesta activa**:

- Registra el agente en el grupo `windows` (config FIM centralizada del manager).
- Copia los binarios de respuesta activa (`netsh-block.exe` para bloquear la IP
  atacante en el firewall, y `remove-threat.exe` para borrar archivos maliciosos)
  a `active-response\bin`.
- Habilita la auditoría de inicios de sesión fallidos (evento **4625**), necesaria
  para detectar fuerza bruta.
- Añade al `ossec.conf` la recolección del log de **Suricata** (`eve.json`).
- Reinicia el servicio y hace un **test de puertos 1514/1515** contra el manager
  (avisa en el registro si la IP es incorrecta).

El instalador es **autolimpiante**: si ya hay un agente (p. ej. con una IP
anterior incorrecta), ofrece reinstalarlo limpio; si detecta restos de una
instalación fallida, los limpia solo; y si la instalación falla, limpia y
reintenta una vez.

Los scripts de respuesta activa se editan en `Agente-Monitorizacion\active-response\src\`
(`netsh-block.py`, `remove-threat.py`) y `build.ps1` los recompila a `.exe`
automáticamente.

### 6.2 Agente de Red

1. Instalar **antes** el Agente de Monitorización (ver arriba).
2. Clic derecho en `InstaladorAgenteRed.exe` → **Ejecutar como administrador**.
3. Elegir en la lista la **interfaz de red** a monitorizar (Wi-Fi, Ethernet…).
4. Pulsar **Instalar**. El progreso se muestra en la ventana.

Qué hace por dentro, de forma automática:

1. Instala el **controlador de captura de red (Npcap)** si falta.
2. Instala el **motor de detección** (sensor IDS) en silencio.
3. Descarga el **conjunto de reglas** (recortado para entorno de empresa: se
   descartan categorías ruidosas) y omite reglas no compatibles con Windows.
4. Configura la red vigilada (`HOME_NET`) según la interfaz elegida y activa la
   salida de eventos en formato JSON.
5. Enlaza esa salida con el **Agente de Monitorización** para que reenvíe las
   alertas al sistema central.
6. Deja el sensor **arrancando automáticamente con Windows** (tarea programada) y
   lo pone en marcha.

### 6.3 Versión Linux/UNIX (scripts `.sh`)

Para equipos **Linux/UNIX** hay dos instaladores en forma de **script silencioso**
(sin ventana; todo por parámetros), pensados para despliegue masivo. Los agentes
Linux se enrolan en el grupo **`unix`**. Requieren **root** y `systemd`; el equipo
necesita acceso a internet para descargar los paquetes.

**Agente de Monitorización (Linux)** — `Agente-Monitorizacion-Linux/install-agent.sh`:

```bash
sudo ./install-agent.sh -m <IP_DEL_MANAGER> [-n nombre] [-g unix] \
     [-f "/datos,/var/www"] [--force]
```

Detecta la distribución (apt/dnf/yum/zypper), instala `wazuh-agent` y lo enrola en
el grupo `unix`, y luego deja el equipo listo para respuesta activa:

- Copia la respuesta activa portada a Linux: `firewall-block.py` (bloqueo de IP
  con **iptables/ip6tables**) y `remove-threat.py`, en `/var/ossec/active-response/bin`.
- La detección de **fuerza bruta** se apoya en los logs de autenticación SSH
  (`/var/log/auth.log` o `/var/log/secure`), que Wazuh recoge por defecto (no hace
  falta `auditpol`, que es de Windows).
- Añade la recolección de **Suricata** (`/var/log/suricata/eve.json`) al `ossec.conf`.
- Añade las **carpetas FIM extra** indicadas con `-f` (vigilancia en tiempo real).
- Reinicia el servicio y hace un **test de puertos 1514/1515**.
- `--force` purga cualquier instalación previa para una instalación limpia.

**Agente de Red / Suricata (Linux)** — `Agente-Red-Linux/install-suricata.sh`
(instala **antes** el de monitorización):

```bash
sudo ./install-suricata.sh [-i eth0] [-H 192.168.0.0/16]
```

Instala Suricata, descarga las reglas (`suricata-update`), lo configura sobre la
interfaz indicada (o la de la ruta por defecto), y engancha la recolección del
`eve.json` al agente Wazuh (que es quien pertenece al grupo `unix` y reenvía al
manager).

> Los scripts de respuesta activa de Linux se editan en
> `Agente-Monitorizacion-Linux/active-response/`. Requieren Python 3 en el equipo
> destino (se ejecutan como scripts, no se compilan).

---

## 7. Verificar que funciona

**Agente de Monitorización**: en la consola del sistema central, el equipo debe
aparecer como *Active* (conectado).

**Agente de Red** — test de detección seguro (tráfico HTTP de prueba):

```powershell
(Invoke-WebRequest "http://testmynids.org/uid/index.html" -UseBasicParsing).Content
```

Devuelve `uid=0(root)...`, que dispara una regla de detección conocida. En la
consola del sistema central, filtra los eventos de red (grupo `suricata` / IDS) y
comprueba que aparece la alerta del equipo correspondiente. Localmente, el
proceso `suricata` debe estar en ejecución (`Get-Process suricata`) y el fichero
de eventos debe crecer.

---

## 8. Posibles problemas y soluciones

| Síntoma | Causa y solución |
|---|---|
| **"Editor desconocido"** al abrir el `.exe` | El `.exe` no está firmado. Ejecuta `sign.ps1` (sección 4) y, en otros equipos, instala `ESALab.cer`. |
| **"No se puede ejecutar scripts"** al lanzar `build.ps1`/`sign.ps1` | Directiva de ejecución de PowerShell. Usa `powershell -ExecutionPolicy Bypass -File <script>.ps1`. |
| El instalador **no hace nada / pide permisos** | Debe ejecutarse **como Administrador** (clic derecho → Ejecutar como administrador). |
| Al compilar: **"No se encontró csc.exe"** | Falta .NET Framework 4.x en el equipo de compilación (viene de serie en Windows 10/11) o compila abriendo `Instalador.sln` en Visual Studio. |
| **Se abre una ventana del controlador de captura (Npcap)** y pide clics | La versión gratuita de Npcap **no permite instalación silenciosa** (es función de la versión de pago). Deja marcada la opción *"WinPcap API-compatible Mode"* y pulsa *Install/Next*. Si Npcap ya estaba instalado, este paso se salta solo. |
| El **Agente de Red no descarga** nada / falla la descarga | Ese instalador **necesita internet** en el equipo destino. Comprueba la conexión y que no haya un proxy/cortafuegos bloqueando las descargas. |
| El equipo **no aparece conectado** en el sistema central | Suele ser una **IP del sistema central incorrecta**. Vuelve a ejecutar el Agente de Monitorización con la IP correcta y acepta la reinstalación limpia. (Una IP mal escrita no hace fallar la instalación: el agente se instala pero no conecta.) |
| El **sensor de red captura** (su fichero de eventos crece) **pero no llega nada** al sistema central | (a) El Agente de Monitorización no está leyendo el fichero de eventos del sensor, o lo lee desde el final (genera tráfico nuevo tras instalar). (b) En el servidor, el **reenviador de eventos hacia el indexador (Filebeat)** puede estar caído o con credenciales caducadas (`filebeat test output` → error 401): revisa sus credenciales. (c) Falta el índice del día en el indexador. |
| En la consola central **no sale nada ni sin filtro** | Amplía el **rango de tiempo** (posible desfase de reloj) y confirma que el índice del día existe. Si sigue vacío, el problema está en el envío al indexador (ver fila anterior). |
| **No sale nada solo al filtrar por el nombre de una amenaza** | Las búsquedas con comodines y espacios fallan. Filtra por el **identificador numérico** de la regla en vez del texto. |
| El sensor de red **solo detecta pings** y nada más | No se cargó el conjunto de reglas completo. Reejecuta el Agente de Red (paso de descarga de reglas). |
| Elegí la interfaz equivocada (**Ethernet vs Wi-Fi**) | Si el equipo tiene ambas activas, el tráfico sale por la de menor métrica. Reejecuta el Agente de Red y elige la interfaz por la que realmente navega el equipo. |
| El sensor **no ve tráfico cifrado (HTTPS)** en detalle | Es normal en cualquier IDS de red: del tráfico cifrado solo se ven metadatos (dominio, certificado), no el contenido. Por eso los tests van por `http://`. |

---

## 9. Estructura del repositorio

```
AgentInstaller\
├─ README.md                       ← este documento (guía única y completa)
├─ Agente-Monitorizacion\          ← instalador del agente de monitorización de host
│  ├─ build.ps1  sign.ps1  branding.json
│  ├─ Instalador.csproj / .sln
│  ├─ src\        (código de la aplicación)
│  ├─ Resources\  (logo, icono, instalador embebido)
│  └─ dist\       (InstaladorAgente.exe tras compilar)
├─ Agente-Red\                     ← instalador del agente de red (IDS) — Windows
│  ├─ build.ps1  sign.ps1  branding.json
│  ├─ Instalador.csproj / .sln
│  ├─ src\
│  ├─ Resources\ (logo, icono, script de instalación embebido)
│  └─ dist\       (InstaladorAgenteRed.exe tras compilar)
├─ Agente-Monitorizacion-Linux\    ← instalador del agente de monitorización — Linux
│  ├─ install-agent.sh             (script silencioso, grupo unix)
│  └─ active-response\             (firewall-block.py [iptables], remove-threat.py)
└─ Agente-Red-Linux\               ← instalador del agente de red (Suricata) — Linux
   └─ install-suricata.sh          (script silencioso)
```

---

## 10. Notas técnicas

- Ambos `.exe` requieren permisos de Administrador (solicitan elevación por UAC).
- El Agente de Monitorización lleva su instalador **embebido** (uso offline); el
  Agente de Red **descarga** sus componentes al instalar (necesita internet).
- Códigos de salida del instalador subyacente: `0` = correcto, `3010` = correcto
  pero requiere reinicio (ambos se consideran éxito).
- Compatibles con Windows 10/11 y Windows Server. Requieren .NET Framework 4.x
  (incluido de serie en Windows).
- El Agente de Red analiza únicamente el tráfico del equipo donde se instala.
