using System;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
[assembly: System.Runtime.Versioning.TargetFramework(".NETFramework,Version=v4.8")]
public static class GlyphAtlas {
    [STAThread]
    public static int Main(string[] args) {
        string outDir = args[0];
        int start = Convert.ToInt32(args[1], 16), end = Convert.ToInt32(args[2], 16);
        var tf = new Typeface(new FontFamily("Segoe Fluent Icons"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
        GlyphTypeface gt; if (!tf.TryGetGlyphTypeface(out gt)) { Console.WriteLine("no glyph typeface"); return 1; }
        var cps = new System.Collections.Generic.List<int>();
        for (int c = start; c <= end; c++) if (gt.CharacterToGlyphMap.ContainsKey(c)) cps.Add(c);
        Console.WriteLine("glyphs: " + cps.Count);
        int cols = 16, cellW = 64, cellH = 60, perPage = 256, page = 0;
        for (int i0 = 0; i0 < cps.Count; i0 += perPage, page++) {
            int n = Math.Min(perPage, cps.Count - i0); int rows = (n + cols - 1) / cols;
            var dv = new DrawingVisual();
            using (var dc = dv.RenderOpen()) {
                dc.DrawRectangle(Brushes.White, null, new Rect(0, 0, cols * cellW, rows * cellH));
                for (int k = 0; k < n; k++) {
                    int c = cps[i0 + k]; double x = (k % cols) * cellW, y = (k / cols) * cellH;
                    var g = new FormattedText(char.ConvertFromUtf32(c), System.Globalization.CultureInfo.InvariantCulture, FlowDirection.LeftToRight, tf, 26, Brushes.Black);
                    dc.DrawText(g, new Point(x + (cellW - g.Width) / 2, y + 4));
                    var t = new FormattedText(c.ToString("X4"), System.Globalization.CultureInfo.InvariantCulture, FlowDirection.LeftToRight, new Typeface("Consolas"), 11, Brushes.Firebrick);
                    dc.DrawText(t, new Point(x + (cellW - t.Width) / 2, y + 40));
                    dc.DrawRectangle(null, new Pen(Brushes.Gainsboro, 1), new Rect(x, y, cellW, cellH));
                }
            }
            var bmp = new RenderTargetBitmap(cols * cellW, rows * cellH, 96, 96, PixelFormats.Pbgra32); bmp.Render(dv);
            var enc = new PngBitmapEncoder(); enc.Frames.Add(BitmapFrame.Create(bmp));
            using (var fs = File.Create(Path.Combine(outDir, "atlas_" + page.ToString("00") + ".png"))) enc.Save(fs);
        }
        return 0;
    }
}
