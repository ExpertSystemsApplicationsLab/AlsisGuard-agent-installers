# Instalador del Agente Wazuh (Windows, .exe con branding editable)

Genera un único `.exe` para Windows que instala el **agente Wazuh** apuntándolo
al **manager** de tu elección. Quien lo ejecuta solo tiene que escribir la **IP
del manager** (y opcionalmente el **nombre del agente**) y pulsar *Instalar*.

El MSI oficial del agente Wazuh queda **embebido dentro del propio `.exe`**, así
que funciona en equipos **sin conexión a internet**.

- Agente Wazuh embebido: **v4.14.6-1**
- El branding (nombre de empresa, logo, colores) es **editable sin recompilar**.

---

## 1. Compilar el .exe (recomendado, sin Visual Studio)

Necesitas un PC con **Windows** (cualquier Windows 10/11 sirve; ya trae el
compilador de .NET Framework).

1. Copia esta carpeta completa al PC con Windows.
2. Clic derecho en **`build.ps1`** → **Ejecutar con PowerShell**.
   - Si PowerShell bloquea el script, abre una terminal en la carpeta y ejecuta:
     `powershell -ExecutionPolicy Bypass -File build.ps1`
3. El script descarga el MSI del agente (solo la primera vez), lo embebe y compila.
4. Resultado: **`dist\InstaladorAgente.exe`**

> Si el PC de compilación no tiene internet, descarga manualmente el MSI desde
> `https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.6-1.msi`
> y guárdalo como `Resources\wazuh-agent.msi` antes de ejecutar `build.ps1`.

### Alternativa con Visual Studio
Coloca primero el MSI en `Resources\wazuh-agent.msi` (o ejecuta `build.ps1` una
vez), abre **`Instalador.sln`** y compila en modo *Release*.

---

## 2. Personalizar la marca (empresa, logo, colores)

Hay dos maneras:

**A) Sin recompilar (lo más fácil).** Junto al `.exe` (en `dist\`) hay dos
archivos que puedes editar y redistribuir con el `.exe`:

- **`branding.json`** — textos, colores, IP por defecto.
- **`logo.png`** — reemplázalo por el logo de tu empresa (se recomienda PNG
  horizontal, fondo transparente, aprox. 320×120 px).

Campos de `branding.json`:

| Campo | Para qué sirve |
|---|---|
| `companyName` | Nombre de tu empresa (título de la cabecera). |
| `productTitle` | Título de la ventana. |
| `subtitle` | Texto secundario bajo el nombre. |
| `defaultManagerIp` | IP del manager precargada en el campo (déjalo vacío para que la escriba el usuario). |
| `lockManagerIp` | `true` para fijar la IP y que el usuario no pueda cambiarla. |
| `primaryColor` | Color principal en hexadecimal (ej. `#172A45`). |
| `accentColor` | Color de acento / botón (ej. `#5EC8E5`). |
| `supportText` | Texto de pie (ej. datos de contacto de soporte). |
| `logoFile` | Nombre del archivo de logo (por defecto `logo.png`). |

Si `branding.json` o `logo.png` no están junto al `.exe`, se usan los valores y
el logo **embebidos por defecto**.

**B) Embebido en el .exe.** Sustituye `Resources\logo.png` y `Resources\app.ico`
por los tuyos y edita el `branding.json` de la raíz antes de compilar. Así el
`.exe` sale ya con tu marca por defecto aunque no lleve archivos al lado.

---

## 3. Usar el instalador (en el equipo destino)

1. Clic derecho en `InstaladorAgente.exe` → **Ejecutar como administrador**
   (es obligatorio; el propio programa lo pide por UAC).
2. Escribir la **IP o dominio del Wazuh Manager**.
3. (Opcional) Ajustar el **nombre del agente** (por defecto, el nombre del equipo).
4. Pulsar **Instalar agente**.

El instalador ejecuta en silencio:

```
msiexec.exe /i wazuh-agent-4.14.6-1.msi /qn /norestart ^
    WAZUH_MANAGER="<IP>" WAZUH_REGISTRATION_SERVER="<IP>" WAZUH_AGENT_NAME="<nombre>"
```

y a continuación arranca el servicio `WazuhSvc`. Verás el progreso y un registro
en la propia ventana.

---

## 4. Actualizar la versión del agente Wazuh

Edita la variable `$WazuhVersion` al principio de `build.ps1`, borra
`Resources\wazuh-agent.msi` y vuelve a ejecutar `build.ps1` (descargará la nueva
versión). O coloca manualmente el nuevo MSI en `Resources\wazuh-agent.msi`.

---

## 5. Quitar el aviso de "Editor desconocido" (firmar el .exe)

Windows muestra "Editor desconocido" porque el `.exe` no está firmado. El nombre
del editor sale de la **firma digital**, no de un texto editable.

Para uso interno, ejecuta (PowerShell **como administrador**), después de compilar:

```
powershell -ExecutionPolicy Bypass -File sign.ps1
```

Crea un certificado autofirmado **ESALab**, confía en él en este equipo y firma
`dist\InstaladorAgente.exe`. A partir de ahí el aviso mostrará **ESALab**.

En **otros equipos** el aviso solo desaparece si instalas el certificado
`ESALab.cer` (que genera el script) en los almacenes *Entidades de certificación
raíz de confianza* y *Editores de confianza* (a mano o por GPO en un dominio):

```
Import-Certificate -FilePath ESALab.cer -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath ESALab.cer -CertStoreLocation Cert:\LocalMachine\TrustedPublisher
```

> Para que **cualquier** equipo (también externos) confíe sin instalar nada, hace
> falta un certificado de firma de código **de pago** (OV/EV) emitido a ESALab por
> una autoridad certificadora. El nombre a mostrar se cambia con la variable
> `$Publisher` al inicio de `sign.ps1`.

## Estructura del proyecto

```
AgentInstaller\
├─ build.ps1              ← compila el .exe (un clic, sin Visual Studio)
├─ branding.json          ← marca editable (empresa, colores, IP por defecto)
├─ Instalador.sln         ← solución de Visual Studio (opcional)
├─ Instalador.csproj      ← proyecto de Visual Studio (opcional)
├─ src\
│  ├─ Program.cs          ← punto de entrada
│  ├─ MainForm.cs         ← interfaz (Windows Forms) y lógica de instalación
│  ├─ Branding.cs         ← carga de branding.json / logo
│  └─ app.manifest        ← fuerza ejecución como Administrador (UAC)
├─ Resources\
│  ├─ logo.png            ← logo por defecto (reemplázalo por el tuyo)
│  └─ app.ico             ← icono del .exe
└─ dist\                  ← aquí aparece InstaladorAgente.exe tras compilar
```

## Notas técnicas
- El agente Wazuh requiere permisos de administrador para instalarse y para
  registrar/arrancar su servicio; por eso el `.exe` solicita elevación (UAC).
- Códigos de salida de `msiexec`: `0` = correcto, `3010` = correcto pero requiere
  reinicio (ambos se consideran éxito). Cualquier otro se muestra como error.
- Compatible con Windows 10/11 y Windows Server. Requiere .NET Framework 4.x
  (incluido de serie en Windows).
