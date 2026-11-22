// Port of MicroCode AppTheme (Models/AppState.swift) + SyntaxEngine/ThemeManager default themes.
using System;
using System.Collections.Generic;
using System.Windows.Media;

namespace MicroCode.Core
{
    public class ThemeDef
    {
        public readonly string Raw, DisplayName;
        public readonly bool IsDark, IsGlass;
        public readonly bool? DarkGlassSidebar;
        public readonly Color EditorBackground, EditorText, Keyword, String, Comment, Number, Type, Function, Selection, LineHighlight;

        public ThemeDef(string raw, string display, bool isDark, bool isGlass, bool? darkGlassSidebar,
            Color editorBg, Color editorText, Color keyword, Color str, Color comment, Color number, Color type, Color function, Color selection, Color lineHighlight)
        {
            Raw = raw; DisplayName = display; IsDark = isDark; IsGlass = isGlass; DarkGlassSidebar = darkGlassSidebar;
            EditorBackground = editorBg; EditorText = editorText; Keyword = keyword; String = str; Comment = comment;
            Number = number; Type = type; Function = function; Selection = selection; LineHighlight = lineHighlight;
        }
    }

    public static partial class ThemeTable
    {
        public static ThemeDef Find(string raw)
        {
            foreach (var t in All) if (t.Raw == raw) return t;
            foreach (var t in All) if (t.Raw == "dark") return t;
            return All[0];
        }
    }

    /// <summary>Resolved palette for the active AppTheme (macOS semantic colours in the theme's appearance).</summary>
    public class Theme
    {
        public static Theme Current = new Theme(ThemeTable.Find("dark"));
        public static event Action Changed;

        public static void Apply(string raw)
        {
            Current = new Theme(ThemeTable.Find(raw));
            if (Changed != null) Changed();
        }

        public readonly ThemeDef Def;
        public readonly bool IsDark;

        // AppTheme derived colours
        public readonly SolidColorBrush WorkspaceBackground, PanelBackground, ElevatedBackground, EditorBackground, EditorText, SidebarBackground;
        // macOS semantic colours (labelColor etc.)
        public readonly SolidColorBrush Primary, Secondary, Tertiary, Quaternary, Separator, Accent, WindowBackground, TextBackground, ControlBackground,
            SelectedContent, MenuBackground, MenuBorder, MenuHighlight;
        public readonly SolidColorBrush SysRed, SysOrange, SysYellow, SysGreen, SysBlue, SysPurple, SysCyan, SysGray, SysPink, SysMint, SysIndigo, SysTeal;
        public readonly Color AccentColor, PrimaryColor;
        // Code editor syntax theme (ThemeManager "MicroCode Pro Dark" for .dark; AppTheme token colours otherwise)
        public readonly Syntax Syntax;

        public static Color Rgb(int r, int g, int b) { return Color.FromRgb((byte)r, (byte)g, (byte)b); }
        public static Color Rgba(int r, int g, int b, double a) { return Color.FromArgb((byte)Math.Round(a * 255), (byte)r, (byte)g, (byte)b); }
        public static Color Hex(string hex)
        {
            hex = hex.TrimStart('#');
            if (hex.Length == 6) hex = "FF" + hex;
            return Color.FromArgb(Convert.ToByte(hex.Substring(0, 2), 16), Convert.ToByte(hex.Substring(2, 2), 16), Convert.ToByte(hex.Substring(4, 2), 16), Convert.ToByte(hex.Substring(6, 2), 16));
        }
        public static SolidColorBrush B(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }
        public static Color WithAlpha(Color c, double a) { return Color.FromArgb((byte)Math.Round(a * 255), c.R, c.G, c.B); }
        static Color Blend(Color c, Color target, double f)
        {
            return Color.FromArgb(255, (byte)Math.Round(c.R * (1 - f) + target.R * f), (byte)Math.Round(c.G * (1 - f) + target.G * f), (byte)Math.Round(c.B * (1 - f) + target.B * f));
        }

