<#
=====================================================================
 Instalador-Suricata-Windows.ps1   (AlsisGuard)
 Instalador automatico de Suricata como sensor IDS integrado con Wazuh.

 DOS MODOS:
   - GUI (sin parametros):  ventana grafica para elegir opciones.
       .\Instalador-Suricata-Windows.ps1
   - Silencioso (desatendido, para desplegar en varios equipos):
       .\Instalador-Suricata-Windows.ps1 -Silent -InterfaceName "Wi-Fi"

 QUE HACE:
   1. Instala Npcap (si falta) y Suricata (MSI, silencioso)
   2. Descarga el ruleset Emerging Threats (recortado para PYME)
   3. Filtra reglas incompatibles con Windows (file.magic)
   4. Configura HOME_NET, interfaz y salida EVE JSON
   5. Configura el agente Wazuh para leer el eve.json
   6. Deja Suricata en autostart (tarea programada) y lo arranca

 NOTA sobre Npcap: la version gratuita NO permite instalacion
 silenciosa (solo la OEM de pago). Si Npcap no esta instalado, se
 lanza su instalador grafico con las opciones ya marcadas y hay que
 pulsar un par de veces. Si ya esta instalado, se detecta y se salta.

 Ejecutar SIEMPRE como Administrador.
=====================================================================
#>

param(
    [switch]$Silent,
    [string]$InterfaceName,
    [string]$HomeNet,                       # opcional; si se omite se autodetecta
    [string]$SuricataMsiUrl = "https://download.openinfosecfoundation.org/download/windows/Suricata-8.0.6-1-64bit.msi",
    [string]$NpcapUrl       = "https://npcap.com/dist/npcap-1.79.exe"
)

# ---------------- Rutas y constantes --------------------------------
$SuricataDir  = "C:\Program Files\Suricata"
$SuricataExe  = Join-Path $SuricataDir "suricata.exe"
$SuricataYaml = Join-Path $SuricataDir "suricata.yaml"
$RulesDir     = Join-Path $SuricataDir "rules"
$LocalRules   = Join-Path $RulesDir "local.rules"
$OutRules     = Join-Path $RulesDir "suricata.rules"
$SuricataLog  = Join-Path $SuricataDir "log\eve.json"
$AgentConf    = "C:\Program Files (x86)\ossec-agent\ossec.conf"
$TaskName     = "Suricata-IDS"
$Tmp          = Join-Path $env:TEMP "alsisguard-suricata"

$disabledGroups = @('emerging-games','emerging-chat','emerging-p2p',
                    'emerging-inappropriate','emerging-policy','emerging-info','emerging-icmp_info')
