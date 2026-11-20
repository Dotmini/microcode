// Port of the parts of MicroCode/Models/AppState.swift that drive the main window.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Threading;

namespace MicroCode.Core
{
    public enum EditorMode { Code, Science, Playground, Notebook, Scenario, RemoteX, Embedded, AIAgent, Browser, ApiClient, Extensions }
    public enum Surface { Agent, Editor }

    public static class EditorModeInfo
    {
        public static string DisplayName(EditorMode m)
        {
            switch (m)
            {
                case EditorMode.Code: return "Code Editor";
                case EditorMode.Science: return "Science Mode";
                case EditorMode.Playground: return "Playground";
                case EditorMode.RemoteX: return "Remote Explorer";
                case EditorMode.Notebook: return "Notebook";
                case EditorMode.Scenario: return "Scenario";
                case EditorMode.Embedded: return "Embed & IoT Studio";
                case EditorMode.AIAgent: return "AI Agent";
                case EditorMode.Browser: return "Browser";
                case EditorMode.ApiClient: return "API Studio";
                default: return "Extension Studio";
            }
        }

        public static string Icon(EditorMode m)
        {
            switch (m)
            {
                case EditorMode.Code: return "doc.text";
                case EditorMode.Science: return "atom";
                case EditorMode.Playground: return "play.rectangle";
                case EditorMode.RemoteX: return "server.rack";
                case EditorMode.Notebook: return "book.pages";
                case EditorMode.Scenario: return "flowchart";
                case EditorMode.Embedded: return "cpu.fill";
                case EditorMode.AIAgent: return "brain.head.profile";
                case EditorMode.Browser: return "globe";
                case EditorMode.ApiClient: return "network";
                default: return "puzzlepiece.extension";
            }
        }
    }

    public class FileNode
    {
        public string Name, Path;
        public bool IsDirectory, Loaded;
        public List<FileNode> Children = new List<FileNode>();
    }

    public class CodeFile
    {
        public Guid Id = Guid.NewGuid();
        public string Path, Name, Content, Language;
        public bool IsUnsaved, UsesCRLF;
        /// <summary>Never written back: previews (image/pdf/binary) and placeholders for files too large or unreadable.</summary>
        public bool ReadOnly;
        /// <summary>image | pdf | binary when the editor shows a preview instead of text.</summary>
        public string PreviewKind;
    }

