// Line diff engine (Myers O(ND) with common prefix/suffix trimming) and the agent's diff UI, ported from
// AIAgentMessageRowsAndDiffCards.swift: PendingChangeCard (file header, +N -M, Split Diff, Show/Hide Diff, Applied / Reverted,
// codeDiffSection with accent bar + dual line-number gutter + 64-line fold) and the side-by-side Split Diff window.
using System;
using System.Collections.Generic;
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
    public enum DiffKind { Context, Add, Del, Hunk }

    public class DiffLine
    {
        public DiffKind Kind;
        public int OldNo, NewNo;
        public string Text;
    }

    public class DiffResult
    {
        public readonly List<DiffLine> Lines = new List<DiffLine>();
        public int Added, Removed;
    }

    public static class Differ
    {
        struct Op { public int Type, A, B; } // 0 = equal, 1 = delete a[A], 2 = insert b[B]

        static string[] Split(string s) { return string.IsNullOrEmpty(s) ? new string[0] : s.Replace("\r\n", "\n").TrimEnd('\n').Split('\n'); }

        /// <summary>Unified diff with <paramref name="context"/> lines around each change; context &lt; 0 keeps every line.</summary>
        public static DiffResult Compute(string before, string after, int context)
        {
            var a = Split(before); var b = Split(after);
            var ops = Ops(a, b);
            var all = new List<DiffLine>();
            int on = 0, nn = 0;
            var res = new DiffResult();
            foreach (var op in ops)
            {
                if (op.Type == 0) { on++; nn++; all.Add(new DiffLine { Kind = DiffKind.Context, OldNo = on, NewNo = nn, Text = a[op.A] }); }
                else if (op.Type == 1) { on++; res.Removed++; all.Add(new DiffLine { Kind = DiffKind.Del, OldNo = on, Text = a[op.A] }); }
                else { nn++; res.Added++; all.Add(new DiffLine { Kind = DiffKind.Add, NewNo = nn, Text = b[op.B] }); }
            }
            if (context < 0 || all.Count == 0) { res.Lines.AddRange(all); return res; }
            var keep = new bool[all.Count];
            for (int i = 0; i < all.Count; i++)
                if (all[i].Kind != DiffKind.Context)
                    for (int j = Math.Max(0, i - context); j <= Math.Min(all.Count - 1, i + context); j++) keep[j] = true;
            for (int i = 0; i < all.Count; )
            {
                if (!keep[i]) { i++; continue; }
                int end = i;
                while (end < all.Count && keep[end]) end++;
                int oStart = 0, nStart = 0, oCount = 0, nCount = 0;
                for (int k = i; k < end; k++)
                {
                    var l = all[k];
                    if (l.Kind != DiffKind.Add) { if (oStart == 0) oStart = l.OldNo; oCount++; }
                    if (l.Kind != DiffKind.Del) { if (nStart == 0) nStart = l.NewNo; nCount++; }
                }
                res.Lines.Add(new DiffLine { Kind = DiffKind.Hunk, Text = "@@ -" + oStart + "," + oCount + " +" + nStart + "," + nCount + " @@" });
                for (int k = i; k < end; k++) res.Lines.Add(all[k]);
                i = end;
            }
            return res;
        }

        static List<Op> Ops(string[] a, string[] b)
        {
            int pre = 0;
            while (pre < a.Length && pre < b.Length && a[pre] == b[pre]) pre++;
            int suf = 0;
            while (suf < a.Length - pre && suf < b.Length - pre && a[a.Length - 1 - suf] == b[b.Length - 1 - suf]) suf++;
            var ops = new List<Op>();
            for (int i = 0; i < pre; i++) ops.Add(new Op { Type = 0, A = i, B = i });
            int n = a.Length - pre - suf, m = b.Length - pre - suf;
            if (n + m > 12000)
            {
                // huge rewrite: show it as a block replacement rather than spending seconds in the solver
                for (int i = 0; i < n; i++) ops.Add(new Op { Type = 1, A = pre + i });
                for (int i = 0; i < m; i++) ops.Add(new Op { Type = 2, B = pre + i });
            }
            else ops.AddRange(Myers(a, b, pre, n, m));
            for (int i = 0; i < suf; i++) ops.Add(new Op { Type = 0, A = a.Length - suf + i, B = b.Length - suf + i });
            return ops;
        }

        static List<Op> Myers(string[] a, string[] b, int off0, int n, int m)
        {
            var ops = new List<Op>();
            int max = n + m;
            if (max == 0) return ops;
            int off = max + 1;
            var v = new int[2 * max + 3];
            var trace = new List<int[]>();
            int found = -1;
            for (int d = 0; d <= max && found < 0; d++)
            {
                trace.Add((int[])v.Clone());
                for (int k = -d; k <= d; k += 2)
                {
                    int x = (k == -d || (k != d && v[off + k - 1] < v[off + k + 1])) ? v[off + k + 1] : v[off + k - 1] + 1;
                    int y = x - k;
                    while (x < n && y < m && a[off0 + x] == b[off0 + y]) { x++; y++; }
                    v[off + k] = x;
                    if (x >= n && y >= m) { found = d; break; }
                }
            }
            int cx = n, cy = m;
            for (int d = found; d > 0; d--)
            {
                var vp = trace[d];
                int k = cx - cy;
                int prevK = (k == -d || (k != d && vp[off + k - 1] < vp[off + k + 1])) ? k + 1 : k - 1;
                int prevX = vp[off + prevK], prevY = prevX - prevK;
                while (cx > prevX && cy > prevY) { ops.Add(new Op { Type = 0, A = off0 + cx - 1, B = off0 + cy - 1 }); cx--; cy--; }
                if (cx == prevX) ops.Add(new Op { Type = 2, B = off0 + prevY });
                else ops.Add(new Op { Type = 1, A = off0 + prevX });
                cx = prevX; cy = prevY;
            }
            while (cx > 0 && cy > 0) { ops.Add(new Op { Type = 0, A = off0 + cx - 1, B = off0 + cy - 1 }); cx--; cy--; }
            ops.Reverse();
            return ops;
        }
    }

    public static class DiffViews
    {
        static readonly Color Green = Color.FromRgb(52, 199, 89), Red = Color.FromRgb(255, 69, 58), Cyan = Color.FromRgb(90, 200, 250);
        const int Fold = 64;
        /// <summary>Test hook (--expand-diffs): change cards start expanded.</summary>
        public static bool ForceOpen;

        /// <summary>codeDiffSection: accent bar, "old new" gutter, +/- prefix, monospaced text; folds after 64 lines.</summary>
        public static FrameworkElement Section(DiffResult diff)
        {
            var t = Theme.Current;
            var rows = new StackPanel { Margin = new Thickness(0, 3, 0, 3) };
            bool showAll = false;
            var wrap = new StackPanel();
            var scroller = new ScrollViewer { Content = rows, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled, Background = t.EditorBackground };
            wrap.Children.Add(new Border { Height = 1, Background = t.P(0.08) });
            wrap.Children.Add(scroller);
            Border foldBar = null;
            Action render = null;
            render = () =>
            {
                rows.Children.Clear();
                var lines = showAll ? diff.Lines : diff.Lines.Take(Fold).ToList();
                foreach (var l in lines) rows.Children.Add(Row(l));
                if (diff.Lines.Count == 0) rows.Children.Add(new TextBlock { Text = "No textual changes.", Margin = new Thickness(12, 4, 0, 4), FontSize = 11, Foreground = t.Secondary });
                if (foldBar != null)
                    ((TextBlock)((Stack)((Btn)foldBar.Child).Child).Children[1]).Text = showAll ? "Collapse diff (" + Fold + " of " + diff.Lines.Count + " lines)" : "Show all " + diff.Lines.Count + " diff lines";
            };
            if (diff.Lines.Count > Fold)
            {
                var label = V.T("", 10.5, FontWeights.Medium, t.Secondary);
                var chev = Sym.Icon("chevron.down", 9, t.Secondary, FontWeights.SemiBold);
                var btn = V.Button(V.H(5, chev, label), null);
                btn.Click += () => { showAll = !showAll; chev.Glyph.Text = Sym.GlyphText(showAll ? "chevron.up" : "chevron.down"); render(); };
                foldBar = new Border { Child = btn, Padding = new Thickness(10, 5, 10, 5), BorderBrush = t.P(0.06), BorderThickness = new Thickness(0, 1, 0, 0) };
                wrap.Children.Add(foldBar);
            }
            render();
            return wrap;
        }

        static UIElement Row(DiffLine l)
        {
            var t = Theme.Current;
            var g = new Grid { MinHeight = 19 };
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(2.5) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(70) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(18) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            Func<UIElement, int, UIElement> at = (e, c) => { Grid.SetColumn(e, c); g.Children.Add(e); return e; };
            if (l.Kind == DiffKind.Hunk)
            {
                g.Background = Theme.B(Theme.WithAlpha(Cyan, t.IsDark ? 0.09 : 0.07));
                at(new Border { Background = Theme.B(Theme.WithAlpha(Cyan, 0.85)) }, 0);
                at(new TextBlock { Text = "⋯", FontFamily = UIFonts.Mono, FontSize = 10, FontWeight = FontWeights.SemiBold, Foreground = Theme.B(Theme.WithAlpha(Cyan, 0.8)), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center }, 1);
                at(new Border { Background = t.P(0.08) }, 2);
                var h = new TextBlock { Text = l.Text, FontFamily = UIFonts.Mono, FontSize = 10.5, FontWeight = FontWeights.Medium, Foreground = Theme.B(Theme.WithAlpha(Cyan, 0.9)), Margin = new Thickness(10, 0, 20, 0), VerticalAlignment = VerticalAlignment.Center };
                Grid.SetColumnSpan(h, 2);
                at(h, 3);
                return g;
            }
            Color accent = l.Kind == DiffKind.Add ? Green : l.Kind == DiffKind.Del ? Red : Colors.Transparent;
            if (l.Kind == DiffKind.Add) g.Background = Theme.B(Theme.WithAlpha(Green, t.IsDark ? 0.15 : 0.12));
            else if (l.Kind == DiffKind.Del) g.Background = Theme.B(Theme.WithAlpha(Red, t.IsDark ? 0.14 : 0.10));
            at(new Border { Background = Theme.B(accent) }, 0);
            string gutter = (l.OldNo > 0 ? l.OldNo.ToString() : "").PadLeft(4) + " " + (l.NewNo > 0 ? l.NewNo.ToString() : "").PadLeft(4);
            at(new TextBlock { Text = gutter, FontFamily = UIFonts.Mono, FontSize = 10, Foreground = t.S(0.6), HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 0, 6, 0), VerticalAlignment = VerticalAlignment.Center }, 1);
            at(new Border { Background = t.P(0.08) }, 2);
            at(new TextBlock { Text = l.Kind == DiffKind.Add ? "+" : l.Kind == DiffKind.Del ? "-" : "", FontFamily = UIFonts.Mono, FontSize = 11, FontWeight = FontWeights.Bold, Foreground = Theme.B(accent), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center }, 3);
            at(new TextBlock { Text = (l.Text ?? "").Replace("\t", "    "), FontFamily = UIFonts.Mono, FontSize = 11.5, Foreground = l.Kind == DiffKind.Del ? Theme.B(Theme.WithAlpha(((SolidColorBrush)t.EditorText).Color, 0.76)) : l.Kind == DiffKind.Context ? Theme.B(Theme.WithAlpha(((SolidColorBrush)t.EditorText).Color, 0.88)) : t.EditorText, Margin = new Thickness(0, 0, 20, 0), VerticalAlignment = VerticalAlignment.Center }, 4);
            return g;
        }

        /// <summary>PendingChangeCard for an edit the agent already applied: header (icon, name, +N -M, description), Split Diff,
        /// Show/Hide Diff, status chip, and Revert / Restore.</summary>
        public static FrameworkElement Card(string path, string before, string after, string description, bool reverted, bool startOpen, Action open, Action revert)
        {
            var t = Theme.Current;
            var diff = Differ.Compute(before ?? "", after ?? "", 3);
            string name = Path.GetFileName(path);
            bool show = startOpen || ForceOpen;
            var body = new Border();
            var stats = V.H(5);
            if (diff.Added > 0) stats.Children.Add(V.Mono("+" + diff.Added, 9.5, FontWeights.Medium, t.Secondary));
            if (diff.Removed > 0) stats.Children.Add(V.Mono("-" + diff.Removed, 9.5, FontWeights.Medium, t.S(0.75)));
            var descTb = V.T(description, 9, FontWeights.Normal, t.Secondary);
            descTb.TextTrimming = TextTrimming.CharacterEllipsis;
            var title = V.Button(V.H(8, Sym.Icon(FileTreeView.IconName(name, false), 14, FileTreeView.IconColor(name, false)),
                V.Shrink(V.VLead(1, V.H(6, V.Mono(name, 11, FontWeights.SemiBold, t.Primary), stats), descTb))), open);
            title.ToolTip = path;
            V.Shrink(title);
            Func<string, string, Action, Btn> small = (icon, label, a) => V.Button(V.Box(V.H(3, Sym.Icon(icon, 9, t.Secondary), V.T(label, 10, FontWeights.Medium, t.Secondary)), V.P(6, 3), t.P(0.05), 4), a);
            // Split Diff opens the full diff in the right split pane, which can pop out the side-by-side window
            var split = small("arrow.left.and.right.square", "Split Diff", () => PreviewDock.OpenDiff(name, before ?? "", after ?? ""));
            split.ToolTip = "Open a side-by-side diff of " + name;
            var toggleLabel = V.T(show ? "Hide Diff" : "Show Diff", 10, FontWeights.Medium, t.Secondary);
            var toggleChev = Sym.Icon(show ? "chevron.up" : "chevron.down", 8, t.Secondary, FontWeights.SemiBold);
            var toggle = V.Button(V.Box(V.H(3, toggleLabel, toggleChev), V.P(6, 3), t.P(0.05), 4), null);
            Action renderBody = () => { body.Child = show ? Section(diff) : null; toggleLabel.Text = show ? "Hide Diff" : "Show Diff"; toggleChev.Glyph.Text = Sym.GlyphText(show ? "chevron.up" : "chevron.down"); };
            toggle.Click += () => { show = !show; renderBody(); };
            UIElement status = reverted
                ? (UIElement)V.Box(V.T("Reverted", 9.5, FontWeights.Medium, t.S(0.75)), V.P(6, 2), t.P(0.04), 4)
                : V.Box(V.H(3, Sym.Icon("checkmark", 8, t.Secondary, FontWeights.SemiBold), V.T("Applied", 9.5, FontWeights.Medium, t.Secondary)), V.P(6, 2), t.P(0.045), 4);
            var head = V.H(8, title, V.Sp(), split, toggle, status);
            if (revert != null)
            {
                var rv = small(reverted ? "arrow.uturn.forward" : "arrow.uturn.backward", reverted ? "Restore" : "Revert", revert);
                rv.ToolTip = reverted ? "Apply this change again" : "Undo this change and restore the previous file content";
                head.Children.Add(rv);
            }
            var col = V.VLead(0, V.Self(V.Box(head, V.P(10, 8), t.IsDark ? t.PanelBackground : t.P(0.03), 0), Cross.Stretch), V.Self(body, Cross.Stretch));
            col.Align = Cross.Stretch;
            var card = new Border { Child = col, CornerRadius = new CornerRadius(8), BorderBrush = reverted ? t.P(0.05) : t.P(0.09), BorderThickness = new Thickness(1), Background = t.IsDark ? t.PanelBackground : t.P(0.02), ClipToBounds = true, Opacity = reverted ? 0.75 : 1 };
            renderBody();
            return card;
        }

        /// <summary>Side-by-side diff window (Split Diff).</summary>
        public static void ShowSplit(string title, string before, string after)
        {
            var w = SplitWindow(title, before, after);
            var owner = Application.Current != null ? Application.Current.MainWindow : null;
            if (owner != null && owner.IsVisible) w.Owner = owner; else w.WindowStartupLocation = WindowStartupLocation.CenterScreen;
            w.Show();
        }

        public static Window SplitWindow(string title, string before, string after)
        {
            var t = Theme.Current;
            var diff = Differ.Compute(before, after, -1);
            var rows = new List<Tuple<DiffLine, DiffLine>>();
            var dels = new List<DiffLine>(); var adds = new List<DiffLine>();
            Action flush = () =>
            {
                int n = Math.Max(dels.Count, adds.Count);
                for (int i = 0; i < n; i++) rows.Add(Tuple.Create(i < dels.Count ? dels[i] : null, i < adds.Count ? adds[i] : null));
                dels.Clear(); adds.Clear();
            };
            foreach (var l in diff.Lines)
            {
                if (l.Kind == DiffKind.Del) { if (adds.Count > 0) flush(); dels.Add(l); }
                else if (l.Kind == DiffKind.Add) adds.Add(l);
                else { flush(); rows.Add(Tuple.Create(l, l)); }
            }
            flush();
            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var left = new StackPanel(); var right = new StackPanel();
            Func<DiffLine, bool, UIElement> cell = (l, isNew) =>
            {
                var g = new Grid { Height = 19 };
                g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(46) });
                g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                if (l == null) { g.Background = t.P(0.03); return g; }
                bool changed = l.Kind != DiffKind.Context;
                if (changed) g.Background = Theme.B(Theme.WithAlpha(isNew ? Green : Red, t.IsDark ? 0.15 : 0.11));
                var no = new TextBlock { Text = (isNew ? l.NewNo : l.OldNo).ToString(), FontFamily = UIFonts.Mono, FontSize = 10, Foreground = t.S(0.6), HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center };
                var tx = new TextBlock { Text = (l.Text ?? "").Replace("\t", "    "), FontFamily = UIFonts.Mono, FontSize = 11.5, Foreground = t.EditorText, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.None };
                Grid.SetColumn(tx, 1);
                g.Children.Add(no); g.Children.Add(tx);
                return g;
            };
            foreach (var r in rows.Take(5000)) { left.Children.Add(cell(r.Item1, false)); right.Children.Add(cell(r.Item2, true)); }
            var ls = new ScrollViewer { Content = left, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            var rs = new ScrollViewer { Content = right, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            bool syncing = false;
            ls.ScrollChanged += (s, e) => { if (syncing) return; syncing = true; rs.ScrollToVerticalOffset(ls.VerticalOffset); syncing = false; };
            rs.ScrollChanged += (s, e) => { if (syncing) return; syncing = true; ls.ScrollToVerticalOffset(rs.VerticalOffset); syncing = false; };
            Grid.SetColumn(rs, 2);
            var sep = new Border { Background = t.Separator }; Grid.SetColumn(sep, 1);
            grid.Children.Add(ls); grid.Children.Add(sep); grid.Children.Add(rs);
            var header = new Grid { Height = 30, Background = t.PanelBackground };
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1) });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var lh = V.Box(V.H(6, Sym.Icon("minus.circle", 10, Theme.B(Red)), V.T("Before", 11, FontWeights.SemiBold, t.Primary), V.Mono("-" + diff.Removed, 10, FontWeights.Medium, t.Secondary)), V.P(10, 0), null, 0);
            var rh = V.Box(V.H(6, Sym.Icon("plus.circle", 10, Theme.B(Green)), V.T("After", 11, FontWeights.SemiBold, t.Primary), V.Mono("+" + diff.Added, 10, FontWeights.Medium, t.Secondary)), V.P(10, 0), null, 0);
            lh.VerticalAlignment = rh.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(rh, 2);
            header.Children.Add(lh); header.Children.Add(rh);
            var root = new DockPanel { Background = t.EditorBackground };
            DockPanel.SetDock(header, Dock.Top);
            root.Children.Add(header);
            root.Children.Add(grid);
            var w = new Window
            {
                Title = title + " — Split Diff", Content = root, Width = 1100, Height = 720, Background = t.EditorBackground,
                WindowStartupLocation = WindowStartupLocation.CenterOwner, FontFamily = UIFonts.UI, ShowInTaskbar = false
            };
            w.SourceInitialized += delegate { Native.StyleWindow(w, t.IsDark); };
            w.PreviewKeyDown += (s, e) => { if (e.Key == Key.Escape) w.Close(); };
            return w;
        }
    }
}
