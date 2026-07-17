<#
====================================================================
  build.ps1  -  Compila el instalador del agente de red a .exe
====================================================================
  NO necesita Visual Studio: usa el compilador C# (csc.exe) incluido en
  Windows (.NET Framework).

  Uso:
    Clic derecho > "Ejecutar con PowerShell"
    (o:  powershell -ExecutionPolicy Bypass -File build.ps1)

  Resultado:  dist\InstaladorAgenteRed.exe
              (con el script de instalacion embebido dentro)

  A diferencia del agente de monitorizacion (que embebe su instalador
  para uso offline), este DESCARGA sus componentes en tiempo de
  ejecucion, por lo que el equipo destino necesita conexion a internet.
====================================================================
#>

$ErrorActionPreference = "Stop"

$OutName = "InstaladorAgenteRed.exe"

$Root     = Split-Path -Parent $MyInvocation.MyCommand.Definition
$SrcDir   = Join-Path $Root "src"
$ResDir   = Join-Path $Root "Resources"
$DistDir  = Join-Path $Root "dist"
$Ps1Path  = Join-Path $ResDir "Instalador-Suricata-Windows.ps1"
$LogoPath = Join-Path $ResDir "logo.png"
$IconPath = Join-Path $ResDir "app.ico"
$Manifest = Join-Path $SrcDir "app.manifest"
$OutPath  = Join-Path $DistDir $OutName

Write-Host "=== Instalador del agente de red - build ===" -ForegroundColor Cyan

if (-not (Test-Path $DistDir)) { New-Item -ItemType Directory -Path $DistDir | Out-Null }
if (-not (Test-Path $Ps1Path)) { throw "Falta el script embebido: $Ps1Path" }

# Localizar csc.exe
$cscCandidates = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)
$csc = $cscCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $csc) { throw "No se encontro csc.exe (.NET Framework 4.x). Instala .NET Framework 4.x o usa Visual Studio (Instalador.sln)." }
Write-Host "Compilador: $csc" -ForegroundColor Green

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
    "/resource:`"$Ps1Path`",Instalador-Suricata-Windows.ps1",
    "/resource:`"$LogoPath`",logo.png",
    "/resource:`"$IconPath`",app.ico"
) + ($sources | ForEach-Object { "`"$_`"" })

Write-Host "Compilando..." -ForegroundColor Yellow
& $csc $cscArgs
if ($LASTEXITCODE -ne 0) { throw "La compilacion fallo (csc devolvio $LASTEXITCODE)." }

# Copiar archivos editables junto al exe (branding y logo)
Copy-Item (Join-Path $Root "branding.json") $DistDir -Force -ErrorAction SilentlyContinue
Copy-Item $LogoPath $DistDir -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== LISTO ===" -ForegroundColor Cyan
Write-Host "Ejecutable: $OutPath" -ForegroundColor Green
Write-Host "Personaliza la marca sin recompilar editando: dist\branding.json y dist\logo.png" -ForegroundColor Gray
