// Self-checking tests for File Preview, Markdown links and LaTeX, compiled against out-dev\MicroCode.exe by run-tests.cmd.
// Every fixture is generated in a fresh temp folder and the settings live in an isolated data dir, so a run never touches
// the user's %APPDATA%\MicroCode or any real project file.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using MicroCode.Core;
using MicroCode.Views;

static class PreviewTests
{
    static int _pass, _fail;

    static void Check(bool ok, string name)
    {
        Console.WriteLine((ok ? "PASS  " : "FAIL  ") + name);
        if (ok) _pass++; else _fail++;
    }

    static string Hash(string path)
    {
        using (var sha = SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(File.ReadAllBytes(path)));
    }

    /// <summary>A minimal valid PDF with the given number of Letter pages (612 × 792 pt), xref offsets computed.</summary>
    static void WritePdf(string path, int pages)
    {
        var objs = new List<string>();
        objs.Add("<< /Type /Catalog /Pages 2 0 R >>");
        var kids = string.Join(" ", Enumerable.Range(0, pages).Select(i => (3 + i * 2) + " 0 R"));
        objs.Add("<< /Type /Pages /Kids [" + kids + "] /Count " + pages + " >>");
        for (int i = 0; i < pages; i++)
        {
            string stream = "BT /F1 24 Tf 72 700 Td (Page " + (i + 1) + ") Tj ET";
            objs.Add("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents " + (4 + i * 2) + " 0 R /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> >>");
            objs.Add("<< /Length " + stream.Length + " >>\nstream\n" + stream + "\nendstream");
        }
        var sb = new StringBuilder("%PDF-1.4\n");
        var offsets = new List<int>();
        for (int i = 0; i < objs.Count; i++) { offsets.Add(sb.Length); sb.Append(i + 1).Append(" 0 obj\n").Append(objs[i]).Append("\nendobj\n"); }
        int xref = sb.Length;
        sb.Append("xref\n0 ").Append(objs.Count + 1).Append("\n0000000000 65535 f \n");
        foreach (var o in offsets) sb.Append(o.ToString("D10")).Append(" 00000 n \n");
        sb.Append("trailer\n<< /Size ").Append(objs.Count + 1).Append(" /Root 1 0 R >>\nstartxref\n").Append(xref).Append("\n%%EOF\n");
        File.WriteAllBytes(path, Encoding.ASCII.GetBytes(sb.ToString()));
    }

    static void WritePng(string path, int w, int h)
    {
        var dv = new DrawingVisual();
        using (var dc = dv.RenderOpen()) dc.DrawRectangle(Brushes.SteelBlue, null, new Rect(0, 0, w, h));
        var bmp = new RenderTargetBitmap(w, h, 96, 96, PixelFormats.Pbgra32);
        bmp.Render(dv);
        var enc = new PngBitmapEncoder();
        enc.Frames.Add(BitmapFrame.Create(bmp));
        using (var fs = File.Create(path)) enc.Save(fs);
    }

