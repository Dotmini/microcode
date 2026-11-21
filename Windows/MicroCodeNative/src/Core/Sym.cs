// SF Symbols are licensed for Apple platforms only. On Windows each symbol name used by the macOS source maps to
// the closest glyph in the Windows 11 system icon font (Segoe Fluent Icons); a few with no system equivalent are drawn as vectors.
using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;

namespace MicroCode.UI
{
    public class SymbolIcon : Grid
    {
        public TextBlock Glyph;
        public Path Vector;
        public void SetBrush(Brush b)
        {
            if (Glyph != null) Glyph.Foreground = b;
            if (Vector != null)
            {
                if (Vector.Stroke != null) Vector.Stroke = b;
                if (Vector.Fill != null && Vector.Fill != Brushes.Transparent) Vector.Fill = b;
            }
        }
    }

    public static class Sym
    {
        /// <summary>SF Symbol point size → Segoe Fluent Icons em size (Segoe glyph art fills the em box; SF symbols track cap height).</summary>
        public static double Scale = 1.18;

        static readonly Dictionary<string, int> Map = new Dictionary<string, int>
        {
            {"sidebar.left",0xE90C},{"sidebar.right",0xE90D},{"sidebar.leading",0xE90C},{"sidebar.trailing",0xE90D},
            {"folder",0xE8B7},{"folder.fill",0xE8D5},{"folder.badge.plus",0xE8F4},{"folder.badge.gearshape",0xE8B7},
            {"arrow.triangle.branch",0xF003},{"magnifyingglass",0xE721},{"exclamationmark.triangle",0xE7BA},
            {"exclamationmark.triangle.fill",0xE814},{"exclamationmark.circle",0xE783},{"exclamationmark.octagon",0xE783},
            {"ellipsis",0xE712},{"ellipsis.circle",0xE712},{"plus",0xE710},{"plus.circle",0xECC8},{"plus.circle.fill",0xECC8},
            {"plus.square",0xECCD},{"minus",0xE738},
            {"xmark",0xE711},{"xmark.circle.fill",0xEB90},{"xmark.circle",0xEB90},{"xmark.octagon.fill",0xEB90},
            {"gearshape",0xE713},{"gearshape.fill",0xF8B0},{"gearshape.2",0xE9F5},{"gear",0xE713},
            {"play.fill",0xF5B0},{"play",0xE768},{"play.circle",0xEC57},{"play.circle.fill",0xEC58},{"stop.fill",0xEE95},
            {"stop.circle.fill",0xECCB},{"pause.fill",0xF8AE},{"forward.fill",0xEB9D},
            {"terminal",0xE756},{"terminal.fill",0xE756},{"apple.terminal",0xE756},
            {"curlybraces",0xE943},{"curlybraces.square",0xE943},{"chevron.left.forwardslash.chevron.right",0xF54C},{"swift",0xF54C},
            {"square.grid.2x2",0xF0E2},{"square.grid.2x2.fill",0xF0E2},{"square.grid.3x1.below.line.grid.1x2",0xF0E2},
            {"chevron.down",0xE70D},{"chevron.up",0xE70E},{"chevron.right",0xE76C},{"chevron.left",0xE76B},
            {"chevron.up.chevron.down",0xE8CB},
            {"bubble.left.and.bubble.right",0xE8F2},{"bubble.left",0xE8BD},{"text.bubble",0xE8BD},{"ellipsis.bubble",0xE8F2},
            {"list.bullet.clipboard",0xF0E3},{"checklist",0xE9D5},{"doc.text.magnifyingglass",0xE773},
            {"chart.bar.xaxis",0xE9D2},{"chart.line.uptrend.xyaxis",0xEAFC},{"shield.checkered",0xEA18},{"checkmark.shield",0xF760},
            {"person.2",0xE716},{"person.2.fill",0xE716},{"person",0xE77B},{"person.fill",0xE77B},{"person.crop.circle",0xE77B},
            {"link.badge.plus",0xE71B},{"link",0xE71B},{"slider.horizontal.3",0xE9E9},{"database",0xEE94},
            {"shippingbox",0xF158},{"shippingbox.fill",0xF158},{"shippingbox.and.arrow.backward",0xF158},{"cube",0xF158},{"cube.fill",0xF158},
            {"arrow.down.doc.fill",0xE896},{"arrow.uturn.backward",0xE7A7},{"arrow.counterclockwise",0xE7A7},{"trash",0xE74D},
            {"rectangle.split.2x1",0xF57C},{"square.split.1x2.fill",0xF57B},{"iphone",0xE8EA},{"server.rack",0xF20C},
            {"network",0xE968},{"puzzlepiece.extension",0xEA86},{"atom",0xF22C},{"play.rectangle",0xE786},{"play.rectangle.fill",0xE786},
            {"book.pages",0xE736},{"book",0xE82D},{"cpu",0xE950},{"cpu.fill",0xE950},{"memorychip",0xEEA1},{"globe",0xE774},
            {"doc.text",0xF000},{"doc.text.fill",0xF000},{"doc",0xE7C3},{"doc.fill",0xE7C3},{"doc.richtext",0xE8A5},
            {"doc.badge.plus",0xEA1A},{"doc.on.doc",0xE8C8},{"doc.plaintext",0xF000},
            {"arrow.clockwise",0xE72C},{"arrow.triangle.2.circlepath",0xE895},{"clock",0xE823},{"clock.fill",0xE823},
            {"clock.arrow.circlepath",0xE81C},{"list.bullet.rectangle",0xE8FD},{"list.bullet",0xE8FD},{"lock.doc",0xE72E},
            {"lock",0xE72E},{"lock.fill",0xE72E},{"wand.and.stars",0xF6C7},{"sparkles",0xF4A5},
            {"arrow.down.circle",0xE896},{"play.laptopcomputer",0xE7F8},{"laptopcomputer",0xE7F8},{"desktopcomputer",0xE7F4},
            {"qrcode",0xED14},{"macwindow",0xE737},{"mic",0xE720},{"mic.fill",0xF8B1},{"paperclip",0xE723},{"photo",0xE91B},
            {"at",0xE910},{"arrow.up",0xF0AD},{"arrow.down",0xF0AE},{"arrow.left",0xE72B},{"arrow.right",0xE72A},
            {"arrow.left.arrow.right",0xF1CB},{"checkmark",0xE73E},{"checkmark.circle.fill",0xEC61},{"checkmark.circle",0xE930},
            {"checkmark.seal.fill",0xEC61},{"info.circle",0xE946},{"questionmark.circle",0xE9CE},{"bolt.fill",0xE945},{"bolt",0xE945},
            {"cloud",0xE753},{"icloud",0xE753},{"key",0xE8D7},{"eye",0xE7B3},{"eye.fill",0xE7B3},{"doc.on.clipboard",0xE77F},{"arrow.up.forward.square",0xE8A7},{"pencil",0xE70F},{"square.and.pencil",0xE932},
            {"square.and.arrow.up",0xE72D},{"square.and.arrow.down",0xE74E},{"arrow.up.right.square",0xE8A7},{"house",0xE80F},
            {"bell",0xEA8F},{"star",0xE734},{"star.fill",0xE735},{"flag",0xE7C1},{"tag",0xE8EC},{"pin",0xE718},
            {"line.3.horizontal",0xE700},{"textformat",0xE8D2},{"paintbrush",0xE771},{"paintpalette",0xE790},
            {"antenna.radiowaves.left.and.right",0xEC05},{"wifi",0xE701},{"creditcard",0xE8C7},{"timer",0xE916},
            {"keyboard",0xE765},{"arrow.up.left.and.arrow.down.right",0xE740},{"arrow.down.right.and.arrow.up.left",0xE73F},
            {"circle",0xEA3A},{"circle.fill",0xEA3B},{"wrench",0xE90F},{"wrench.and.screwdriver",0xEC7A},{"hammer",0xEC7A},
            {"hammer.fill",0xEC7A},{"ladybug",0xEBE8},{"ant",0xEBE8},{"flowchart",0xF003},{"waveform",0xE9D9},
            {"speaker.wave.2",0xE767},{"camera",0xE722},{"video",0xE714},{"envelope",0xE715},{"calendar",0xE787},
            {"square.stack.3d.up",0xE81E},{"square.on.square",0xE8C8},{"power",0xE7E8},{"moon",0xE708},{"sun.max",0xE706},
            {"cursorarrow",0xE8B0},{"text.alignleft",0xE8E4},{"arrow.down.to.line",0xE896},{"externaldrive",0xEDA2},
            {"display",0xE7F4},{"rectangle.on.rectangle",0xE8C8},{"square.and.arrow.down.on.square",0xE74E},
            {"scope",0xF272},{"text.cursor",0xE8D2},{"iphone.radiowaves.left.and.right",0xE8EA},{"person.badge.key",0xE8D7},{"building.2",0xEC08},{"puzzlepiece.extension.fill",0xEA86},{"bookmark",0xE8EC},{"paperplane.fill",0xE725},{"paperplane",0xE724},{"cup.and.saucer.fill",0xEC32},{"tag.fill",0xE8EC},{"lock.shield",0xEA18},{"flame.fill",0xECAD},{"flame",0xECAD},{"lock.open",0xE785},
            {"n.square.fill",0xF16B},{"speedometer",0xEC48},{"apps.iphone",0xE8EA},{"leaf",0xF1E8},{"v.circle.fill",0xEA3A},
            {"shield",0xEA18},{"airplane.circle",0xE709},{"arrow.down.doc",0xE74E},{"arrow.left.and.right.square",0xE8AB},{"arrow.uturn.forward",0xE7A6},{"checkmark.shield.fill",0xEA18},{"checkmark.square.fill",0xE73A},{"list.bullet.clipboard.fill",0xE77F},{"minus.circle",0xE738},{"questionmark.circle.fill",0xE9CE},{"square",0xE739},{"tablecells",0xF0E2},{"play.tv",0xE7F4},{"arrow.triangle.swap",0xE8AB},{"minus.magnifyingglass",0xE71F},{"plus.magnifyingglass",0xE8A3},{"scroll",0xE7C3},{"book.closed",0xE736},{"viewfinder",0xE8B3},{"candybarphone",0xE8EA},{"ipad",0xE70A},{"rotate.right",0xE7AD},{"cable.connector",0xE88E},{"shield.lefthalf.filled",0xEA18},{"exclamationmark.shield.fill",0xE7BA},{"point.3.connected.trianglepath.dotted",0xF003},{"checkmark.seal",0xEC61},{"safari",0xE774},{"person.crop.circle.badge.checkmark",0xE8D7},{"folder.badge.questionmark",0xE8B7},{"bubble.left.fill",0xE8BD},{"arrow.up.circle.fill",0xF0AD},
            {"cylinder",0xEE94},{"cylinder.fill",0xEE94},{"sparkles.tv",0xE7F4},{"sparkles.tv.fill",0xE7F4},
            {"exclamationmark.arrow.triangle.2.circlepath",0xE895},{"bolt.badge.automatic.fill",0xE945},{"bolt.circle",0xE945},
            {"tablecells.badge.ellipsis",0xF0E2},{"sparkles.rectangle.stack",0xF4A5},{"exclamationmark.bubble",0xE783},
            {"list.number",0xE8FD},{"applelogo",0xE7F8},{"apple.logo",0xE7F8},{"doc.zipper",0xE7B8},{"chart.bar",0xE9D2},
            {"paintbrush.pointed",0xE771},{"arrow.triangle.2.circlepath.circle",0xE895},{"text.line.first.and.arrowtriangle.forward",0xE8E4},
            {"hourglass",0xE916},{"arrow.up.message",0xE724},{"key.fill",0xE8D7},{"stop.circle",0xECCB},{"xmark.square",0xE711},
            {"brain.filled.head.profile",0}, {"brain",0}, {"brain.head.profile",0}
        };