$unsupportedKeywords = @('file.magic')
$etUrls = @(
    "https://rules.emergingthreats.net/open/suricata-8.0/emerging.rules.tar.gz",
    "https://rules.emergingthreats.net/open/suricata-7.0.3/emerging.rules.tar.gz",
    "https://rules.emergingthreats.net/open/suricata/emerging.rules.tar.gz"
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"
$script:Log = New-Object System.Collections.Generic.List[string]

function Say($m,$c="Gray"){ Write-Host $m -ForegroundColor $c; $script:Log.Add($m) }
function Info($m){ Say "[INFO ] $m" "Cyan" }
function Ok($m){   Say "[  OK ] $m" "Green" }
function Warn($m){ Say "[WARN ] $m" "Yellow" }
function Fail($m){ Say "[FALLO] $m" "Red" }
function Write-NoBom($p,$t){ [System.IO.File]::WriteAllText($p,$t,(New-Object System.Text.UTF8Encoding($false))) }

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------- Calcular subred de una interfaz -------------------
function Get-CidrForAdapter($adapter) {
    $ipInfo = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
              Where-Object { $_.IPAddress -notlike '169.254*' } | Select-Object -First 1
    if (-not $ipInfo) { return $null }
    $ipBytes = [System.Net.IPAddress]::Parse($ipInfo.IPAddress).GetAddressBytes()
    $prefix  = $ipInfo.PrefixLength
    $net = New-Object 'System.Byte[]' 4
    for ($i=0;$i -lt 4;$i++){
        $bits = [math]::Min(8,[math]::Max(0,$prefix-($i*8)))
        $mask = ((0xFF -shl (8-$bits)) -band 0xFF)
        $net[$i] = [byte]($ipBytes[$i] -band $mask)
    }
    return "$($net -join '.')/$prefix"
}

# ---------------- Pasos de instalacion ------------------------------
function Ensure-Npcap {
    if (Get-Service npcap -ErrorAction SilentlyContinue) { Ok "Npcap ya instalado"; return $true }
    Info "Npcap no encontrado. Descargando..."
    $npf = Join-Path $Tmp "npcap.exe"
    try { Invoke-WebRequest -Uri $NpcapUrl -OutFile $npf -UseBasicParsing }
    catch { Fail "No pude descargar Npcap: $($_.Exception.Message)"; return $false }
    Warn "Npcap gratuito NO admite instalacion silenciosa: se abrira su ventana."
    Warn "Deja marcada la opcion 'WinPcap API-compatible Mode' y pulsa Install/Next."
    # winpcap_mode enforced para que quede compatible; el resto por GUI
    $p = Start-Process -FilePath $npf -ArgumentList "/winpcap_mode=enforced" -Wait -PassThru
    Start-Sleep 3
    if (Get-Service npcap -ErrorAction SilentlyContinue) { Ok "Npcap instalado"; return $true }
    Fail "Npcap no quedo instalado."; return $false
}

function Ensure-Suricata {
    if (Test-Path $SuricataExe) { Ok "Suricata ya instalado"; return $true }
    Info "Descargando Suricata MSI..."
    $msi = Join-Path $Tmp "suricata.msi"
    try { Invoke-WebRequest -Uri $SuricataMsiUrl -OutFile $msi -UseBasicParsing }
    catch { Fail "No pude descargar el MSI de Suricata: $($_.Exception.Message)"; return $false }
    Info "Instalando Suricata en silencio (msiexec /qn)..."
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait -PassThru
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { Fail "msiexec devolvio $($p.ExitCode)"; return $false }
    if (Test-Path $SuricataExe) { Ok "Suricata instalado"; return $true }
    Fail "Suricata no quedo instalado."; return $false
}

function Get-ETRules {
    Info "Descargando ruleset Emerging Threats..."
    $tgz = Join-Path $Tmp "emerging.rules.tar.gz"
    $done = $false
    foreach ($u in $etUrls) {
        try {
            Invoke-WebRequest -Uri $u -OutFile $tgz -UseBasicParsing -ErrorAction Stop
            if ((Get-Item $tgz).Length -gt 100000) { Ok "Descargado de $u"; $done=$true; break }
        } catch { Warn "No disponible: $u" }
    }
    if (-not $done) { Fail "No pude descargar el ruleset ET"; return $false }

    $ex = Join-Path $Tmp "et"
    Remove-Item $ex -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $ex | Out-Null
    tar -xzf $tgz -C $ex
    $src = Join-Path $ex "rules"; if (-not (Test-Path $src)) { $src = $ex }
    $files = @(Get-ChildItem (Join-Path $src "*.rules") -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) { Fail "No hay ficheros .rules tras extraer"; return $false }

    if (-not (Test-Path $RulesDir)) { New-Item -ItemType Directory -Path $RulesDir | Out-Null }
    if (Test-Path $OutRules) { Remove-Item $OutRules -Force }
    $kept=0; $dropped=0
    $sw = New-Object System.IO.StreamWriter($OutRules,$false,(New-Object System.Text.UTF8Encoding($false)))
    foreach ($rf in $files) {
        if ($disabledGroups -contains $rf.BaseName) { continue }
        foreach ($line in [System.IO.File]::ReadAllLines($rf.FullName)) {
            $bad=$false; foreach($kw in $unsupportedKeywords){ if($line -like "*$kw*"){$bad=$true;break} }
            if ($bad) { $dropped++; continue }
            $sw.WriteLine($line)
        }
        $kept++
    }
    $sw.Close()
    foreach ($cfg in @("classification.config","reference.config")) {
        $s = Join-Path $src $cfg
        if (Test-Path $s) { Copy-Item $s (Join-Path $SuricataDir $cfg) -Force }
    }
    Ok "Reglas ET listas ($kept categorias; descartadas $dropped incompatibles)"
    return $true
}

function Configure-Yaml($cidr) {
    Copy-Item $SuricataYaml "$SuricataYaml.bak" -Force
    $y = Get-Content $SuricataYaml -Raw
    # HOME_NET
    if ($y -match '(?m)^\s*HOME_NET:\s*.*$') {
        $y = $y -replace '(?m)^(\s*)HOME_NET:\s*.*$', "`$1HOME_NET: `"[$cidr]`""
    }
    # regla de prueba
    if (-not (Test-Path $LocalRules) -or ((Get-Content $LocalRules -Raw) -notmatch 'sid:1000001')) {
        [System.IO.File]::AppendAllText($LocalRules,
            'alert icmp any any -> any any (msg:"SURICATA TEST - ICMP"; sid:1000001; rev:1;)'+"`r`n",
            (New-Object System.Text.UTF8Encoding($false)))
    }
    # enlazar local.rules y suricata.rules respetando indentacion
    if ($y -match '(?m)^(?<ind>[^\S\r\n]*)rule-files:[^\S\r\n]*\r?\n(?<e>[^\S\r\n]*)-') {
        $ind = $Matches['e']
        $y = $y -replace '(?ms)(^[^\S\r\n]*rule-files:[^\S\r\n]*\r?\n)(?:[^\S\r\n]*-[^\r\n]*\r?\n)+',
                         "`$1$ind- local.rules`r`n$ind- suricata.rules`r`n"
    }
    Write-NoBom $SuricataYaml $y
    Ok "suricata.yaml configurado (HOME_NET=$cidr, reglas enlazadas)"
}

function Configure-Agent {
    if (-not (Test-Path $AgentConf)) { Warn "Agente Wazuh no encontrado; omito integracion."; return }
    $c = Get-Content $AgentConf -Raw
    if ($c -match [regex]::Escape('Suricata\log\eve.json')) { Info "Agente ya lee el eve.json"; return }
    Copy-Item $AgentConf "$AgentConf.bak" -Force
    $block = "  <localfile>`r`n    <log_format>json</log_format>`r`n    <location>$SuricataLog</location>`r`n  </localfile>"
    $idx = $c.LastIndexOf("</ossec_config>")
    if ($idx -lt 0) { Warn "ossec.conf sin </ossec_config>; revisar a mano."; return }
    $c = $c.Substring(0,$idx) + $block + "`r`n" + $c.Substring($idx)
    Write-NoBom $AgentConf $c
    $svc = Get-Service -Name 'WazuhSvc','Wazuh','OssecSvc' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($svc) { Restart-Service $svc.Name -Force; Ok "Agente Wazuh configurado y reiniciado" }
    else { Ok "Agente configurado (reinicia el servicio Wazuh manualmente)" }
}

function Setup-Autostart($device) {
    Get-Process suricata -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep 2
    $arg = "-c `"$SuricataYaml`" -i `"$device`""
    $a = New-ScheduledTaskAction -Execute $SuricataExe -Argument $arg -WorkingDirectory $SuricataDir
    $t = New-ScheduledTaskTrigger -AtStartup
    $pr = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
    Register-ScheduledTask -TaskName $TaskName -Action $a -Trigger $t -Principal $pr -Settings $s -Force | Out-Null
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep 5
    if (Get-Process suricata -ErrorAction SilentlyContinue) { Ok "Suricata en ejecucion + autostart configurado" }
    else { Warn "Suricata no arranco; revisa $SuricataDir\log\suricata.log" }
}

# ---------------- Orquestacion --------------------------------------
function Run-Install($adapter,$cidr) {
    New-Item -ItemType Directory -Path $Tmp -Force | Out-Null
    if (-not (Ensure-Npcap))    { return $false }
    if (-not (Ensure-Suricata)) { return $false }
    if (-not (Get-ETRules))     { return $false }
    Configure-Yaml $cidr
    Info "Validando configuracion..."
    & $SuricataExe -T -c $SuricataYaml | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "La configuracion no valida (-T). Revisa el log."; return $false }
    Ok "Configuracion valida"
    Configure-Agent
    $device = "\Device\NPF_$($adapter.InterfaceGuid)"
    Setup-Autostart $device
    Ok "INSTALACION COMPLETADA"
    return $true
}

