// Ties CollabService to the running IDE. AppState lives on the UI thread, while the collaboration host answers HTTP / WebSocket
// traffic on worker threads, so the bridge keeps a lock-protected snapshot of the open buffers (refreshed on the UI thread) for
// reads and posts every change back to the UI thread asynchronously — the service never blocks on the dispatcher while it
// holds its own lock, which would deadlock against an edit coming from the UI.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Threading;
using MicroCode.Core;
using MicroCode.Editor;

namespace MicroCode.Views
{
    public class AppCollabIde : ICollabIde
    {
        readonly object _lock = new object();
        List<CollabOpenFile> _open = new List<CollabOpenFile>();
        string _workspace, _current;
        readonly Dispatcher _ui;

        public AppCollabIde()
        {
            _ui = Application.Current != null ? Application.Current.Dispatcher : Dispatcher.CurrentDispatcher;
            AppState.Shared.Changed += w => { if (w == "files" || w == "workspace" || w == "dirty" || w == "content" || w == "tree") Capture(); };
            Capture();
        }

        /// <summary>UI thread only: copies the open buffers, workspace and current file into the snapshot.</summary>
        public void Capture()
        {
            var app = AppState.Shared;
            var list = app.OpenFiles.Where(f => !f.ReadOnly && f.PreviewKind == null && Path.IsPathRooted(f.Path ?? ""))
                .Select(f => new CollabOpenFile { FullPath = f.Path, Name = f.Name, Language = f.Language, Content = f.Content }).ToList();
            var cur = app.CurrentFile;
            lock (_lock) { _open = list; _workspace = app.WorkspaceFolder; _current = cur != null && Path.IsPathRooted(cur.Path ?? "") ? cur.Path : null; }
        }

        public void CaptureContent(string fullPath, string content)
        {
            lock (_lock) foreach (var f in _open) if (string.Equals(f.FullPath, fullPath, StringComparison.OrdinalIgnoreCase)) f.Content = content;
        }

        public string WorkspaceFolder { get { lock (_lock) return _workspace; } }
        public string CurrentFilePath { get { lock (_lock) return _current; } }
        public List<CollabOpenFile> OpenFiles()
        {
            lock (_lock) return _open.Select(f => new CollabOpenFile { FullPath = f.FullPath, Name = f.Name, Language = f.Language, Content = f.Content }).ToList();
        }

        void Ui(Action a) { _ui.BeginInvoke(a); }

        public void ApplyRemoteContent(string fullPath, string content)
        {
            CaptureContent(fullPath, content);
            Ui(() =>
            {
                var f = AppState.Shared.OpenFiles.FirstOrDefault(x => string.Equals(x.Path, fullPath, StringComparison.OrdinalIgnoreCase));
                if (f == null || f.ReadOnly || f.Content == content) return;
                f.Content = content; // the service wrote the same text to disk, so the dirty flag stays as it was
                AppState.Shared.Notify("content");
            });
        }

        public void MountWorkspace(string root, string activeFileFullPath)
        {
            Ui(() =>
            {
                AppState.Shared.OpenWorkspace(root);
                if (activeFileFullPath != null) AppState.Shared.LoadFile(activeFileFullPath);
                Capture();
            });
        }

        public void OpenFile(string fullPath, int line)
        {
            Ui(() =>
            {
                AppState.Shared.LoadFile(fullPath);
                var win = Application.Current != null ? Application.Current.MainWindow as MainWindow : null;
                if (win != null && line > 0) win.GoToLine(line - 1);
            });
        }

        public void RefreshTree() { Ui(() => AppState.Shared.RefreshFileTree()); }

        public void ApplyRemoteOp(string fullPath, TextOperation op, string previous, string resulting, Action<string> applied)
        {
            Ui(() =>
            {
                string after = null;
                try
                {
                    var f = AppState.Shared.OpenFiles.FirstOrDefault(x => string.Equals(x.Path, fullPath, StringComparison.OrdinalIgnoreCase));
                    if (f == null || f.ReadOnly) return;
                    string current = (f.Content ?? "").Replace("\r\n", "\n");
                    // keystrokes typed after the op was committed are transformed over it (client op first)
                    var patch = OTEditorPatch.Rebase(previous, current, op);
                    after = patch.Apply(current);
                    var area = EditorArea.Current;
                    var ed = area != null ? area.EditorFor(f) : null;
                    if (ed != null && !ed.ApplyOperation(patch)) ed.ReplaceText(after);
                    f.Content = after;
                    CaptureContent(fullPath, after);
                }
                catch (OTException) { after = resulting; }
                finally { applied(after); }
            });
        }

