<#
====================================================================
  build.ps1  -  Compila el instalador del agente Wazuh en un .exe
====================================================================
  NO necesita Visual Studio: usa el compilador C# (csc.exe) incluido
  en Windows (.NET Framework).

  Uso:
    powershell -ExecutionPolicy Bypass -File build.ps1

  Que hace:
    1) Descarga el MSI del agente Wazuh (si no lo tienes ya).
    2) Compila los scripts de respuesta activa (active-response\src\*.py)
       a .exe con PyInstaller  (requiere Python + PyInstaller).
    3) Compila el instalador, embebiendo el MSI y los .exe de respuesta activa.

  Resultado:  dist\InstaladorAgente.exe
====================================================================
#>

$ErrorActionPreference = "Stop"

# -------- Configuracion --------
$WazuhVersion = "4.14.6-1"
$MsiUrl       = "https://packages.wazuh.com/4.x/windows/wazuh-agent-$WazuhVersion.msi"
$OutName      = "InstaladorAgente.exe"
# -------------------------------

$Root      = Split-Path -Parent $MyInvocation.MyCommand.Definition
$SrcDir    = Join-Path $Root "src"
$ResDir    = Join-Path $Root "Resources"
$DistDir   = Join-Path $Root "dist"
$MsiPath   = Join-Path $ResDir "wazuh-agent.msi"
$LogoPath  = Join-Path $ResDir "logo.png"
$IconPath  = Join-Path $ResDir "app.ico"
$Manifest  = Join-Path $SrcDir "app.manifest"
$OutPath   = Join-Path $DistDir $OutName

$ArSrcDir   = Join-Path $Root "active-response\src"     # .py de respuesta activa
$ArBinDir   = Join-Path $ResDir "active-response\bin"   # .exe generados
$ArManifest = Join-Path $ResDir "active-response\ar-manifest.txt"

Write-Host "=== Instalador Agente Wazuh - build ===" -ForegroundColor Cyan

if (-not (Test-Path $DistDir)) { New-Item -ItemType Directory -Path $DistDir | Out-Null }
if (-not (Test-Path $ArBinDir)) { New-Item -ItemType Directory -Path $ArBinDir -Force | Out-Null }

# 1) Descargar el MSI si no esta presente
if (-not (Test-Path $MsiPath)) {
    Write-Host "Descargando MSI del agente Wazuh $WazuhVersion ..." -ForegroundColor Yellow
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $MsiUrl -OutFile $MsiPath -UseBasicParsing
        Write-Host "MSI descargado." -ForegroundColor Green
    } catch {
        Write-Host "No se pudo descargar el MSI. Descargalo manualmente y guardalo como:" -ForegroundColor Red
        Write-Host "  $MsiPath  (URL: $MsiUrl)" -ForegroundColor Red
        throw
    }
} else {
    Write-Host "MSI ya presente: $MsiPath" -ForegroundColor Green
}

# 2) Compilar los scripts de respuesta activa (.py -> .exe) con PyInstaller
$pyFiles = @()
if (Test-Path $ArSrcDir) { $pyFiles = Get-ChildItem -Path $ArSrcDir -Filter *.py -ErrorAction SilentlyContinue }