# ---------------- Seleccion de interfaz (comun) ---------------------
function Get-Adapters { @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }) }

# =====================================================================
#  MODO SILENCIOSO
# =====================================================================
if ($Silent) {
    if (-not (Test-Admin)) { Fail "Ejecuta como Administrador."; exit 1 }
    $ads = Get-Adapters
    if ($ads.Count -eq 0) { Fail "No hay interfaces activas."; exit 1 }
    if ($InterfaceName) {
        $adapter = $ads | Where-Object { $_.Name -eq $InterfaceName } | Select-Object -First 1
        if (-not $adapter) { Fail "No hay interfaz '$InterfaceName'. Activas: $($ads.Name -join ', ')"; exit 1 }
    } else { $adapter = $ads[0]; Warn "Sin -InterfaceName; uso la primera activa: $($adapter.Name)" }
    $cidr = if ($HomeNet) { $HomeNet } else { Get-CidrForAdapter $adapter }
    if (-not $cidr) { Fail "No pude determinar la subred; pasa -HomeNet."; exit 1 }
    if (Run-Install $adapter $cidr) { exit 0 } else { exit 1 }
}

# =====================================================================
#  MODO GUI (WinForms)
# =====================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not (Test-Admin)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Debes ejecutar este instalador como Administrador.",
        "AlsisGuard - Suricata",'OK','Error') | Out-Null
    exit 1
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "AlsisGuard - Instalador de Suricata"
$form.Size = New-Object System.Drawing.Size(560,440)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"; $form.MaximizeBox = $false

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "Instalador de Suricata (sensor IDS para Wazuh)"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI",11,[System.Drawing.FontStyle]::Bold)
$lblTitle.Location = '20,15'; $lblTitle.Size = '520,25'
$form.Controls.Add($lblTitle)

