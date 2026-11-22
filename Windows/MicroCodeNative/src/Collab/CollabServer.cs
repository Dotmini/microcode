// The collaboration host's embedded HTTP/1.1 + RFC 6455 WebSocket server (the Mac uses NWListener): plain TcpListener on
// the dedicated port range 8490-8515, one thread per connection, Connection: close for HTTP and a long-lived thread per
// WebSocket. No http.sys URL reservation is needed, so a normal user account can host LAN sessions.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

namespace MicroCode.Views
{
    public class CollabRequest
    {
        public string Method = "GET", Target = "/", Path = "/";
        public Dictionary<string, string> Headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        public Dictionary<string, string> Query = new Dictionary<string, string>(StringComparer.Ordinal);
        public byte[] Body = new byte[0];
        public string BodyText { get { return Encoding.UTF8.GetString(Body); } }
        public string Header(string name) { string v; return Headers.TryGetValue(name, out v) ? v : null; }
    }

    public class CollabResponse
    {
        public string Status = "200 OK", ContentType = "application/json; charset=utf-8";
        public byte[] Body = new byte[0];
        public Dictionary<string, string> Extra = new Dictionary<string, string>();
        public static CollabResponse Json(string json) { return new CollabResponse { Body = Encoding.UTF8.GetBytes(json) }; }
        public static CollabResponse Text(string status, string type, string text) { return new CollabResponse { Status = status, ContentType = type, Body = Encoding.UTF8.GetBytes(text) }; }
    }

    /// <summary>One connected WebSocket client (HostWSClient).</summary>
    public class CollabWsClient
    {
        public readonly Guid Id = Guid.NewGuid();
        public string UserId;
        /// <summary>Said caps:["ot1"] in its hello: gets "op" messages instead of legacy "fileBuffer".</summary>
        public volatile bool SupportsOT;
        internal NetworkStream Stream;
        internal TcpClient Tcp;
        readonly object _send = new object();
        public volatile bool Closed;

        public void SendText(string text)
        {
            if (Closed) return;
            var frame = CollabServer.Frame(0x1, Encoding.UTF8.GetBytes(text));
            try { lock (_send) Stream.Write(frame, 0, frame.Length); }
            catch (IOException) { Close(); } catch (ObjectDisposedException) { Close(); } catch (InvalidOperationException) { Close(); }
        }

        internal void SendFrame(byte opcode, byte[] payload)
        {
            var frame = CollabServer.Frame(opcode, payload);
            try { lock (_send) Stream.Write(frame, 0, frame.Length); }
            catch (IOException) { } catch (ObjectDisposedException) { } catch (InvalidOperationException) { }
        }

        public void Close()
        {
            if (Closed) return;
            Closed = true;
            CollabServer.Kill(Tcp);
        }
    }

    public class CollabServer
    {
        public const int FirstPort = 8490, LastPort = 8515;
        const int MaxBody = 16 * 1024 * 1024;

        TcpListener _listener;
        volatile bool _running;
        readonly List<CollabWsClient> _clients = new List<CollabWsClient>();
        public int Port { get; private set; }
        public bool IsRunning { get { return _running; } }

        /// <summary>HTTP handler; return null to send 404. Runs on the connection thread.</summary>
        public Func<CollabRequest, CollabResponse> OnRequest;
        /// <summary>WebSocket upgrade gate (e.g. room code check); return a response to refuse the upgrade.</summary>
        public Func<CollabRequest, CollabResponse> OnUpgrade;
        public Action<CollabWsClient> OnWsOpen;
        public Action<CollabWsClient, string> OnWsText;
        public Action<CollabWsClient> OnWsClose;

        public List<CollabWsClient> Clients { get { lock (_clients) return _clients.Where(c => !c.Closed).ToList(); } }

