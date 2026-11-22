// Settings sheet (theme, editor, window controls, AI providers), keyboard shortcuts cheat sheet, git actions, other mode surfaces.
using System;
using System.Collections.Generic;
using System.Diagnostics;
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
    public static class ShortcutsWindow
    {
        public static readonly string[,] Items = {
            {"Run Code","Ctrl+R"},{"Build Project","Ctrl+Shift+B"},{"Stop Execution","Ctrl+."},{"Save","Ctrl+S"},{"Save As","Ctrl+Shift+S"},
            {"New File","Ctrl+N"},{"New AI Conversation","Ctrl+Shift+N"},{"Open File","Ctrl+O"},{"Open Folder","Ctrl+Shift+O"},{"Close Tab","Ctrl+W"},
            {"Next / Previous Tab","Ctrl+] / Ctrl+["},{"Toggle Sidebar","Ctrl+B"},{"Toggle Preview & Inspector","Ctrl+I"},{"Toggle Terminal / Console","Ctrl+J"},
            {"Find in Workspace","Ctrl+Shift+F"},{"Inline AI Edit","Ctrl+K"},{"Settings","Ctrl+,"},{"Keyboard Shortcuts","Ctrl+/"},
            {"Code Editor / Agent / Cells / Playground","Alt+1 … Alt+4"},{"Science / Browser / Remote / IoT / API","Alt+5 … Alt+9"},{"Welcome Dashboard","Alt+0"},
            {"Font Size","Ctrl+= / Ctrl+- / Ctrl+0"},{"Show menu bar","Alt"}
        };

        public static UIElement Table()
        {
            var t = Theme.Current;
            var list = V.VLead(0); list.Align = Cross.Stretch;
            for (int i = 0; i < Items.GetLength(0); i++)
                list.Children.Add(V.Self(V.Box(V.H(10, V.T(Items[i, 0], 12.5, FontWeights.Normal, t.Primary), V.Sp(), V.Box(V.Mono(Items[i, 1], 11.5, FontWeights.Medium, t.P(0.9)), V.P(7, 2), t.P(0.08), 5)), V.P(12, 7), i % 2 == 0 ? t.P(0.02) : Brushes.Transparent, 6), Cross.Stretch));
            return list;
        }

        public static void Show()
        {
            var t = Theme.Current;
            var w = new Window { Title = "Keyboard Shortcuts", Width = 520, Height = 640, Owner = Application.Current.MainWindow, WindowStartupLocation = WindowStartupLocation.CenterOwner, Background = t.WorkspaceBackground, ShowInTaskbar = false, FontFamily = UIFonts.UI };
            w.SourceInitialized += delegate { Native.StyleWindow(w, t.IsDark); };
            w.Content = new ScrollViewer { Content = V.Box(Table(), V.P(18), null, 0), VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            w.KeyDown += delegate(object s, KeyEventArgs e) { if (e.Key == Key.Escape) w.Close(); };
            w.Show();
        }
    }

    public static class GitActions
    {
        public static void Run(AppState app, string args)
        {
            if (app.WorkspaceFolder == null) return;
            app.ConsoleOutput = "$ git " + args + "\n" + GitPanel.Git(app.WorkspaceFolder, args + " 2>&1") + "\n";
            app.ConsoleVisible = true; app.SelectedConsoleTab = 0;
            app.Notify("console"); app.Notify("consoleOutput");
        }

        public static void Commit(AppState app)
        {
            if (app.WorkspaceFolder == null) return;
            string msg = Prompt.Ask("Commit Changes", "Commit message:", "");
            if (string.IsNullOrWhiteSpace(msg)) return;
            GitPanel.Git(app.WorkspaceFolder, "add -A");
            Run(app, "commit -m \"" + msg.Replace("\"", "\\\"") + "\"");
        }
    }
}