$lblIf = New-Object System.Windows.Forms.Label
$lblIf.Text = "Interfaz de red a monitorizar:"
$lblIf.Location = '20,55'; $lblIf.Size = '250,20'
$form.Controls.Add($lblIf)

$cmb = New-Object System.Windows.Forms.ComboBox
$cmb.Location = '20,78'; $cmb.Size = '500,24'; $cmb.DropDownStyle = "DropDownList"
$adapters = Get-Adapters
foreach ($a in $adapters) {
    $cidr = Get-CidrForAdapter $a
    $cmb.Items.Add("$($a.Name)  |  $cidr  |  $($a.InterfaceDescription)") | Out-Null
}
if ($cmb.Items.Count -gt 0) { $cmb.SelectedIndex = 0 }
$form.Controls.Add($cmb)

$lblInfo = New-Object System.Windows.Forms.Label
$lblInfo.Text = "El instalador hara: Npcap (si falta) + Suricata (MSI) + reglas ET recortadas + integracion con el agente Wazuh + autostart. HOME_NET se detecta de la interfaz elegida."
$lblInfo.Location = '20,115'; $lblInfo.Size = '510,55'
$form.Controls.Add($lblInfo)

$txt = New-Object System.Windows.Forms.TextBox
$txt.Location = '20,180'; $txt.Size = '510,160'
$txt.Multiline = $true; $txt.ScrollBars = "Vertical"; $txt.ReadOnly = $true
$txt.Font = New-Object System.Drawing.Font("Consolas",8)
$form.Controls.Add($txt)

$btn = New-Object System.Windows.Forms.Button
$btn.Text = "Instalar"; $btn.Location = '20,355'; $btn.Size = '120,30'
$form.Controls.Add($btn)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Cerrar"; $btnClose.Location = '410,355'; $btnClose.Size = '120,30'
$btnClose.Add_Click({ $form.Close() })
$form.Controls.Add($btnClose)

$btn.Add_Click({
    if ($cmb.SelectedIndex -lt 0) {
        [System.Windows.Forms.MessageBox]::Show("Selecciona una interfaz.","AlsisGuard",'OK','Warning') | Out-Null
        return
    }
    $btn.Enabled = $false; $cmb.Enabled = $false
    $adapter = $adapters[$cmb.SelectedIndex]
    $cidr = Get-CidrForAdapter $adapter
    $script:Log.Clear()
    $txt.Text = "Instalando... esto puede tardar varios minutos (descargas)." + [Environment]::NewLine
    $form.Refresh()
    try {
        $okAll = Run-Install $adapter $cidr
    } catch { Fail "Error inesperado: $($_.Exception.Message)"; $okAll = $false }
    $txt.Text = ($script:Log -join [Environment]::NewLine)
    $txt.SelectionStart = $txt.Text.Length; $txt.ScrollToCaret()
    if ($okAll) {
        [System.Windows.Forms.MessageBox]::Show("Instalacion completada. Suricata corre y arranca con Windows.","AlsisGuard",'OK','Information') | Out-Null
    } else {
        [System.Windows.Forms.MessageBox]::Show("La instalacion no se completo. Revisa el registro en la ventana.","AlsisGuard",'OK','Error') | Out-Null
    }
    $btn.Enabled = $true; $cmb.Enabled = $true
})

[void]$form.ShowDialog()