    /// <summary>PreviewFileType.detect: code (editable text), markdown, table (csv/tsv), patch, image, pdf or binary.</summary>
    public static class FileKinds
    {
        static readonly HashSet<string> Images = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".ico", ".tif", ".tiff", ".webp" };
        static readonly HashSet<string> Tables = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".csv", ".tsv" };
        static readonly HashSet<string> Markdown = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".md", ".markdown", ".mdx", ".rmd" };
        static readonly HashSet<string> KnownBinary = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ".exe", ".dll", ".pdb", ".zip", ".7z", ".rar", ".gz", ".tgz", ".tar", ".mp3", ".mp4", ".m4a", ".mov", ".avi", ".mkv", ".wav", ".flac", ".docx", ".xlsx", ".pptx", ".doc", ".xls", ".ppt", ".so", ".dylib", ".class", ".jar", ".pyc", ".woff", ".woff2", ".ttf", ".otf", ".psd", ".sqlite", ".db", ".bin", ".iso", ".dmg", ".msi" };

        public static string Detect(string path)
        {
            string ext = System.IO.Path.GetExtension(path ?? "");
            if (Images.Contains(ext)) return "image";
            if (ext.Equals(".pdf", StringComparison.OrdinalIgnoreCase)) return "pdf";
            if (Tables.Contains(ext)) return "table";
            if (ext.Equals(".diff", StringComparison.OrdinalIgnoreCase) || ext.Equals(".patch", StringComparison.OrdinalIgnoreCase)) return "patch";
            if (Markdown.Contains(ext)) return "markdown";
            if (KnownBinary.Contains(ext)) return "binary";
            return LooksLikeText(path) ? "code" : "binary";
        }

        /// <summary>Sniffs the first 8 KB: a byte-order mark means text, a NUL byte means binary.</summary>
        public static bool LooksLikeText(string path)
        {
            try
            {
                using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                {
                    var buf = new byte[8192];
                    int n = fs.Read(buf, 0, buf.Length);
                    if (n >= 2 && ((buf[0] == 0xFF && buf[1] == 0xFE) || (buf[0] == 0xFE && buf[1] == 0xFF))) return true;
                    if (n >= 3 && buf[0] == 0xEF && buf[1] == 0xBB && buf[2] == 0xBF) return true;
                    for (int i = 0; i < n; i++) if (buf[i] == 0) return false;
                    return true;
                }
            }
            // unreadable here: treat as text so the editor reports the read error itself
            catch (IOException) { return true; }
            catch (UnauthorizedAccessException) { return true; }
        }

        public static bool IsText(string kind) { return kind == "code" || kind == "markdown" || kind == "table" || kind == "patch"; }
    }

    /// <summary>UserDefaults equivalent: %APPDATA%\MicroCode\settings.json.
    /// Several MicroCode windows/processes can share the file, so a flush re-reads it and writes back only the keys this
    /// process changed (like NSUserDefaults), under a named mutex, through a temp file + atomic replace — a reader can never
    /// see a half-written file and one process can no longer wipe another's API keys.</summary>
    public static class Defaults
    {
        static Dictionary<string, object> _d;
        static readonly HashSet<string> _dirty = new HashSet<string>();
        static readonly HashSet<string> _removed = new HashSet<string>();
        static string _dirOverride;
        public static string Dir { get { return _dirOverride ?? System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "MicroCode"); } }
        /// <summary>Moves every store (settings, chats, notebooks, logs) to another folder. --snapshot uses this so test renders never touch the user's data.</summary>
        public static void UseDir(string dir) { _dirOverride = dir; _d = null; _dirty.Clear(); _removed.Clear(); }
        static string FilePath { get { return System.IO.Path.Combine(Dir, "settings.json"); } }

        static Dictionary<string, object> D
        {
            get
            {
                if (_d == null) { bool ok; _d = ReadDisk(out ok); }
                return _d;
            }
        }

        /// <summary>Reads settings.json; retries while another process is mid-write. ok=false means the file exists but could not be parsed.</summary>
        static Dictionary<string, object> ReadDisk(out bool ok)
        {
            ok = true;
            if (!File.Exists(FilePath)) return new Dictionary<string, object>();
            for (int attempt = 0; attempt < 6; attempt++)
            {
                try
                {
                    string text = ReadShared(FilePath);
                    if (string.IsNullOrWhiteSpace(text)) { if (attempt < 5) { System.Threading.Thread.Sleep(30); continue; } return new Dictionary<string, object>(); }
                    return new JavaScriptSerializer { MaxJsonLength = int.MaxValue }.Deserialize<Dictionary<string, object>>(text) ?? new Dictionary<string, object>();
                }
                catch { System.Threading.Thread.Sleep(30); }
            }
            ok = false;
            return new Dictionary<string, object>();
        }

        public static string ReadShared(string path)
        {
            using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (var sr = new StreamReader(fs, Encoding.UTF8)) return sr.ReadToEnd();
        }

        /// <summary>Write text through a temp file and an atomic replace so readers never observe a truncated file.</summary>
        public static void WriteAtomic(string path, string text)
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path));
            string tmp = path + "." + System.Diagnostics.Process.GetCurrentProcess().Id + ".tmp";
            File.WriteAllText(tmp, text, new UTF8Encoding(false));
            for (int attempt = 0; ; attempt++)
            {
                try
                {
                    if (File.Exists(path)) File.Replace(tmp, path, null, true); else File.Move(tmp, path);
                    return;
                }
                catch (IOException)
                {
                    if (attempt < 8) { System.Threading.Thread.Sleep(25); continue; }
                    File.Copy(tmp, path, true); // last resort: not atomic, but never loses the data
                    try { File.Delete(tmp); } catch { }
                    return;
                }
            }
        }

        /// <summary>Cross-process lock for read-merge-write of a shared file.</summary>
        public static void WithFileLock(string name, Action body)
        {
            System.Threading.Mutex m = null;
            bool owned = false;
            try
            {
                m = new System.Threading.Mutex(false, "Local\\MicroCode." + name + "." + (Dir.ToLowerInvariant().GetHashCode() & 0x7fffffff));
                try { owned = m.WaitOne(3000); } catch (System.Threading.AbandonedMutexException) { owned = true; }
            }
            catch { }
            try { body(); }
            finally { if (owned) try { m.ReleaseMutex(); } catch { } if (m != null) m.Dispose(); }
        }

        public static bool Has(string k) { return D.ContainsKey(k); }
        public static object Get(string k) { object v; return D.TryGetValue(k, out v) ? v : null; }
        public static bool Bool(string k, bool def) { var v = Get(k); return v is bool ? (bool)v : def; }
        public static double Num(string k, double def) { var v = Get(k); try { return v == null ? def : Convert.ToDouble(v); } catch { return def; } }
        public static string Str(string k, string def) { var v = Get(k) as string; return v ?? def; }
        public static List<string> List(string k)
        {
            var v = Get(k) as System.Collections.ArrayList;
            var r = new List<string>();
            if (v != null) foreach (var o in v) if (o is string) r.Add((string)o);
            return r;
        }
        public static void Set(string k, object v)
        {
            lock (_dirty) { D[k] = v; _dirty.Add(k); _removed.Remove(k); }
            Save();
        }
        /// <summary>Value of a key as currently stored on disk (another window may have changed it).</summary>
        public static object PeekDisk(string k)
        {
            bool ok; object v;
            return ReadDisk(out ok).TryGetValue(k, out v) ? v : null;
        }
        /// <summary>Replace the in-memory value without marking it as changed by this process.</summary>
        public static void Adopt(string k, object v) { lock (_dirty) { if (v == null) D.Remove(k); else D[k] = v; } }
        public static void Remove(string k)
        {
            lock (_dirty) { D.Remove(k); _dirty.Remove(k); _removed.Add(k); }
            Save();
        }

        static DispatcherTimer _saveTimer;
        static void Save()
        {
            var app = System.Windows.Application.Current;
            if (app == null || !app.Dispatcher.CheckAccess()) { Flush(); return; }
            if (_saveTimer == null)
            {
                _saveTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
                _saveTimer.Tick += delegate { _saveTimer.Stop(); Flush(); };
            }
            _saveTimer.Stop();
            _saveTimer.Start();
        }

        public static void Flush()
        {
            lock (_dirty)
            {
                if (_dirty.Count == 0 && _removed.Count == 0) return;
                try
                {
                    WithFileLock("settings", delegate
                    {
                        bool ok;
                        var disk = ReadDisk(out ok);
                        if (!ok) try { File.Copy(FilePath, System.IO.Path.Combine(Dir, "settings.unreadable-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".json"), true); } catch { }
                        foreach (var k in _removed) disk.Remove(k);
                        foreach (var k in _dirty) { object v; if (D.TryGetValue(k, out v)) disk[k] = v; }
                        WriteAtomic(FilePath, new JavaScriptSerializer { MaxJsonLength = int.MaxValue }.Serialize(disk));
                        // adopt what other windows saved meanwhile
                        foreach (var kv in disk) _d[kv.Key] = kv.Value;
                        _dirty.Clear(); _removed.Clear();
                    });
                }
                catch { }
            }
        }
    }

    public class AppState
    {
        public static AppState Shared = new AppState();
        public event Action<string> Changed;
        public void Notify(string what) { if (Changed != null) Changed(what); }

        public string WorkspaceFolder;
        public List<FileNode> FileTree = new List<FileNode>();
        public int FileTreeRevision;
        public string FileTreeLimitWarning;
        public List<CodeFile> OpenFiles = new List<CodeFile>();
        public int CurrentFileIndex = -1;
        public EditorMode Mode = EditorMode.Code;
        public Surface Surface = Surface.Editor;
        public bool ConsoleVisible, AgenticContextVisible, ShowingWelcomeHome, ShowingPreviewView;
        public int SelectedConsoleTab;
        public string ConsoleOutput = "";
        public double FontSize = 16;
        public string ThemeRaw = "dark";
        public bool IsRunning;
        Process _running;

        // SidebarStateController
        public bool SidebarVisible = true;
        public double SidebarWidth = 270;
        // WindowTrafficLightsController
        public bool AutoHideTrafficLights = true;

        public CodeFile CurrentFile
        {
            get { return CurrentFileIndex >= 0 && CurrentFileIndex < OpenFiles.Count ? OpenFiles[CurrentFileIndex] : null; }
        }

        public void Load()
        {
            ThemeRaw = Defaults.Str("appTheme", "dark");
            Theme.Apply(ThemeRaw);
            SidebarVisible = Defaults.Bool("sidebarVisible", true);
            double w = Defaults.Num("microcode_agentic_sidebar_width", 0);
            SidebarWidth = w >= 160 ? Math.Min(600, w) : 270;
            AutoHideTrafficLights = Defaults.Bool("autoHideWindowTrafficLights", true);
            FontSize = Defaults.Num("editorFontSize", 16);
            ConsoleVisible = Defaults.Bool("showConsoleOnStartup", false);
        }

        // MARK: - Recents (AppState.getRecentWorkspaces / getRecentFiles)
        public static List<string> RecentWorkspaces() { return Defaults.List("recentWorkspaces").Where(Directory.Exists).ToList(); }
        public static List<string> RecentFiles() { return Defaults.List("recentFiles").Where(File.Exists).ToList(); }
        static void Record(string key, string path, int max)
        {
            var l = Defaults.List(key);
            l.RemoveAll(p => string.Equals(p, path, StringComparison.OrdinalIgnoreCase));
            l.Insert(0, path);
            if (l.Count > max) l.RemoveRange(max, l.Count - max);
            Defaults.Set(key, l);
        }

        // MARK: - Workspace
        public void OpenWorkspace(string path)
        {
            if (!Directory.Exists(path)) return;
            WorkspaceFolder = path;
            ShowingWelcomeHome = false;
            Record("recentWorkspaces", path, 12);
            RefreshFileTree();
            Notify("workspace");
        }

        public void CloseWorkspace()
        {
            WorkspaceFolder = null;
            FileTree = new List<FileNode>();
            OpenFiles.Clear();
            CurrentFileIndex = -1;
            FileTreeRevision++;
            Notify("workspace");
            Notify("files");
        }

        static readonly HashSet<string> Ignored = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            { ".git", "node_modules", ".build", "build", "DerivedData", ".DS_Store", "__pycache__", ".venv", "target", ".idea", ".vs", "bin", "obj" };

        public void RefreshFileTree()
        {
            FileTree = WorkspaceFolder == null ? new List<FileNode>() : ReadDir(WorkspaceFolder);
            FileTreeRevision++;
            Notify("tree");
        }

        public List<FileNode> ReadDir(string dir)
        {
            var list = new List<FileNode>();
            try
            {
                var di = new DirectoryInfo(dir);
                foreach (var d in di.GetDirectories().OrderBy(x => x.Name, StringComparer.OrdinalIgnoreCase))
                {
                    if ((d.Attributes & FileAttributes.Hidden) != 0 && d.Name != ".github") continue;
                    if (Ignored.Contains(d.Name) && d.Name != "build") continue;
                    list.Add(new FileNode { Name = d.Name, Path = d.FullName, IsDirectory = true });
                }
                foreach (var f in di.GetFiles().OrderBy(x => x.Name, StringComparer.OrdinalIgnoreCase))
                {
                    if (f.Name == ".DS_Store") continue;
                    list.Add(new FileNode { Name = f.Name, Path = f.FullName, IsDirectory = false, Loaded = true });
                }
            }
            catch { }
            return list;
        }

        public void LoadChildren(FileNode node)
        {
            if (node.Loaded) return;
            node.Children = ReadDir(node.Path);
            node.Loaded = true;
        }

        // MARK: - Files
        public void LoadFile(string path)
        {
            if (!File.Exists(path)) return;
            int idx = OpenFiles.FindIndex(f => string.Equals(f.Path, path, StringComparison.OrdinalIgnoreCase));
            if (idx < 0)
            {
                var cf = new CodeFile { Path = path, Name = System.IO.Path.GetFileName(path), Content = "", Language = DetectLanguage(path) };
                string kind = FileKinds.Detect(path);
                if (!FileKinds.IsText(kind))
                {
                    // images, PDFs and other binaries open as previews; decoding them as text and saving would corrupt them
                    cf.PreviewKind = kind;
                    cf.ReadOnly = true;
                }
                else
                {
                    try
                    {
                        var fi = new FileInfo(path);
                        if (fi.Length > 8 * 1024 * 1024) { cf.Content = "// File too large to open in the editor (" + (fi.Length / 1024 / 1024) + " MB)"; cf.ReadOnly = true; }
                        else
                        {
                            string content = File.ReadAllText(path);
                            cf.Content = content.Replace("\r\n", "\n");
                            cf.UsesCRLF = content.Contains("\r\n");
                        }
                    }
                    catch (Exception ex) { cf.Content = "// Unable to read file: " + ex.Message; cf.ReadOnly = true; }
                }
                OpenFiles.Add(cf);
                idx = OpenFiles.Count - 1;
                Record("recentFiles", path, 20);
            }
            CurrentFileIndex = idx;
            if (Mode != EditorMode.Code && Surface == Surface.Editor) Mode = EditorMode.Code;
            Notify("files");
        }

        public void SelectFile(CodeFile f)
        {
            int i = OpenFiles.IndexOf(f);
            if (i >= 0) { CurrentFileIndex = i; Notify("files"); }
        }

        public void CloseFile(CodeFile f)
        {
            int i = OpenFiles.IndexOf(f);
            if (i < 0) return;
            if (f.IsUnsaved)
            {
                var r = MessageBox.Show("Do you want to save the changes you made to \"" + f.Name + "\"?", "MicroCode", MessageBoxButton.YesNoCancel, MessageBoxImage.Warning);
                if (r == MessageBoxResult.Cancel) return;
                if (r == MessageBoxResult.Yes) Save(f);
            }
            OpenFiles.RemoveAt(i);
            if (CurrentFileIndex >= OpenFiles.Count) CurrentFileIndex = OpenFiles.Count - 1;
            else if (i < CurrentFileIndex) CurrentFileIndex--;
            Notify("files");
        }

        public void UpdateContent(CodeFile f, string text)
        {
            if (f.ReadOnly || f.Content == text) return;
            f.Content = text;
            if (!f.IsUnsaved) { f.IsUnsaved = true; Notify("dirty"); }
        }

        public void Save(CodeFile f)
        {
            if (f == null) return;
            if (f.ReadOnly) return; // previews and placeholder text must never overwrite the file on disk
            if (string.IsNullOrEmpty(f.Path) || !System.IO.Path.IsPathRooted(f.Path)) { SaveFileAs(); return; }
            try
            {
                File.WriteAllText(f.Path, f.UsesCRLF ? f.Content.Replace("\n", "\r\n") : f.Content, new UTF8Encoding(false));
                f.IsUnsaved = false;
                Notify("dirty");
            }
            catch (Exception ex) { MessageBox.Show(ex.Message, "MicroCode"); }
        }

        public void SaveCurrentFile() { Save(CurrentFile); }

        public void SaveFileAs()
        {
            var f = CurrentFile;
            if (f == null || f.ReadOnly) return;
            var dlg = new Microsoft.Win32.SaveFileDialog { FileName = f.Name, InitialDirectory = WorkspaceFolder ?? "" };
            if (dlg.ShowDialog() == true)
            {
                f.Path = dlg.FileName;
                f.Name = System.IO.Path.GetFileName(dlg.FileName);
                f.Language = DetectLanguage(f.Path);
                Save(f);
                if (WorkspaceFolder != null) RefreshFileTree();
                Notify("files");
            }
        }

        int _untitled = 1;
        public void NewFile()
        {
            string name = "Untitled-" + (_untitled++) + ".txt";
            OpenFiles.Add(new CodeFile { Path = name, Name = name, Content = "", Language = "text" });
            CurrentFileIndex = OpenFiles.Count - 1;
            if (Surface == Surface.Editor) Mode = EditorMode.Code;
            Notify("files");
        }

        public void OpenFileDialog()
        {
            var dlg = new Microsoft.Win32.OpenFileDialog { Multiselect = true, InitialDirectory = WorkspaceFolder ?? "" };
            if (dlg.ShowDialog() == true) foreach (var p in dlg.FileNames) LoadFile(p);
        }

        public void OpenFolderDialog()
        {
            var p = Native.PickFolder("Open Project or Folder", WorkspaceFolder);
            if (p != null) OpenWorkspace(p);
        }

        public void CreateFolder(string parent, string name)
        {
            try
            {
                string target = System.IO.Path.Combine(parent, name);
                int n = 2;
                while (Directory.Exists(target)) target = System.IO.Path.Combine(parent, name + " " + (n++));
                Directory.CreateDirectory(target);
                RefreshFileTree();
            }
            catch (Exception ex) { MessageBox.Show(ex.Message, "MicroCode"); }
        }

        public void UpdateFileLanguage(string lang, CodeFile f)
        {
            if (f == null) return;
            f.Language = lang;
            Notify("files");
        }

        // MARK: - Modes & panels
        public void SwitchToMode(EditorMode m)
        {
            ShowingWelcomeHome = false;
            Mode = m;
            Surface = m == EditorMode.AIAgent ? Surface.Agent : Surface.Editor;
            Notify("mode");
        }

        public void ToggleSidebar() { SetSidebarVisible(!SidebarVisible); }
        public void SetSidebarVisible(bool v)
        {
            if (SidebarVisible == v) return;
            SidebarVisible = v;
            Defaults.Set("sidebarVisible", v);
            Notify("sidebar");
        }

        public void SetSidebarWidth(double w)
        {
            w = Math.Max(160, Math.Min(600, Math.Round(w)));
            if (Math.Abs(w - SidebarWidth) < 0.25) return;
            SidebarWidth = w;
            Defaults.Set("microcode_agentic_sidebar_width", w);
            Notify("sidebarWidth");
        }

        public void ToggleConsole() { ConsoleVisible = !ConsoleVisible; Notify("console"); }
        public void ToggleAgenticContext() { AgenticContextVisible = !AgenticContextVisible; Notify("inspector"); }

        public void SetTheme(string raw)
        {
            ThemeRaw = raw;
            Defaults.Set("appTheme", raw);
            Theme.Apply(raw);
            Notify("theme");
        }

        public void SetFontSize(double size)
        {
            FontSize = Math.Max(9, Math.Min(36, size));
            Defaults.Set("editorFontSize", FontSize);
            Notify("font");
        }

        // MARK: - Run / Build
        public void AppendConsole(string s)
        {
            ConsoleOutput += s;
            Notify("consoleOutput");
        }

        public void RunCode()
        {
            var file = CurrentFile;
            if (file == null) { ConsoleOutput = "No file open. Open a file to run it.\n"; ConsoleVisible = true; Notify("console"); return; }
            if (file.IsUnsaved && System.IO.Path.IsPathRooted(file.Path)) Save(file);
            ConsoleOutput = "Running " + file.Name + "...\n";
            ConsoleVisible = true;
            SelectedConsoleTab = 0;
            Notify("console");
            string path = file.Path;
            if (!System.IO.Path.IsPathRooted(path))
            {
                path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "microcode_run_" + file.Name);
                File.WriteAllText(path, file.Content);
            }
            AppendConsole("📍 Running locally...\n");
            string exe, args;
            if (!Runner.CommandFor(file.Language, path, out exe, out args))
            {
                AppendConsole("Error: No runner configured for language '" + file.Language + "'.\n");
                return;
            }
            StartProcess(exe, args, System.IO.Path.GetDirectoryName(path));
        }

        public void BuildProject()
        {
            if (WorkspaceFolder == null) { RunCode(); return; }
            string exe, args;
            if (!Runner.BuildCommand(WorkspaceFolder, out exe, out args))
            {
                ConsoleOutput = "Build: no build system detected in " + System.IO.Path.GetFileName(WorkspaceFolder) + " (package.json, Cargo.toml, go.mod, *.csproj, Makefile, CMakeLists.txt).\n";
                ConsoleVisible = true; Notify("console");
                return;
            }
            ConsoleOutput = "Building " + System.IO.Path.GetFileName(WorkspaceFolder) + "...\n$ " + exe + " " + args + "\n";
            ConsoleVisible = true; SelectedConsoleTab = 0; Notify("console");
            StartProcess(exe, args, WorkspaceFolder);
        }

        void StartProcess(string exe, string args, string cwd)
        {
            StopExecution();
            var sw = Stopwatch.StartNew();
            var psi = new ProcessStartInfo(exe, args)
            {
                UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true,
                WorkingDirectory = cwd, StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
            };
            psi.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8";
            psi.EnvironmentVariables["PYTHONUNBUFFERED"] = "1";
            var p = new Process { StartInfo = psi, EnableRaisingEvents = true };
            var disp = Application.Current.Dispatcher;
            var err = new StringBuilder();
            p.OutputDataReceived += delegate(object s, DataReceivedEventArgs e) { if (e.Data != null) disp.BeginInvoke(new Action(() => AppendConsole(e.Data + "\n"))); };
            p.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e) { if (e.Data != null) lock (err) err.AppendLine(e.Data); };
            p.Exited += delegate
            {
                p.WaitForExit();
                sw.Stop();
                string errText; lock (err) errText = err.ToString();
                int code = p.ExitCode;
                disp.BeginInvoke(new Action(() =>
                {
                    if (errText.Length > 0) AppendConsole("\n" + errText);
                    AppendConsole("\n\nExited with code " + code + " in " + sw.Elapsed.TotalSeconds.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture) + "s\n");
                    IsRunning = false; _running = null; Notify("running");
                }));
            };
            try
            {
                p.Start();
                p.BeginOutputReadLine();
                p.BeginErrorReadLine();
                _running = p; IsRunning = true; Notify("running");
            }
            catch (Exception ex)
            {
                AppendConsole("Error: Failed to start '" + exe + "': " + ex.Message + "\nMake sure the runtime is installed and on PATH.\n");
            }
        }

        public void StopExecution()
        {
            var p = _running;
            if (p == null) return;
            try { if (!p.HasExited) { p.Kill(); AppendConsole("\n⏹ Execution stopped.\n"); } } catch { }
            _running = null; IsRunning = false; Notify("running");
        }

        // MARK: - detectLanguage(from:)
        public static string DetectLanguage(string path)
        {
            string ext = (System.IO.Path.GetExtension(path) ?? "").TrimStart('.').ToLowerInvariant();
            switch (ext)
            {
                case "py": return "python";
                case "js": case "jsx": case "mjs": case "cjs": return "javascript";
                case "ts": case "tsx": case "mts": case "cts": return "typescript";
                case "rs": return "rust";
                case "swift": return "swift";
                case "go": return "go";
                case "rb": return "ruby";
                case "java": return "java";
                case "kt": case "kts": return "kotlin";
                case "cpp": case "cc": case "cxx": case "c++": case "hpp": case "hxx": case "hh": return "cpp";
                case "m": return "objective-c";
                case "mm": return "objective-cpp";
                case "c": case "h": return "c";
                case "json": case "jsonc": return "json";
                case "xml": case "svg": case "xhtml": return "xml";
                case "html": case "htm": return "html";
                case "vue": return "vue";
                case "svelte": return "svelte";
                case "css": case "scss": case "sass": case "less": return "css";
                case "md": case "mdown": case "markdown": return "markdown";
                case "sh": case "zsh": case "bash": case "fish": return "shell";
                case "yaml": case "yml": return "yaml";
                case "toml": case "ini": case "conf": case "config": case "env": case "properties": return "toml";
                case "ar": return "ardium";
                case "dart": return "dart";
                case "php": case "phtml": case "php8": return "php";
                case "cs": return "csharp";
                case "lua": return "lua";
                case "pl": case "pm": return "perl";
                case "r": return "r";
                case "jl": return "julia";
                case "sql": case "pgsql": case "mysql": case "sqlite": return "sql";
                case "graphql": case "gql": return "graphql";
                case "ml": case "mli": return "ocaml";
                case "hs": return "haskell";
                case "zig": return "zig";
                case "nim": return "nim";
                case "d": return "d";
                case "f90": case "f95": case "f03": return "fortran";
                case "pas": case "pp": return "pascal";
                case "ex": case "exs": return "elixir";
                case "clj": case "cljs": return "clojure";
                case "groovy": return "groovy";
                case "hx": return "haxe";
                case "scala": case "sc": return "scala";
                case "fs": case "fsi": case "fsx": return "fsharp";
                case "vala": return "vala";
                case "ps1": return "powershell";
                case "asm": case "s": return "assembly";
                case "sol": return "solidity";
                case "bat": case "cmd": return "batch";
                default: return "text";
            }
        }
    }

    /// <summary>Local runtimes on Windows for runCode()/buildProject().</summary>
    public static class Runner
    {
        static string Q(string p) { return "\"" + p + "\""; }

        public static bool CommandFor(string lang, string file, out string exe, out string args)
        {
            exe = null; args = null;
            string outExe = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "microcode_" + System.IO.Path.GetFileNameWithoutExtension(file) + ".exe");
            switch (lang)
            {
                case "python": exe = "python"; args = "-u " + Q(file); return true;
                case "javascript": exe = "node"; args = Q(file); return true;
                case "typescript": exe = "cmd.exe"; args = "/c npx --yes tsx " + Q(file); return true;
                case "go": exe = "go"; args = "run " + Q(file); return true;
                case "rust": exe = "cmd.exe"; args = "/c rustc " + Q(file) + " -o " + Q(outExe) + " && " + Q(outExe); return true;
                case "c": exe = "cmd.exe"; args = "/c gcc " + Q(file) + " -o " + Q(outExe) + " && " + Q(outExe); return true;
                case "cpp": exe = "cmd.exe"; args = "/c g++ -std=c++17 " + Q(file) + " -o " + Q(outExe) + " && " + Q(outExe); return true;
                case "java": exe = "java"; args = Q(file); return true;
                case "ruby": exe = "ruby"; args = Q(file); return true;
                case "php": exe = "php"; args = Q(file); return true;
                case "perl": exe = "perl"; args = Q(file); return true;
                case "lua": exe = "lua"; args = Q(file); return true;
                case "r": exe = "Rscript"; args = Q(file); return true;
                case "julia": exe = "julia"; args = Q(file); return true;
                case "dart": exe = "dart"; args = "run " + Q(file); return true;
                case "swift": exe = "swift"; args = Q(file); return true;
                case "kotlin": exe = "cmd.exe"; args = "/c kotlinc -script " + Q(file); return true;
                case "shell": exe = "bash"; args = Q(file); return true;
                case "powershell": exe = "powershell.exe"; args = "-NoProfile -ExecutionPolicy Bypass -File " + Q(file); return true;
                case "batch": exe = "cmd.exe"; args = "/c " + Q(file); return true;
                case "csharp": exe = "dotnet"; args = "run"; return true;
                case "html": exe = "explorer.exe"; args = Q(file); return true;
            }
            return false;
        }

        public static bool BuildCommand(string ws, out string exe, out string args)
        {
            exe = "cmd.exe"; args = null;
            Func<string, bool> has = n => File.Exists(System.IO.Path.Combine(ws, n));
            if (has("package.json")) { args = "/c npm run build"; return true; }
            if (has("Cargo.toml")) { args = "/c cargo build"; return true; }
            if (has("go.mod")) { args = "/c go build ./..."; return true; }
            if (Directory.GetFiles(ws, "*.sln").Length > 0 || Directory.GetFiles(ws, "*.csproj").Length > 0) { args = "/c dotnet build"; return true; }
            if (has("CMakeLists.txt")) { args = "/c cmake -S . -B build && cmake --build build"; return true; }
            if (has("Makefile")) { args = "/c make"; return true; }
            if (has("Package.swift")) { args = "/c swift build"; return true; }
            if (has("pom.xml")) { args = "/c mvn -q package"; return true; }
            if (has("build.gradle") || has("build.gradle.kts")) { args = "/c gradle build"; return true; }
            return false;
        }
    }
}
