// EmbeddedDeviceDockView.swift for Windows: the Preview tab of the right inspector. A multi-purpose tab strip (WebApp
// Preview · iOS Sim · Android Emu · opened files and diffs, each closable, "+" to add) over a content router. The web and
// Android surfaces are single long-lived instances, so switching tabs or re-rendering the pane never reloads the page or
// drops the emulator stream.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using MicroCode.Core;
using MicroCode.UI;

namespace MicroCode.Views
{
    public class PreviewDockView : Border
    {
        readonly AppState _app;
        readonly Border _webHost = new Border(), _androidHost = new Border(), _otherHost = new Border(), _stripHost = new Border();
        PreviewItem _shownItem;

        public PreviewDockView(AppState app)
        {
            _app = app;
            var t = Theme.Current;
            PreviewDock.EnsureDefaultTabs();
            var dock = new DockPanel();
            _stripHost.Child = TabStrip();
            DockPanel.SetDock(_stripHost, Dock.Top);
            dock.Children.Add(_stripHost);
            var content = new Grid();
            content.Children.Add(_webHost); content.Children.Add(_androidHost); content.Children.Add(_otherHost);
            dock.Children.Add(content);
            Child = dock;
            Background = t.EditorBackground;
            AllowDrop = true;
            Drop += (s, e) =>
            {
                var files = e.Data.GetData(DataFormats.FileDrop) as string[];
                if (files != null && files.Length > 0 && File.Exists(files[0])) PreviewDock.OpenFile(files[0]);
            };
            Route();
            Unloaded += delegate { if (_androidAttached) AndroidPreview.Shared.SetVisible(false); };
        }

        bool _androidAttached;

        /// <summary>Tabs changed (opened, closed, selected): redraw the strip and route the content; an unchanged file tab
        /// keeps its view (scroll position, zoom, selected regions).</summary>
        public void Refresh()
        {
            _stripHost.Child = TabStrip();
            Route();
        }

        static void Attach(Border host, FrameworkElement child)
        {
            var old = child.Parent as Decorator;
            if (old != null && old != host) old.Child = null;
            if (host.Child != child) host.Child = child;
        }

        void Route()
        {
            var a = PreviewDock.Active;
            string kind = a == null ? null : a.Kind;
            bool web = kind == "web", android = kind == "android";
            // keep live surfaces parented (hidden) once they exist so the browser / stream survive tab switches
            if (web || WebAppPreviewCreated) Attach(_webHost, WebAppPreview.Shared);
            if (android || AndroidCreated) { Attach(_androidHost, AndroidPreview.Shared); _androidAttached = true; }
            _webHost.Visibility = web ? Visibility.Visible : Visibility.Collapsed;
            _androidHost.Visibility = android ? Visibility.Visible : Visibility.Collapsed;
            _otherHost.Visibility = web || android ? Visibility.Collapsed : Visibility.Visible;
            if (_androidAttached) AndroidPreview.Shared.SetVisible(android);
            if (web || android) { _otherHost.Child = null; _shownItem = null; return; }
            if (a != null && a == _shownItem && _otherHost.Child != null) return;
            _shownItem = a;
            if (a == null) _otherHost.Child = Hub();
            else if (kind == "ios") _otherHost.Child = IosSimulator();
            else _otherHost.Child = FilePreview.ForItem(a, _app);
        }

        static bool WebAppPreviewCreated { get { return PreviewDock.WebCreated; } }
        static bool AndroidCreated { get { return PreviewDock.AndroidCreated; } }

