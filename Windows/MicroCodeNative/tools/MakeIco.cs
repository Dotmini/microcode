// Builds a multi-resolution Windows .ico (PNG-compressed entries) from a square PNG using WPF scaling.
using System;
using System.Collections.Generic;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
public static class MakeIco {
    [STAThread]
    public static int Main(string[] a) {
        var src = BitmapFrame.Create(new Uri(Path.GetFullPath(a[0])), BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
        int[] sizes = { 16, 20, 24, 32, 40, 48, 64, 128, 256 };
        var pngs = new List<byte[]>();
        foreach (int s in sizes) {
            var dv = new DrawingVisual();
            using (var dc = dv.RenderOpen()) { RenderOptions.SetBitmapScalingMode(dv, BitmapScalingMode.HighQuality); dc.DrawImage(src, new Rect(0, 0, s, s)); }
            var rtb = new RenderTargetBitmap(s, s, 96, 96, PixelFormats.Pbgra32); rtb.Render(dv);
            var enc = new PngBitmapEncoder(); enc.Frames.Add(BitmapFrame.Create(rtb));
            using (var ms = new MemoryStream()) { enc.Save(ms); pngs.Add(ms.ToArray()); }
        }
        using (var fs = File.Create(a[1])) using (var w = new BinaryWriter(fs)) {
            w.Write((short)0); w.Write((short)1); w.Write((short)sizes.Length);
            int offset = 6 + 16 * sizes.Length;
            for (int i = 0; i < sizes.Length; i++) {
                w.Write((byte)(sizes[i] >= 256 ? 0 : sizes[i])); w.Write((byte)(sizes[i] >= 256 ? 0 : sizes[i]));
                w.Write((byte)0); w.Write((byte)0); w.Write((short)1); w.Write((short)32);
                w.Write(pngs[i].Length); w.Write(offset); offset += pngs[i].Length;
            }
            foreach (var p in pngs) w.Write(p);
        }
        Console.WriteLine("ico written: " + a[1]);
        return 0;
    }
}