        // Vector fallbacks (16-unit box, stroked) for symbols with no Windows system glyph.
        static readonly Dictionary<string, string> Vectors = new Dictionary<string, string>
        {
            // brain: two lobed hemispheres with a central fissure and folds
            {"arrow.turn.right.down", "M2.5,3.5 L9.5,3.5 C11.7,3.5 12.5,4.6 12.5,6.5 L12.5,13.5 M9.6,10.6 L12.5,13.5 L15.4,10.6"},
            {"chart.xyaxis.line", "M2,1.5 L2,14 L14.5,14 M4.2,11.2 L7,7.4 L9.6,9.4 L13.6,3.6"},
            {"plus.rectangle.on.rectangle", "M5,1.8 L14.2,1.8 L14.2,10.8 L5,10.8 Z M2,4.6 L2,14.2 L11.4,14.2 M9.6,4 L9.6,8.6 M7.3,6.3 L11.9,6.3"},
            {"plus.rectangle", "M1.8,3 L14.2,3 L14.2,13 L1.8,13 Z M8,5.4 L8,10.6 M5.4,8 L10.6,8"},
            {"arrow.up.right", "M3.6,12.4 L12.2,3.8 M6,3.6 L12.4,3.6 L12.4,10"},
            {"rectangle.grid.1x2", "M2,2 L14,2 L14,7.2 L2,7.2 Z M2,8.8 L14,8.8 L14,14 L2,14 Z"},
            {"number.square", "M2,2 L14,2 L14,14 L2,14 Z M6.7,4.4 L5.7,11.6 M10.3,4.4 L9.3,11.6 M4.6,6.5 L11.6,6.5 M4.3,9.5 L11.3,9.5"},
            {"waveform.path.ecg", "M1,8.4 L4.2,8.4 L5.6,4.2 L7.6,12.2 L9.6,5.8 L10.7,8.4 L15,8.4"},
            {"circle.dotted", "M8,1.8 L8,2.9 M12.4,3.6 L11.6,4.4 M14.2,8 L13.1,8 M12.4,12.4 L11.6,11.6 M8,14.2 L8,13.1 M3.6,12.4 L4.4,11.6 M1.8,8 L2.9,8 M3.6,3.6 L4.4,4.4"},
            {"brain", "M8,2.6 C7.3,1.7 5.7,1.6 4.9,2.6 C3.6,2.6 2.8,3.7 3,4.8 C1.9,5.3 1.6,6.8 2.3,7.7 C1.5,8.6 1.8,10.2 2.9,10.7 C2.8,12.1 4,13.2 5.3,13 C5.9,14.1 7.3,14.4 8,13.6 Z M8,2.6 C8.7,1.7 10.3,1.6 11.1,2.6 C12.4,2.6 13.2,3.7 13,4.8 C14.1,5.3 14.4,6.8 13.7,7.7 C14.5,8.6 14.2,10.2 13.1,10.7 C13.2,12.1 12,13.2 10.7,13 C10.1,14.1 8.7,14.4 8,13.6 M8,2.6 L8,13.6 M5,5.2 C5.8,5.4 6.3,6 6.2,6.8 M3.2,8.6 C4.2,8.4 5.1,8.9 5.4,9.8 M11,5.2 C10.2,5.4 9.7,6 9.8,6.8 M12.8,8.6 C11.8,8.4 10.9,8.9 10.6,9.8"},
        };

