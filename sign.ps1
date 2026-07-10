<#
====================================================================
  sign.ps1  -  Firma el .exe para que Windows muestre "ESALab"
               como editor (en vez de "Editor desconocido").
====================================================================
  Usa un certificado AUTOFIRMADO (gratuito). El editor "ESALab" se
  mostrara SOLO en los equipos que confien en ese certificado.

  USO (PowerShell COMO ADMINISTRADOR):
      powershell -ExecutionPolicy Bypass -File sign.ps1

  Que hace:
   1) Crea (una sola vez) un certificado de firma de codigo "ESALab".
   2) Lo instala como raiz de confianza y editor de confianza en ESTE equipo.
   3) Firma dist\InstaladorAgente.exe.
   4) Exporta ESALab.cer para instalarlo en otros equipos (ver mas abajo).

  Para que OTROS equipos muestren "ESALab" sin aviso, hay que instalar
  ESALab.cer en ellos, en los almacenes:
     - Entidades de certificacion raiz de confianza (Trusted Root)
     - Editores de confianza (Trusted Publishers)
  Se puede hacer a mano o por GPO en un dominio. Comando por equipo (admin):
     Import-Certificate -FilePath ESALab.cer -CertStoreLocation Cert:\LocalMachine\Root
     Import-Certificate -FilePath ESALab.cer -CertStoreLocation Cert:\LocalMachine\TrustedPublisher
====================================================================
#>

$ErrorActionPreference = "Stop"

# -------- Configuracion --------
$Publisher = "ESALab"                                   # nombre que vera el usuario
$TimeStampServer = "http://timestamp.digicert.com"      # sella la fecha de la firma
# -------------------------------

# --- Comprobar que se ejecuta como Administrador (imprescindible) ---
$isAdmin = ([Security.Principal.WindowsPrincipal]`
    [Security.Principal.WindowsIdentity]::GetCurrent()`
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: este script debe ejecutarse COMO ADMINISTRADOR." -ForegroundColor Red
    Write-Host "Sin admin, el certificado no se puede instalar como raiz de confianza y" -ForegroundColor Red
    Write-Host "Windows seguira mostrando 'Editor desconocido'." -ForegroundColor Red
    Write-Host "Abre PowerShell con clic derecho > 'Ejecutar como administrador' y repite." -ForegroundColor Yellow
    exit 1
}

$Root    = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ExePath = Join-Path $Root "dist\InstaladorAgente.exe"
$CerPath = Join-Path $Root "$Publisher.cer"

if (-not (Test-Path $ExePath)) {
    throw "No existe $ExePath. Ejecuta primero build.ps1 para generar el .exe."
}

# 1) Buscar un certificado ESALab ya existente, o crearlo
$cert = Get-ChildItem Cert:\CurrentUser\My |
        Where-Object { $_.Subject -eq "CN=$Publisher" -and $_.HasPrivateKey } |
        Sort-Object NotAfter -Descending | Select-Object -First 1

if (-not $cert) {
    Write-Host "Creando certificado de firma de codigo '$Publisher'..." -ForegroundColor Yellow
    $cert = New-SelfSignedCertificate `
        -Type CodeSigningCert `
        -Subject "CN=$Publisher" `
        -FriendlyName "$Publisher Code Signing" `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -KeyExportPolicy Exportable `
        -KeyUsage DigitalSignature `
        -NotAfter (Get-Date).AddYears(5)
    Write-Host "Certificado creado. Huella: $($cert.Thumbprint)" -ForegroundColor Green
} else {
    Write-Host "Usando certificado existente. Huella: $($cert.Thumbprint)" -ForegroundColor Green
}

# 2) Exportar la parte publica e instalar como confiable en este equipo
Export-Certificate -Cert $cert -FilePath $CerPath -Force | Out-Null
Write-Host "Certificado publico exportado: $CerPath" -ForegroundColor Green

function Trust-Store($store) {
    try {
        Import-Certificate -FilePath $CerPath -CertStoreLocation $store | Out-Null
        Write-Host "  Confiado en: $store" -ForegroundColor Green
    } catch {
        Write-Host "  No se pudo instalar en $store (¿ejecutas como administrador?): $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}
Write-Host "Instalando confianza en este equipo..." -ForegroundColor Yellow
Trust-Store "Cert:\LocalMachine\Root"
Trust-Store "Cert:\LocalMachine\TrustedPublisher"

# 3) Firmar el ejecutable
Write-Host "Firmando $ExePath ..." -ForegroundColor Yellow
$sig = Set-AuthenticodeSignature -FilePath $ExePath -Certificate $cert -TimeStampServer $TimeStampServer -HashAlgorithm SHA256
if ($sig.Status -ne "Valid") {
    throw "La firma no quedo valida. Estado: $($sig.Status) - $($sig.StatusMessage)"
}

# 4) Verificacion final: firma valida + certificado en la raiz de confianza
$check = Get-AuthenticodeSignature -FilePath $ExePath
$inRoot = Get-ChildItem Cert:\LocalMachine\Root |
          Where-Object { $_.Thumbprint -eq $cert.Thumbprint }

Write-Host ""
Write-Host "=== RESULTADO ===" -ForegroundColor Cyan
Write-Host ("Estado de la firma : {0}" -f $check.Status)
if ($inRoot) {
    Write-Host "Certificado en raiz de confianza (LocalMachine\Root): SI" -ForegroundColor Green
} else {
    Write-Host "Certificado en raiz de confianza (LocalMachine\Root): NO" -ForegroundColor Red
    Write-Host "=> Por eso Windows sigue mostrando 'Editor desconocido'." -ForegroundColor Red
}

if ($check.Status -eq "Valid" -and $inRoot) {
    Write-Host ""
    Write-Host "OK. El .exe muestra el editor: $Publisher" -ForegroundColor Green
    Write-Host "Cierra cualquier ventana del instalador ya abierta y vuelve a ejecutarlo." -ForegroundColor Gray
    Write-Host "Para otros equipos, distribuye e instala: $CerPath" -ForegroundColor Gray
} else {
    Write-Host ""
    Write-Host "Aun no esta correcto. Revisa los mensajes de arriba." -ForegroundColor Yellow
}
