// Stdio JSON-RPC 2.0 Content-Length framed Language Server Protocol (LSP) client & auto-detecting manager.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace MicroCode.Views
{
    public class LspDiagnostic
    {
        public string FilePath = "";
        public string Message = "";
        public string Severity = "error";
        public string Code = "";
        public string Source = "";
        public int StartLine;
        public int StartColumn;
        public int EndLine;
        public int EndColumn;
    }

    public class LspLocation
    {
        public string Uri = "";
        public string FilePath = "";
        public int StartLine;
        public int StartColumn;
        public int EndLine;
        public int EndColumn;
    }

    public class LspCompletionItem
    {
        public string Label = "";
        public string Detail = "";
        public string Documentation = "";
        public string InsertText = "";
        public string Kind = "";
    }

    public class LspServerSpec
    {
        public string Language = "";
        public string ServerName = "";
        public string Command = "";
        public List<string> Args = new List<string>();
        public bool Available;
        public string ResolvedPath = "";
    }

    public static class LspJsonRpc
    {
        static readonly UTF8Encoding Utf8NoBom = new UTF8Encoding(false);

        public static byte[] Encode(object payload)
        {
            string json = DJ.Ser(payload);
            byte[] body = Utf8NoBom.GetBytes(json);
            byte[] header = Encoding.ASCII.GetBytes("Content-Length: " + body.Length.ToString(CultureInfo.InvariantCulture) + "\r\n\r\n");
            byte[] frame = new byte[header.Length + body.Length];
            Buffer.BlockCopy(header, 0, frame, 0, header.Length);
            Buffer.BlockCopy(body, 0, frame, header.Length, body.Length);
            return frame;
        }

        public static bool TryReadMessage(Stream stream, out Dictionary<string, object> message)
        {
            message = null;
            if (stream == null) return false;

            int contentLength = -1;
            var lineBuf = new MemoryStream();
            bool sawHeaderByte = false;

            while (true)
            {
                int b = stream.ReadByte();
                if (b < 0)
                {
                    if (!sawHeaderByte) return false;
                    return false;
                }
                sawHeaderByte = true;
                if (b == '\n')
                {
                    string line = Encoding.ASCII.GetString(lineBuf.ToArray()).TrimEnd('\r');
                    lineBuf.SetLength(0);
                    if (line.Length == 0)
                    {
                        if (contentLength >= 0) break;
                        continue;
                    }
                    int colon = line.IndexOf(':');
                    if (colon > 0)
                    {
                        string key = line.Substring(0, colon).Trim();
                        string val = line.Substring(colon + 1).Trim();
                        if (string.Equals(key, "Content-Length", StringComparison.OrdinalIgnoreCase))
                        {
                            int len;
                            if (int.TryParse(val, NumberStyles.Integer, CultureInfo.InvariantCulture, out len))
                            {
                                contentLength = len;
                            }
                        }
                    }
                }
                else
                {
                    lineBuf.WriteByte((byte)b);
                }
            }

            if (contentLength <= 0 || contentLength > 32 * 1024 * 1024) return false;
            byte[] payload = new byte[contentLength];
            int offset = 0;
            while (offset < contentLength)
            {
                int read = stream.Read(payload, offset, contentLength - offset);
                if (read <= 0) return false;
                offset += read;
            }

            string json = Utf8NoBom.GetString(payload);
            message = DJ.Obj(json);
            return message != null;
        }

        public static bool TryReadMessage(byte[] buffer, ref int offset, int count, out Dictionary<string, object> message)
        {
            message = null;
            if (buffer == null || offset < 0 || offset >= count) return false;

            int end = Math.Min(count, buffer.Length);
            int headerStart = offset;
            int headerEnd = -1;
            int sepLen = 4;

            for (int i = headerStart; i <= end - 4; i++)
            {
                if (buffer[i] == '\r' && buffer[i + 1] == '\n' && buffer[i + 2] == '\r' && buffer[i + 3] == '\n')
                {
                    headerEnd = i;
                    sepLen = 4;
                    break;
                }
            }
            if (headerEnd < 0)
            {
                for (int i = headerStart; i <= end - 2; i++)
                {
                    if (buffer[i] == '\n' && buffer[i + 1] == '\n')
                    {
                        headerEnd = i;
                        sepLen = 2;
                        break;
                    }
                }
            }
            if (headerEnd < 0) return false;

            string headerText = Encoding.ASCII.GetString(buffer, headerStart, headerEnd - headerStart);
            int contentLength = -1;
            string[] lines = headerText.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
            for (int i = 0; i < lines.Length; i++)
            {
                int colon = lines[i].IndexOf(':');
                if (colon <= 0) continue;
                string k = lines[i].Substring(0, colon).Trim();
                string v = lines[i].Substring(colon + 1).Trim();
                if (string.Equals(k, "Content-Length", StringComparison.OrdinalIgnoreCase))
                {
                    int len;
                    if (int.TryParse(v, NumberStyles.Integer, CultureInfo.InvariantCulture, out len))
                    {
                        contentLength = len;
                    }
                }
            }
            if (contentLength < 0) return false;

            int bodyStart = headerEnd + sepLen;
            if (bodyStart + contentLength > end) return false;

            string json = Utf8NoBom.GetString(buffer, bodyStart, contentLength);
            message = DJ.Obj(json);
            if (message == null) return false;
            offset = bodyStart + contentLength;
            return true;
        }
    }

    public class LspServerProcess : IDisposable
    {
        readonly object _sendGate = new object();
        readonly object _pendingGate = new object();
        readonly object _docGate = new object();
        readonly object _diagGate = new object();
        readonly Dictionary<int, TaskCompletionSource<Dictionary<string, object>>> _pending = new Dictionary<int, TaskCompletionSource<Dictionary<string, object>>>();
        readonly Dictionary<string, int> _docVersions = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        readonly Dictionary<string, List<LspDiagnostic>> _diagnostics = new Dictionary<string, List<LspDiagnostic>>(StringComparer.OrdinalIgnoreCase);

        Process _proc;
        Stream _stdin;
        Thread _readThread;
        Thread _errThread;
        int _nextId;
        volatile bool _running;

        public string Language { get; private set; }
        public string ServerName { get; private set; }
        public string RootUri { get; private set; }
        public bool IsRunning { get { return _running && _proc != null && !_proc.HasExited; } }
        public bool Initialized { get; private set; }
        public string LastError { get; private set; }

        public LspServerProcess(string language, string serverName)
        {
            Language = language ?? "";
            ServerName = serverName ?? "";
        }

        public bool Start(string command, IList<string> args, string rootUri, int initTimeoutMs)
        {
            Shutdown();
            RootUri = NormalizeUriOrPathToUri(rootUri);
            LastError = null;
            Initialized = false;

            try
            {
                var psi = new ProcessStartInfo();
                psi.FileName = command;
                psi.Arguments = BuildArgString(args);
                psi.UseShellExecute = false;
                psi.RedirectStandardInput = true;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                psi.CreateNoWindow = true;

                string rootPath = UriToPath(RootUri);
                if (!string.IsNullOrEmpty(rootPath) && Directory.Exists(rootPath))
                {
                    psi.WorkingDirectory = rootPath;
                }

                _proc = new Process();
                _proc.StartInfo = psi;
                _proc.EnableRaisingEvents = true;
                _proc.Exited += delegate { _running = false; FailAllPending("LSP server exited."); };

                if (!_proc.Start())
                {
                    LastError = "Failed to start LSP process: " + command;
                    return false;
                }

                _stdin = _proc.StandardInput.BaseStream;
                _running = true;

                _readThread = new Thread(ReadLoop);
                _readThread.IsBackground = true;
                _readThread.Name = "LspRead-" + Language;
                _readThread.Start();

                _errThread = new Thread(ReadStderrLoop);
                _errThread.IsBackground = true;
                _errThread.Name = "LspErr-" + Language;
                _errThread.Start();

                var initParams = new Dictionary<string, object>
                {
                    { "processId", Process.GetCurrentProcess().Id },
                    { "rootUri", RootUri },
                    { "capabilities", new Dictionary<string, object>
                        {
                            { "textDocument", new Dictionary<string, object>
                                {
                                    { "hover", new Dictionary<string, object> { { "contentFormat", new[] { "markdown", "plaintext" } } } },
                                    { "completion", new Dictionary<string, object> { { "completionItem", new Dictionary<string, object> { { "snippetSupport", false } } } } },
                                    { "definition", new Dictionary<string, object> { { "linkSupport", true } } },
                                    { "publishDiagnostics", new Dictionary<string, object>() }
                                }
                            }
                        }
                    }
                };

                var resp = SendRequest("initialize", initParams, initTimeoutMs > 0 ? initTimeoutMs : 10000);
                if (resp == null || resp.ContainsKey("error"))
                {
                    LastError = resp != null && resp.ContainsKey("error") ? DJ.ErrorText(DJ.Ser(resp)) : "LSP initialize timed out.";
                    Shutdown();
                    return false;
                }

                SendNotification("initialized", new Dictionary<string, object>());
                Initialized = true;
                return true;
            }
            catch (Exception ex)
            {
                LastError = ex.Message;
                Shutdown();
                return false;
            }
        }

        void ReadLoop()
        {
            try
            {
                Stream stdout = _proc.StandardOutput.BaseStream;
                while (_running)
                {
                    Dictionary<string, object> msg;
                    if (!LspJsonRpc.TryReadMessage(stdout, out msg)) break;
                    DispatchMessage(msg);
                }
            }
            catch (Exception ex)
            {
                LastError = ex.Message;
            }
            finally
            {
                _running = false;
                FailAllPending("LSP stream closed.");
            }
        }

        void ReadStderrLoop()
        {
            try
            {
                string line;
                while (_proc != null && !_proc.HasExited && (line = _proc.StandardError.ReadLine()) != null)
                {
                    if (!string.IsNullOrWhiteSpace(line)) LastError = line;
                }
            }
            catch { }
        }

        void DispatchMessage(Dictionary<string, object> msg)
        {
            if (msg == null) return;
            object idObj;
            bool hasId = msg.TryGetValue("id", out idObj) && idObj != null;
            string method = DJ.Str(msg, "method");

            if (hasId && string.IsNullOrEmpty(method))
            {
                int id;
                if (TryParseId(idObj, out id))
                {
                    TaskCompletionSource<Dictionary<string, object>> tcs = null;
                    lock (_pendingGate)
                    {
                        if (_pending.TryGetValue(id, out tcs))
                        {
                            _pending.Remove(id);
                        }
                    }
                    if (tcs != null) tcs.TrySetResult(msg);
                }
                return;
            }

            if (hasId && !string.IsNullOrEmpty(method))
            {
                // Respond to server-initiated requests so server does not block.
                var ack = new Dictionary<string, object>
                {
                    { "jsonrpc", "2.0" },
                    { "id", idObj },
                    { "result", null }
                };
                SendRaw(ack);
                return;
            }

            if (string.Equals(method, "textDocument/publishDiagnostics", StringComparison.Ordinal))
            {
                HandlePublishDiagnostics(DJ.Child(msg, "params"));
            }
        }

        void HandlePublishDiagnostics(Dictionary<string, object> p)
        {
            if (p == null) return;
            string uri = DJ.Str(p, "uri");
            if (string.IsNullOrEmpty(uri)) return;
            string filePath = UriToPath(uri);
            var list = new List<LspDiagnostic>();
            var arr = DJ.Arr(p, "diagnostics");
            if (arr != null)
            {
                for (int i = 0; i < arr.Count; i++)
                {
                    var d = arr[i] as Dictionary<string, object>;
                    if (d == null) continue;
                    var diag = new LspDiagnostic();
                    diag.FilePath = filePath;
                    diag.Message = DJ.Str(d, "message") ?? "";
                    diag.Code = DJ.Str(d, "code") ?? "";
                    diag.Source = DJ.Str(d, "source") ?? ServerName;
                    double? sev = DJ.Num(d, "severity");
                    diag.Severity = MapSeverity(sev.HasValue ? (int)sev.Value : 1);

                    var range = DJ.Child(d, "range");
                    var start = DJ.Child(range, "start");
                    var end = DJ.Child(range, "end");
                    double? sl = DJ.Num(start, "line");
                    double? sc = DJ.Num(start, "character");
                    double? el = DJ.Num(end, "line");
                    double? ec = DJ.Num(end, "character");
                    diag.StartLine = sl.HasValue ? (int)sl.Value : 0;
                    diag.StartColumn = sc.HasValue ? (int)sc.Value : 0;
                    diag.EndLine = el.HasValue ? (int)el.Value : diag.StartLine;
                    diag.EndColumn = ec.HasValue ? (int)ec.Value : diag.StartColumn;
                    list.Add(diag);
                }
            }

            string key = NormalizePathKey(filePath);
            lock (_diagGate)
            {
                _diagnostics[key] = list;
            }
        }

        static string MapSeverity(int s)
        {
            switch (s)
            {
                case 1: return "error";
                case 2: return "warning";
                case 3: return "info";
                case 4: return "hint";
                default: return "error";
            }
        }

        public void NotifyOpen(string path, string languageId, string text)
        {
            if (!IsRunning) return;
            string uri = PathToUri(path);
            int ver;
            lock (_docGate)
            {
                ver = 1;
                _docVersions[uri] = ver;
            }
            var p = new Dictionary<string, object>
            {
                { "textDocument", new Dictionary<string, object>
                    {
                        { "uri", uri },
                        { "languageId", string.IsNullOrEmpty(languageId) ? Language : languageId },
                        { "version", ver },
                        { "text", text ?? "" }
                    }
                }
            };
            SendNotification("textDocument/didOpen", p);
        }

        public void NotifyChange(string path, string text)
        {
            if (!IsRunning) return;
            string uri = PathToUri(path);
            int ver;
            bool opened;
            lock (_docGate)
            {
                opened = _docVersions.TryGetValue(uri, out ver);
                ver = opened ? ver + 1 : 1;
                _docVersions[uri] = ver;
            }
            if (!opened)
            {
                NotifyOpen(path, Language, text);
                return;
            }
            var p = new Dictionary<string, object>
            {
                { "textDocument", new Dictionary<string, object> { { "uri", uri }, { "version", ver } } },
                { "contentChanges", new[] { new Dictionary<string, object> { { "text", text ?? "" } } } }
            };
            SendNotification("textDocument/didChange", p);
        }

        public void NotifySave(string path, string text)
        {
            if (!IsRunning) return;
            string uri = PathToUri(path);
            var p = new Dictionary<string, object>
            {
                { "textDocument", new Dictionary<string, object> { { "uri", uri } } }
            };
            if (text != null) p["text"] = text;
            SendNotification("textDocument/didSave", p);
        }

        public void NotifyClose(string path)
        {
            if (!IsRunning) return;
            string uri = PathToUri(path);
            lock (_docGate) { _docVersions.Remove(uri); }
            var p = new Dictionary<string, object>
            {
                { "textDocument", new Dictionary<string, object> { { "uri", uri } } }
            };
            SendNotification("textDocument/didClose", p);
        }

        public string Hover(string path, int line, int col, int timeoutMs)
        {
            if (!IsRunning) return null;
            var p = PositionParams(path, line, col);
            var resp = SendRequest("textDocument/hover", p, timeoutMs > 0 ? timeoutMs : 5000);
            if (resp == null) return null;
            object res;
            if (!resp.TryGetValue("result", out res) || res == null) return null;
            var dict = res as Dictionary<string, object>;
            if (dict == null) return null;
            object contents;
            if (!dict.TryGetValue("contents", out contents) || contents == null) return null;
            return ExtractHoverText(contents);
        }

        static string ExtractHoverText(object contents)
        {
            if (contents == null) return null;
            var str = contents as string;
            if (str != null) return str;
            var dict = contents as Dictionary<string, object>;
            if (dict != null)
            {
                string val = DJ.Str(dict, "value");
                if (!string.IsNullOrEmpty(val)) return val;
                return DJ.Ser(dict);
            }
            var arr = DJ.AsList(contents);
            if (arr != null)
            {
                var parts = new List<string>();
                for (int i = 0; i < arr.Count; i++)
                {
                    string part = ExtractHoverText(arr[i]);
                    if (!string.IsNullOrEmpty(part)) parts.Add(part);
                }
                return parts.Count > 0 ? string.Join("\n\n", parts.ToArray()) : null;
            }
            return Convert.ToString(contents, CultureInfo.InvariantCulture);
        }

        public List<LspLocation> Definition(string path, int line, int col, int timeoutMs)
        {
            var list = new List<LspLocation>();
            if (!IsRunning) return list;
            var p = PositionParams(path, line, col);
            var resp = SendRequest("textDocument/definition", p, timeoutMs > 0 ? timeoutMs : 5000);
            if (resp == null) return list;
            object res;
            if (!resp.TryGetValue("result", out res) || res == null) return list;

            var single = res as Dictionary<string, object>;
            if (single != null)
            {
                var loc = ParseLocation(single);
                if (loc != null) list.Add(loc);
                return list;
            }
            var arr = DJ.AsList(res);
            if (arr != null)
            {
                for (int i = 0; i < arr.Count; i++)
                {
                    var item = arr[i] as Dictionary<string, object>;
                    var loc = ParseLocation(item);
                    if (loc != null) list.Add(loc);
                }
            }
            return list;
        }

        static LspLocation ParseLocation(Dictionary<string, object> d)
        {
            if (d == null) return null;
            string uri = DJ.Str(d, "uri") ?? DJ.Str(d, "targetUri");
            if (string.IsNullOrEmpty(uri)) return null;
            var range = DJ.Child(d, "range") ?? DJ.Child(d, "targetSelectionRange") ?? DJ.Child(d, "targetRange");
            var start = DJ.Child(range, "start");
            var end = DJ.Child(range, "end");
            double? sl = DJ.Num(start, "line");
            double? sc = DJ.Num(start, "character");
            double? el = DJ.Num(end, "line");
            double? ec = DJ.Num(end, "character");
            var loc = new LspLocation();
            loc.Uri = uri;
            loc.FilePath = UriToPath(uri);
            loc.StartLine = sl.HasValue ? (int)sl.Value : 0;
            loc.StartColumn = sc.HasValue ? (int)sc.Value : 0;
            loc.EndLine = el.HasValue ? (int)el.Value : loc.StartLine;
            loc.EndColumn = ec.HasValue ? (int)ec.Value : loc.StartColumn;
            return loc;
        }

        public List<LspCompletionItem> Completion(string path, int line, int col, int timeoutMs)
        {
            var list = new List<LspCompletionItem>();
            if (!IsRunning) return list;
            var p = PositionParams(path, line, col);
            var resp = SendRequest("textDocument/completion", p, timeoutMs > 0 ? timeoutMs : 5000);
            if (resp == null) return list;
            object res;
            if (!resp.TryGetValue("result", out res) || res == null) return list;

            ArrayList items = null;
            var obj = res as Dictionary<string, object>;
            if (obj != null) items = DJ.Arr(obj, "items");
            else items = DJ.AsList(res);

            if (items == null) return list;
            for (int i = 0; i < items.Count; i++)
            {
                var d = items[i] as Dictionary<string, object>;
                if (d == null) continue;
                var item = new LspCompletionItem();
                item.Label = DJ.Str(d, "label") ?? "";
                item.Detail = DJ.Str(d, "detail") ?? "";
                item.InsertText = DJ.Str(d, "insertText") ?? item.Label;
                var docObj = DJ.Child(d, "documentation");
                item.Documentation = docObj != null ? (DJ.Str(docObj, "value") ?? "") : (DJ.Str(d, "documentation") ?? "");
                double? k = DJ.Num(d, "kind");
                item.Kind = k.HasValue ? ((int)k.Value).ToString(CultureInfo.InvariantCulture) : "";
                list.Add(item);
            }
            return list;
        }

        public List<LspDiagnostic> GetDiagnostics(string path)
        {
            string key = NormalizePathKey(path);
            lock (_diagGate)
            {
                List<LspDiagnostic> list;
                if (_diagnostics.TryGetValue(key, out list))
                {
                    return new List<LspDiagnostic>(list);
                }
            }
            return new List<LspDiagnostic>();
        }

        public int TotalDiagnosticsCount()
        {
            int count = 0;
            lock (_diagGate)
            {
                foreach (var kv in _diagnostics) count += kv.Value.Count;
            }
            return count;
        }

        Dictionary<string, object> PositionParams(string path, int line, int col)
        {
            return new Dictionary<string, object>
            {
                { "textDocument", new Dictionary<string, object> { { "uri", PathToUri(path) } } },
                { "position", new Dictionary<string, object> { { "line", Math.Max(0, line) }, { "character", Math.Max(0, col) } } }
            };
        }

        public Dictionary<string, object> SendRequest(string method, Dictionary<string, object> parameters, int timeoutMs)
        {
            if (!IsRunning) return null;
            int id = Interlocked.Increment(ref _nextId);
            var tcs = new TaskCompletionSource<Dictionary<string, object>>();
            lock (_pendingGate) { _pending[id] = tcs; }

            var payload = new Dictionary<string, object>
            {
                { "jsonrpc", "2.0" },
                { "id", id },
                { "method", method },
                { "params", parameters ?? new Dictionary<string, object>() }
            };

            if (!SendRaw(payload))
            {
                lock (_pendingGate) { _pending.Remove(id); }
                return null;
            }

            try
            {
                if (tcs.Task.Wait(timeoutMs > 0 ? timeoutMs : 5000))
                {
                    return tcs.Task.Result;
                }
            }
            catch { }

            lock (_pendingGate) { _pending.Remove(id); }
            return null;
        }

        public void SendNotification(string method, Dictionary<string, object> parameters)
        {
            if (!IsRunning) return;
            var payload = new Dictionary<string, object>
            {
                { "jsonrpc", "2.0" },
                { "method", method },
                { "params", parameters ?? new Dictionary<string, object>() }
            };
            SendRaw(payload);
        }

        bool SendRaw(Dictionary<string, object> payload)
        {
            byte[] bytes = LspJsonRpc.Encode(payload);
            lock (_sendGate)
            {
                if (_stdin == null) return false;
                try
                {
                    _stdin.Write(bytes, 0, bytes.Length);
                    _stdin.Flush();
                    return true;
                }
                catch (Exception ex)
                {
                    LastError = ex.Message;
                    return false;
                }
            }
        }

        void FailAllPending(string reason)
        {
            List<TaskCompletionSource<Dictionary<string, object>>> copy;
            lock (_pendingGate)
            {
                copy = new List<TaskCompletionSource<Dictionary<string, object>>>(_pending.Values);
                _pending.Clear();
            }
            for (int i = 0; i < copy.Count; i++)
            {
                copy[i].TrySetResult(new Dictionary<string, object>
                {
                    { "error", new Dictionary<string, object> { { "message", reason } } }
                });
            }
        }

        public void Shutdown()
        {
            if (_running && _proc != null && !_proc.HasExited)
            {
                try { SendRequest("shutdown", new Dictionary<string, object>(), 800); } catch { }
                try { SendNotification("exit", new Dictionary<string, object>()); } catch { }
            }
            _running = false;
            FailAllPending("LSP shutdown.");
            if (_proc != null)
            {
                try { if (!_proc.HasExited && !_proc.WaitForExit(400)) _proc.Kill(); } catch { }
                try { _proc.Dispose(); } catch { }
                _proc = null;
            }
            _stdin = null;
        }

        public void Dispose()
        {
            Shutdown();
        }

        static bool TryParseId(object idObj, out int id)
        {
            id = 0;
            if (idObj == null) return false;
            try
            {
                id = Convert.ToInt32(idObj, CultureInfo.InvariantCulture);
                return true;
            }
            catch { return false; }
        }

        public static string PathToUri(string path)
        {
            if (string.IsNullOrEmpty(path)) return "file:///";
            if (path.StartsWith("file://", StringComparison.OrdinalIgnoreCase)) return path;
            string full = Path.GetFullPath(path);
            string norm = full.Replace('\\', '/');
            if (!norm.StartsWith("/")) norm = "/" + norm;
            return "file://" + Uri.EscapeUriString(norm).Replace("%3A", ":");
        }

        public static string UriToPath(string uri)
        {
            if (string.IsNullOrEmpty(uri)) return "";
            if (!uri.StartsWith("file://", StringComparison.OrdinalIgnoreCase)) return uri;
            try
            {
                var u = new Uri(uri);
                return u.LocalPath;
            }
            catch
            {
                string raw = uri.Substring(7);
                if (raw.Length >= 3 && raw[0] == '/' && raw[2] == ':') raw = raw.Substring(1);
                return Uri.UnescapeDataString(raw);
            }
        }

        static string NormalizeUriOrPathToUri(string rootUriOrPath)
        {
            if (string.IsNullOrEmpty(rootUriOrPath)) return PathToUri(Environment.CurrentDirectory);
            if (rootUriOrPath.StartsWith("file://", StringComparison.OrdinalIgnoreCase)) return rootUriOrPath;
            return PathToUri(rootUriOrPath);
        }

        static string NormalizePathKey(string path)
        {
            if (string.IsNullOrEmpty(path)) return "";
            string p = path.StartsWith("file://", StringComparison.OrdinalIgnoreCase) ? UriToPath(path) : path;
            try { return Path.GetFullPath(p).Replace('\\', '/'); }
            catch { return p.Replace('\\', '/'); }
        }

        static string BuildArgString(IList<string> args)
        {
            if (args == null || args.Count == 0) return "";
            var sb = new StringBuilder();
            for (int i = 0; i < args.Count; i++)
            {
                if (i > 0) sb.Append(' ');
                string a = args[i] ?? "";
                if (a.IndexOf(' ') >= 0 || a.IndexOf('"') >= 0 || a.Length == 0)
                {
                    sb.Append('"').Append(a.Replace("\"", "\\\"")).Append('"');
                }
                else
                {
                    sb.Append(a);
                }
            }
            return sb.ToString();
        }
    }

    public class LspManager : IDisposable
    {
        public static readonly LspManager Shared = new LspManager();

        readonly object _gate = new object();
        readonly Dictionary<string, LspServerProcess> _servers = new Dictionary<string, LspServerProcess>(StringComparer.OrdinalIgnoreCase);
        readonly Dictionary<string, List<LspServerSpec>> _registry = new Dictionary<string, List<LspServerSpec>>(StringComparer.OrdinalIgnoreCase);
        string _lastRootUri;

        public LspManager()
        {
            RegisterDefaults();
        }

        void RegisterDefaults()
        {
            AddDefault("python", "pyright-langserver", "pyright-langserver", "--stdio");
            AddDefault("python", "pylsp", "pylsp");
            AddDefault("typescript", "typescript-language-server", "typescript-language-server", "--stdio");
            AddDefault("javascript", "typescript-language-server", "typescript-language-server", "--stdio");
            AddDefault("rust", "rust-analyzer", "rust-analyzer");
            AddDefault("go", "gopls", "gopls");
            AddDefault("cpp", "clangd", "clangd");
            AddDefault("c", "clangd", "clangd");
            AddDefault("csharp", "omnisharp", "omnisharp", "-lsp");
            AddDefault("csharp", "csharp-ls", "csharp-ls");
            AddDefault("java", "jdtls", "jdtls");
        }

        void AddDefault(string lang, string name, string cmd, params string[] args)
        {
            List<LspServerSpec> list;
            if (!_registry.TryGetValue(lang, out list))
            {
                list = new List<LspServerSpec>();
                _registry[lang] = list;
            }
            var spec = new LspServerSpec();
            spec.Language = lang;
            spec.ServerName = name;
            spec.Command = cmd;
            if (args != null) spec.Args.AddRange(args);
            list.Add(spec);
        }

        public void RegisterServer(string lang, string serverName, string command, params string[] args)
        {
            string norm = NormalizeLanguage(lang);
            lock (_gate)
            {
                var list = new List<LspServerSpec>();
                var spec = new LspServerSpec();
                spec.Language = norm;
                spec.ServerName = serverName ?? command;
                spec.Command = command;
                if (args != null) spec.Args.AddRange(args);
                list.Add(spec);
                _registry[norm] = list;
            }
        }

        public static string NormalizeLanguage(string langOrExt)
        {
            string s = (langOrExt ?? "").Trim().ToLowerInvariant();
            if (s.StartsWith(".")) s = s.Substring(1);
            switch (s)
            {
                case "py": case "python": return "python";
                case "ts": case "tsx": case "typescript": return "typescript";
                case "js": case "jsx": case "mjs": case "cjs": case "javascript": return "javascript";
                case "rs": case "rust": return "rust";
                case "go": case "golang": return "go";
                case "c": return "c";
                case "cpp": case "cc": case "cxx": case "hpp": case "h": case "c++": return "cpp";
                case "cs": case "csharp": case "c#": return "csharp";
                case "java": return "java";
                default: return s;
            }
        }

        public static string DetectLanguage(string path)
        {
            if (string.IsNullOrEmpty(path)) return "";
            string ext = Path.GetExtension(path);
            if (!string.IsNullOrEmpty(ext)) return NormalizeLanguage(ext);
            return NormalizeLanguage(path);
        }

        public List<LspServerSpec> DetectAvailableServers()
        {
            var found = new List<LspServerSpec>();
            lock (_gate)
            {
                foreach (var kv in _registry)
                {
                    for (int i = 0; i < kv.Value.Count; i++)
                    {
                        var src = kv.Value[i];
                        string resolved = FindExecutable(src.Command);
                        var copy = new LspServerSpec();
                        copy.Language = src.Language;
                        copy.ServerName = src.ServerName;
                        copy.Command = src.Command;
                        copy.Args = new List<string>(src.Args);
                        copy.ResolvedPath = resolved ?? "";
                        copy.Available = !string.IsNullOrEmpty(resolved);
                        found.Add(copy);
                    }
                }
            }
            return found;
        }

        public LspServerProcess EnsureStarted(string lang, string rootUri)
        {
            string normLang = NormalizeLanguage(lang);
            if (string.IsNullOrEmpty(normLang)) return null;
            string normRoot = string.IsNullOrEmpty(rootUri) ? (_lastRootUri ?? LspServerProcess.PathToUri(Environment.CurrentDirectory)) : (rootUri.StartsWith("file://", StringComparison.OrdinalIgnoreCase) ? rootUri : LspServerProcess.PathToUri(rootUri));
            _lastRootUri = normRoot;
            string key = normLang + "|" + normRoot;

            lock (_gate)
            {
                LspServerProcess existing;
                if (_servers.TryGetValue(key, out existing) && existing.IsRunning)
                {
                    return existing;
                }
            }

            List<LspServerSpec> candidates = null;
            lock (_gate)
            {
                List<LspServerSpec> reg;
                if (_registry.TryGetValue(normLang, out reg))
                {
                    candidates = new List<LspServerSpec>(reg);
                }
            }
            if (candidates == null || candidates.Count == 0) return null;

            for (int i = 0; i < candidates.Count; i++)
            {
                var spec = candidates[i];
                string exe = File.Exists(spec.Command) ? spec.Command : FindExecutable(spec.Command);
                if (string.IsNullOrEmpty(exe)) continue;

                var proc = new LspServerProcess(normLang, spec.ServerName);
                if (proc.Start(exe, spec.Args, normRoot, 10000))
                {
                    lock (_gate) { _servers[key] = proc; }
                    return proc;
                }
            }
            return null;
        }

        LspServerProcess ResolveForPath(string path, bool autoStart)
        {
            string lang = DetectLanguage(path);
            if (string.IsNullOrEmpty(lang)) return null;

            lock (_gate)
            {
                foreach (var kv in _servers)
                {
                    if (kv.Value.Language == lang && kv.Value.IsRunning)
                    {
                        return kv.Value;
                    }
                }
            }

            if (!autoStart) return null;
            string dir = null;
            try { dir = Path.GetDirectoryName(Path.GetFullPath(path)); } catch { }
            return EnsureStarted(lang, _lastRootUri ?? dir ?? Environment.CurrentDirectory);
        }

        public void NotifyOpen(string path, string text)
        {
            var srv = ResolveForPath(path, true);
            if (srv != null) srv.NotifyOpen(path, DetectLanguage(path), text);
        }

        public void NotifyChange(string path, string text)
        {
            var srv = ResolveForPath(path, true);
            if (srv != null) srv.NotifyChange(path, text);
        }

        public string Hover(string path, int line, int col)
        {
            var srv = ResolveForPath(path, true);
            return srv != null ? srv.Hover(path, line, col, 5000) : null;
        }

        public List<LspLocation> Definition(string path, int line, int col)
        {
            var srv = ResolveForPath(path, true);
            return srv != null ? srv.Definition(path, line, col, 5000) : new List<LspLocation>();
        }

        public List<LspCompletionItem> Completion(string path, int line, int col)
        {
            var srv = ResolveForPath(path, true);
            return srv != null ? srv.Completion(path, line, col, 5000) : new List<LspCompletionItem>();
        }

        public List<LspDiagnostic> GetDiagnostics(string path)
        {
            var srv = ResolveForPath(path, false);
            return srv != null ? srv.GetDiagnostics(path) : new List<LspDiagnostic>();
        }

        public string StatusSummary()
        {
            var sb = new StringBuilder();
            List<LspServerProcess> active;
            lock (_gate)
            {
                active = new List<LspServerProcess>(_servers.Values);
            }
            sb.AppendLine("Active LSP servers: " + active.Count(s => s.IsRunning));
            for (int i = 0; i < active.Count; i++)
            {
                var s = active[i];
                sb.AppendLine(string.Format(CultureInfo.InvariantCulture, "  - {0} ({1}): {2}, diagnostics={3}", s.Language, s.ServerName, s.IsRunning ? "running" : "stopped", s.TotalDiagnosticsCount()));
            }
            var avail = DetectAvailableServers().Where(x => x.Available).ToList();
            sb.AppendLine("Detected binaries: " + (avail.Count > 0 ? string.Join(", ", avail.Select(x => x.ServerName).Distinct().ToArray()) : "none"));
            return sb.ToString().TrimEnd();
        }

        public static string FindExecutable(string command)
        {
            if (string.IsNullOrWhiteSpace(command)) return null;
            if (Path.IsPathRooted(command) && File.Exists(command)) return command;

            bool isWin = Environment.OSVersion.Platform == PlatformID.Win32NT;
            string pathEnv = Environment.GetEnvironmentVariable("PATH") ?? "";
            char sep = isWin ? ';' : ':';
            string[] dirs = pathEnv.Split(new[] { sep }, StringSplitOptions.RemoveEmptyEntries);
            string[] exts = isWin ? new[] { "", ".exe", ".cmd", ".bat" } : new[] { "" };

            for (int i = 0; i < dirs.Length; i++)
            {
                string dir = dirs[i].Trim().Trim('"');
                if (dir.Length == 0) continue;
                for (int e = 0; e < exts.Length; e++)
                {
                    string candidate = Path.Combine(dir, command + exts[e]);
                    if (File.Exists(candidate)) return candidate;
                }
            }
            return null;
        }

        public void Dispose()
        {
            List<LspServerProcess> all;
            lock (_gate)
            {
                all = new List<LspServerProcess>(_servers.Values);
                _servers.Clear();
            }
            for (int i = 0; i < all.Count; i++)
            {
                all[i].Dispose();
            }
        }
    }
}
