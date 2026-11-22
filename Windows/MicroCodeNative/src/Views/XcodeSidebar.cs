// Port of XcodeEditorSidebar (Views/Workspace/WorkspaceXcodeNavigatorAndInspector.swift).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using MicroCode.Core;
using MicroCode.UI;

namespace MicroCode.Views
{
    public class XcodeSidebar : Grid
    {
        enum Tab { Project, SourceControl, Search, Issues }
        readonly AppState _app;
        Tab _tab = Tab.Project;
        readonly Border _tabBar = new Border(), _header = new Border(), _content = new Border(), _bottom = new Border();
        readonly FileTreeView _tree;
        string _filter = "";
        bool _recentOnly;
        TextBox _filterBox;
        // workspace search
        TextBox _searchBox, _replaceBox;
        bool _showReplace, _caseSensitive, _regex, _searching;
        List<Tuple<string, int, int, string>> _matches = new List<Tuple<string, int, int, string>>();
        string _replaceMessage;
        CancellationTokenSource _searchCts;
        DispatcherTimer _searchDebounce;

        public XcodeSidebar(AppState app)
        {
            _app = app;
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(36) });
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(30) });
            RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            SetRow(_tabBar, 0); SetRow(_header, 1); SetRow(_content, 2); SetRow(_bottom, 3);
            Children.Add(_tabBar); Children.Add(_header); Children.Add(_content); Children.Add(_bottom);
            _tree = new FileTreeView(app);
            BuildBottom();
            Render();
            app.Changed += OnChanged;
            Unloaded += delegate { };
        }

        void OnChanged(string what)
        {
            if (what == "workspace" || what == "tree" || what == "theme") Render();
            if (what == "files" && _app.CurrentFile != null) _tree.SelectPath(_app.CurrentFile.Path);
        }

        public void Render()
        {
            var t = Theme.Current;
            // MARK: navigatorTabBar — 70pt leading inset reserves the (auto-hidden) traffic lights
            var bar = V.H(2);
            bar.Children.Add(new Border { Width = 70 });
            foreach (Tab tab in Enum.GetValues(typeof(Tab)))
            {
                var tb = tab;
                bool sel = _tab == tab;
                string icon = tab == Tab.Project ? "folder" : tab == Tab.SourceControl ? "arrow.triangle.branch" : tab == Tab.Search ? "magnifyingglass" : "exclamationmark.triangle";
                string title = tab == Tab.Project ? "Project Navigator" : tab == Tab.SourceControl ? "Source Control" : tab == Tab.Search ? "Search in Workspace" : "Issue Navigator";
                var b = V.Button(V.Size(V.Box(Sym.Icon(sel ? icon + ".fill" : icon, 11, sel ? t.Accent : t.Secondary, sel ? FontWeights.SemiBold : FontWeights.Normal), V.P(0), sel ? t.P(0.10) : Brushes.Transparent, 4), 24, 22), () => { _tab = tb; Render(); });
                ((Border)b.Child).HorizontalAlignment = HorizontalAlignment.Center;
                ((Border)b.Child).Child.SetValue(FrameworkElement.HorizontalAlignmentProperty, HorizontalAlignment.Center);
                b.ToolTip = title;
                bar.Children.Add(b);
            }
            bar.Children.Add(V.Sp());
            _tabBar.Child = V.Box(bar, V.P(6, 0, 4, 0), null, 0);

            // MARK: projectHeaderBar
            bool hasWs = _app.WorkspaceFolder != null;
            var menuBtn = V.Size(V.Button(Sym.Icon("ellipsis.circle", 12, t.Secondary), null), 20, 20);
            menuBtn.ToolTip = "Project Options";
            menuBtn.MenuItems = ProjectMenu;
            _header.Child = V.Box(V.H(6,
                Sym.Icon(hasWs ? "folder.fill" : "folder", 11, hasWs ? t.Accent : t.Secondary),
                V.Shrink(V.T(hasWs ? Path.GetFileName(_app.WorkspaceFolder.TrimEnd('\\')) : "No Project", 11.5, FontWeights.SemiBold, t.Primary)),
                V.Sp(),
                menuBtn), V.P(10, 0), null, 0);

            // MARK: content
            switch (_tab)
            {
                case Tab.Project: _content.Child = hasWs ? ProjectContent() : EmptyProjectState(); break;
                case Tab.Search: _content.Child = SearchContent(); break;
                case Tab.SourceControl: _content.Child = new GitPanel(_app); break;
                default: _content.Child = IssuesContent(); break;
            }
        }

        List<MenuItemSpec> ProjectMenu()
        {
            var items = new List<MenuItemSpec>();
            items.Add(MenuItemSpec.Item("Open Project or Folder…", "folder.badge.plus", _app.OpenFolderDialog));
            items.Add(MenuItemSpec.Item("Open File…", "doc.badge.plus", _app.OpenFileDialog));
            var rp = AppState.RecentWorkspaces();
            var rf = AppState.RecentFiles();
            if (rp.Count > 0)
            {
                items.Add(MenuItemSpec.Sep());
                items.Add(MenuItemSpec.Sub("Recent Projects", null, rp.Take(8).Select(p => MenuItemSpec.Item(Path.GetFileName(p.TrimEnd('\\')), null, () => _app.OpenWorkspace(p))).ToList()));
            }
            if (rf.Count > 0) items.Add(MenuItemSpec.Sub("Recent Files", null, rf.Take(10).Select(p => MenuItemSpec.Item(Path.GetFileName(p), null, () => _app.LoadFile(p))).ToList()));
            items.Add(MenuItemSpec.Sep());
            items.Add(MenuItemSpec.Item("New File", "doc.badge.plus", _app.NewFile));
            items.Add(MenuItemSpec.Item("Refresh File Tree", "arrow.clockwise", _app.RefreshFileTree));
            if (_app.WorkspaceFolder != null)
            {
                items.Add(MenuItemSpec.Sep());
                items.Add(new MenuItemSpec { Title = "Close Project", Destructive = true, Action = _app.CloseWorkspace });
            }
            items.Add(MenuItemSpec.Sep());
            items.Add(MenuItemSpec.Item("Switch to AI Agent Mode", "brain", () => _app.SwitchToMode(EditorMode.AIAgent)));
            return items;
        }

        UIElement ProjectContent()
        {
            bool filtered = _filter.Trim().Length > 0 || _recentOnly;
            _tree.SetSource(filtered ? Filter(_app.FileTree, _filter.Trim(), _recentOnly) : _app.FileTree, filtered);
            if (_tree.Scroller.Parent is Decorator) ((Decorator)_tree.Scroller.Parent).Child = null;
            return _tree.Scroller;
        }

        List<FileNode> Filter(List<FileNode> nodes, string q, bool recentOnly)
        {
            var recent = new HashSet<string>(AppState.RecentFiles().Concat(_app.OpenFiles.Select(f => f.Path)), StringComparer.OrdinalIgnoreCase);
            var result = new List<FileNode>();
            foreach (var n in nodes)
            {
                if (n.IsDirectory)
                {
                    if (!n.Loaded && q.Length > 0) _app.LoadChildren(n);
                    var kids = Filter(n.Children, q, recentOnly);
                    if (kids.Count > 0) result.Add(new FileNode { Name = n.Name, Path = n.Path, IsDirectory = true, Loaded = true, Children = kids });
                }
                else
                {
                    bool mq = q.Length == 0 || n.Name.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0;
                    bool mr = !recentOnly || recent.Contains(n.Path);
                    if (mq && mr) result.Add(n);
                }
            }
            return result;
        }

        UIElement EmptyProjectState()
        {
            var t = Theme.Current;
            var openFolder = V.Button(V.Box(V.H(5, Sym.Icon("folder.badge.plus", 11, t.Accent), V.T("Open Folder…", 11, FontWeights.Medium, t.Accent)), V.P(10, 5), t.A(0.12), 6), _app.OpenFolderDialog);
            var openFile = V.Button(V.Box(V.H(5, Sym.Icon("doc", 11, t.Primary), V.T("Open File…", 11, FontWeights.Medium, t.Primary)), V.P(10, 5), t.P(0.06), 6), _app.OpenFileDialog);
            var head = V.Vs(8,
                V.Box(Sym.Icon("folder.badge.gearshape", 34, t.A(0.85)), V.P(0, 24, 0, 0), null, 0),
                V.T("Xcode Project Navigator", 13, FontWeights.SemiBold, t.Primary),
                V.Box(V.Wrap(V.T("Open a folder or file to explore and edit your code.", 11, FontWeights.Normal, t.Secondary), TextAlignment.Center), V.P(16, 0), null, 0),
                V.Box(V.H(10, openFolder, openFile), V.P(0, 4, 0, 0), null, 0));
            var stack = V.Vs(16, head);
            var rp = RecentSection("RECENT PROJECTS", AppState.RecentWorkspaces().Take(6).ToList(), true);
            if (rp != null) stack.Children.Add(rp);
            var rf = RecentSection("RECENT FILES", AppState.RecentFiles().Take(6).ToList(), false);
            if (rf != null) stack.Children.Add(rf);
            return new ScrollViewer { Content = V.Box(stack, V.P(0, 0, 0, 16), null, 0), VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        }

        UIElement RecentSection(string title, List<string> paths, bool projects)
        {
            if (paths.Count == 0) return null;
            var t = Theme.Current;
            var list = V.Vs(2);
            list.Align = Cross.Stretch;
            foreach (var p in paths)
            {
                string path = p;
                var row = V.Button(V.Box(V.H(8,
                    Sym.Icon(projects ? "folder.fill" : "doc.text.fill", 12, projects ? t.Accent : t.Secondary),
                    V.Flex(V.VLead(1, V.T(Path.GetFileName(path.TrimEnd('\\')), 11.5, FontWeights.Medium, t.Primary), V.T(path, 9.5, FontWeights.Normal, t.Secondary)))),
                    V.P(10, 5), t.P(0.03), 6), () => { if (projects) _app.OpenWorkspace(path); else _app.LoadFile(path); });
                list.Children.Add(row);
            }
            var sec = V.VLead(6, V.Box(V.T(title, 9.5, FontWeights.Bold, t.Secondary), V.P(14, 0), null, 0), V.Self(V.Box(list, V.P(10, 0), null, 0), Cross.Stretch));
            return V.Self(sec, Cross.Stretch);
        }

        UIElement IssuesContent()
        {
            var t = Theme.Current;
            return V.Vs(8, V.Sp(), Sym.Icon("checkmark.circle.fill", 22, t.Op(t.SysGreen, 0.75)), V.T("No Issues", 12, FontWeights.Medium, t.Secondary), V.Sp());
        }

        // MARK: - Search in Workspace (ripgrep equivalent)
        UIElement SearchContent()
        {
            var t = Theme.Current;
            var root = V.Vs(6); root.Align = Cross.Stretch;
            var chevron = V.Size(V.Button(Sym.Icon(_showReplace ? "chevron.down" : "chevron.right", 9, t.Secondary, FontWeights.Bold), () => { _showReplace = !_showReplace; Render(); }), 14, 18);
            chevron.ToolTip = "Toggle Replace in Workspace (Ctrl+Shift+H)";
            string prev = _searchBox != null ? _searchBox.Text : "";
            var field = Styles.Field("Find in Workspace (Ctrl+Shift+F)…", 11.5, t.Primary, t.Secondary, out _searchBox);
            _searchBox.Text = prev;
            _searchBox.TextChanged += delegate { ScheduleSearch(); };
            _searchBox.KeyDown += delegate(object s, System.Windows.Input.KeyEventArgs e) { if (e.Key == System.Windows.Input.Key.Enter) RunSearch(); };
            Func<string, bool, string, Action, Btn> toggle = (label, on, tip, act) =>
            {
                var b = V.Button(V.Box(V.Mono(label, 9.5, FontWeights.Bold, on ? t.Accent : t.Secondary), V.P(4, 2), on ? t.A(0.22) : Brushes.Transparent, 3), act);
                b.ToolTip = tip; return b;
            };
            var findRow = V.H(4, chevron, V.Flex(V.Box(V.H(5, Sym.Icon("magnifyingglass", 10.5, t.Secondary), V.Flex(field),
                toggle("Aa", _caseSensitive, "Match Case", () => { _caseSensitive = !_caseSensitive; Render(); RunSearch(); }),
                toggle(".*", _regex, "Use Regular Expression", () => { _regex = !_regex; Render(); RunSearch(); })), V.P(6, 5), t.P(0.05), 6)));
            var top = V.Vs(5, V.Self(findRow, Cross.Stretch)); top.Align = Cross.Stretch;
            if (_showReplace)
            {
                string prevR = _replaceBox != null ? _replaceBox.Text : "";
                var rf = Styles.Field("Replace with…", 11.5, t.Primary, t.Secondary, out _replaceBox);
                _replaceBox.Text = prevR;
                bool can = _matches.Count > 0;
                var all = V.Button(V.Box(V.T("All", 10, FontWeights.SemiBold, can ? t.Accent : t.Secondary), V.P(7, 5), can ? t.A(0.18) : t.S(0.1), 5), ReplaceAll);
                all.ToolTip = "Replace All Across Workspace";
                top.Children.Add(V.H(4, new Border { Width = 14 }, V.Flex(V.Box(V.H(5, Sym.Icon("arrow.left.arrow.right", 10, t.Secondary), V.Flex(rf)), V.P(6, 5), t.P(0.05), 6)), all));
            }
            root.Children.Add(V.Box(top, V.P(8, 8, 8, 0), null, 0));
            if (_replaceMessage != null)
                root.Children.Add(V.Box(V.H(4, Sym.Icon("checkmark.circle.fill", 10, t.SysGreen), V.T(_replaceMessage, 10, FontWeights.Normal, t.Secondary), V.Sp()), V.P(12, 0), null, 0));
            if (_app.WorkspaceFolder == null)
            {
                var g = new Grid(); g.Children.Add(V.T("No Workspace Open", 11, FontWeights.Normal, t.Secondary)); ((TextBlock)g.Children[0]).HorizontalAlignment = HorizontalAlignment.Center;
                root.Children.Add(V.Flex(g));
                return root;
            }
            string q = _searchBox.Text;
            var status = V.H(4);
            if (_searching) status.Children.Add(V.T("Searching workspace…", 10, FontWeights.Normal, t.Secondary));
            else if (q.Length > 0) status.Children.Add(V.T(_matches.Count + " results in " + _matches.Select(m => m.Item1).Distinct().Count() + " files", 10, FontWeights.Medium, t.Secondary));
            status.Children.Add(V.Sp());
            root.Children.Add(V.Box(status, V.P(12, 0), null, 0));
            var list = V.VLead(2); list.Align = Cross.Stretch;
            if (q.Length > 0)
            {
                var files = new List<FileNode>();
                CollectNames(_app.FileTree, q, files);
                if (files.Count > 0)
                {
                    list.Children.Add(V.Box(V.T("FILES", 9, FontWeights.Bold, t.Secondary), V.P(6, 2, 6, 0), null, 0));
                    foreach (var n in files.Take(12))
                    {
                        var node = n;
                        list.Children.Add(V.Button(V.Box(V.H(6, Sym.Icon(node.IsDirectory ? "folder.fill" : "doc.text.fill", 10.5, node.IsDirectory ? t.Accent : t.Secondary), V.T(node.Name, 11, FontWeights.Medium, t.Primary), V.Sp()), V.P(8, 3), t.P(0.03), 4), () => { if (!node.IsDirectory) _app.LoadFile(node.Path); }));
                    }
                }
            }
            if (_matches.Count > 0)
            {
                list.Children.Add(V.Box(V.T("TEXT MATCHES", 9, FontWeights.Bold, t.Secondary), V.P(6, 6, 6, 0), null, 0));
                foreach (var m in _matches.Take(400))
                {
                    var match = m;
                    string rel = match.Item1.StartsWith(_app.WorkspaceFolder, StringComparison.OrdinalIgnoreCase) ? match.Item1.Substring(_app.WorkspaceFolder.Length).TrimStart('\\') : match.Item1;
                    var row = V.VLead(1,
                        V.H(4, V.T(Path.GetFileName(match.Item1), 10.5, FontWeights.SemiBold, t.Primary), V.T(":" + match.Item2, 10, FontWeights.Normal, t.Secondary), V.Sp(), V.Shrink(V.T(Path.GetDirectoryName(rel), 9, FontWeights.Normal, t.S(0.7)))),
                        V.Mono(match.Item4.Trim(), 10, FontWeights.Normal, t.P(0.8)));
                    list.Children.Add(V.Button(V.Box(row, V.P(8, 4), t.P(0.03), 4), () => { _app.LoadFile(match.Item1); if (Window.GetWindow(this) is MainWindow) ((MainWindow)Window.GetWindow(this)).GoToLine(match.Item2 - 1); }));
                }
            }
            var sv = new ScrollViewer { Content = V.Box(list, V.P(6, 0), null, 0), VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            root.Children.Add(V.Flex(sv));
            return root;
        }

        void CollectNames(List<FileNode> nodes, string q, List<FileNode> outList)
        {
            foreach (var n in nodes)
            {
                if (outList.Count >= 50) return;
                if (n.Name.IndexOf(q, StringComparison.OrdinalIgnoreCase) >= 0) outList.Add(n);
                CollectNames(n.Children, q, outList);
            }
        }

        void ScheduleSearch()
        {
            if (_searchDebounce == null)
            {
                _searchDebounce = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(350) };
                _searchDebounce.Tick += delegate { _searchDebounce.Stop(); RunSearch(); };
            }
            _searchDebounce.Stop(); _searchDebounce.Start();
        }

        static readonly HashSet<string> SkipDirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".git", "node_modules", "build", ".build", "DerivedData", "target", "bin", "obj", ".venv", "__pycache__", "dist" };

        void RunSearch()
        {
            if (_searchCts != null) _searchCts.Cancel();
            string q = _searchBox != null ? _searchBox.Text : "";
            string ws = _app.WorkspaceFolder;
            if (q.Length == 0 || ws == null) { _matches = new List<Tuple<string, int, int, string>>(); _searching = false; KeepFocusRender(); return; }
            var cts = new CancellationTokenSource(); _searchCts = cts;
            bool cs = _caseSensitive, rx = _regex;
            _searching = true; KeepFocusRender();
            Task.Factory.StartNew(() =>
            {
                var res = new List<Tuple<string, int, int, string>>();
                Regex re = null;
                try { re = new Regex(rx ? q : Regex.Escape(q), cs ? RegexOptions.None : RegexOptions.IgnoreCase); } catch { return res; }
                var stack = new Stack<string>(); stack.Push(ws);
                while (stack.Count > 0 && res.Count < 2000 && !cts.IsCancellationRequested)
                {
                    string d = stack.Pop();
                    try
                    {
                        foreach (var sub in Directory.GetDirectories(d)) if (!SkipDirs.Contains(Path.GetFileName(sub))) stack.Push(sub);
                        foreach (var f in Directory.GetFiles(d))
                        {
                            var fi = new FileInfo(f);
                            if (fi.Length > 1024 * 1024) continue;
                            string[] lines;
                            try { lines = File.ReadAllLines(f); } catch { continue; }
                            if (lines.Any(l => l.IndexOf('\0') >= 0)) continue;
                            for (int i = 0; i < lines.Length && res.Count < 2000; i++)
                            {
                                var m = re.Match(lines[i]);
                                if (m.Success) res.Add(Tuple.Create(f, i + 1, m.Index + 1, lines[i].Length > 200 ? lines[i].Substring(0, 200) : lines[i]));
                            }
                        }
                    }
                    catch { }
                }
                return res;
            }, cts.Token).ContinueWith(task =>
            {
                if (cts.IsCancellationRequested) return;
                _matches = task.Result; _searching = false; KeepFocusRender();
            }, TaskScheduler.FromCurrentSynchronizationContext());
        }

        void KeepFocusRender()
        {
            bool had = _searchBox != null && _searchBox.IsKeyboardFocused;
            int caret = _searchBox != null ? _searchBox.CaretIndex : 0;
            Render();
            if (had && _searchBox != null) { _searchBox.Focus(); _searchBox.CaretIndex = caret; }
        }

        void ReplaceAll()
        {
            if (_matches.Count == 0 || _replaceBox == null || _searchBox == null) return;
            string q = _searchBox.Text, rep = _replaceBox.Text;
            var re = new Regex(_regex ? q : Regex.Escape(q), _caseSensitive ? RegexOptions.None : RegexOptions.IgnoreCase);
            int files = 0, count = 0;
            foreach (var f in _matches.Select(m => m.Item1).Distinct())
            {
                try
                {
                    string s = File.ReadAllText(f);
                    int c = re.Matches(s).Count;
                    if (c == 0) continue;
                    File.WriteAllText(f, re.Replace(s, _regex ? rep : rep.Replace("$", "$$")));
                    files++; count += c;
                    var open = _app.OpenFiles.FirstOrDefault(o => string.Equals(o.Path, f, StringComparison.OrdinalIgnoreCase));
                    if (open != null && !open.IsUnsaved) open.Content = File.ReadAllText(f).Replace("\r\n", "\n");
                }
                catch { }
            }
            _replaceMessage = "Replaced " + count + " occurrences in " + files + " files";
            _app.Notify("files");
            RunSearch();
        }

        // MARK: bottomFilterBar
        void BuildBottom()
        {
            var t = Theme.Current;
            var plus = V.Size(V.Button(Sym.Icon("plus", 11, t.Secondary, FontWeights.Medium), null), 18, 18);
            plus.ToolTip = "Add file or folder";
            plus.MenuItems = () => new List<MenuItemSpec>
            {
                MenuItemSpec.Item("New File…", "doc.badge.plus", _app.NewFile),
                MenuItemSpec.Item("New Folder…", "folder.badge.plus", () => { if (_app.WorkspaceFolder != null) _app.CreateFolder(_app.WorkspaceFolder, "New Folder"); else _app.OpenFolderDialog(); }),
                MenuItemSpec.Sep(),
                MenuItemSpec.Item("Open File…", "doc", _app.OpenFileDialog),
                MenuItemSpec.Item("Open Folder…", "folder", _app.OpenFolderDialog)
            };
            var field = Styles.Field("Filter", 11, t.Primary, t.Secondary, out _filterBox);
            var clear = V.Button(Sym.Icon("xmark.circle.fill", 9, t.Secondary), () => { _filterBox.Text = ""; });
            clear.Visibility = Visibility.Collapsed;
            _filterBox.TextChanged += delegate
            {
                _filter = _filterBox.Text;
                clear.Visibility = _filter.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
                if (_tab == Tab.Project && _app.WorkspaceFolder != null) ProjectContent();
            };
            Btn clock = null;
            clock = V.Size(V.Button(Sym.Icon("clock", 11, t.Secondary), () =>
            {
                _recentOnly = !_recentOnly;
                clock.Child = Sym.Icon(_recentOnly ? "clock.fill" : "clock", 11, _recentOnly ? Theme.Current.Accent : Theme.Current.Secondary);
                if (_tab == Tab.Project && _app.WorkspaceFolder != null) ProjectContent();
            }), 18, 18);
            clock.ToolTip = "Show only recently opened files";
            _bottom.Child = V.Box(V.H(8, plus, V.Flex(V.Box(V.H(4, Sym.Icon("magnifyingglass", 10, t.Secondary), V.Flex(field), clear), V.P(6, 3), t.P(0.04), 4)), clock), V.P(8, 6), null, 0);
        }
    }

    /// <summary>Source Control navigator (GitPanelView): branch + changed files from `git status --porcelain`.</summary>
    public class GitPanel : Border
    {
        readonly AppState _app;
        public GitPanel(AppState app) { _app = app; Refresh(); }

        void Refresh()
        {
            var t = Theme.Current;
            string ws = _app.WorkspaceFolder;
            if (ws == null || !Directory.Exists(Path.Combine(ws, ".git")))
            {
                Child = V.Vs(8, V.Sp(), Sym.Icon("arrow.triangle.branch", 22, t.Secondary), V.T(ws == null ? "No Workspace Open" : "Not a Git repository", 11.5, FontWeights.Medium, t.Secondary), V.Sp());
                return;
            }
            string branch = Git(ws, "rev-parse --abbrev-ref HEAD").Trim();
            var lines = Git(ws, "status --porcelain").Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries);
            var list = V.VLead(2); list.Align = Cross.Stretch;
            list.Children.Add(V.Box(V.H(6, Sym.Icon("arrow.triangle.branch", 11, t.Accent), V.T(branch, 11.5, FontWeights.SemiBold, t.Primary), V.Sp(),
                V.Button(Sym.Icon("arrow.clockwise", 10.5, t.Secondary), Refresh)), V.P(10, 8), null, 0));
            list.Children.Add(V.Box(V.T("CHANGES (" + lines.Length + ")", 9.5, FontWeights.Bold, t.Secondary), V.P(10, 4), null, 0));
            foreach (var l in lines.Take(500))
            {
                if (l.Length < 4) continue;
                string code = l.Substring(0, 2).Trim(), file = l.Substring(3).Trim().Trim('"');
                Brush c = code.Contains("M") ? t.SysOrange : code.Contains("A") || code == "??" ? t.SysGreen : code.Contains("D") ? t.SysRed : t.Secondary;
                string full = Path.Combine(ws, file.Replace('/', '\\'));
                list.Children.Add(V.Button(V.Box(V.H(6, Sym.Icon(FileTreeView.IconName(file, false), 11, FileTreeView.IconColor(file, false)), V.Shrink(V.T(Path.GetFileName(file), 11.5, FontWeights.Normal, t.Primary)),
                    V.Shrink(V.T(Path.GetDirectoryName(file), 10, FontWeights.Normal, t.S(0.7))), V.Sp(), V.Mono(code == "??" ? "U" : code, 10, FontWeights.Bold, c)), V.P(10, 3), null, 0), () => { if (File.Exists(full)) _app.LoadFile(full); }));
            }
            Child = new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        }

        public static string Git(string cwd, string args)
        {
            try
            {
                var p = Process.Start(new ProcessStartInfo("git", args) { WorkingDirectory = cwd, UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true, StandardOutputEncoding = System.Text.Encoding.UTF8 });
                string o = p.StandardOutput.ReadToEnd();
                p.WaitForExit(5000);
                return o;
            }
            catch { return ""; }
        }
    }
}
