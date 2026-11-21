// Port of Views/Components/AuthenticFileTree.swift (NSOutlineView, plain style, rowHeight 24, insets top 4 / bottom 12).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using MicroCode.Core;
using MicroCode.UI;

namespace MicroCode.Views
{
    public class FileTreeView : FrameworkElement
    {
        class Row { public FileNode Node; public int Level; }

        const double RowH = 24, TopInset = 4, BottomInset = 12, Indent = 14;
        readonly AppState _app;
        readonly List<Row> _rows = new List<Row>();
        readonly HashSet<string> _expanded = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        public ScrollViewer Scroller;
        string _selected;
        List<FileNode> _source;
        bool _filtered;

        public FileTreeView(AppState app)
        {
            _app = app;
            Focusable = true;
            FocusVisualStyle = null;
            SnapsToDevicePixels = true;
            Scroller = new ScrollViewer
            {
                Content = this, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
                Focusable = false, Background = Brushes.Transparent
            };
            Scroller.ScrollChanged += delegate { InvalidateVisual(); };
            GotKeyboardFocus += delegate { InvalidateVisual(); };
            LostKeyboardFocus += delegate { InvalidateVisual(); };
        }

        public void SetSource(List<FileNode> nodes, bool filtered)
        {
            _source = nodes;
            _filtered = filtered;
            Rebuild();
        }

        public void Rebuild()
        {
            _rows.Clear();
            if (_source != null) Flatten(_source, 0);
            InvalidateMeasure();
            InvalidateVisual();
        }

        void Flatten(List<FileNode> nodes, int level)
        {
            foreach (var n in nodes)
            {
                _rows.Add(new Row { Node = n, Level = level });
                if (n.IsDirectory && (_filtered || _expanded.Contains(n.Path)))
                {
                    if (!_filtered) _app.LoadChildren(n);
                    Flatten(n.Children, level + 1);
                }
            }
        }

        protected override Size MeasureOverride(Size availableSize)
        {
            return new Size(0, TopInset + _rows.Count * RowH + BottomInset);
        }

        // AuthenticFileTree.fileIconName(for:isDirectory:) / iconColor(for:isDirectory:)
        public static string IconName(string name, bool dir)
        {
            if (dir) return "folder.fill";
            switch ((System.IO.Path.GetExtension(name) ?? "").TrimStart('.').ToLowerInvariant())
            {
                case "swift": return "swift";
                case "py": return "curlybraces.square";
                case "js": case "ts": return "curlybraces";
                case "rs": return "gearshape.2";
                case "json": return "curlybraces.square";
                case "md": return "doc.richtext";
                case "plist": return "list.bullet.rectangle";
                case "storyboard": case "xib": return "square.grid.2x2";
                case "entitlements": return "lock.doc";
                default: return "doc.text";
            }
        }

        public static Brush IconColor(string name, bool dir)
        {
            var t = Theme.Current;
            if (dir) return Theme.B(Theme.Rgb(245, 191, 77)); // Xcode yellow folder (0.96, 0.75, 0.30)
            switch ((System.IO.Path.GetExtension(name) ?? "").TrimStart('.').ToLowerInvariant())
            {
                case "swift": return t.SysOrange;
                case "py": return t.SysGreen;
                case "js": return t.SysYellow;
                case "ts": return t.SysBlue;
                case "rs": return t.SysOrange;
                case "json": return t.SysPurple;
                case "md": return t.SysCyan;
                case "plist": case "entitlements": return t.SysGray;
                default: return t.Secondary;
            }
        }

        static readonly Dictionary<string, int> GlyphCache = new Dictionary<string, int>();

