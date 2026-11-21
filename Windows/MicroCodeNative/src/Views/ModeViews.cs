// Mode surfaces reachable from "More Mode": Playground, Cell Mode, API Studio and the Web Browser are ported; the remaining studios show their entry surface.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using MicroCode.Core;
using MicroCode.Editor;
using MicroCode.UI;

namespace MicroCode.Views
{
    public static class ModeViews
    {
        public static UIElement Create(EditorMode mode, AppState app)
        {
            if (mode == EditorMode.Playground) return new PlaygroundView(app);
            if (mode == EditorMode.Notebook) return new NotebookView(app);
            if (mode == EditorMode.ApiClient) return new ApiStudioView(app);
            if (mode == EditorMode.Browser) return new IdeBrowserView(app);
            return new StudioPlaceholder(EditorModeInfo.DisplayName(mode), EditorModeInfo.Icon(mode));
        }

        public static void ShowStudio(string name)
        {
            var t = Theme.Current;
            var w = new Window { Title = name, Width = 900, Height = 600, Owner = Application.Current.MainWindow, WindowStartupLocation = WindowStartupLocation.CenterOwner, Background = t.WorkspaceBackground, FontFamily = UIFonts.UI };
            w.SourceInitialized += delegate { Native.StyleWindow(w, t.IsDark); };
            w.Content = new StudioPlaceholder(name, "square.grid.2x2");
            w.Show();
        }
    }

    public class StudioPlaceholder : Grid
    {
        public StudioPlaceholder(string name, string icon)
        {
            var t = Theme.Current;
            Background = t.EditorBackground;
            Children.Add(V.Vs(10, V.Sp(), Sym.Icon(icon, 34, t.P(0.85)), V.T(name, 20, FontWeights.SemiBold, t.Primary),
                V.T("This studio is being ported to the Windows build.", 12.5, FontWeights.Normal, t.Secondary), V.Sp()));
        }
    }

    /// <summary>Port of PlaygroundView: toolbar + code editor + output pane.</summary>
    public class PlaygroundView : Grid
    {
        readonly AppState _app;
        string _language = Defaults.Str("playground_language", "python");
        bool _showOutput = true, _showPreview, _showData, _autoRun, _hotReload, _cellMode, _executing;
        double _execTime;
        readonly StringBuilder _output = new StringBuilder();
        CodeEditorView _editor;
        TextBox _outBox;
        readonly Border _toolbar = new Border(), _main = new Border();
        Process _proc;
        System.Windows.Threading.DispatcherTimer _autoTimer;

        static readonly string[] Languages = { "python", "r", "julia", "ruby", "swift", "rust", "go", "c", "c++", "javascript", "typescript", "java", "kotlin", "php", "perl", "lua", "dart", "shell", "powershell", "sql", "markdown", "html" };