        /// <summary>Binds the first free port in 8490-8515 (exclusively, on all interfaces so LAN teammates reach it).</summary>
        public bool Start(int firstPort = FirstPort, int lastPort = LastPort)
        {
            Stop();
            for (int port = firstPort; port <= lastPort; port++)
            {
                var l = new TcpListener(IPAddress.Any, port) { ExclusiveAddressUse = true };
                try { l.Start(); }
                catch (SocketException) { continue; }
                _listener = l; Port = port; _running = true;
                var t = new Thread(AcceptLoop) { IsBackground = true, Name = "collab-accept" };
                t.Start();
                return true;
            }
            return false;
        }

        /// <summary>Every accepted connection, upgraded or not, of the current generation: Stop must close the ones that are
        /// still mid-handshake too, or a peer joining while the host ends the room keeps a live-looking socket forever.</summary>
        readonly HashSet<TcpClient> _conns = new HashSet<TcpClient>();
        int _generation;

        public void Stop()
        {
            List<TcpClient> conns; List<CollabWsClient> clients;
            lock (_clients)
            {
                _running = false;
                _generation++;
                conns = _conns.ToList(); _conns.Clear();
                clients = _clients.ToList(); _clients.Clear();
            }
            if (_listener != null) { try { _listener.Stop(); } catch (SocketException) { /* already stopped */ } _listener = null; }
            foreach (var c in clients) c.Close();
            foreach (var tcp in conns) Kill(tcp);
        }

        internal static void Kill(TcpClient tcp)
        {
            // Shutdown before Close: a connection thread blocked in Read keeps the socket alive through Close alone.
            // Client is null once the TcpClient was closed, so a second Kill is a no-op.
            var sock = tcp.Client;
            if (sock != null) { try { sock.Shutdown(SocketShutdown.Both); } catch (SocketException) { /* already reset */ } catch (ObjectDisposedException) { /* already closed */ } }
            try { tcp.Close(); } catch (SocketException) { /* closing anyway */ } catch (ObjectDisposedException) { /* already closed */ }
        }

        void AcceptLoop()
        {
            var l = _listener;
            int gen; lock (_clients) gen = _generation;
            while (_running && l != null)
            {
                TcpClient tcp;
                try { tcp = l.AcceptTcpClient(); }
                catch (SocketException) { return; } catch (ObjectDisposedException) { return; } catch (InvalidOperationException) { return; }
                lock (_clients)
                {
                    if (!_running || gen != _generation) { Kill(tcp); return; }
                    _conns.Add(tcp);
                }
                var th = new Thread(() => Serve(tcp, gen)) { IsBackground = true, Name = "collab-conn" };
                th.Start();
            }
        }

        void Serve(TcpClient tcp, int gen)
        {
            try { ServeOne(tcp, gen); }
            finally { lock (_clients) _conns.Remove(tcp); }
        }

        void ServeOne(TcpClient tcp, int gen)
        {
            bool keepOpen = false;
            try
            {
                NetworkStream s;
                lock (_clients)
                {
                    // Stop takes the same lock before it closes connections: past this point a stop shows up as IO errors on
                    // the stream (caught below), never as a closed TcpClient touched by this thread
                    if (!_conns.Contains(tcp)) return;
                    tcp.NoDelay = true;
                    s = tcp.GetStream();
                }
                s.ReadTimeout = 30000;
                var req = ReadRequest(s);
                if (req == null) return;
                if (req.Method == "OPTIONS") { Write(s, new CollabResponse { Status = "204 No Content", ContentType = "text/plain" }); return; }
                string upgrade = req.Header("Upgrade"), key = req.Header("Sec-WebSocket-Key");
                if (req.Method == "GET" && upgrade != null && upgrade.IndexOf("websocket", StringComparison.OrdinalIgnoreCase) >= 0 && key != null)
                {
                    var refuse = OnUpgrade != null ? OnUpgrade(req) : null;
                    if (refuse != null) { Write(s, refuse); return; }
                    keepOpen = true;
                    RunWebSocket(tcp, s, key, gen);
                    return;
                }
                CollabResponse resp;
                try { resp = OnRequest != null ? OnRequest(req) : null; }
                catch (Exception ex) { Debug.WriteLine("collab handler: " + ex); resp = CollabResponse.Text("500 Internal Server Error", "application/json", "{\"error\":\"Internal error\"}"); }
                Write(s, resp ?? CollabResponse.Text("404 Not Found", "application/json", "{\"error\":\"Not found\"}"));
            }
            catch (IOException) { /* client went away */ } catch (ObjectDisposedException) { /* server stopped */ } catch (SocketException) { /* reset */ }
            catch (InvalidOperationException) { /* Stop closed the socket before this thread started (GetStream on a closed client) */ }
            finally { if (!keepOpen) { try { tcp.Close(); } catch (SocketException) { /* closing anyway */ } } }
        }