        protected override void OnRender(DrawingContext dc)
        {
            var t = Theme.Current;
            double w = ActualWidth;
            dc.DrawRectangle(Brushes.Transparent, null, new Rect(0, 0, w, ActualHeight));
            double dip = VisualTreeHelper.GetDpi(this).PixelsPerDip;
            double top = Scroller != null ? Scroller.VerticalOffset : 0;
            double vh = Scroller != null && Scroller.ViewportHeight > 0 ? Scroller.ViewportHeight : ActualHeight;
            int first = Math.Max(0, (int)Math.Floor((top - TopInset) / RowH));
            int last = Math.Min(_rows.Count - 1, (int)Math.Ceiling((top + vh - TopInset) / RowH));
            bool focused = IsKeyboardFocusWithin;
            var uiFace = new Typeface(UIFonts.UI, FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
            var iconFace = new Typeface(UIFonts.Icons, FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
            for (int i = first; i <= last; i++)
            {
                var r = _rows[i];
                double y = TopInset + i * RowH;
                bool sel = _selected != null && string.Equals(_selected, r.Node.Path, StringComparison.OrdinalIgnoreCase);
                if (sel) dc.DrawRectangle(focused ? t.SelectedContent : Theme.B(t.IsDark ? Theme.Rgb(70, 70, 70) : Theme.Rgb(220, 220, 220)), null, new Rect(0, y, w, RowH));
                double baseX = 6 + r.Level * Indent;
                Brush text = sel && focused ? Brushes.White : t.Primary;
                if (r.Node.IsDirectory)
                {
                    bool open = _filtered || _expanded.Contains(r.Node.Path);
                    var chev = new FormattedText(char.ConvertFromUtf32(open ? 0xE70D : 0xE76C), CultureInfo.InvariantCulture, FlowDirection.LeftToRight, iconFace, 10, sel && focused ? Brushes.White : t.Secondary, dip);
                    dc.DrawText(chev, new Point(baseX + 5 - chev.Width / 2 + 2, y + (RowH - chev.Height) / 2));
                }
                // icon 16x16 at leading + 2
                double ix = baseX + 14;
                string glyph = Sym.GlyphText(IconName(r.Node.Name, r.Node.IsDirectory));
                var g = new FormattedText(glyph, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, iconFace, 15, sel && focused ? Brushes.White : IconColor(r.Node.Name, r.Node.IsDirectory), dip);
                dc.DrawText(g, new Point(ix + (16 - g.Width) / 2, y + (RowH - g.Height) / 2));
                var ft = new FormattedText(r.Node.Name, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, uiFace, 13, text, dip);
                double tx = ix + 16 + 5;
                ft.MaxTextWidth = Math.Max(1, w - tx - 6);
                ft.MaxLineCount = 1;
                ft.Trimming = TextTrimming.CharacterEllipsis;
                dc.DrawText(ft, new Point(tx, y + (RowH - ft.Height) / 2));
            }
        }

        int RowAt(Point p)
        {
            int i = (int)Math.Floor((p.Y - TopInset) / RowH);
            return i >= 0 && i < _rows.Count ? i : -1;
        }

        protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
        {
            Focus();
            var p = e.GetPosition(this);
            int i = RowAt(p);
            if (i < 0) return;
            var r = _rows[i];
            _selected = r.Node.Path;
            if (r.Node.IsDirectory)
            {
                Toggle(r.Node);
            }
            else
            {
                _app.LoadFile(r.Node.Path);
            }
            InvalidateVisual();
            e.Handled = true;
        }

        protected override void OnMouseRightButtonUp(MouseButtonEventArgs e)
        {
            var p = e.GetPosition(this);
            int i = RowAt(p);
            FileNode node = i >= 0 ? _rows[i].Node : null;
            if (node != null) { _selected = node.Path; InvalidateVisual(); }
            string dir = node == null ? _app.WorkspaceFolder : (node.IsDirectory ? node.Path : System.IO.Path.GetDirectoryName(node.Path));
            var items = new List<MenuItemSpec>();
            if (node != null && !node.IsDirectory) items.Add(MenuItemSpec.Item("Open", "doc.text", () => _app.LoadFile(node.Path)));
            items.Add(MenuItemSpec.Item("New File…", "doc.badge.plus", () => NewFileIn(dir)));
            items.Add(MenuItemSpec.Item("New Folder…", "folder.badge.plus", () => { if (dir != null) _app.CreateFolder(dir, "New Folder"); }));
            if (node != null)
            {
                items.Add(MenuItemSpec.Sep());
                items.Add(MenuItemSpec.Item("Rename…", "pencil", () => Rename(node)));
                items.Add(MenuItemSpec.Item("Copy Path", "doc.on.doc", () => Clipboard.SetText(node.Path)));
                items.Add(MenuItemSpec.Item("Reveal in File Explorer", "folder", () => System.Diagnostics.Process.Start("explorer.exe", "/select,\"" + node.Path + "\"")));
                items.Add(MenuItemSpec.Item("Open in Terminal", "terminal", () => System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("cmd.exe") { WorkingDirectory = dir })));
                items.Add(MenuItemSpec.Sep());
                items.Add(new MenuItemSpec { Title = "Move to Recycle Bin", Icon = "trash", Destructive = true, Action = () => Delete(node) });
            }
            MacMenu.ShowAtMouse(items);
            e.Handled = true;
        }

        void NewFileIn(string dir)
        {
            if (dir == null) { _app.NewFile(); return; }
            string name = Prompt.Ask("New File", "Name of the new file:", "untitled.txt");
            if (string.IsNullOrWhiteSpace(name)) return;
            string path = System.IO.Path.Combine(dir, name.Trim());
            try
            {
                if (!File.Exists(path)) { File.WriteAllText(path, ""); CollabHooks.FileEvent("write", path, null, ""); }
                _expanded.Add(dir); _app.RefreshFileTree(); _app.LoadFile(path);
            }
            catch (Exception ex) { MessageBox.Show(ex.Message, "MicroCode"); }
        }

        void Rename(FileNode node)
        {
            string name = Prompt.Ask("Rename", "New name:", node.Name);
            if (string.IsNullOrWhiteSpace(name) || name == node.Name) return;
            try
            {
                string target = System.IO.Path.Combine(System.IO.Path.GetDirectoryName(node.Path), name.Trim());
                if (node.IsDirectory) Directory.Move(node.Path, target); else File.Move(node.Path, target);
                CollabHooks.FileEvent("rename", node.Path, target);
                foreach (var f in _app.OpenFiles.Where(f => string.Equals(f.Path, node.Path, StringComparison.OrdinalIgnoreCase))) { f.Path = target; f.Name = System.IO.Path.GetFileName(target); }
                _app.RefreshFileTree();
                _app.Notify("files");
            }
            catch (Exception ex) { MessageBox.Show(ex.Message, "MicroCode"); }
        }

        void Delete(FileNode node)
        {
            try
            {
                if (node.IsDirectory) Microsoft.VisualBasic.FileIO.FileSystem.DeleteDirectory(node.Path, Microsoft.VisualBasic.FileIO.UIOption.OnlyErrorDialogs, Microsoft.VisualBasic.FileIO.RecycleOption.SendToRecycleBin);
                else Microsoft.VisualBasic.FileIO.FileSystem.DeleteFile(node.Path, Microsoft.VisualBasic.FileIO.UIOption.OnlyErrorDialogs, Microsoft.VisualBasic.FileIO.RecycleOption.SendToRecycleBin);
                if (!File.Exists(node.Path) && !Directory.Exists(node.Path)) CollabHooks.FileEvent("delete", node.Path);
            }
            catch (Exception ex) { MessageBox.Show(ex.Message, "MicroCode"); }
            _app.RefreshFileTree();
        }

        void Toggle(FileNode n)
        {
            if (_filtered) return;
            if (_expanded.Contains(n.Path)) _expanded.Remove(n.Path);
            else { _expanded.Add(n.Path); _app.LoadChildren(n); }
            Rebuild();
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            int i = _rows.FindIndex(r => string.Equals(r.Node.Path, _selected, StringComparison.OrdinalIgnoreCase));
            if (e.Key == Key.Down || e.Key == Key.Up)
            {
                int j = Math.Max(0, Math.Min(_rows.Count - 1, i + (e.Key == Key.Down ? 1 : -1)));
                if (_rows.Count > 0) { _selected = _rows[j].Node.Path; Reveal(j); if (!_rows[j].Node.IsDirectory) _app.LoadFile(_rows[j].Node.Path); }
                e.Handled = true;
            }
            else if ((e.Key == Key.Right || e.Key == Key.Left) && i >= 0 && _rows[i].Node.IsDirectory)
            {
                bool open = _expanded.Contains(_rows[i].Node.Path);
                if ((e.Key == Key.Right) != open) Toggle(_rows[i].Node);
                e.Handled = true;
            }
            else if (e.Key == Key.Enter && i >= 0)
            {
                if (_rows[i].Node.IsDirectory) Toggle(_rows[i].Node); else _app.LoadFile(_rows[i].Node.Path);
                e.Handled = true;
            }
            InvalidateVisual();
        }

        void Reveal(int i)
        {
            if (Scroller == null) return;
            double y = TopInset + i * RowH;
            if (y < Scroller.VerticalOffset) Scroller.ScrollToVerticalOffset(y);
            else if (y + RowH > Scroller.VerticalOffset + Scroller.ViewportHeight) Scroller.ScrollToVerticalOffset(y + RowH - Scroller.ViewportHeight);
        }

        public void SelectPath(string path)
        {
            _selected = path;
            InvalidateVisual();
        }
    }