if ($pyFiles.Count -gt 0) {
    # PyInstaller escribe avisos en stderr; evitamos que PowerShell los trate
    # como errores y aborte. Comprobamos el resultado con $LASTEXITCODE.
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        # Localizar Python
        $py = $null
        foreach ($cand in @("python", "py")) {
            try { & $cand --version 2>&1 | Out-Null; if ($LASTEXITCODE -eq 0) { $py = $cand; break } } catch { }
        }
        if (-not $py) {
            Write-Host "AVISO: no se encontro Python. No se compilaran los scripts de respuesta activa." -ForegroundColor DarkYellow
            Write-Host "Instala Python (https://www.python.org) y luego: pip install pyinstaller" -ForegroundColor DarkYellow
        } else {
            # Asegurar PyInstaller
            & $py -m PyInstaller --version 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Instalando PyInstaller..." -ForegroundColor Yellow
                & $py -m pip install --quiet pyinstaller 2>&1 | Out-Null
            }
            foreach ($f in $pyFiles) {
                Write-Host "Compilando respuesta activa: $($f.Name) ..." -ForegroundColor Yellow
                $work = Join-Path $env:TEMP ("pyi_" + $f.BaseName)
                # 2>&1 fusiona stderr con stdout para que los avisos no aborten el script.
                & $py -m PyInstaller --onefile --clean --noconfirm `
                    --distpath $ArBinDir --workpath $work --specpath $work $f.FullName 2>&1 |
                    ForEach-Object { Write-Host "   $_" }
                if ($LASTEXITCODE -ne 0) { throw "PyInstaller fallo compilando $($f.Name) (codigo $LASTEXITCODE)." }
            }
            Write-Host "Scripts de respuesta activa compilados." -ForegroundColor Green
        }
    }
    finally {
        $ErrorActionPreference = $prevEAP
    }
} else {
    Write-Host "AVISO: no hay scripts en active-response\src. Se compila sin respuesta activa." -ForegroundColor DarkYellow
}

# Generar el manifiesto con los .exe de respuesta activa presentes
$arExes = @()
if (Test-Path $ArBinDir) { $arExes = Get-ChildItem -Path $ArBinDir -Filter *.exe -ErrorAction SilentlyContinue }
($arExes | ForEach-Object { $_.Name }) -join "`r`n" | Set-Content -Path $ArManifest -Encoding UTF8
Write-Host ("Respuesta activa a embeber: " + (($arExes | ForEach-Object { $_.Name }) -join ", ")) -ForegroundColor Green

# 3) Localizar csc.exe
$cscCandidates = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)
$csc = $cscCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $csc) { throw "No se encontro csc.exe (.NET Framework 4.x)." }
Write-Host "Compilador: $csc" -ForegroundColor Green

# 4) Compilar el instalador
$sources = Get-ChildItem -Path $SrcDir -Filter *.cs | ForEach-Object { $_.FullName }

$cscArgs = @(
    "/nologo",
    "/target:winexe",
    "/platform:anycpu",
    "/optimize+",
    "/out:`"$OutPath`"",
    "/win32icon:`"$IconPath`"",
    "/win32manifest:`"$Manifest`"",
    "/reference:System.dll",
    "/reference:System.Drawing.dll",
    "/reference:System.Windows.Forms.dll",
    "/resource:`"$MsiPath`",wazuh-agent.msi",
    "/resource:`"$LogoPath`",logo.png",
    "/resource:`"$IconPath`",app.ico",
    "/resource:`"$ArManifest`",ar-manifest.txt"
)
# Embeber cada .exe de respuesta activa con nombre logico "ar/<archivo>"
foreach ($e in $arExes) {
    $cscArgs += "/resource:`"$($e.FullName)`",ar/$($e.Name)"
}
$cscArgs += ($sources | ForEach-Object { "`"$_`"" })

Write-Host "Compilando el instalador..." -ForegroundColor Yellow
& $csc $cscArgs
if ($LASTEXITCODE -ne 0) { throw "La compilacion fallo (csc devolvio $LASTEXITCODE)." }

# 5) Copiar archivos editables junto al exe (branding y logo)
Copy-Item (Join-Path $Root "branding.json") $DistDir -Force -ErrorAction SilentlyContinue
Copy-Item $LogoPath $DistDir -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== LISTO ===" -ForegroundColor Cyan
Write-Host "Ejecutable: $OutPath" -ForegroundColor Green
Write-Host "Ahora firma con:  powershell -ExecutionPolicy Bypass -File sign.ps1  (como admin)" -ForegroundColor Gray