        /// <summary>Glyph character for a symbol (for custom-drawn surfaces such as the file tree).</summary>
        public static string GlyphText(string name)
        {
            int cp;
            if (!Map.TryGetValue(name, out cp) || cp == 0)
            {
                string baseName = name.EndsWith(".fill") ? name.Substring(0, name.Length - 5) : name;
                if (!Map.TryGetValue(baseName, out cp) || cp == 0) cp = 0xE7C3;
            }
            return char.ConvertFromUtf32(cp);
        }

        public static SymbolIcon Icon(string name, double size, Brush fg)
        {
            return Icon(name, size, fg, FontWeights.Normal);
        }

        public static SymbolIcon Icon(string name, double size, Brush fg, FontWeight weight)
        {
            var box = new SymbolIcon { VerticalAlignment = VerticalAlignment.Center, SnapsToDevicePixels = true };
            double em = Math.Round(size * Scale * 2) / 2;
            var letter = System.Text.RegularExpressions.Regex.Match(name ?? "", @"^([a-z]|number)\.circle(\.fill)?$");
            if (letter.Success)
            {
                // SF "x.circle.fill": a filled disc with the letter knocked out (drawn in the surface colour).
                bool filled = letter.Groups[2].Success;
                double d = Math.Round(em * 0.86 * 2) / 2;
                var disc = new Ellipse { Width = d, Height = d, Fill = filled ? fg : Brushes.Transparent, Stroke = filled ? null : fg, StrokeThickness = 1.1 };
                var ch = new TextBlock
                {
                    Text = letter.Groups[1].Value == "number" ? "#" : letter.Groups[1].Value, FontFamily = UIFonts.UI, FontWeight = FontWeights.Bold,
                    FontSize = Math.Max(6, d * 0.68), Foreground = filled ? (Brush)Core.Theme.Current.ElevatedBackground : fg,
                    HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 0, d * 0.08)
                };
                box.Width = em; box.Height = em;
                box.Children.Add(disc); box.Children.Add(ch);
                return box;
            }
            if (name == "function")
            {
                var fx = new TextBlock
                {
                    Text = "ƒx", FontFamily = new FontFamily("Cambria Math"), FontStyle = FontStyles.Italic, FontSize = em * 0.92, Foreground = fg,
                    HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center
                };
                box.Glyph = fx;
                box.Height = em; box.MinWidth = em;
                box.Children.Add(fx);
                return box;
            }
            string key = name;
            if (key == "brain.head.profile" || key == "brain.filled.head.profile") key = "brain";
            string geo;
            if (Vectors.TryGetValue(key, out geo))
            {
                var p = new Path
                {
                    Data = Geometry.Parse(geo), Stroke = fg, StrokeThickness = weight.ToOpenTypeWeight() >= 600 ? 1.45 : 1.2,
                    StrokeLineJoin = PenLineJoin.Round, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
                    Stretch = Stretch.Uniform, Width = em * 0.92, Height = em * 0.92, Fill = Brushes.Transparent
                };
                box.Vector = p;
                box.Width = em; box.Height = em;
                p.HorizontalAlignment = HorizontalAlignment.Center;
                p.VerticalAlignment = VerticalAlignment.Center;
                box.Children.Add(p);
                return box;
            }
            int cp;
            if (!Map.TryGetValue(name, out cp) || cp == 0)
            {
                string baseName = name.EndsWith(".fill") ? name.Substring(0, name.Length - 5) : name;
                if (!Map.TryGetValue(baseName, out cp) || cp == 0) cp = 0xE7C3;
            }
            var tb = new TextBlock
            {
                Text = char.ConvertFromUtf32(cp), FontFamily = UIFonts.Icons, FontSize = em, Foreground = fg,
                TextAlignment = TextAlignment.Center, LineHeight = em, LineStackingStrategy = LineStackingStrategy.BlockLineHeight,
                HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center
            };
            box.Glyph = tb;
            box.Width = em; box.Height = em;
            box.Children.Add(tb);
            return box;
        }
    }
}