    /// <summary>Small native text prompt (NSAlert with accessory text field equivalent).</summary>
    public static class Prompt
    {
        public static string Ask(string title, string message, string initial)
        {
            var t = Theme.Current;
            var w = new Window
            {
                Title = title, Width = 380, SizeToContent = SizeToContent.Height, WindowStartupLocation = WindowStartupLocation.CenterOwner,
                ResizeMode = ResizeMode.NoResize, Background = t.ElevatedBackground, ShowInTaskbar = false,
                Owner = Application.Current.MainWindow
            };
            TextBox box;
            var field = Styles.Field("", 13, t.Primary, t.Secondary, out box);
            box.Text = initial ?? "";
            string result = null;
            var ok = V.Button(V.Box(V.T("OK", 13, FontWeights.Medium, Brushes.White), V.P(16, 5), t.Accent, 6), null);
            var cancel = V.Button(V.Box(V.T("Cancel", 13, FontWeights.Normal, t.Primary), V.P(14, 5), t.P(0.1), 6), null);
            ok.Click += delegate { result = box.Text; w.DialogResult = true; };
            cancel.Click += delegate { w.DialogResult = false; };
            box.KeyDown += delegate(object s, KeyEventArgs e) { if (e.Key == Key.Enter) { result = box.Text; w.DialogResult = true; } else if (e.Key == Key.Escape) w.DialogResult = false; };
            w.Content = V.Box(V.VLead(10,
                V.T(message, 13, FontWeights.SemiBold, t.Primary),
                V.Self(V.Box(field, V.P(8, 5), t.P(0.06), 6, t.P(0.15), 1), Cross.Stretch),
                V.Self(V.H(8, V.Sp(), cancel, ok), Cross.Stretch)), V.P(18), null, 0);
            w.Loaded += delegate { Native.StyleWindow(w, t.IsDark); box.Focus(); box.SelectAll(); };
            w.ShowDialog();
            return result;
        }
    }
}