        /// <summary>SwiftUI Color.primary.opacity(x).</summary>
        public SolidColorBrush P(double opacity) { return B(WithAlpha(PrimaryColor, PrimaryColor.A / 255.0 * opacity)); }
        /// <summary>SwiftUI Color.secondary.opacity(x).</summary>
        public SolidColorBrush S(double opacity) { var c = Secondary.Color; return B(WithAlpha(c, c.A / 255.0 * opacity)); }
        /// <summary>Color.accentColor.opacity(x).</summary>
        public SolidColorBrush A(double opacity) { return B(WithAlpha(AccentColor, opacity)); }
        public SolidColorBrush Op(SolidColorBrush b, double opacity) { var c = b.Color; return B(WithAlpha(c, c.A / 255.0 * opacity)); }

        public Theme(ThemeDef d)
        {
            Def = d;
            IsDark = d.IsDark;
            bool pureBlack = d.Raw == "dark" || d.Raw == "xcodeDark";
            Color editorBg = d.EditorBackground;
            Color ws = d.IsGlass ? editorBg : (pureBlack ? Colors.Black : WithAlpha(editorBg, 1));
            Color panel = d.IsGlass ? editorBg : (pureBlack ? Rgb(5, 5, 5) : Blend(WithAlpha(editorBg, 1), IsDark ? Colors.White : Colors.Black, IsDark ? 0.035 : 0.025));
            Color elevated = d.IsGlass ? editorBg : (pureBlack ? Rgb(26, 26, 26) : Blend(WithAlpha(editorBg, 1), IsDark ? Colors.White : Colors.Black, IsDark ? 0.07 : 0.045));
            if (d.IsGlass)
            {
                // Windows has no behind-window vibrancy for WPF; glass themes fall back to their tinted opaque look.
                ws = IsDark ? Rgb(22, 22, 24) : Rgb(236, 236, 238);
                panel = IsDark ? Rgb(28, 28, 30) : Rgb(242, 242, 244);
                elevated = IsDark ? Rgb(40, 40, 42) : Rgb(230, 230, 232);
                editorBg = ws;
            }
            WorkspaceBackground = B(ws);
            PanelBackground = B(panel);
            ElevatedBackground = B(elevated);
            EditorBackground = B(editorBg);
            EditorText = B(d.EditorText);
            bool darkGlass = d.DarkGlassSidebar.HasValue ? d.DarkGlassSidebar.Value : IsDark;
            // ObsidianSidebarGlass: underlay rgb(0.005,0.006,0.010) + vibrancy + veil rgba(0.006,0.007,0.012,0.94)
            SidebarBackground = B(darkGlass ? Rgb(4, 4, 6) : panel);

            if (IsDark)
            {
                PrimaryColor = Rgba(255, 255, 255, 0.85);
                Secondary = B(Rgba(255, 255, 255, 0.55));
                Tertiary = B(Rgba(255, 255, 255, 0.25));
                Quaternary = B(Rgba(255, 255, 255, 0.10));
                Separator = B(Rgba(255, 255, 255, 0.10));
                AccentColor = Rgb(10, 132, 255);
                WindowBackground = B(Rgb(50, 50, 50));
                TextBackground = B(Rgb(30, 30, 30));
                ControlBackground = B(Rgb(30, 30, 30));
                SelectedContent = B(Rgb(0, 88, 208));
                MenuBackground = B(Rgba(40, 40, 42, 0.96));
                MenuBorder = B(Rgba(255, 255, 255, 0.14));
                SysRed = B(Rgb(255, 69, 58)); SysOrange = B(Rgb(255, 159, 10)); SysYellow = B(Rgb(255, 214, 10));
                SysGreen = B(Rgb(50, 215, 75)); SysBlue = B(Rgb(10, 132, 255)); SysPurple = B(Rgb(191, 90, 242));
                SysCyan = B(Rgb(100, 210, 255)); SysGray = B(Rgb(152, 152, 157)); SysPink = B(Rgb(255, 55, 95));
                SysMint = B(Rgb(102, 212, 207)); SysIndigo = B(Rgb(94, 92, 230)); SysTeal = B(Rgb(106, 196, 220));
            }
            else
            {
                PrimaryColor = Rgba(0, 0, 0, 0.85);
                Secondary = B(Rgba(0, 0, 0, 0.5));
                Tertiary = B(Rgba(0, 0, 0, 0.26));
                Quaternary = B(Rgba(0, 0, 0, 0.10));
                Separator = B(Rgba(0, 0, 0, 0.10));
                AccentColor = Rgb(0, 122, 255);
                WindowBackground = B(Rgb(236, 236, 236));
                TextBackground = B(Colors.White);
                ControlBackground = B(Colors.White);
                SelectedContent = B(Rgb(0, 99, 225));
                MenuBackground = B(Rgba(246, 246, 246, 0.97));
                MenuBorder = B(Rgba(0, 0, 0, 0.12));
                SysRed = B(Rgb(255, 59, 48)); SysOrange = B(Rgb(255, 149, 0)); SysYellow = B(Rgb(255, 204, 0));
                SysGreen = B(Rgb(40, 205, 65)); SysBlue = B(Rgb(0, 122, 255)); SysPurple = B(Rgb(175, 82, 222));
                SysCyan = B(Rgb(85, 190, 240)); SysGray = B(Rgb(142, 142, 147)); SysPink = B(Rgb(255, 45, 85));
                SysMint = B(Rgb(0, 199, 190)); SysIndigo = B(Rgb(88, 86, 214)); SysTeal = B(Rgb(89, 173, 196));
            }
            Primary = B(PrimaryColor);
            Accent = B(AccentColor);
            MenuHighlight = B(AccentColor);
            Syntax = d.Raw == "dark" || d.Raw == "xcodeDark" || d.Raw == "system" ? Syntax.MicroCodeProDark() : Syntax.From(d, editorBg);
        }
    }

