<#
====================================================================
  build.ps1  -  Compila el instalador del agente Wazuh en un .exe
====================================================================
  NO necesita Visual Studio: usa el compilador C# (csc.exe) que ya
  viene incluido en Windows (.NET Framework).

  Uso:
    1) Clic derecho sobre este archivo  >  "Ejecutar con PowerShell"
       (o en una terminal:  powershell -ExecutionPolicy Bypass -File build.ps1)
    2) El script descarga el MSI del agente Wazuh (si no lo tienes ya),
       compila y deja el ejecutable en la carpeta  dist\

  Resultado:  dist\InstaladorAgente.exe   (con el MSI embebido dentro)
====================================================================
#>

$ErrorActionPreference = "Stop"

# -------- Configuracion --------
$WazuhVersion = "4.14.6-1"                                            # version del agente a embeber
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

Write-Host "=== Instalador Agente Wazuh - build ===" -ForegroundColor Cyan

if (-not (Test-Path $DistDir)) { New-Item -ItemType Directory -Path $DistDir | Out-Null }

# 1) Descargar el MSI si no esta presente
if (-not (Test-Path $MsiPath)) {
    Write-Host "Descargando MSI del agente Wazuh $WazuhVersion ..." -ForegroundColor Yellow
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $MsiUrl -OutFile $MsiPath -UseBasicParsing
        Write-Host "MSI descargado." -ForegroundColor Green
    } catch {
        Write-Host "No se pudo descargar el MSI automaticamente." -ForegroundColor Red
        Write-Host "Descarga manualmente este archivo y guardalo como:" -ForegroundColor Red
        Write-Host "  $MsiPath" -ForegroundColor Red
        Write-Host "  URL: $MsiUrl" -ForegroundColor Red
        throw
    }
} else {
    Write-Host "MSI ya presente: $MsiPath" -ForegroundColor Green
}

# 2) Localizar csc.exe (compilador de .NET Framework, incluido en Windows)
$cscCandidates = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)
$csc = $cscCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $csc) {
    throw "No se encontro csc.exe (.NET Framework 4.x). Instala .NET Framework 4.x o compila con Visual Studio abriendo Instalador.sln."
}
Write-Host "Compilador: $csc" -ForegroundColor Green

# 3) Compilar
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
    "/resource:`"$IconPath`",app.ico"
) + ($sources | ForEach-Object { "`"$_`"" })

Write-Host "Compilando..." -ForegroundColor Yellow
& $csc $cscArgs
if ($LASTEXITCODE -ne 0) { throw "La compilacion fallo (csc devolvio $LASTEXITCODE)." }

# 4) Copiar archivos editables junto al exe (branding y logo)
Copy-Item (Join-Path $Root "branding.json") $DistDir -Force -ErrorAction SilentlyContinue
Copy-Item $LogoPath $DistDir -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== LISTO ===" -ForegroundColor Cyan
Write-Host "Ejecutable: $OutPath" -ForegroundColor Green
Write-Host "Para personalizar la marca sin recompilar, edita:" -ForegroundColor Gray
Write-Host "  dist\branding.json   y   dist\logo.png" -ForegroundColor Gray