        public PlaygroundView(AppState app)
        {
            _app = app;
            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(1) });
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            SetRow(_toolbar, 0); Children.Add(_toolbar);
            var div = V.Line(Theme.Current.Separator, true); SetRow(div, 1); Children.Add(div);
            SetRow(_main, 2); Children.Add(_main);
            _editor = new CodeEditorView(Defaults.Str("playground_code_" + _language, DefaultCode(_language)), LangKey(_language), Defaults.Num("playgroundFontSize", 13), UIFonts.Code("playgroundFontName", "SF Mono"));
            _editor.TextEdited += text =>
            {
                Defaults.Set("playground_code_" + _language, text);
                if (_autoRun)
                {
                    if (_autoTimer == null) { _autoTimer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(900) }; _autoTimer.Tick += delegate { _autoTimer.Stop(); Run(); }; }
                    _autoTimer.Stop(); _autoTimer.Start();
                }
            };
            Render();
        }

        static string LangKey(string l) { return l == "c++" ? "cpp" : l; }

        static string DefaultCode(string lang)
        {
            switch (lang)
            {
                case "python": return "print(\"Hello Thailand 1st IDE !\")\n\nsquares = [x**2 for x in range(10)]\n\nprint(f\"Squares: {squares}\")\n";
                case "javascript": return "console.log(\"Hello from MicroCode Playground\");\n";
                case "typescript": return "const greet = (name: string): string => `Hello, ${name}`;\nconsole.log(greet(\"MicroCode\"));\n";
                case "go": return "package main\n\nimport \"fmt\"\n\nfunc main() {\n    fmt.Println(\"Hello from MicroCode Playground\")\n}\n";
                case "rust": return "fn main() {\n    println!(\"Hello from MicroCode Playground\");\n}\n";
                case "c": return "#include <stdio.h>\n\nint main(void) {\n    printf(\"Hello from MicroCode Playground\\n\");\n    return 0;\n}\n";
                case "c++": return "#include <iostream>\n\nint main() {\n    std::cout << \"Hello from MicroCode Playground\" << std::endl;\n}\n";
                case "ruby": return "puts \"Hello from MicroCode Playground\"\n";
                case "powershell": return "Write-Output \"Hello from MicroCode Playground\"\n";
                default: return "";
            }
        }

        static string Icon(string lang)
        {
            switch (lang) { case "python": return "chevron.left.forwardslash.chevron.right"; case "javascript": case "typescript": return "curlybraces"; case "rust": return "gearshape.2"; case "markdown": return "doc.richtext"; default: return "doc.text"; }
        }

        UIElement Toggle(string icon, string label, bool on, Action act)
        {
            var t = Theme.Current;
            var ctrl = Theme.B(Theme.WithAlpha(t.Def.EditorBackground, 0.85));
            var b = V.Button(V.Box(V.H(4, Sym.Icon(icon, 11, on ? Brushes.White : t.Secondary), V.T(label, 11, FontWeights.Medium, on ? Brushes.White : t.Secondary)), V.P(5, 5), on ? Theme.B(Theme.WithAlpha(Colors.White, 0.16)) : ctrl, 6, on ? Theme.B(Theme.WithAlpha(Colors.White, 0.22)) : Brushes.Transparent, 1), act);
            return b;
        }

        void Render()
        {
            var t = Theme.Current;
            var ctrl = Theme.B(Theme.WithAlpha(t.Def.EditorBackground, 0.85));
            var lang = V.Button(V.Box(V.H(6, Sym.Icon(Icon(_language), 12, t.Accent), V.T(Cap(_language), 12, FontWeights.SemiBold, t.Primary), Sym.Icon("chevron.down", 9, t.Secondary, FontWeights.Bold)), V.P(10, 5), ctrl, 6), null);
            lang.MenuItems = () => Languages.Select(l => new MenuItemSpec { Title = Cap(l), Checked = l == _language, Action = () => SetLanguage(l) }).ToList();
            var gear = V.Button(V.Box(Sym.Icon("gearshape.fill", 12, t.Secondary), V.P(6), ctrl, 6), () => SettingsWindow.Show(_app));
            var seg = V.Box(V.H(0,
                V.Button(V.Box(V.T("Editor", 11.5, FontWeights.Medium, !_cellMode ? t.Primary : t.Secondary), V.P(14, 3), !_cellMode ? t.P(0.16) : Brushes.Transparent, 5), () => { _cellMode = false; Render(); }),
                V.Button(V.Box(V.T("Cell Mode", 11.5, FontWeights.Medium, _cellMode ? t.Primary : t.Secondary), V.P(14, 3), _cellMode ? t.P(0.16) : Brushes.Transparent, 5), () => { _app.SwitchToMode(EditorMode.Notebook); })), V.P(2), t.P(0.06), 6);
            var runFg = _executing ? Theme.B(Theme.Rgb(255, 115, 115)) : Brushes.White;
            var run = V.Button(V.Box(V.H(5, Sym.Icon(_executing ? "stop.fill" : "play.fill", 10, runFg, FontWeights.Bold), V.T(_executing ? "Stop" : "Run", 12, FontWeights.SemiBold, runFg)), V.P(12, 5),
                _executing ? Theme.B(Theme.Rgb(89, 26, 26)) : Theme.B(Theme.Rgb(31, 31, 31)), 6, _executing ? t.Op(t.SysRed, 0.4) : Theme.B(Theme.WithAlpha(Colors.White, 0.22)), 1), () => { if (_executing) Stop(); else Run(); });
            run.ToolTip = "Run (Ctrl+R)";
            var trash = V.Button(V.Box(Sym.Icon("trash", 11, t.Secondary), V.P(6), ctrl, 6), () => { _output.Clear(); _execTime = 0; UpdateOutput(); Render(); });
            trash.ToolTip = "Clear Output";
            var autoRun = V.H(6, V.T("Auto-run", 11, FontWeights.Normal, t.Primary), MiniSwitch(_autoRun, v => { _autoRun = v; }));
            var bar = V.H(4, lang, gear, V.Size(V.Line(t.Separator, false), 1, 16), seg,
                Toggle("folder.badge.gearshape", "Open", false, OpenFile), Toggle("square.and.arrow.down", "Save", false, SaveFile),
                V.Sp(), // the Mac's "Document" sheet is not ported yet; the button is left out rather than doing nothing
                Toggle("folder", "Data", _showData, () => { _showData = !_showData; Render(); }),
                Toggle("terminal", "Output", _showOutput, () => { _showOutput = !_showOutput; Render(); }),
                Toggle("macwindow", "Preview", _showPreview, () => { _showPreview = !_showPreview; Render(); }),
                V.Size(V.Line(t.Separator, false), 1, 16), autoRun,
                Toggle("bolt.fill", "Hot Reload", _hotReload, () => { _hotReload = !_hotReload; _autoRun = _hotReload; Render(); }));
            if (_execTime > 0) bar.Children.Add(V.Box(V.H(4, Sym.Icon("clock", 10, t.Secondary), V.T(_execTime.ToString("0.00") + "s", 10, FontWeights.Medium, t.Secondary)), V.P(6, 5), ctrl, 4));
            bar.Children.Add(run); bar.Children.Add(trash);
            _toolbar.Child = V.Box(bar, V.P(12, 8), t.PanelBackground, 0);

            // panes
            var codeHeader = V.Box(V.H(6, Sym.Icon("chevron.left.forwardslash.chevron.right", 10, t.Accent), V.T("Code", 11, FontWeights.SemiBold, t.Primary), V.Sp()), V.P(10, 6), t.PanelBackground, 0);
            var codePane = new Grid();
            codePane.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            codePane.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            codePane.Children.Add(codeHeader);
            if (_editor.Parent is Panel) ((Panel)_editor.Parent).Children.Remove(_editor);
            Grid.SetRow(_editor, 1); codePane.Children.Add(_editor);
            if (!_showOutput && !_showPreview) { _main.Child = codePane; return; }
            var outPane = new Grid { Background = t.EditorBackground };
            outPane.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            outPane.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            outPane.Children.Add(V.Box(V.H(6, Sym.Icon("terminal", 10, t.SysGreen), V.T("Output", 11, FontWeights.SemiBold, t.Primary), V.Sp()), V.P(10, 6), t.PanelBackground, 0));
            if (_outBox == null)
            {
                _outBox = new TextBox { IsReadOnly = true, FontFamily = UIFonts.Mono, FontSize = 13, BorderThickness = new Thickness(0), Background = Brushes.Transparent, Padding = new Thickness(4, 6, 4, 6), TextWrapping = TextWrapping.Wrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, CaretBrush = Brushes.Transparent };
            }
            _outBox.Foreground = t.EditorText;
            if (_outBox.Parent is Panel) ((Panel)_outBox.Parent).Children.Remove(_outBox);
            Grid.SetRow(_outBox, 1); outPane.Children.Add(_outBox);
            UpdateOutput();
            var split = new Grid();
            split.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0.55, GridUnitType.Star), MinWidth = 200 });
            split.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(4) });
            split.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0.45, GridUnitType.Star), MinWidth = 200 });
            split.Children.Add(codePane);
            var gs = new GridSplitter { Width = 4, HorizontalAlignment = HorizontalAlignment.Stretch, Background = t.P(0.08) };
            Grid.SetColumn(gs, 1); split.Children.Add(gs);
            Grid.SetColumn(outPane, 2); split.Children.Add(outPane);
            _main.Child = split;
        }

        static UIElement MiniSwitch(bool on, Action<bool> changed)
        {
            var t = Theme.Current;
            var knob = new System.Windows.Shapes.Ellipse { Width = 14, Height = 14, Fill = Brushes.White, HorizontalAlignment = on ? HorizontalAlignment.Right : HorizontalAlignment.Left, Margin = new Thickness(1.5) };
            var track = new Border { Width = 30, Height = 17, CornerRadius = new CornerRadius(8.5), Background = on ? t.Accent : t.P(0.2), Child = knob };
            var b = V.Button(track, null);
            b.Click += delegate { on = !on; knob.HorizontalAlignment = on ? HorizontalAlignment.Right : HorizontalAlignment.Left; track.Background = on ? t.Accent : t.P(0.2); changed(on); };
            return b;
        }

        static string Cap(string s) { return string.IsNullOrEmpty(s) ? s : char.ToUpper(s[0]) + s.Substring(1); }

        void SetLanguage(string l)
        {
            _language = l;
            Defaults.Set("playground_language", l);
            _editor.SetLanguage(LangKey(l));
            _editor.Box.Text = Defaults.Str("playground_code_" + l, DefaultCode(l));
            Render();
        }

        void UpdateOutput()
        {
            if (_outBox == null) return;
            _outBox.Text = _output.ToString();
            _outBox.ScrollToEnd();
        }

        void Run()
        {
            Stop();
            string ext = _language == "python" ? "py" : _language == "javascript" ? "js" : _language == "typescript" ? "ts" : _language == "c++" ? "cpp" : _language == "ruby" ? "rb" : _language == "rust" ? "rs" : _language == "powershell" ? "ps1" : _language == "shell" ? "sh" : _language == "kotlin" ? "kt" : _language == "julia" ? "jl" : _language == "perl" ? "pl" : _language;
            string dir = Path.Combine(Path.GetTempPath(), "MicroCodePlayground");
            Directory.CreateDirectory(dir);
            string file = Path.Combine(dir, "main." + ext);
            File.WriteAllText(file, _editor.Text);
            string exe, args;
            _output.Clear();
            if (!Runner.CommandFor(LangKey(_language), file, out exe, out args)) { _output.Append("No runtime configured for " + Cap(_language) + " on Windows.\n"); UpdateOutput(); return; }
            var sw = Stopwatch.StartNew();
            _executing = true; Render();
            var psi = new ProcessStartInfo(exe, args) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true, WorkingDirectory = dir, StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8 };
            psi.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8";
            var p = new Process { StartInfo = psi, EnableRaisingEvents = true };
            DataReceivedEventHandler h = (s, e) => { if (e.Data != null) Dispatcher.BeginInvoke(new Action(() => { _output.Append(e.Data).Append('\n'); UpdateOutput(); })); };
            p.OutputDataReceived += h; p.ErrorDataReceived += h;
            p.Exited += delegate
            {
                p.WaitForExit();
                int code = p.ExitCode;
                Dispatcher.BeginInvoke(new Action(() =>
                {
                    _execTime = sw.Elapsed.TotalSeconds;
                    _output.Append("\nExited with code " + code + " in " + _execTime.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture) + "s\n");
                    _executing = false; _proc = null; UpdateOutput(); Render();
                }));
            };
            try { p.Start(); p.BeginOutputReadLine(); p.BeginErrorReadLine(); _proc = p; }
            catch (Exception ex) { _output.Append("Failed to start '" + exe + "': " + ex.Message + "\n"); _executing = false; UpdateOutput(); Render(); }
        }

        void Stop()
        {
            try { if (_proc != null && !_proc.HasExited) _proc.Kill(); } catch { }
            _proc = null;
            if (_executing) { _executing = false; Render(); }
        }

        void OpenFile()
        {
            var dlg = new Microsoft.Win32.OpenFileDialog { Filter = "MicroCode Playground (*.microplay)|*.microplay|All files|*.*" };
            if (dlg.ShowDialog() == true) _editor.Box.Text = File.ReadAllText(dlg.FileName);
        }

        void SaveFile()
        {
            var dlg = new Microsoft.Win32.SaveFileDialog { Filter = "MicroCode Playground (*.microplay)|*.microplay", FileName = "playground.microplay" };
            if (dlg.ShowDialog() == true) File.WriteAllText(dlg.FileName, _editor.Text);
        }
    }
}
