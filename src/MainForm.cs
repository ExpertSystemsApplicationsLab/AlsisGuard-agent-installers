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

        private readonly string _baseDir;
        private readonly Branding _brand;

        private TextBox txtIp;
        private TextBox txtName;
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
            ClientSize = new Size(560, 560);
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

            // Franja de acento inferior en la cabecera
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

            int x = 30, y = 155, w = 500;

            AddLabel(_brand.ManagerLabel + " *", x, y);
            txtIp = new TextBox { Location = new Point(x, y + 22), Width = w, Font = new Font("Segoe UI", 11F) };
            txtIp.Text = _brand.DefaultManagerIp;
            if (_brand.LockManagerIp && !string.IsNullOrEmpty(_brand.DefaultManagerIp))
                txtIp.ReadOnly = true;
            Controls.Add(txtIp);
            y += 70;

            AddLabel("Nombre del agente (opcional, por defecto el del equipo)", x, y);
            txtName = new TextBox { Location = new Point(x, y + 22), Width = w, Font = new Font("Segoe UI", 11F) };
            txtName.Text = Environment.MachineName;
            Controls.Add(txtName);
            y += 70;

            btnInstall = new Button
            {
                Text = "Instalar agente",
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
            y += 55;

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
            y += 24;

            lblStatus = new Label
            {
                Location = new Point(x, y),
                Width = w,
                Height = 20,
                ForeColor = _brand.Primary,
                Font = new Font("Segoe UI", 9F, FontStyle.Bold)
            };
            Controls.Add(lblStatus);
            y += 26;

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
            y += 128;

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
            progress.Visible = busy;
            progress.MarqueeAnimationSpeed = busy ? 30 : 0;
        }

        private void OnInstallClick(object sender, EventArgs e)
        {
            string ip = (txtIp.Text ?? "").Trim();
            string name = (txtName.Text ?? "").Trim();

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
            var t = new Thread(() => RunInstall(ip, name));
            t.IsBackground = true;
            t.Start();
        }

        private void RunInstall(string ip, string name)
        {
            try
            {
                string msiPath = ExtractMsi();
                Log("MSI preparado en: " + msiPath);

                // Aviso si ya hay una instalacion previa (causa habitual del error 1603).
                if (Directory.Exists(@"C:\Program Files (x86)\ossec-agent") ||
                    Directory.Exists(@"C:\Program Files\ossec-agent"))
                {
                    Log("AVISO: se detecto una instalacion previa del agente (carpeta ossec-agent).");
                }

                string logPath = Path.Combine(Path.GetTempPath(), "wazuh-install.log");
                try { File.Delete(logPath); } catch { }

                var args = new StringBuilder();
                args.Append("/i \"").Append(msiPath).Append("\" /qn /norestart");
                args.Append(" /l*v \"").Append(logPath).Append("\"");
                args.Append(" WAZUH_MANAGER=\"").Append(ip).Append("\"");
                args.Append(" WAZUH_REGISTRATION_SERVER=\"").Append(ip).Append("\"");
                if (!string.IsNullOrEmpty(name))
                    args.Append(" WAZUH_AGENT_NAME=\"").Append(name).Append("\"");

                Log("Ejecutando msiexec " + args);
                int code = RunProcess("msiexec.exe", args.ToString());
                Log("msiexec finalizo con codigo " + code);

                if (code != 0 && code != 3010)
                {
                    DumpMsiError(logPath);
                    Log("Log completo en: " + logPath);
                    throw new Exception(
                        "La instalacion del MSI fallo (codigo " + code + ").\n\n" +
                        "Revisa las lineas de error en el registro de la ventana.\n" +
                        "Log detallado: " + logPath + "\n\n" +
                        "Causa mas habitual del 1603: ya existe una instalacion del agente. " +
                        "Desinstalala primero (Panel de control > Programas, o el desinstalador de Wazuh) " +
                        "y vuelve a intentarlo.");
                }

                Log("Iniciando servicio " + ServiceName + "...");
                RunProcess("net.exe", "start " + ServiceName); // no-fatal si ya esta iniciado

                try { File.Delete(msiPath); } catch { }

                SetStatus("Instalacion completada correctamente.", Color.FromArgb(0, 128, 0));
                Log("Agente instalado y apuntando al manager " + ip + ".");
                Invoke(new Action(() => MessageBox.Show(this,
                    "El agente se instalo correctamente y esta conectado al manager " + ip + ".",
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

        // Lee el log verboso de msiexec y muestra las lineas relevantes del fallo.
        private void DumpMsiError(string logPath)
        {
            try
            {
                if (!File.Exists(logPath)) return;
                string[] lines;
                // El log de msiexec suele ir en UTF-16.
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