        public void RunAgentPrompt(string prompt, Action<string, string> done)
        {
            Ui(() =>
            {
                var win = Application.Current != null ? Application.Current.MainWindow as MainWindow : null;
                if (win == null) { done(null, "MicroCode's main window is not open on the host."); return; }
                win.Agent.RunPromptWithReply(prompt, m => done(m.Content, m.Error));
            });
        }

        public void PathMoved(string oldFullPath, string newFullPath)
        {
            Ui(() =>
            {
                bool any = false;
                foreach (var f in AppState.Shared.OpenFiles)
                {
                    if (f.Path == null) continue;
                    string moved = null;
                    if (string.Equals(f.Path, oldFullPath, StringComparison.OrdinalIgnoreCase)) moved = newFullPath;
                    else if (f.Path.StartsWith(oldFullPath + "\\", StringComparison.OrdinalIgnoreCase)) moved = newFullPath + f.Path.Substring(oldFullPath.Length);
                    if (moved == null) continue;
                    f.Path = moved; f.Name = Path.GetFileName(moved); any = true;
                }
                if (any) { AppState.Shared.Notify("files"); Capture(); }
            });
        }
    }

    /// <summary>Editor → room events. Edits are debounced per file (150 ms) so a burst of keystrokes becomes one buffer update.</summary>
    public static class CollabHooks
    {
        static readonly Dictionary<string, DispatcherTimer> Pending = new Dictionary<string, DispatcherTimer>(StringComparer.OrdinalIgnoreCase);

        static bool Live { get { return CollabService.HasShared && CollabService.Shared.Session != null; } }

        public static void LocalEdit(CodeFile f, string text)
        {
            if (!Live || f == null || f.ReadOnly || !Path.IsPathRooted(f.Path ?? "")) return;
            var ide = CollabService.Shared.Ide as AppCollabIde;
            if (ide != null) ide.CaptureContent(f.Path, text);
            DispatcherTimer t;
            if (!Pending.TryGetValue(f.Path, out t))
            {
                t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(150) };
                string path = f.Path;
                var file = f;
                t.Tick += delegate { t.Stop(); Pending.Remove(path); if (Live) CollabService.Shared.NotifyLocalFileEdited(path, file.Content); };
                Pending[f.Path] = t;
            }
            t.Stop(); t.Start();
        }

        /// <summary>notifyLocalFileSystemEvent call sites (Save, New File, New Folder, Rename, Delete): op is write / mkdir /
        /// rename / delete. A save first flushes the pending debounced edit so the room never sees the two out of order.</summary>
        public static void FileEvent(string op, string path, string newPath = null, string content = null)
        {
            if (!Live || string.IsNullOrEmpty(path)) return;
            DispatcherTimer pending;
            if (op == "write" && Pending.TryGetValue(path, out pending)) { pending.Stop(); Pending.Remove(path); }
            var ide = CollabService.Shared.Ide as AppCollabIde;
            if (ide != null && content != null) ide.CaptureContent(path, content);
            CollabService.Shared.NotifyLocalFileSystemEvent(op, path, newPath, content);
            if (ide != null) ide.Capture();
        }

        public static void Caret(CodeFile f, CodeEditorView ed, bool typing)
        {
            if (!Live || f == null || ed == null || !Path.IsPathRooted(f.Path ?? "")) return;
            var box = ed.Box;
            var a = Position(ed, box.SelectionStart);
            var b = Position(ed, box.SelectionStart + box.SelectionLength);
            CollabService.Shared.UpdateLocalEditorSelection(f.Path, a.Item1, a.Item2, b.Item1, b.Item2, typing);
        }

        /// <summary>1-based line / column of a character offset.</summary>
        static Tuple<int, int> Position(CodeEditorView ed, int offset)
        {
            var starts = ed.LineStarts;
            int lo = 0, hi = starts.Count - 1;
            while (lo < hi) { int mid = (lo + hi + 1) / 2; if (starts[mid] <= offset) lo = mid; else hi = mid - 1; }
            return Tuple.Create(lo + 1, offset - starts[lo] + 1);
        }
    }
}
