using System;
using System.Drawing;
using System.IO;

namespace WazuhAgentInstaller
{
    // Carga la configuracion de marca desde branding.json (junto al .exe).
    // Si no existe el archivo, usa los valores por defecto de abajo.
    // NO hace falta recompilar para cambiar el nombre de empresa, colores o logo:
    // basta con editar branding.json y logo.png que estan junto al ejecutable.
    public class Branding
    {
        public string CompanyName = "Mi Empresa";
        public string ProductTitle = "Instalador del Agente de Seguridad";
        public string Subtitle = "Despliegue del agente Wazuh";
        public string DefaultManagerIp = "";
        public bool LockManagerIp = false;
        public string PrimaryColor = "#172A45";
        public string AccentColor = "#5EC8E5";
        public string HeaderColor = "#FFFFFF";
        public string ManagerLabel = "IP o dominio del sistema central";
        public string SupportText = "";
        public string LogoFile = "logo.png";

        public Color Primary { get { return FromHex(PrimaryColor, Color.FromArgb(23, 42, 69)); } }
        public Color Accent { get { return FromHex(AccentColor, Color.FromArgb(94, 200, 229)); } }
        public Color Header { get { return FromHex(HeaderColor, Color.White); } }

        // true si la cabecera es clara (para elegir color de texto con buen contraste)
        public bool HeaderIsLight
        {
            get
            {
                Color c = Header;
                double lum = (0.299 * c.R + 0.587 * c.G + 0.114 * c.B);
                return lum > 150;
            }
        }

        public static Branding Load(string baseDir)
        {
            var b = new Branding();
            try
            {
                string path = Path.Combine(baseDir, "branding.json");
                if (File.Exists(path))
                {
                    string txt = File.ReadAllText(path);
                    b.CompanyName    = GetJson(txt, "companyName",    b.CompanyName);
                    b.ProductTitle   = GetJson(txt, "productTitle",   b.ProductTitle);
                    b.Subtitle       = GetJson(txt, "subtitle",       b.Subtitle);
                    b.DefaultManagerIp = GetJson(txt, "defaultManagerIp", b.DefaultManagerIp);
                    b.LockManagerIp  = GetJson(txt, "lockManagerIp",  "false").ToLower() == "true";
                    b.PrimaryColor   = GetJson(txt, "primaryColor",   b.PrimaryColor);
                    b.AccentColor    = GetJson(txt, "accentColor",    b.AccentColor);
                    b.HeaderColor    = GetJson(txt, "headerColor",    b.HeaderColor);
                    b.ManagerLabel   = GetJson(txt, "managerLabel",   b.ManagerLabel);
                    b.SupportText    = GetJson(txt, "supportText",    b.SupportText);
                    b.LogoFile       = GetJson(txt, "logoFile",       b.LogoFile);
                }
            }
            catch { /* usa valores por defecto */ }
            return b;
        }

        // Carga el logo: primero busca logo.png junto al exe, si no usa el embebido.
        public Image LoadLogo(string baseDir)
        {
            try
            {
                string path = Path.Combine(baseDir, LogoFile);
                if (File.Exists(path))
                    using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read))
                        return Image.FromStream(fs);
            }
            catch { }
            try
            {
                var asm = System.Reflection.Assembly.GetExecutingAssembly();
                using (var s = asm.GetManifestResourceStream("logo.png"))
                    if (s != null) return Image.FromStream(s);
            }
            catch { }
            return null;
        }

        // --- helpers minimos (sin dependencias externas) ---
        private static string GetJson(string json, string key, string def)
        {
            try
            {
                string pat = "\"" + key + "\"";
                int i = json.IndexOf(pat, StringComparison.OrdinalIgnoreCase);
                if (i < 0) return def;
                i = json.IndexOf(':', i + pat.Length);
                if (i < 0) return def;
                i++;
                while (i < json.Length && (json[i] == ' ' || json[i] == '\t' || json[i] == '\r' || json[i] == '\n')) i++;
                if (i >= json.Length) return def;
                if (json[i] == '"')
                {
                    int end = json.IndexOf('"', i + 1);
                    if (end < 0) return def;
                    return json.Substring(i + 1, end - i - 1);
                }
                else
                {
                    int end = i;
                    while (end < json.Length && json[end] != ',' && json[end] != '}' && json[end] != '\r' && json[end] != '\n') end++;
                    return json.Substring(i, end - i).Trim();
                }
            }
            catch { return def; }
        }

        private static Color FromHex(string hex, Color def)
        {
            try
            {
                hex = (hex ?? "").Trim().TrimStart('#');
                if (hex.Length == 6)
                    return Color.FromArgb(
                        Convert.ToInt32(hex.Substring(0, 2), 16),
                        Convert.ToInt32(hex.Substring(2, 2), 16),
                        Convert.ToInt32(hex.Substring(4, 2), 16));
            }
            catch { }
            return def;
        }
    }
}