        static CollabRequest ReadRequest(NetworkStream s)
        {
            var head = new List<byte>(1024);
            while (true)
            {
                int b = s.ReadByte();
                if (b < 0) return null;
                head.Add((byte)b);
                int n = head.Count;
                if (n >= 4 && head[n - 4] == 13 && head[n - 3] == 10 && head[n - 2] == 13 && head[n - 1] == 10) break;
                if (n > 65536) return null;
            }
            var lines = Encoding.UTF8.GetString(head.ToArray()).Split(new[] { "\r\n" }, StringSplitOptions.None);
            var first = lines[0].Split(' ');
            if (first.Length < 2) return null;
            var req = new CollabRequest { Method = first[0].ToUpperInvariant(), Target = first[1] };
            foreach (var l in lines.Skip(1)) { int c = l.IndexOf(':'); if (c > 0) req.Headers[l.Substring(0, c).Trim()] = l.Substring(c + 1).Trim(); }
            int q = req.Target.IndexOf('?');
            req.Path = q >= 0 ? req.Target.Substring(0, q) : req.Target;
            if (q >= 0)
                foreach (var pair in req.Target.Substring(q + 1).Split('&'))
                {
                    if (pair.Length == 0) continue;
                    int e = pair.IndexOf('=');
                    // like URLComponents: percent-decoding only, '+' stays '+' (Mac peers send file names like a+b.txt unescaped)
                    string k = Uri.UnescapeDataString(e >= 0 ? pair.Substring(0, e) : pair);
                    string v = e >= 0 ? Uri.UnescapeDataString(pair.Substring(e + 1)) : "";
                    if (!req.Query.ContainsKey(k)) req.Query[k] = v;
                }
            int len = 0; string cl = req.Header("Content-Length");
            if (cl != null) int.TryParse(cl, out len);
            if (len < 0 || len > MaxBody) return null;
            if (string.Equals(req.Header("Expect"), "100-continue", StringComparison.OrdinalIgnoreCase)) { var cont = Encoding.ASCII.GetBytes("HTTP/1.1 100 Continue\r\n\r\n"); s.Write(cont, 0, cont.Length); }
            var body = new byte[len]; int got = 0;
            while (got < len) { int r = s.Read(body, got, len - got); if (r <= 0) break; got += r; }
            req.Body = got == len ? body : body.Take(got).ToArray();
            return req;
        }

        /// <summary>sendHTTPResponse: CORS open, no-store, Connection: close.</summary>
        static void Write(NetworkStream s, CollabResponse r)
        {
            var sb = new StringBuilder();
            sb.Append("HTTP/1.1 ").Append(r.Status).Append("\r\n");
            sb.Append("Content-Type: ").Append(r.ContentType).Append("\r\n");
            sb.Append("Content-Length: ").Append(r.Body.Length).Append("\r\n");
            sb.Append("Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Headers: Content-Type\r\nCache-Control: no-store\r\n");
            foreach (var kv in r.Extra) sb.Append(kv.Key).Append(": ").Append(kv.Value).Append("\r\n");
            sb.Append("Connection: close\r\n\r\n");
            var head = Encoding.UTF8.GetBytes(sb.ToString());
            s.Write(head, 0, head.Length);
            if (r.Body.Length > 0) s.Write(r.Body, 0, r.Body.Length);
            s.Flush();
        }

