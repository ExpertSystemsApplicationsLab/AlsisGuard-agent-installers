using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace WazuhAgentInstaller
{
    public class MainForm : Form
    {
        // Nombre del recurso embebido con el MSI del agente Wazuh.
        private const string MsiResourceName = "wazuh-agent.msi";
        // Nombre del servicio Windows del agente Wazuh.
        private const string ServiceName = "WazuhSvc";
        // GUID de la subcategoria "Inicio de sesion" (evento 4625). Funciona en
        // cualquier idioma de Windows.
        private const string AuditLogonGuid = "{0CCE9215-69AE-11D9-BED3-505054503030}";

        private readonly string _baseDir;
        private readonly Branding _brand;

        private TextBox txtIp;
        private TextBox txtName;
        private CheckBox chkFim;
        private TextBox txtFimFolders;
        private TextBox txtLog;
        private Button btnInstall;
        private Label lblStatus;
        private ProgressBar progress;

        public MainForm()
        {
            _baseDir = AppDomain.CurrentDomain.BaseDirectory;
            _brand = Branding.Load(_baseDir);
            BuildUi();
        }

        private void BuildUi()
        {
            Text = _brand.ProductTitle + " - " + _brand.CompanyName;
            StartPosition = FormStartPosition.CenterScreen;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            ClientSize = new Size(560, 660);
            BackColor = Color.White;
            Font = new Font("Segoe UI", 9F);
            try
            {
                using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("app.ico"))
                    if (s != null) Icon = new Icon(s);
            }
            catch { }

            // ----- Cabecera (fondo claro por defecto para que se vea el logo) -----
            bool lightHeader = _brand.HeaderIsLight;
            Color titleColor = lightHeader ? _brand.Primary : Color.White;
            Color subColor = lightHeader ? Color.FromArgb(110, 120, 130) : _brand.Accent;

            var header = new Panel { Dock = DockStyle.Top, Height = 130, BackColor = _brand.Header };
            Controls.Add(header);

            var accentStrip = new Panel { Dock = DockStyle.Bottom, Height = 4, BackColor = _brand.Accent };
            header.Controls.Add(accentStrip);

            var pic = new PictureBox
            {
                SizeMode = PictureBoxSizeMode.Zoom,
                Location = new Point(20, 20),
                Size = new Size(200, 88),
                BackColor = Color.Transparent
            };
            var logo = _brand.LoadLogo(_baseDir);
            if (logo != null) pic.Image = logo;
            header.Controls.Add(pic);

            var lblTitle = new Label
            {
                Text = _brand.CompanyName,
                ForeColor = titleColor,
                Font = new Font("Segoe UI Semibold", 15F, FontStyle.Bold),
                AutoSize = true,
                Location = new Point(235, 35),
                BackColor = Color.Transparent
            };
            header.Controls.Add(lblTitle);

            var lblSub = new Label
            {
                Text = _brand.Subtitle,
                ForeColor = subColor,
                Font = new Font("Segoe UI", 10F),
                AutoSize = true,
                Location = new Point(237, 70),
                BackColor = Color.Transparent
            };
            header.Controls.Add(lblSub);

            int x = 30, y = 148, w = 500;

            AddLabel(_brand.ManagerLabel + " *", x, y);
            txtIp = new TextBox { Location = new Point(x, y + 22), Width = w, Font = new Font("Segoe UI", 11F) };
            txtIp.Text = _brand.DefaultManagerIp;
            if (_brand.LockManagerIp && !string.IsNullOrEmpty(_brand.DefaultManagerIp))
                txtIp.ReadOnly = true;
            Controls.Add(txtIp);
            y += 66;

            AddLabel("Nombre del agente (opcional, por defecto el del equipo)", x, y);
            txtName = new TextBox { Location = new Point(x, y + 22), Width = w, Font = new Font("Segoe UI", 11F) };
            txtName.Text = Environment.MachineName;
            Controls.Add(txtName);
            y += 62;

            // ----- Opcion: carpetas extra a vigilar por FIM -----
            chkFim = new CheckBox
            {
                Text = "Vigilar carpetas extra con FIM (integridad de archivos)",
                Location = new Point(x, y),
                Width = w,
                AutoSize = true,
                ForeColor = _brand.Primary,
                Font = new Font("Segoe UI Semibold", 9.5F, FontStyle.Bold)
            };
            chkFim.CheckedChanged += (s, e) => { txtFimFolders.Enabled = chkFim.Checked; };
            Controls.Add(chkFim);
            y += 26;

            txtFimFolders = new TextBox
            {
                Location = new Point(x, y),
                Width = w,
                Height = 56,
                Multiline = true,
                Enabled = false,
                ScrollBars = ScrollBars.Vertical,
                Font = new Font("Consolas", 9F)
            };
            Controls.Add(txtFimFolders);
            y += 60;

            var lblFimHint = new Label
            {
                Text = "Una carpeta por linea. Ej: C:\\datos   D:\\compartida",
                Location = new Point(x, y),
                Width = w,
                ForeColor = Color.Gray,
                Font = new Font("Segoe UI", 8F)
            };
            Controls.Add(lblFimHint);
            y += 24;

            btnInstall = new Button
            {
                Text = "Instalar y configurar agente",
                Location = new Point(x, y),
                Width = w,
                Height = 42,
                FlatStyle = FlatStyle.Flat,
                BackColor = _brand.Accent,
                ForeColor = _brand.Primary,
                Font = new Font("Segoe UI Semibold", 11F, FontStyle.Bold),
                Cursor = Cursors.Hand
            };
            btnInstall.FlatAppearance.BorderSize = 0;
            btnInstall.Click += OnInstallClick;
            Controls.Add(btnInstall);
            y += 52;

            progress = new ProgressBar
            {
                Location = new Point(x, y),
                Width = w,
                Height = 16,
                Style = ProgressBarStyle.Marquee,
                MarqueeAnimationSpeed = 0,
                Visible = false
            };
            Controls.Add(progress);
            y += 22;

            lblStatus = new Label
            {
                Location = new Point(x, y),
                Width = w,
                Height = 20,
                ForeColor = _brand.Primary,
                Font = new Font("Segoe UI", 9F, FontStyle.Bold)
            };
            Controls.Add(lblStatus);
            y += 24;

            txtLog = new TextBox
            {
                Location = new Point(x, y),
                Width = w,
                Height = 120,
                Multiline = true,
                ReadOnly = true,
                ScrollBars = ScrollBars.Vertical,
                BackColor = Color.FromArgb(245, 247, 250),
                Font = new Font("Consolas", 8.5F)
            };
            Controls.Add(txtLog);
            y += 126;

            var lblSupport = new Label
            {
                Text = string.IsNullOrEmpty(_brand.SupportText)
                    ? "Requiere ejecutarse como Administrador."
                    : _brand.SupportText,
                Location = new Point(x, y),
                Width = w,
                ForeColor = Color.Gray,
                Font = new Font("Segoe UI", 8F)
            };
            Controls.Add(lblSupport);
        }

        private void AddLabel(string text, int x, int y)
        {
            Controls.Add(new Label
            {
                Text = text,
                Location = new Point(x, y),
                AutoSize = true,
                ForeColor = _brand.Primary,
                Font = new Font("Segoe UI Semibold", 9.5F, FontStyle.Bold)
            });
        }

        private void Log(string msg)
        {
            if (txtLog.InvokeRequired) { txtLog.BeginInvoke(new Action<string>(Log), msg); return; }
            txtLog.AppendText("[" + DateTime.Now.ToString("HH:mm:ss") + "] " + msg + Environment.NewLine);
        }

        private void SetStatus(string msg, Color c)
        {
            if (lblStatus.InvokeRequired) { lblStatus.BeginInvoke(new Action<string, Color>(SetStatus), msg, c); return; }
            lblStatus.Text = msg; lblStatus.ForeColor = c;
        }

        private void SetBusy(bool busy)
        {
            if (InvokeRequired) { BeginInvoke(new Action<bool>(SetBusy), busy); return; }
            btnInstall.Enabled = !busy;
            txtIp.Enabled = !busy && !(_brand.LockManagerIp && !string.IsNullOrEmpty(_brand.DefaultManagerIp));
            txtName.Enabled = !busy;
            chkFim.Enabled = !busy;
            txtFimFolders.Enabled = !busy && chkFim.Checked;
            progress.Visible = busy;
            progress.MarqueeAnimationSpeed = busy ? 30 : 0;
        }

        private void OnInstallClick(object sender, EventArgs e)
        {
            string ip = (txtIp.Text ?? "").Trim();
            string name = (txtName.Text ?? "").Trim();
            string[] fim = chkFim.Checked ? (txtFimFolders.Text ?? "").Split(new[] { '\r', '\n' },
                              StringSplitOptions.RemoveEmptyEntries) : new string[0];

            if (string.IsNullOrEmpty(ip))
            {
                MessageBox.Show(this, "Introduce la IP o dominio del Wazuh Manager.",
                    "Falta la IP", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                txtIp.Focus();
                return;
            }
            if (!IsAdministrator())
            {
                MessageBox.Show(this,
                    "Este instalador debe ejecutarse como Administrador.\n\n" +
                    "Cierra la aplicacion y vuelve a abrirla con clic derecho > 'Ejecutar como administrador'.",
                    "Permisos insuficientes", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            SetBusy(true);
            SetStatus("Instalando...", _brand.Primary);
            var t = new Thread(() => RunInstall(ip, name, fim));
            t.IsBackground = true;
            t.Start();
        }

        private void RunInstall(string ip, string name, string[] fimFolders)
        {
            try
            {
                string msiPath = ExtractMsi();
                Log("MSI preparado en: " + msiPath);

                // 1) Ver el estado actual del equipo.
                bool folder = InstallDir() != null;
                bool service = ServiceExists();

                if (folder && service)
                {
                    if (!AskYesNo(
                            "Ya hay un agente instalado en este equipo.\n\n" +
                            "Se desinstalara el actual y se instalara de nuevo apuntando a " + ip + ".\n\n" +
                            "¿Continuar?",
                            "Agente ya instalado"))
                    {
                        Log("Operacion cancelada por el usuario.");
                        SetStatus("Cancelado.", _brand.Primary);
                        return;
                    }
                    CleanUninstall(msiPath);
                }
                else if (folder || service)
                {
                    Log("Detectados restos de una instalacion anterior. Limpiando automaticamente...");
                    CleanUninstall(msiPath);
                }

                // 2) Instalar. Si falla, limpiar los restos y reintentar UNA vez.
                int code = InstallMsi(msiPath, ip, name);
                if (code != 0 && code != 3010)
                {
                    Log("La instalacion fallo (codigo " + code + "). Limpiando restos y reintentando...");
                    CleanUninstall(msiPath);
                    code = InstallMsi(msiPath, ip, name);
                }
                if (code != 0 && code != 3010)
                {
                    throw new Exception(
                        "La instalacion del agente fallo (codigo " + code + ") incluso tras limpiar.\n\n" +
                        "Revisa las lineas de error del registro de la ventana.\n" +
                        "Causas posibles: un antivirus/EDR bloqueando el servicio, o falta de permisos.");
                }

                Log("Iniciando servicio " + ServiceName + "...");
                RunProcess("net.exe", "start " + ServiceName); // dispara el enrolamiento

                // Borra solo la copia temporal del MSI.
                if (msiPath.StartsWith(Path.GetTempPath(), StringComparison.OrdinalIgnoreCase))
                    try { File.Delete(msiPath); } catch { }

                // 3) Dejar el equipo listo para respuesta activa (AR, auditoria,
                //    Suricata, FIM extra) y reiniciar el servicio.
                Provision(ip, fimFolders);

                // 4) Test de conectividad con el manager (avisa si la IP es incorrecta).
                PortTest(ip);

                SetStatus("Instalacion y configuracion completadas.", Color.FromArgb(0, 128, 0));
                Log("Agente instalado, configurado y apuntando al manager " + ip + ".");
                Invoke(new Action(() => MessageBox.Show(this,
                    "El agente se instalo y configuro correctamente:\n" +
                    " - Registrado en el grupo '" + _brand.AgentGroup + "'\n" +
                    " - Respuesta activa lista (bloqueo de IP y borrado de amenazas)\n" +
                    " - Auditoria de logins fallidos (4625) habilitada\n" +
                    " - Recoleccion de Suricata configurada\n\n" +
                    "Manager: " + ip + "\n\n" +
                    "Revisa el registro de la ventana para ver el detalle y el test de puertos.",
                    "Instalacion completada", MessageBoxButtons.OK, MessageBoxIcon.Information)));
            }
            catch (Exception ex)
            {
                SetStatus("Error en la instalacion.", Color.FromArgb(178, 34, 34));
                Log("ERROR: " + ex.Message);
                Invoke(new Action(() => MessageBox.Show(this,
                    "No se pudo completar la instalacion:\n\n" + ex.Message,
                    "Error", MessageBoxButtons.OK, MessageBoxIcon.Error)));
            }
            finally
            {
                SetBusy(false);
            }
        }

        // ================== PROVISION (respuesta activa + monitorizacion) ==================

        private void Provision(string ip, string[] fimFolders)
        {
            string dir = InstallDir();
            if (dir == null)
            {
                Log("Aviso: no se encuentra la carpeta del agente; se omite la configuracion.");
                return;
            }

            Log("Configurando respuesta activa y monitorizacion...");

            // Copiar los binarios de respuesta activa a active-response\bin
            CopyActiveResponse(dir);

            // Habilitar auditoria de inicios de sesion fallidos (evento 4625)
            Log("Habilitando auditoria de inicios de sesion fallidos (4625)...");
            int ap = RunProcess("auditpol.exe",
                "/set /subcategory:\"" + AuditLogonGuid + "\" /failure:enable");
            Log("auditpol finalizo con codigo " + ap);

            // ossec.conf: recoleccion de Suricata + carpetas FIM extra
            PatchOssecConf(dir, fimFolders);

            // Reiniciar el servicio para aplicar la configuracion
            Log("Reiniciando servicio " + ServiceName + " para aplicar la configuracion...");
            RunProcessQuiet("net.exe", "stop " + ServiceName);
            Thread.Sleep(2000);
            RunProcess("net.exe", "start " + ServiceName);
        }

        // Copia los .exe de respuesta activa (embebidos) a active-response\bin.
        private void CopyActiveResponse(string agentDir)
        {
            var names = ReadArManifest();
            if (names.Count == 0)
            {
                Log("Aviso: no hay binarios de respuesta activa embebidos (se omite la copia).");
                return;
            }
            string binDir = Path.Combine(agentDir, @"active-response\bin");
            try { Directory.CreateDirectory(binDir); } catch { }

            var asm = Assembly.GetExecutingAssembly();
            foreach (var n in names)
            {
                try
                {
                    using (var s = asm.GetManifestResourceStream("ar/" + n))
                    {
                        if (s == null) { Log("Aviso: recurso AR no encontrado: " + n); continue; }
                        string outp = Path.Combine(binDir, n);
                        using (var fs = new FileStream(outp, FileMode.Create, FileAccess.Write))
                            s.CopyTo(fs);
                        Log("Respuesta activa: copiado " + n);
                    }
                }
                catch (Exception ex) { Log("Aviso: no se pudo copiar " + n + ": " + ex.Message); }
            }
        }

        // Lee el manifiesto embebido con los nombres de los .exe de respuesta activa.
        private System.Collections.Generic.List<string> ReadArManifest()
        {
            var list = new System.Collections.Generic.List<string>();
            try
            {
                var asm = Assembly.GetExecutingAssembly();
                using (var s = asm.GetManifestResourceStream("ar-manifest.txt"))
                {
                    if (s == null) return list;
                    using (var r = new StreamReader(s))
                    {
                        string line;
                        while ((line = r.ReadLine()) != null)
                        {
                            line = line.Trim();
                            if (line.Length > 0) list.Add(line);
                        }
                    }
                }
            }
            catch { }
            return list;
        }

        // Anade al ossec.conf del agente la recoleccion de Suricata y las carpetas
        // FIM extra, sin duplicar si ya existen. Se anaden como bloques ossec_config
        // adicionales al final (Wazuh los combina).
        private void PatchOssecConf(string agentDir, string[] fimFolders)
        {
            string conf = Path.Combine(agentDir, "ossec.conf");
            if (!File.Exists(conf))
            {
                Log("Aviso: no se encontro ossec.conf; se omite su configuracion.");
                return;
            }

            string text;
            try { text = File.ReadAllText(conf); }
            catch (Exception ex) { Log("No se pudo leer ossec.conf: " + ex.Message); return; }

            var sb = new StringBuilder();

            // Recoleccion de Suricata (eve.json) si no esta ya presente.
            if (text.IndexOf("eve.json", StringComparison.OrdinalIgnoreCase) < 0)
            {
                sb.Append("\r\n<ossec_config>\r\n");
                sb.Append("  <localfile>\r\n");
                sb.Append("    <log_format>json</log_format>\r\n");
                sb.Append("    <location>").Append(_brand.SuricataEveLog).Append("</location>\r\n");
                sb.Append("  </localfile>\r\n");
                sb.Append("</ossec_config>\r\n");
                Log("ossec.conf: anadida recoleccion de Suricata (" + _brand.SuricataEveLog + ").");
            }
            else
            {
                Log("ossec.conf: Suricata ya presente (no se duplica).");
            }

            // Carpetas FIM extra.
            if (fimFolders != null && fimFolders.Length > 0)
            {
                var toAdd = new System.Collections.Generic.List<string>();
                foreach (var raw in fimFolders)
                {
                    string folder = (raw ?? "").Trim();
                    if (folder.Length == 0) continue;
                    if (text.IndexOf(folder, StringComparison.OrdinalIgnoreCase) >= 0)
                    {
                        Log("FIM: '" + folder + "' ya vigilada (no se duplica).");
                        continue;
                    }
                    if (!toAdd.Contains(folder)) toAdd.Add(folder);
                }
                if (toAdd.Count > 0)
                {
                    sb.Append("\r\n<ossec_config>\r\n  <syscheck>\r\n");
                    foreach (var folder in toAdd)
                    {
                        sb.Append("    <directories realtime=\"yes\" check_all=\"yes\">")
                          .Append(folder).Append("</directories>\r\n");
                        Log("FIM: vigilando en tiempo real " + folder);
                    }
                    sb.Append("  </syscheck>\r\n</ossec_config>\r\n");
                }
            }

            if (sb.Length > 0)
            {
                try { File.AppendAllText(conf, sb.ToString()); Log("ossec.conf actualizado."); }
                catch (Exception ex) { Log("No se pudo escribir ossec.conf: " + ex.Message); }
            }
        }

        // Comprueba si los puertos del manager estan accesibles (avisa si la IP falla).
        private void PortTest(string ip)
        {
            Log("Comprobando conectividad con el manager " + ip + " (puertos 1514/1515)...");
            bool p1514 = TestTcp(ip, 1514, 3000);
            bool p1515 = TestTcp(ip, 1515, 3000);
            Log("  Puerto 1514 (datos)    : " + (p1514 ? "accesible" : "NO accesible"));
            Log("  Puerto 1515 (registro) : " + (p1515 ? "accesible" : "NO accesible"));
            if (!p1514 || !p1515)
                Log("AVISO: revisa la IP del manager y el firewall. Si la IP es incorrecta, el agente no conectara.");
        }

        private static bool TestTcp(string host, int port, int timeoutMs)
        {
            try
            {
                using (var c = new System.Net.Sockets.TcpClient())
                {
                    var ar = c.BeginConnect(host, port, null, null);
                    bool ok = ar.AsyncWaitHandle.WaitOne(timeoutMs);
                    if (!ok) return false;
                    c.EndConnect(ar);
                    return c.Connected;
                }
            }
            catch { return false; }
        }

        // ================== INSTALACION / LIMPIEZA ==================

        // Extrae el MSI embebido a una carpeta temporal. Si no hay MSI embebido,
        // busca wazuh-agent.msi junto al .exe como alternativa.
        private string ExtractMsi()
        {
            string outPath = Path.Combine(Path.GetTempPath(), "wazuh-agent.msi");
            var asm = Assembly.GetExecutingAssembly();
            using (var s = asm.GetManifestResourceStream(MsiResourceName))
            {
                if (s != null)
                {
                    using (var fs = new FileStream(outPath, FileMode.Create, FileAccess.Write))
                        s.CopyTo(fs);
                    return outPath;
                }
            }
            string local = Path.Combine(_baseDir, "wazuh-agent.msi");
            if (File.Exists(local)) return local;

            throw new Exception("No se encontro el MSI del agente. Debe estar embebido en el .exe o " +
                                "situado como 'wazuh-agent.msi' junto al ejecutable.");
        }

        private static readonly string[] InstallDirs =
        {
            @"C:\Program Files (x86)\ossec-agent",
            @"C:\Program Files\ossec-agent"
        };

        private static string InstallDir()
        {
            foreach (var d in InstallDirs)
                if (Directory.Exists(d)) return d;
            return null;
        }

        private bool ServiceExists()
        {
            try { return RunProcessQuiet("sc.exe", "query " + ServiceName) == 0; }
            catch { return false; }
        }

        // Ejecuta la instalacion del MSI y devuelve el codigo de salida.
        // Registra el agente en el grupo configurado (por defecto "windows") para
        // recibir la configuracion FIM centralizada del manager.
        private int InstallMsi(string msiPath, string ip, string name)
        {
            string logPath = Path.Combine(Path.GetTempPath(), "wazuh-install.log");
            try { File.Delete(logPath); } catch { }

            var args = new StringBuilder();
            args.Append("/i \"").Append(msiPath).Append("\" /qn /norestart");
            args.Append(" /l*v \"").Append(logPath).Append("\"");
            args.Append(" WAZUH_MANAGER=\"").Append(ip).Append("\"");
            args.Append(" WAZUH_REGISTRATION_SERVER=\"").Append(ip).Append("\"");
            if (!string.IsNullOrEmpty(_brand.AgentGroup))
                args.Append(" WAZUH_AGENT_GROUP=\"").Append(_brand.AgentGroup).Append("\"");
            if (!string.IsNullOrEmpty(name))
                args.Append(" WAZUH_AGENT_NAME=\"").Append(name).Append("\"");

            Log("Ejecutando msiexec " + args);
            int code = RunProcess("msiexec.exe", args.ToString());
            Log("msiexec finalizo con codigo " + code);
            if (code != 0 && code != 3010)
            {
                DumpMsiError(logPath);
                Log("Log completo en: " + logPath);
            }
            return code;
        }

        // Desinstala por completo cualquier resto del agente.
        private void CleanUninstall(string msiPath)
        {
            Log("Limpiando instalacion previa del agente...");

            RunProcessQuiet("sc.exe", "stop " + ServiceName);
            Thread.Sleep(2000);

            string ulog = Path.Combine(Path.GetTempPath(), "wazuh-uninstall.log");
            RunProcessQuiet("msiexec.exe", "/x \"" + msiPath + "\" /qn /norestart /l*v \"" + ulog + "\"");

            foreach (string productCode in FindWazuhProductCodes())
            {
                Log("Desinstalando producto " + productCode + " ...");
                RunProcessQuiet("msiexec.exe", "/x " + productCode + " /qn /norestart");
            }

            RunProcessQuiet("sc.exe", "delete " + ServiceName);
            Thread.Sleep(1000);

            string dir = InstallDir();
            if (dir != null)
            {
                try { Directory.Delete(dir, true); Log("Carpeta eliminada: " + dir); }
                catch (Exception ex) { Log("Aviso: no se pudo eliminar " + dir + ": " + ex.Message); }
            }

            Log("Limpieza completada.");
        }

        private System.Collections.Generic.List<string> FindWazuhProductCodes()
        {
            var list = new System.Collections.Generic.List<string>();
            string[] roots =
            {
                @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
                @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
            };
            foreach (var root in roots)
            {
                try
                {
                    using (var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(root))
                    {
                        if (key == null) continue;
                        foreach (var sub in key.GetSubKeyNames())
                        {
                            try
                            {
                                using (var k = key.OpenSubKey(sub))
                                {
                                    if (k == null) continue;
                                    var name = k.GetValue("DisplayName") as string;
                                    if (!string.IsNullOrEmpty(name) &&
                                        name.IndexOf("Wazuh", StringComparison.OrdinalIgnoreCase) >= 0 &&
                                        sub.StartsWith("{") && sub.EndsWith("}") &&
                                        !list.Contains(sub))
                                    {
                                        list.Add(sub);
                                    }
                                }
                            }
                            catch { }
                        }
                    }
                }
                catch { }
            }
            return list;
        }

        private bool AskYesNo(string message, string title)
        {
            bool result = false;
            Invoke(new Action(() =>
            {
                result = MessageBox.Show(this, message, title,
                    MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes;
            }));
            return result;
        }

        private int RunProcessQuiet(string file, string arguments)
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = file,
                    Arguments = arguments,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };
                using (var p = Process.Start(psi))
                {
                    p.StandardOutput.ReadToEnd();
                    p.StandardError.ReadToEnd();
                    p.WaitForExit();
                    return p.ExitCode;
                }
            }
            catch { return -1; }
        }

        private void DumpMsiError(string logPath)
        {
            try
            {
                if (!File.Exists(logPath)) return;
                string[] lines;
                try { lines = File.ReadAllLines(logPath, Encoding.Unicode); }
                catch { lines = File.ReadAllLines(logPath); }

                Log("----- Detalle del error (msiexec) -----");
                int shown = 0;
                foreach (var l in lines)
                {
                    bool hit = l.IndexOf("Return value 3", StringComparison.OrdinalIgnoreCase) >= 0
                            || l.IndexOf("Error ", StringComparison.OrdinalIgnoreCase) >= 0
                            || l.IndexOf("failed", StringComparison.OrdinalIgnoreCase) >= 0
                            || (l.IndexOf("CustomAction", StringComparison.OrdinalIgnoreCase) >= 0
                                && l.IndexOf("returned", StringComparison.OrdinalIgnoreCase) >= 0);
                    if (hit)
                    {
                        Log(l.Trim());
                        if (++shown >= 20) break;
                    }
                }
                if (shown == 0)
                {
                    int start = Math.Max(0, lines.Length - 15);
                    for (int i = start; i < lines.Length; i++) Log(lines[i].Trim());
                }
                Log("---------------------------------------");
            }
            catch (Exception ex) { Log("No se pudo leer el log: " + ex.Message); }
        }

        private int RunProcess(string file, string arguments)
        {
            var psi = new ProcessStartInfo
            {
                FileName = file,
                Arguments = arguments,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            using (var p = Process.Start(psi))
            {
                string so = p.StandardOutput.ReadToEnd();
                string se = p.StandardError.ReadToEnd();
                p.WaitForExit();
                if (!string.IsNullOrWhiteSpace(so)) Log(so.Trim());
                if (!string.IsNullOrWhiteSpace(se)) Log(se.Trim());
                return p.ExitCode;
            }
        }

        private static bool IsAdministrator()
        {
            try
            {
                var id = System.Security.Principal.WindowsIdentity.GetCurrent();
                var pr = new System.Security.Principal.WindowsPrincipal(id);
                return pr.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
            }
            catch { return false; }
        }
    }
}