    [STAThread]
    static int Main()
    {
        string root = Path.Combine(Path.GetTempPath(), "MicroCode-tests-" + Guid.NewGuid().ToString("N").Substring(0, 8));
        string ws = Path.Combine(root, "ws");
        Directory.CreateDirectory(Path.Combine(ws, "docs", "deep"));
        Defaults.UseDir(Path.Combine(root, "data"));
        TaskFiles.HomeOverride = Path.Combine(root, "data", ".microcode");
        try
        {
            File.WriteAllText(Path.Combine(ws, "notes.md"), "# Notes\n\nSee [data](data.csv) and `main.py#L2-L3`.\n");
            File.WriteAllText(Path.Combine(ws, "data.csv"), "a,b\n1,\"x, y\"\n");
            File.WriteAllText(Path.Combine(ws, "main.py"), "import os\nprint(1)\nprint(2)\n");
            File.WriteAllText(Path.Combine(ws, "docs", "deep", "guide.md"), "# Guide\n");
            File.WriteAllBytes(Path.Combine(ws, "blob.dat"), new byte[] { 1, 2, 0, 3, 4 });
            File.WriteAllText(Path.Combine(ws, "utf16.txt"), "hello", Encoding.Unicode);
            File.WriteAllText(Path.Combine(ws, "run.bat"), "@echo off\n");
            WritePng(Path.Combine(ws, "chart.png"), 64, 32);
            WritePdf(Path.Combine(ws, "two.pdf"), 2);

            // ── file kinds ──
            Check(FileKinds.Detect(Path.Combine(ws, "notes.md")) == "markdown", "Detect: .md is markdown");
            Check(FileKinds.Detect(Path.Combine(ws, "data.csv")) == "table", "Detect: .csv is table");
            Check(FileKinds.Detect(Path.Combine(ws, "chart.png")) == "image", "Detect: .png is image");
            Check(FileKinds.Detect(Path.Combine(ws, "two.pdf")) == "pdf", "Detect: .pdf is pdf");
            Check(FileKinds.Detect(Path.Combine(ws, "main.py")) == "code", "Detect: .py is code");
            Check(FileKinds.Detect(Path.Combine(ws, "blob.dat")) == "binary", "Detect: NUL bytes mean binary");
            Check(FileKinds.Detect(Path.Combine(ws, "utf16.txt")) == "code", "Detect: UTF-16 text (BOM) stays text");
            Check(FilePreview.IsRunnable(Path.Combine(ws, "run.bat")) && !FilePreview.IsRunnable(Path.Combine(ws, "chart.png")), "Runnable files are never launched from a preview");

            // ── binary files open read-only and Save never rewrites them ──
            var app = AppState.Shared;
            app.OpenWorkspace(ws);
            string pdf = Path.Combine(ws, "two.pdf"), before = Hash(pdf);
            app.LoadFile(pdf);
            var f = app.CurrentFile;
            Check(f != null && f.ReadOnly && f.PreviewKind == "pdf" && f.Content == "", "LoadFile: PDF opens as a read-only preview");
            app.UpdateContent(f, "garbage");
            app.Save(f);
            app.SaveCurrentFile();
            Check(Hash(pdf) == before && !f.IsUnsaved, "Save: a previewed PDF stays byte-identical");
            app.LoadFile(Path.Combine(ws, "main.py"));
            var py = app.CurrentFile;
            Check(py != null && !py.ReadOnly && py.PreviewKind == null, "LoadFile: source files stay editable");
            app.UpdateContent(py, "print(3)\n");
            app.Save(py);
            Check(File.ReadAllText(Path.Combine(ws, "main.py")) == "print(3)\n", "Save: editable files still save");
            File.WriteAllText(Path.Combine(ws, "main.py"), "import os\nprint(1)\nprint(2)\n");

            // ── link resolution ──
            Check(string.Equals(MarkdownView.ResolveFile("data.csv", ws), Path.Combine(ws, "data.csv"), StringComparison.OrdinalIgnoreCase), "ResolveFile: relative to the document folder");
            Check(string.Equals(MarkdownView.ResolveFile("../notes.md", Path.Combine(ws, "docs")), Path.Combine(ws, "notes.md"), StringComparison.OrdinalIgnoreCase), "ResolveFile: ../ paths");
            Check(string.Equals(MarkdownView.ResolveFile("guide.md", null), Path.Combine(ws, "docs", "deep", "guide.md"), StringComparison.OrdinalIgnoreCase), "ResolveFile: bare name found by workspace search");
            Check(MarkdownView.ResolveFile("missing.md", ws) == null, "ResolveFile: missing file is null");

            app.AgenticContextVisible = true; // links go to the Preview pane
            MarkdownView.OpenLink("main.py#L2-L3", ws);
            Check(PreviewDock.Active != null && PreviewDock.Active.Path.EndsWith("main.py") && PreviewDock.Active.Start == 2 && PreviewDock.Active.End == 3 && PreviewDock.Tab == "preview", "OpenLink: #L2-L3 opens main.py lines 2-3 in Preview");
            MarkdownView.OpenLink("microcode-file://" + Uri.EscapeDataString("main.py:3"), ws);
            Check(PreviewDock.Active.Start == 3 && PreviewDock.Active.End == 3, "OpenLink: file chip with :3 line");
            MarkdownView.OpenLink("chart.png", ws);
            Check(PreviewDock.Active.Kind == "image", "OpenLink: image opens as image preview");
            int items = PreviewDock.Items.Count;
            MarkdownView.OpenLink("main.py", ws);
            Check(PreviewDock.Items.Count == items, "OpenLink: re-opening reuses the same preview tab");

            // ── PDF via Windows.Data.Pdf ──
            var sizes = PdfRender.PageSizes(pdf, 400).Result;
            Check(sizes.Count == 2, "PdfRender: page count 2 (got " + sizes.Count + ")");
            Check(sizes.Count > 0 && Math.Abs(sizes[0].Width / sizes[0].Height - 612.0 / 792.0) < 0.01, "PdfRender: Letter aspect ratio (" + (sizes.Count > 0 ? sizes[0].Width + "x" + sizes[0].Height : "-") + ")");
            var png = PdfRender.Page(pdf, 1, 800).Result;
            Check(png.Length > 100 && png[1] == (byte)'P' && png[2] == (byte)'N' && png[3] == (byte)'G', "PdfRender: page 2 renders to PNG (" + png.Length + " bytes)");

            // ── Markdown renders without throwing (tables, alerts, HTML, images, math) ──
            string md = "---\ntitle: x\n---\n<p align=\"center\"><img src=\"chart.png\" width=\"40\"></p>\n\n# H\n\n> [!NOTE]\n> hi\n\n| a | b |\n|:-|-:|\n| 1 | `x \\| y` |\n\n- [x] done\n  - nested\n\n![c](chart.png) ~~old~~ <https://example.com>\n\n$$\\frac{a}{b}$$\n\n```python\nprint(1)\n```\n";
            Exception mdErr = null;
            try { var e = MarkdownView.Render(md, 14, ws); ((UIElement)e).Measure(new Size(800, double.PositiveInfinity)); } catch (Exception ex) { mdErr = ex; }
            Check(mdErr == null, "MarkdownView.Render: full document renders" + (mdErr != null ? " — " + mdErr.Message : ""));

            // ── Preview dock: default runtime tabs, document pruning, closing the last tab ──
            PreviewDock.Items.Clear(); PreviewDock.Active = null;
            PreviewDock.EnsureDefaultTabs();
            Check(string.Join(",", PreviewDock.Items.Select(x => x.Kind)) == "web,ios,android", "Dock: default tabs are WebApp Preview, iOS Sim, Android Emu");
            PreviewDock.OpenFile(Path.Combine(ws, "notes.md"));
            Check(PreviewDock.Items.Count == 1 && PreviewDock.Active.Kind == "markdown", "Dock: opening a document closes idle runtime tabs");
            PreviewDock.SelectStandard("web");
            Check(PreviewDock.Items[0].Kind == "web" && PreviewDock.Active.Kind == "web", "Dock: WebApp Preview comes back first");
            foreach (var x in PreviewDock.Items.ToList()) PreviewDock.Close(x);
            Check(PreviewDock.Items.Count == 3, "Dock: closing every tab restores the default tabs");
            Check(WebViewport.Find("iphone").ScreenW == 402 && WebViewport.Find("ipad").ScreenW == 834 && WebViewport.Find("nope").IsResponsive, "Viewports: real CSS sizes, unknown id falls back to Responsive");

            // ── dev server detection ──
            File.WriteAllText(Path.Combine(ws, "package.json"), "{\"scripts\":{\"build\":\"vite build\",\"dev\":\"vite\"}}");
            Check(DevServer.DetectCommand(ws) == "npm run dev", "DevServer: package.json dev script → npm run dev");
            File.WriteAllText(Path.Combine(ws, "pnpm-lock.yaml"), "");
            Check(DevServer.DetectCommand(ws) == "pnpm run dev", "DevServer: pnpm lockfile → pnpm run dev");
            File.WriteAllText(Path.Combine(ws, "package.json"), "{\"scripts\":{\"start\":\"node server.js\"}}");
            File.Delete(Path.Combine(ws, "pnpm-lock.yaml"));
            Check(DevServer.DetectCommand(ws) == "npm start", "DevServer: start script → npm start");
            File.Delete(Path.Combine(ws, "package.json"));
            Check(DevServer.DetectCommand(ws) == null, "DevServer: no package.json → nothing to run");
            var ports = LocalPorts.Listening();
            Check(ports.All(p => p.Port >= 1024 && p.Process != "svchost" && p.Process != "System"), "LocalPorts: only user ports, no system services (" + ports.Count + " found)");

            // ── LaTeX layouts ──
            var tex = new[]
            {
                @"\frac{1}{n}\sum_{i=1}^{n} x_i", @"\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}", @"e^{i\pi} + 1 = 0",
                @"f(x) = \begin{cases} x^2 & \text{if } x \ge 0 \\ -x & \text{otherwise} \end{cases}",
                @"\begin{aligned} \nabla \cdot \mathbf{E} &= \frac{\rho}{\varepsilon_0} \\ \nabla \times \mathbf{B} &= \mu_0 \mathbf{J} \end{aligned}",
                @"A = \begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}", @"\sqrt[3]{x^3 + y^3}", @"\left( \frac{a}{b} \right)^2",
                @"\lim_{x \to 0} \frac{\sin x}{x} = 1", @"\binom{n}{k} = \frac{n!}{k!(n-k)!}", @"\hat{x} \vec{v} \overline{AB}",
                @"\mathbb{R}^n \mathcal{L} \mathfrak{g} \operatorname{argmax}_x", @"a \not= b \pmod{3}", @"\text{ความเร็ว } v = \frac{\Delta s}{\Delta t}",
                @"\begin{bmatrix} a & b \\ c & d \end{bmatrix}^{-1}", @"\prod_{k=1}^{\infty} \left(1 - \frac{1}{p_k^s}\right)^{-1}"
            };
            foreach (var x in tex)
            {
                var mv = new MathView(x, 16, true, Brushes.White);
                mv.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
                Check(!mv.Failed && mv.DesiredSize.Width > 10 && mv.DesiredSize.Height > 10, "TeX: " + x);
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine("FAIL  unexpected: " + ex);
            _fail++;
        }
        finally
        {
            try { Directory.Delete(root, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
        Console.WriteLine();
        Console.WriteLine(_pass + " passed, " + _fail + " failed");
        return _fail == 0 ? 0 : 1;
    }
}