    /// <summary>SyntaxEngine ThemeManager token palette.</summary>
    public class Syntax
    {
        public Color Background, Foreground, Selection, LineHighlight, Cursor, Gutter, GutterText;
        public readonly Dictionary<string, Color> Tokens = new Dictionary<string, Color>();
        public readonly HashSet<string> Italic = new HashSet<string>();

        public Color Get(string token)
        {
            Color c;
            if (Tokens.TryGetValue(token, out c)) return c;
            return Foreground;
        }

        public static Syntax MicroCodeProDark()
        {
            var s = new Syntax
            {
                Background = Theme.Hex("#000000"), Foreground = Theme.Hex("#FFFFFF"), Selection = Theme.Hex("#263342"),
                LineHighlight = Theme.Hex("#111114"), Cursor = Theme.Hex("#FFFFFF"), Gutter = Theme.Hex("#000000"), GutterText = Theme.Hex("#4A4A50")
            };
            string[,] map = {
                {"keyword","#FC5FA3"},{"string","#FC6A5D"},{"number","#D0BF69"},{"boolean","#FC5FA3"},{"null","#FC5FA3"},
                {"comment","#6C7986"},{"type","#5DD8CE"},{"function","#41A7FC"},{"identifier","#FFFFFF"},{"variable","#FFFFFF"},
                {"property","#5DD8CE"},{"parameter","#FFFFFF"},{"operator","#FFFFFF"},{"punctuation","#D1D1D6"},{"delimiter","#E5E5EA"},
                {"annotation","#FD8F3F"},{"preprocessor","#FD8F3F"},{"escape","#D7BA7D"},{"tag","#FC5FA3"},{"attribute","#5DD8CE"}
            };
            for (int i = 0; i < map.GetLength(0); i++) s.Tokens[map[i, 0]] = Theme.Hex(map[i, 1]);
            s.Italic.Add("comment");
            return s;
        }

        public static Syntax From(ThemeDef d, Color editorBg)
        {
            var s = new Syntax
            {
                Background = editorBg, Foreground = d.EditorText, Selection = d.Selection, LineHighlight = d.LineHighlight,
                Cursor = d.EditorText, Gutter = editorBg,
                GutterText = Theme.WithAlpha(d.EditorText, 0.35)
            };
            s.Tokens["keyword"] = d.Keyword; s.Tokens["boolean"] = d.Keyword; s.Tokens["null"] = d.Keyword; s.Tokens["tag"] = d.Keyword;
            s.Tokens["string"] = d.String; s.Tokens["escape"] = d.String;
            s.Tokens["comment"] = d.Comment;
            s.Tokens["number"] = d.Number;
            s.Tokens["type"] = d.Type; s.Tokens["property"] = d.Type; s.Tokens["attribute"] = d.Type;
            s.Tokens["function"] = d.Function;
            s.Tokens["annotation"] = d.Function; s.Tokens["preprocessor"] = d.Keyword;
            s.Tokens["punctuation"] = Theme.WithAlpha(d.EditorText, 0.85);
            s.Italic.Add("comment");
            return s;
        }
    }
}