        UIElement TabStrip()
        {
            var t = Theme.Current;
            var tabs = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            foreach (var x in PreviewDock.Items)
            {
                var item = x;
                bool on = item == PreviewDock.Active;
                UIElement icon = item.Path != null ? (UIElement)Sym.Icon(FileTreeView.IconName(item.Title, false), 11, FileTreeView.IconColor(item.Title, false))
                    : Sym.Icon(item.Icon, 10, on ? t.Primary : t.Secondary);
                var label = V.T(item.Title, 11.5, on ? FontWeights.SemiBold : FontWeights.Medium, on ? t.Primary : t.Secondary);
                label.MaxWidth = 150; label.TextTrimming = TextTrimming.CharacterEllipsis;
                var row = V.H(5, icon, label);
                var close = V.Button(V.Size(V.Box(Sym.Icon("xmark", 7.5, on ? t.P(0.8) : t.Secondary, FontWeights.Bold), V.P(0), on ? t.P(0.08) : Brushes.Transparent, 4), 16, 16), () => PreviewDock.Close(item));
                close.ToolTip = "Close tab";
                row.Children.Add(close);
                var b = V.Button(V.Box(row, new Thickness(8, 4, 5, 4), on ? (Brush)t.ElevatedBackground : Brushes.Transparent, 6, on ? t.P(0.16) : Brushes.Transparent, 0.8), () => { PreviewDock.Active = item; AppState.Shared.Notify("inspector"); });
                b.ToolTip = item.Path ?? item.Title;
                b.Margin = new Thickness(0, 0, 4, 0);
                tabs.Children.Add(b);
            }
            var plus = V.Button(V.Size(V.Box(Sym.Icon("plus", 10.5, t.Secondary, FontWeights.Medium), V.P(0), Brushes.Transparent, 5), 22, 22), null);
            plus.ToolTip = "Open WebApp Preview, Simulator, or File in Split Pane";
            plus.MenuItems = () => new List<MenuItemSpec>
            {
                MenuItemSpec.Item("WebApp Preview (Localhost)", "globe", () => PreviewDock.SelectStandard("web")),
                MenuItemSpec.Item("iOS Simulator", "iphone", () => PreviewDock.SelectStandard("ios")),
                MenuItemSpec.Item("Android Emulator", "candybarphone", () => PreviewDock.SelectStandard("android")),
                MenuItemSpec.Sep(),
                MenuItemSpec.Item("Open File to Preview…", "doc.badge.plus", PickFile)
            };
            tabs.Children.Add(plus);
            var sv = new ScrollViewer { Content = tabs, HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled };
            sv.Loaded += delegate
            {
                // keep the active tab in view
                foreach (FrameworkElement c in tabs.Children)
                    if (c.ToolTip as string == (PreviewDock.Active != null ? (PreviewDock.Active.Path ?? PreviewDock.Active.Title) : null)) { c.BringIntoView(); break; }
            };
            sv.PreviewMouseWheel += (s, e) => { sv.ScrollToHorizontalOffset(sv.HorizontalOffset - e.Delta / 2.0); e.Handled = true; };
            var box = new Border { Child = sv, Padding = new Thickness(8, 0, 8, 0), Height = 32, Background = t.PanelBackground, BorderBrush = t.Separator, BorderThickness = new Thickness(0, 0, 0, 1) };
            return box;
        }

        static void PickFile()
        {
            var dlg = new Microsoft.Win32.OpenFileDialog { Title = "Open File to Preview", InitialDirectory = AppState.Shared.WorkspaceFolder ?? "" };
            if (dlg.ShowDialog() == true) PreviewDock.OpenFile(dlg.FileName);
        }

        /// <summary>Quick Preview Hub (only when every tab was closed).</summary>
        static UIElement Hub()
        {
            var t = Theme.Current;
            var col = V.Vs(10, Sym.Icon("rectangle.split.2x1", 26, t.Secondary, FontWeights.Medium), V.T("Live Preview & Device Hub", 13, FontWeights.SemiBold, t.Primary),
                V.T("Select a runtime surface or drop any file here to preview", 11, FontWeights.Normal, t.Secondary));
            var row = V.H(8, PanelUI.Small("globe", "WebApp Preview", () => PreviewDock.SelectStandard("web")), PanelUI.Small("iphone", "iOS Sim", () => PreviewDock.SelectStandard("ios")),
                PanelUI.Small("candybarphone", "Android Emu", () => PreviewDock.SelectStandard("android")), PanelUI.Small("doc", "Open File…", PickFile));
            col.Children.Add(row);
            col.Margin = new Thickness(16, 60, 16, 20);
            return col;
        }

        /// <summary>EmbeddedAppleSimulatorView: the iOS Simulator is part of Xcode and only runs on macOS, so on Windows
        /// this tab says so and offers the closest real alternatives instead of a fake device.</summary>
        static UIElement IosSimulator()
        {
            var t = Theme.Current;
            var col = V.Vs(10, Sym.Icon("iphone", 28, t.S(0.5)), V.T("iOS Simulator", 13, FontWeights.SemiBold, t.Primary));
            var body = V.Wrap(V.T("The iOS Simulator is part of Xcode and runs only on macOS, so it can't start on Windows. Preview your web app in an iPhone frame here, test on Android, or run the native app from a Mac.", 11, FontWeights.Normal, t.Secondary), TextAlignment.Center);
            body.MaxWidth = 320;
            col.Children.Add(body);
            var go = V.Button(V.Box(V.H(4, Sym.Icon("iphone", 10, Brushes.White), V.T("WebApp in iPhone Frame", 11, FontWeights.SemiBold, Brushes.White)), V.P(10, 6), t.Accent, 6), () =>
            {
                WebAppPreview.Shared.Open(null, "iphone");
                PreviewDock.SelectStandard("web");
            });
            col.Children.Add(V.H(8, go, PanelUI.Small("candybarphone", "Android Emulator", () => PreviewDock.SelectStandard("android"))));
            col.Margin = new Thickness(16, 60, 16, 20);
            return col;
        }
    }
}