        void RunWebSocket(TcpClient tcp, NetworkStream s, string key, int gen)
        {
            string accept;
            using (var sha = SHA1.Create()) accept = Convert.ToBase64String(sha.ComputeHash(Encoding.ASCII.GetBytes(key.Trim() + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")));
            var client = new CollabWsClient { Stream = s, Tcp = tcp };
            lock (_clients)
            {
                // the room ended while this peer was still handshaking: refuse instead of joining a stopped server
                if (!_running || gen != _generation) { Kill(tcp); return; }
                _clients.Add(client);
            }
            try
            {
                var hs = Encoding.ASCII.GetBytes("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + "\r\n\r\n");
                s.Write(hs, 0, hs.Length);
                s.ReadTimeout = Timeout.Infinite;
                if (OnWsOpen != null) OnWsOpen(client);
                var message = new List<byte>();
                while (!client.Closed)
                {
                    int b0 = s.ReadByte(), b1 = s.ReadByte();
                    if (b0 < 0 || b1 < 0) break;
                    int opcode = b0 & 0x0F; bool fin = (b0 & 0x80) != 0, masked = (b1 & 0x80) != 0;
                    long len = b1 & 0x7F;
                    if (len == 126) { var l2 = ReadExact(s, 2); len = (l2[0] << 8) | l2[1]; }
                    else if (len == 127) { var l8 = ReadExact(s, 8); len = 0; foreach (var x in l8) len = (len << 8) | x; }
                    if (len > MaxBody) break;
                    var mask = masked ? ReadExact(s, 4) : null;
                    var payload = ReadExact(s, (int)len);
                    if (mask != null) for (int i = 0; i < payload.Length; i++) payload[i] ^= mask[i & 3];
                    if (opcode == 0x8) { client.SendFrame(0x8, new byte[0]); break; }
                    if (opcode == 0x9) { client.SendFrame(0xA, payload); continue; }
                    if (opcode == 0xA) continue;
                    if (opcode == 0x1 || opcode == 0x0 || opcode == 0x2)
                    {
                        message.AddRange(payload);
                        if (!fin) continue;
                        string text = Encoding.UTF8.GetString(message.ToArray());
                        message.Clear();
                        if (OnWsText != null) { try { OnWsText(client, text); } catch (Exception ex) { Debug.WriteLine("collab ws handler: " + ex); } }
                    }
                }
            }
            catch (IOException) { /* peer went away (EndOfStreamException is an IOException) */ } catch (ObjectDisposedException) { /* server stopped */ }
            finally
            {
                client.Close();
                lock (_clients) _clients.Remove(client);
                if (OnWsClose != null) OnWsClose(client);
            }
        }

        static byte[] ReadExact(NetworkStream s, int n)
        {
            var buf = new byte[n]; int got = 0;
            while (got < n) { int r = s.Read(buf, got, n - got); if (r <= 0) throw new EndOfStreamException(); got += r; }
            return buf;
        }

        /// <summary>encodeWebSocketFrame: unmasked server frame (FIN set).</summary>
        public static byte[] Frame(byte opcode, byte[] payload)
        {
            var ms = new MemoryStream();
            ms.WriteByte((byte)(0x80 | (opcode & 0x0F)));
            int count = payload.Length;
            if (count < 126) ms.WriteByte((byte)count);
            else if (count <= 65535) { ms.WriteByte(126); ms.WriteByte((byte)(count >> 8)); ms.WriteByte((byte)count); }
            else { ms.WriteByte(127); for (int sh = 56; sh >= 0; sh -= 8) ms.WriteByte((byte)((long)count >> sh)); }
            ms.Write(payload, 0, payload.Length);
            return ms.ToArray();
        }

        public void Broadcast(string json, string excludingUserId)
        {
            foreach (var c in Clients) if (excludingUserId == null || c.UserId != excludingUserId) c.SendText(json);
        }
    }
}
