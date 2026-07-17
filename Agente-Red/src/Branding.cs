using System;
using System.Drawing;
using System.IO;

namespace SuricataNetAgentInstaller
{
    // Carga la marca desde branding.json (junto al .exe). Si no existe, usa los
    // valores por defecto. No hace falta recompilar para cambiar nombre/colores/logo.
    public class Branding
    {
        public string CompanyName = "AlsisGuard";
        public string ProductTitle = "Instalador del agente de red";
        public string Subtitle = "Despliegue del agente de red";
        public string PrimaryColor = "#172A45";
        public string AccentColor = "#5EC8E5";
        public string HeaderColor = "#FFFFFF";
        public string SupportText = "";
        public string LogoFile = "logo.png";

        public Color Primary { get { return FromHex(PrimaryColor, Color.FromArgb(23, 42, 69)); } }
        public Color Accent  { get { return FromHex(AccentColor, Color.FromArgb(94, 200, 229)); } }
        public Color Header  { get { return FromHex(HeaderColor, Color.White); } }

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
                    b.CompanyName  = GetJson(txt, "companyName",  b.CompanyName);
                    b.ProductTitle = GetJson(txt, "productTitle", b.ProductTitle);
                    b.Subtitle     = GetJson(txt, "subtitle",     b.Subtitle);
                    b.PrimaryColor = GetJson(txt, "primaryColor", b.PrimaryColor);
                    b.AccentColor  = GetJson(txt, "accentColor",  b.AccentColor);
                    b.HeaderColor  = GetJson(txt, "headerColor",  b.HeaderColor);
                    b.SupportText  = GetJson(txt, "supportText",  b.SupportText);
                    b.LogoFile     = GetJson(txt, "logoFile",     b.LogoFile);
                }
            }
            catch { }
            return b;
        }

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
