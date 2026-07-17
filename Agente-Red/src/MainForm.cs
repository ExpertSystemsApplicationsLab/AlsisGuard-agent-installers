using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net.NetworkInformation;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;

namespace SuricataNetAgentInstaller
{
    public class MainForm : Form
    {
        // Recurso embebido con el script de instalacion de Suricata.
        private const string PsResourceName = "Instalador-Suricata-Windows.ps1";

        private readonly string _baseDir;
        private readonly Branding _brand;

        private ComboBox cmbIface;
        private TextBox txtLog;
        private Button btnInstall;
        private Label lblStatus;
        private ProgressBar progress;
        private readonly List<string> _ifaceNames = new List<string>();

        public MainForm()
        {
            _baseDir = AppDomain.CurrentDomain.BaseDirectory;
            _brand = Branding.Load(_baseDir);
            BuildUi();
            PopulateInterfaces();
        }

        private void BuildUi()
        {
            Text = _brand.ProductTitle + " - " + _brand.CompanyName;
            StartPosition = FormStartPosition.CenterScreen;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            ClientSize = new Size(560, 540);
            BackColor = Color.White;
            Font = new Font("Segoe UI", 9F);
            try
            {
                using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("app.ico"))
                    if (s != null) Icon = new Icon(s);
            }
            catch { }

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

            int x = 30, y = 150, w = 500;

            AddLabel("Interfaz de red a monitorizar *", x, y);
            cmbIface = new ComboBox
            {
                Location = new Point(x, y + 22),
                Width = w,
                Font = new Font("Segoe UI", 11F),
                DropDownStyle = ComboBoxStyle.DropDownList
            };
            Controls.Add(cmbIface);
            y += 70;

            var lblInfo = new Label
            {
                Text = "Instala Npcap (si falta) + Suricata + reglas Emerging Threats, lo integra con "
                     + "el agente Wazuh y lo deja arrancando con Windows. Requiere conexion a internet.",
                Location = new Point(x, y),
                Width = w,
                Height = 40,
                ForeColor = Color.FromArgb(90, 100, 110),
                Font = new Font("Segoe UI", 8.5F)
            };
            Controls.Add(lblInfo);
            y += 46;

            btnInstall = new Button
            {
                Text = "Instalar sensor de red",
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
                Height = 150,
                Multiline = true,
                ReadOnly = true,
                ScrollBars = ScrollBars.Vertical,
                BackColor = Color.FromArgb(245, 247, 250),
                Font = new Font("Consolas", 8.5F)
            };
            Controls.Add(txtLog);
            y += 158;

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

        // Lista las interfaces de red activas (no loopback ni tuneles).
        private void PopulateInterfaces()
        {
            try
            {
                foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (ni.OperationalStatus != OperationalStatus.Up) continue;
                    if (ni.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                    if (ni.NetworkInterfaceType == NetworkInterfaceType.Tunnel) continue;

                    string ip = "";
                    foreach (var ua in ni.GetIPProperties().UnicastAddresses)
                        if (ua.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                        { ip = ua.Address.ToString(); break; }

                    _ifaceNames.Add(ni.Name);
                    cmbIface.Items.Add(ni.Name + "   (" + ni.Description + (ip != "" ? "  |  " + ip : "") + ")");
                }
            }
            catch { }
            if (cmbIface.Items.Count > 0) cmbIface.SelectedIndex = 0;
        }

        private void Log(string msg)
        {
            if (msg == null) return;
            if (txtLog.InvokeRequired) { txtLog.BeginInvoke(new Action<string>(Log), msg); return; }
            txtLog.AppendText(msg + Environment.NewLine);
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
            cmbIface.Enabled = !busy;
            progress.Visible = busy;
            progress.MarqueeAnimationSpeed = busy ? 30 : 0;
        }

        private void OnInstallClick(object sender, EventArgs e)
        {
            if (cmbIface.SelectedIndex < 0)
            {
                MessageBox.Show(this, "Selecciona una interfaz de red.",
                    "Falta la interfaz", MessageBoxButtons.OK, MessageBoxIcon.Warning);
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

            string iface = _ifaceNames[cmbIface.SelectedIndex];
            SetBusy(true);
            SetStatus("Instalando... (puede tardar varios minutos por las descargas)", _brand.Primary);
            var t = new Thread(() => RunInstall(iface));
            t.IsBackground = true;
            t.Start();
        }

        private void RunInstall(string iface)
        {
            try
            {
                string ps1 = ExtractScript();
                Log("Script de instalacion preparado.");
                Log("Interfaz seleccionada: " + iface);
                Log("Lanzando instalacion...");

                string args = "-NoProfile -ExecutionPolicy Bypass -File \"" + ps1 + "\" "
                            + "-Silent -InterfaceName \"" + iface + "\"";
                int code = RunPowerShell(args);

                try { if (ps1.StartsWith(Path.GetTempPath(), StringComparison.OrdinalIgnoreCase)) File.Delete(ps1); }
                catch { }

                if (code == 0)
                {
                    SetStatus("Instalacion completada correctamente.", Color.FromArgb(0, 128, 0));
                    Invoke(new Action(() => MessageBox.Show(this,
                        "Suricata quedo instalado, integrado con el agente Wazuh y arrancando con Windows.",
                        "Instalacion completada", MessageBoxButtons.OK, MessageBoxIcon.Information)));
                }
                else
                {
                    SetStatus("La instalacion no se completo (codigo " + code + ").", Color.FromArgb(178, 34, 34));
                    Invoke(new Action(() => MessageBox.Show(this,
                        "La instalacion no se completo. Revisa el registro de la ventana.",
                        "Error", MessageBoxButtons.OK, MessageBoxIcon.Error)));
                }
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

        // Extrae el .ps1 embebido a una carpeta temporal. Si no esta embebido,
        // busca uno junto al .exe como alternativa.
        private string ExtractScript()
        {
            string outPath = Path.Combine(Path.GetTempPath(), "Instalador-Suricata-Windows.ps1");
            var asm = Assembly.GetExecutingAssembly();
            using (var s = asm.GetManifestResourceStream(PsResourceName))
            {
                if (s != null)
                {
                    using (var fs = new FileStream(outPath, FileMode.Create, FileAccess.Write))
                        s.CopyTo(fs);
                    return outPath;
                }
            }
            string local = Path.Combine(_baseDir, PsResourceName);
            if (File.Exists(local)) return local;
            throw new Exception("No se encontro el script de instalacion embebido ni junto al .exe.");
        }

        // Ejecuta powershell.exe y vuelca su salida en vivo al registro.
        private int RunPowerShell(string arguments)
        {
            var psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = arguments,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            using (var p = new Process())
            {
                p.StartInfo = psi;
                p.OutputDataReceived += (s, e) => { if (e.Data != null) Log(e.Data); };
                p.ErrorDataReceived  += (s, e) => { if (e.Data != null) Log(e.Data); };
                p.Start();
                p.BeginOutputReadLine();
                p.BeginErrorReadLine();
                p.WaitForExit();
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
