// Snapshot test hook for Team Collaboration between two real MicroCode instances (two processes, two data folders):
//   host:  MicroCode --data-dir A --folder WS --file WS\a.txt --collab host --collab-token-out tok.txt --wait 8 --snapshot host.png
//   peer:  MicroCode --data-dir B --collab join --collab-join @tok.txt --collab-type "text" --collab-chat "hi" --wait 6 --snapshot peer.png
// The peer joins with the host's LAN token, mounts the mirrored workspace in its main window, types into the editor through
// the real TextBox (TextEdited → CollabHooks → WebSocket) and posts a chat message. Only used with --snapshot.
using System;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using MicroCode.Core;

namespace MicroCode.Views
{
    public static class CollabSnapshot
    {
        static string Arg(string[] args, string name) { int i = Array.IndexOf(args, name); return i >= 0 && i + 1 < args.Length ? args[i + 1] : null; }

        public static Window Prepare(string mode, string[] args, Window main)
        {
            var svc = CollabService.Shared;
            int tab; int.TryParse(Arg(args, "--collab-tab") ?? "-1", out tab);
            if (mode == "host")
            {
                var s = svc.CreateSession();
                string tokenOut = Arg(args, "--collab-token-out");
                if (s != null && tokenOut != null) File.WriteAllText(tokenOut, svc.GetJoinToken()); // the real LAN token (IP:port#CODE) the UI copies
                return args.Contains("--collab-main") ? main : CollabWindow(tab);
            }
            if (mode == "standby") return CollabWindow(tab);
            // join
            string token = Arg(args, "--collab-join") ?? "";
            if (token.StartsWith("@"))
            {
                string path = token.Substring(1);
                var end = DateTime.UtcNow.AddSeconds(30);
                while (!File.Exists(path) && DateTime.UtcNow < end) Thread.Sleep(100);
                token = File.Exists(path) ? File.ReadAllText(path).Trim() : "";
            }
            string type = Arg(args, "--collab-type"), chat = Arg(args, "--collab-chat");
            var join = Task.Run(() => svc.JoinSession(token));
            var ui = main.Dispatcher;
            // once the mirrored workspace is mounted and its file is in the editor, type at the end of line 1 like a user
            var timer = new DispatcherTimer(DispatcherPriority.Background, ui) { Interval = TimeSpan.FromMilliseconds(200) };
            var started = DateTime.UtcNow;
            bool typed = type == null;
            timer.Tick += delegate
            {
                if ((DateTime.UtcNow - started).TotalSeconds > 25) { timer.Stop(); return; }
                if (!join.IsCompleted) return;
                var mw = main as MainWindow;
                var ed = mw != null ? mw.ActiveEditor : null;
                var cur = AppState.Shared.CurrentFile;
                if (!typed && ed != null && cur != null && cur.Path.IndexOf("CollabWorkspaces", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    int eol = ed.Box.Text.IndexOf('\n');
                    ed.Box.CaretIndex = eol < 0 ? ed.Box.Text.Length : eol;
                    ed.Box.SelectedText = type;
                    ed.Box.CaretIndex = (eol < 0 ? ed.Box.Text.Length - type.Length : eol) + type.Length;
                    typed = true;
                }
                if (typed)
                {
                    timer.Stop();
                    if (chat != null) Task.Run(() => svc.SendChatMessage(chat));
                    if (args.Contains("--collab-crud") && svc.SharedRoot != null)
                    {
                        // the same calls the IDE makes: Save (Ctrl+S), New Folder, and the file tree's New File / Rename / Delete
                        AppState.Shared.SaveCurrentFile();
                        AppState.Shared.CreateFolder(svc.SharedRoot, "made-by-peer");
                        string nf = Path.Combine(svc.SharedRoot, "made-by-peer", "notes.txt");
                        File.WriteAllText(nf, "");
                        CollabHooks.FileEvent("write", nf, null, "");
                        string readme = Path.Combine(svc.SharedRoot, "README.md"), renamed = Path.Combine(svc.SharedRoot, "README-renamed.md");
                        if (File.Exists(readme)) { File.Move(readme, renamed); CollabHooks.FileEvent("rename", readme, renamed); }
                        string old = Path.Combine(svc.SharedRoot, "old.txt");
                        if (File.Exists(old)) { File.Delete(old); CollabHooks.FileEvent("delete", old); }
                        AppState.Shared.RefreshFileTree();
                    }
                }
            };
            timer.Start();
            return args.Contains("--collab-view") ? CollabWindow(tab) : main;
        }

        static Window CollabWindow(int tab)
        {
            var t = Theme.Current;
            var view = new CollabView(false);
            if (tab >= 0) view.SelectTab(tab);
            return new Window { Title = "Team Collaboration", Content = view, Background = t.WindowBackground, FontFamily = UI.UIFonts.UI };
        }
    }
}
