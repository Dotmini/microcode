// Mobile Connect 2.0 for Windows — Full port of PhoneCompanionService.swift + PhoneCompanionService+NextGen.swift
// + Offline App Shell SW & CloudAI Standby Shadow Sync / Wake Reconciliation.
// Strict .NET Framework 4.8 / C# 5 compatible (compiles via csc.exe with zero NuGet packages).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using MicroCode.Core;

namespace MicroCode.Views
{
    public enum PhoneConnectionMode { LAN, Tailscale, Online }
    public enum PhoneDeviceApprovalState { Pending, Approved, Rejected }

    public class ConnectedPhoneDevice
    {
        public string Id;
        public string Name;
        public string IpAddress;
        public string ConnectionVia;
        public DateTime FirstConnectedAt;
        public DateTime LastSeenAt;
        public PhoneDeviceApprovalState ApprovalState;
    }

    public class NetworkAdapterInfo
    {
        public string InterfaceName;
        public string IpAddress;
    }

    // ── Pure C# 5 ISO/IEC 18004 QR Code Encoder (Versions 1..10, ECC Level M, Byte Mode) ──────────

    public static class QrEncoder
    {
        // (TotalCodewords, EcPerBlock, NumBlocksGroup1, DataPerBlock1, NumBlocksGroup2, DataPerBlock2)
        // for Versions 1..10 at Error Correction Level M
        static readonly int[][] SpecM = new int[][] {
            null,
            new[] { 26, 10, 1, 16, 0, 0 },     // V1  (21x21)  14 byte cap
            new[] { 44, 16, 1, 28, 0, 0 },     // V2  (25x25)  26 byte cap
            new[] { 70, 26, 1, 44, 0, 0 },     // V3  (29x29)  42 byte cap
            new[] { 100, 18, 2, 32, 0, 0 },    // V4  (33x33)  62 byte cap
            new[] { 134, 24, 2, 43, 0, 0 },    // V5  (37x37)  84 byte cap
            new[] { 172, 16, 4, 27, 0, 0 },    // V6  (41x41) 106 byte cap
            new[] { 196, 18, 4, 31, 0, 0 },    // V7  (45x45) 122 byte cap
            new[] { 242, 22, 2, 38, 2, 39 },   // V8  (49x49) 152 byte cap
            new[] { 292, 22, 3, 36, 2, 37 },   // V9  (53x53) 180 byte cap
            new[] { 346, 26, 4, 43, 1, 44 }    // V10 (57x57) 213 byte cap
        };

        static readonly int[][] AlignCoords = new int[][] {
            null,
            new int[0],
            new[] { 6, 18 },
            new[] { 6, 22 },
            new[] { 6, 26 },
            new[] { 6, 30 },
            new[] { 6, 34 },
            new[] { 6, 22, 38 },
            new[] { 6, 24, 42 },
            new[] { 6, 26, 46 },
            new[] { 6, 28, 50 }
        };

        static readonly int[] VersionBits = {
            0, 0, 0, 0, 0, 0, 0,
            0x07C94, 0x085BC, 0x09A99, 0x0A4D3
        };

        // Format info bits for ECC M (00) + mask 0..7, pre-masked with 0x5412
        static readonly int[] FormatBitsM = {
            0x5412, 0x5125, 0x5E7C, 0x5B4B, 0x45F9, 0x40CE, 0x4F97, 0x4AA0
        };

        static readonly byte[] GfExp = new byte[512];
        static readonly byte[] GfLog = new byte[256];

        static QrEncoder()
        {
            int x = 1;
            for (int i = 0; i < 255; i++)
            {
                GfExp[i] = (byte)x;
                GfLog[x] = (byte)i;
                x <<= 1;
                if ((x & 0x100) != 0) x ^= 0x11D;
            }
            for (int i = 255; i < 512; i++) GfExp[i] = GfExp[i - 255];
        }

        static byte GfMul(byte a, byte b)
        {
            if (a == 0 || b == 0) return 0;
            return GfExp[GfLog[a] + GfLog[b]];
        }

        static byte[] RsGenerator(int ecLen)
        {
            var g = new byte[] { 1 };
            for (int i = 0; i < ecLen; i++)
            {
                var next = new byte[g.Length + 1];
                byte factor = GfExp[i];
                for (int j = 0; j < g.Length; j++)
                {
                    next[j] ^= g[j];
                    next[j + 1] ^= GfMul(g[j], factor);
                }
                g = next;
            }
            return g;
        }

        static byte[] RsCompute(byte[] data, int ecLen)
        {
            var gen = RsGenerator(ecLen);
            var buf = new byte[data.Length + ecLen];
            Buffer.BlockCopy(data, 0, buf, 0, data.Length);
            for (int i = 0; i < data.Length; i++)
            {
                byte coef = buf[i];
                if (coef == 0) continue;
                for (int j = 0; j < gen.Length; j++)
                    buf[i + j] ^= GfMul(gen[j], coef);
            }
            var ec = new byte[ecLen];
            Buffer.BlockCopy(buf, data.Length, ec, 0, ecLen);
            return ec;
        }

        public static bool[,] Encode(string text)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(text ?? "");
            int ver = 1;
            for (; ver <= 10; ver++)
            {
                var sp = SpecM[ver];
                int capBytes = sp[2] * sp[3] + sp[4] * sp[5];
                int overheadBits = 4 + (ver <= 9 ? 8 : 16);
                int availBits = capBytes * 8 - overheadBits;
                if (bytes.Length * 8 <= availBits) break;
            }
            if (ver > 10)
            {
                // Truncate safely if an unexpectedly huge URL arrives
                ver = 10;
                Array.Resize(ref bytes, 210);
            }

            var spec = SpecM[ver];
            int ecPerBlock = spec[1], g1Blocks = spec[2], g1Data = spec[3], g2Blocks = spec[4], g2Data = spec[5];
            int totalDataBytes = g1Blocks * g1Data + g2Blocks * g2Data;

            var bits = new List<int>(totalDataBytes * 8);
            Action<int, int> pushBits = (val, count) =>
            {
                for (int b = count - 1; b >= 0; b--) bits.Add((val >> b) & 1);
            };
            pushBits(0x4, 4); // Byte mode
            pushBits(bytes.Length, ver <= 9 ? 8 : 16);
            foreach (byte by in bytes) pushBits(by, 8);
            int rem = totalDataBytes * 8 - bits.Count;
            if (rem > 0) pushBits(0, Math.Min(4, rem));
            while (bits.Count % 8 != 0) bits.Add(0);
            byte pad = 0xEC;
            while (bits.Count < totalDataBytes * 8)
            {
                pushBits(pad, 8);
                pad = (pad == 0xEC) ? (byte)0x11 : (byte)0xEC;
            }

            var dataBytes = new byte[totalDataBytes];
            for (int i = 0; i < totalDataBytes; i++)
            {
                int v = 0;
                for (int b = 0; b < 8; b++) v = (v << 1) | bits[i * 8 + b];
                dataBytes[i] = (byte)v;
            }

            var dataBlocks = new List<byte[]>();
            var ecBlocks = new List<byte[]>();
            int offset = 0;
            for (int i = 0; i < g1Blocks + g2Blocks; i++)
            {
                int len = i < g1Blocks ? g1Data : g2Data;
                var blk = new byte[len];
                Buffer.BlockCopy(dataBytes, offset, blk, 0, len);
                offset += len;
                dataBlocks.Add(blk);
                ecBlocks.Add(RsCompute(blk, ecPerBlock));
            }

            var codewords = new List<byte>(spec[0]);
            int maxDataLen = Math.Max(g1Data, g2Data);
            for (int i = 0; i < maxDataLen; i++)
                foreach (var blk in dataBlocks)
                    if (i < blk.Length) codewords.Add(blk[i]);
            for (int i = 0; i < ecPerBlock; i++)
                foreach (var ec in ecBlocks)
                    codewords.Add(ec[i]);

            int size = 17 + ver * 4;
            bool[,] bestGrid = null;
            int bestPenalty = int.MaxValue;

            for (int mask = 0; mask < 8; mask++)
            {
                var mod = new bool[size, size];
                var fn = new bool[size, size];
                PlaceFunctionPatterns(ver, size, mod, fn);
                PlaceCodewords(size, mod, fn, codewords);
                ApplyMask(size, mod, fn, mask);
                WriteFormatBits(size, mod, FormatBitsM[mask]);
                if (ver >= 7) WriteVersionBits(size, mod, VersionBits[ver]);
                int pen = ComputePenalty(size, mod);
                if (pen < bestPenalty)
                {
                    bestPenalty = pen;
                    bestGrid = mod;
                }
            }
            return bestGrid;
        }

        static void PlaceFinder(int size, bool[,] mod, bool[,] fn, int row, int col)
        {
            for (int dr = -1; dr <= 7; dr++)
                for (int dc = -1; dc <= 7; dc++)
                {
                    int r = row + dr, c = col + dc;
                    if (r < 0 || r >= size || c < 0 || c >= size) continue;
                    fn[r, c] = true;
                    bool on = dr >= 0 && dr <= 6 && dc >= 0 && dc <= 6 &&
                              (dr == 0 || dr == 6 || dc == 0 || dc == 6 || (dr >= 2 && dr <= 4 && dc >= 2 && dc <= 4));
                    mod[r, c] = on;
                }
        }

        static void PlaceAlign(bool[,] mod, bool[,] fn, int cx, int cy)
        {
            for (int dr = -2; dr <= 2; dr++)
                for (int dc = -2; dc <= 2; dc++)
                {
                    fn[cy + dr, cx + dc] = true;
                    mod[cy + dr, cx + dc] = (Math.Max(Math.Abs(dr), Math.Abs(dc)) != 1);
                }
        }

        static void PlaceFunctionPatterns(int ver, int size, bool[,] mod, bool[,] fn)
        {
            PlaceFinder(size, mod, fn, 0, 0);
            PlaceFinder(size, mod, fn, 0, size - 7);
            PlaceFinder(size, mod, fn, size - 7, 0);
            for (int i = 8; i < size - 8; i++)
            {
                fn[6, i] = true; mod[6, i] = (i % 2 == 0);
                fn[i, 6] = true; mod[i, 6] = (i % 2 == 0);
            }
            var ac = AlignCoords[ver];
            for (int iy = 0; iy < ac.Length; iy++)
                for (int ix = 0; ix < ac.Length; ix++)
                {
                    int cy = ac[iy], cx = ac[ix];
                    if (fn[cy, cx]) continue;
                    PlaceAlign(mod, fn, cx, cy);
                }
            for (int i = 0; i <= 8; i++)
            {
                if (i != 6) { fn[8, i] = true; fn[i, 8] = true; }
            }
            for (int i = 0; i < 8; i++)
            {
                fn[8, size - 1 - i] = true;
                fn[size - 1 - i, 8] = true;
            }
            fn[size - 8, 8] = true;
            mod[size - 8, 8] = true; // dark module
            if (ver >= 7)
            {
                for (int i = 0; i < 6; i++)
                    for (int j = 0; j < 3; j++)
                    {
                        fn[size - 11 + j, i] = true;
                        fn[i, size - 11 + j] = true;
                    }
            }
        }

        static void PlaceCodewords(int size, bool[,] mod, bool[,] fn, List<byte> codewords)
        {
            int bitIdx = 0, totalBits = codewords.Count * 8;
            int col = size - 1;
            bool up = true;
            while (col > 0)
            {
                if (col == 6) col--;
                for (int i = 0; i < size; i++)
                {
                    int row = up ? (size - 1 - i) : i;
                    for (int dc = 0; dc < 2; dc++)
                    {
                        int c = col - dc;
                        if (fn[row, c]) continue;
                        bool dark = false;
                        if (bitIdx < totalBits)
                        {
                            dark = ((codewords[bitIdx >> 3] >> (7 - (bitIdx & 7))) & 1) != 0;
                            bitIdx++;
                        }
                        mod[row, c] = dark;
                    }
                }
                col -= 2;
                up = !up;
            }
        }

        static void ApplyMask(int size, bool[,] mod, bool[,] fn, int mask)
        {
            for (int r = 0; r < size; r++)
                for (int c = 0; c < size; c++)
                {
                    if (fn[r, c]) continue;
                    bool flip = false;
                    switch (mask)
                    {
                        case 0: flip = ((r + c) % 2) == 0; break;
                        case 1: flip = (r % 2) == 0; break;
                        case 2: flip = (c % 3) == 0; break;
                        case 3: flip = ((r + c) % 3) == 0; break;
                        case 4: flip = (((r / 2) + (c / 3)) % 2) == 0; break;
                        case 5: flip = ((r * c) % 2 + (r * c) % 3) == 0; break;
                        case 6: flip = (((r * c) % 2 + (r * c) % 3) % 2) == 0; break;
                        case 7: flip = (((r + c) % 2 + (r * c) % 3) % 2) == 0; break;
                    }
                    if (flip) mod[r, c] = !mod[r, c];
                }
        }

        static void WriteFormatBits(int size, bool[,] mod, int fmt)
        {
            for (int i = 0; i < 6; i++) mod[8, i] = ((fmt >> i) & 1) != 0;
            mod[8, 7] = ((fmt >> 6) & 1) != 0;
            mod[8, 8] = ((fmt >> 7) & 1) != 0;
            mod[7, 8] = ((fmt >> 8) & 1) != 0;
            for (int i = 9; i < 15; i++) mod[14 - i, 8] = ((fmt >> i) & 1) != 0;

            for (int i = 0; i < 8; i++) mod[size - 1 - i, 8] = ((fmt >> i) & 1) != 0;
            for (int i = 8; i < 15; i++) mod[8, size - 15 + i] = ((fmt >> i) & 1) != 0;
        }

        static void WriteVersionBits(int size, bool[,] mod, int verBits)
        {
            for (int i = 0; i < 18; i++)
            {
                bool bit = ((verBits >> i) & 1) != 0;
                mod[i / 3, size - 11 + (i % 3)] = bit;
                mod[size - 11 + (i % 3), i / 3] = bit;
            }
        }

        static int ComputePenalty(int size, bool[,] mod)
        {
            int pen = 0;
            for (int r = 0; r < size; r++)
            {
                int run = 1;
                for (int c = 1; c < size; c++)
                {
                    if (mod[r, c] == mod[r, c - 1]) { run++; if (run == 5) pen += 3; else if (run > 5) pen += 1; }
                    else run = 1;
                }
            }
            for (int c = 0; c < size; c++)
            {
                int run = 1;
                for (int r = 1; r < size; r++)
                {
                    if (mod[r, c] == mod[r - 1, c]) { run++; if (run == 5) pen += 3; else if (run > 5) pen += 1; }
                    else run = 1;
                }
            }
            int dark = 0;
            for (int r = 0; r < size; r++)
                for (int c = 0; c < size; c++)
                {
                    if (mod[r, c]) dark++;
                    if (r + 1 < size && c + 1 < size && mod[r, c] == mod[r + 1, c] && mod[r, c] == mod[r, c + 1] && mod[r, c] == mod[r + 1, c + 1]) pen += 3;
                }
            int pct = (dark * 100) / (size * size);
            pen += (Math.Abs(pct - 50) / 5) * 10;
            return pen;
        }

        public static BitmapSource RenderBitmap(string text, int scale)
        {
            var grid = Encode(text);
            int n = grid.GetLength(0);
            int quiet = 2;
            int total = (n + quiet * 2) * scale;
            var wb = new WriteableBitmap(total, total, 96, 96, PixelFormats.Bgra32, null);
            var pixels = new byte[total * total * 4];
            for (int i = 0; i < pixels.Length; i += 4) { pixels[i] = 255; pixels[i + 1] = 255; pixels[i + 2] = 255; pixels[i + 3] = 255; }
            for (int r = 0; r < n; r++)
                for (int c = 0; c < n; c++)
                {
                    if (!grid[r, c]) continue;
                    int y0 = (r + quiet) * scale, x0 = (c + quiet) * scale;
                    for (int dy = 0; dy < scale; dy++)
                        for (int dx = 0; dx < scale; dx++)
                        {
                            int idx = ((y0 + dy) * total + (x0 + dx)) * 4;
                            pixels[idx] = 16; pixels[idx + 1] = 16; pixels[idx + 2] = 19; pixels[idx + 3] = 255;
                        }
                }
            wb.WritePixels(new Int32Rect(0, 0, total, total), pixels, total * 4, 0);
            wb.Freeze();
            return wb;
        }
    }

    // ── Windows Sleep Prevention (ES_CONTINUOUS | ES_SYSTEM_REQUIRED) ───────────────────────────────

    internal static class WinPowerAssertion
    {
        const uint ES_CONTINUOUS = 0x80000000;
        const uint ES_SYSTEM_REQUIRED = 0x00000001;
        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        static extern uint SetThreadExecutionState(uint esFlags);
        public static void SetKeepAwake(bool enable)
        {
            try { SetThreadExecutionState(enable ? (ES_CONTINUOUS | ES_SYSTEM_REQUIRED) : ES_CONTINUOUS); } catch { }
        }
    }

    // ── Phone Companion Service (Local Server + CloudAI Relay + Seamless Shadow Sync + PWA) ─────────

    public class PhoneCompanionService
    {
        public static readonly PhoneCompanionService Shared = new PhoneCompanionService();
        public event Action Changed;

        const string PrefEnabled = "microcode.phoneCompanion.enabled";
        const string PrefMode = "microcode.phoneCompanion.mode";
        const string PrefToken = "microcode.phoneCompanion.pairingToken";
        const string PrefRequireApproval = "microcode.phoneCompanion.requireApproval";
        const string PrefApprovedIds = "microcode.phoneCompanion.approvedDeviceIds";
        const string PrefKeepAwake = "microcode.phoneCompanion.keepAwake";
        const string PrefSelectedIp = "microcode.phoneCompanion.selectedIp";
        const string PrefRelayEpoch = "microcode.phoneCompanion.relayEpoch";

        static readonly JavaScriptSerializer JsonSer = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
        static readonly HttpClient LoopHttp = new HttpClient { Timeout = TimeSpan.FromSeconds(35) };

        readonly object _lock = new object();
        TcpListener _listener;
        volatile bool _running;
        readonly List<SseClient> _sseClients = new List<SseClient>();
        Timer _sseTimer;
        Timer _shadowTimer;
        string _lastBroadcastFp = "";
        string _lastShadowFp = "";
        DateTime _lastHeavyPushAt = DateTime.MinValue;
        long _lastSyncedCloudOpSeq;
        readonly HashSet<string> _appliedCloudMsgIds = new HashSet<string>();
        readonly Dictionary<string, PinAttemptState> _pinAttempts = new Dictionary<string, PinAttemptState>();

        CancellationTokenSource _relayCts;
        ClientWebSocket _relayWs;
        readonly SemaphoreSlim _relaySendLock = new SemaphoreSlim(1, 1);

        class SseClient
        {
            public TcpClient Tcp;
            public NetworkStream Stream;
            public readonly object WriteLock = new object();
            public volatile bool Closed;
            public void Close() { Closed = true; try { Tcp.Close(); } catch { } }
        }

        class PinAttemptState
        {
            public int Count;
            public DateTime LastAttempt;
        }

        public bool IsEnabled { get; private set; }
        public bool IsServerRunning { get { return _running; } }
        public int ListeningPort { get; private set; }
        public PhoneConnectionMode ConnectionMode { get; private set; }
        public string LanIpAddress { get; private set; }
        public List<NetworkAdapterInfo> AllAdapters { get; private set; }
        public string TailscaleIp { get; private set; }
        public string PairingToken { get; private set; }
        public string OneTimePairingCode { get; private set; }
        public string SixDigitPIN { get; private set; }
        public bool RequireApprovalForNewDevices { get; private set; }
        public bool KeepAwake { get; private set; }
        public string SelectedLanIp { get; private set; }
        public string TunnelStatus { get; private set; } // stopped | starting | connected | failed
        public string PublicTunnelUrl { get; private set; }
        public string TunnelError { get; private set; }
        public string TunnelProvider { get; private set; }
        public readonly List<ConnectedPhoneDevice> ConnectedDevices = new List<ConnectedPhoneDevice>();
        readonly HashSet<string> _approvedIds = new HashSet<string>();

        PhoneCompanionService()
        {
            AllAdapters = new List<NetworkAdapterInfo>();
            LanIpAddress = "127.0.0.1";
            ListeningPort = 8470;
            TunnelStatus = "stopped";
            IsEnabled = Defaults.Bool(PrefEnabled, false);
            string modeStr = (Defaults.Str(PrefMode, "online") ?? "online").ToLowerInvariant();
            ConnectionMode = modeStr == "lan" ? PhoneConnectionMode.LAN : modeStr == "tailscale" ? PhoneConnectionMode.Tailscale : PhoneConnectionMode.Online;
            RequireApprovalForNewDevices = Defaults.Bool(PrefRequireApproval, true);
            KeepAwake = Defaults.Bool(PrefKeepAwake, true);
            SelectedLanIp = Defaults.Str(PrefSelectedIp, "") ?? "";
            PairingToken = LoadOrCreatePairingToken();
            OneTimePairingCode = GenerateSecureToken();
            SixDigitPIN = GenerateSixDigitPIN();
            foreach (var id in Defaults.List(PrefApprovedIds)) _approvedIds.Add(id);
            RefreshNetworks();
            DotminiAuth.Changed += () =>
            {
                if (IsEnabled && ConnectionMode == PhoneConnectionMode.Online && DotminiAuth.SignedIn && TunnelStatus != "connected")
                    StartOnlineTunnel();
            };
        }

        void NotifyChanged()
        {
            DotminiNet.Raise(Changed);
        }

        static string GenerateSecureToken()
        {
            var b = new byte[18];
            using (var rng = RandomNumberGenerator.Create()) rng.GetBytes(b);
            return Convert.ToBase64String(b).Replace('+', '-').Replace('/', '_').TrimEnd('=');
        }

        static string GenerateSixDigitPIN()
        {
            var b = new byte[4];
            using (var rng = RandomNumberGenerator.Create()) rng.GetBytes(b);
            uint v = BitConverter.ToUInt32(b, 0) % 900000 + 100000;
            return v.ToString(CultureInfo.InvariantCulture);
        }

        static string LoadOrCreatePairingToken()
        {
            string stored = Dpapi.Unprotect(Defaults.Str(PrefToken, null));
            if (!string.IsNullOrEmpty(stored) && stored.Length >= 16) return stored;
            string fresh = GenerateSecureToken();
            Defaults.Set(PrefToken, Dpapi.Protect(fresh));
            Defaults.Flush();
            return fresh;
        }

        static string Sha256Hex(string input)
        {
            using (var sha = SHA256.Create())
            {
                var hash = sha.ComputeHash(Encoding.UTF8.GetBytes(input ?? ""));
                var sb = new StringBuilder(hash.Length * 2);
                foreach (byte b in hash) sb.Append(b.ToString("x2", CultureInfo.InvariantCulture));
                return sb.ToString();
            }
        }

        static bool ConstantTimeEquals(string a, string b)
        {
            if (string.IsNullOrEmpty(b) || a == null) return false;
            var x = Encoding.UTF8.GetBytes(a);
            var y = Encoding.UTF8.GetBytes(b);
            if (x.Length != y.Length) return false;
            int diff = 0;
            for (int i = 0; i < x.Length; i++) diff |= x[i] ^ y[i];
            return diff == 0;
        }

        static bool IsVirtualAdapter(NetworkInterface ni)
        {
            string txt = ((ni.Name ?? "") + " " + (ni.Description ?? "")).ToLowerInvariant();
            string[] virt = { "vethernet", "wsl", "hyper-v", "virtualbox", "vmware", "virtual", "docker", "bluetooth", "zerotier", "tailscale", "wireguard", "tap-", "tun", "loopback", "pseudo", "npcap", "nordlynx" };
            foreach (var v in virt) if (txt.Contains(v)) return true;
            return false;
        }

        public void RefreshNetworks()
        {
            var ranked = new List<Tuple<int, NetworkAdapterInfo>>();
            string tsIp = null;
            try
            {
                foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (ni.OperationalStatus != OperationalStatus.Up) continue;
                    if (ni.NetworkInterfaceType == NetworkInterfaceType.Loopback || ni.NetworkInterfaceType == NetworkInterfaceType.Tunnel) continue;
                    var props = ni.GetIPProperties();
                    bool hasGateway = props.GatewayAddresses.Any(g => g.Address != null && g.Address.AddressFamily == AddressFamily.InterNetwork && !g.Address.Equals(IPAddress.Any));
                    bool virt = IsVirtualAdapter(ni);
                    foreach (var ua in props.UnicastAddresses)
                    {
                        if (ua.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                        string ip = ua.Address.ToString();
                        if (ip.StartsWith("169.254.") || ip == "127.0.0.1") continue;
                        var octets = ip.Split('.').Select(s => { int n; return int.TryParse(s, out n) ? n : -1; }).ToArray();
                        bool isCgnat = octets.Length == 4 && octets[0] == 100 && octets[1] >= 64 && octets[1] <= 127;
                        if (isCgnat && tsIp == null) tsIp = ip;
                        int score = 0;
                        if (!virt) score += 100;
                        if (hasGateway) score += 50;
                        if (ni.NetworkInterfaceType == NetworkInterfaceType.Wireless80211) score += 30;
                        else if (ni.NetworkInterfaceType == NetworkInterfaceType.Ethernet) score += 20;
                        if (ip.StartsWith("192.168.")) score += 15;
                        else if (ip.StartsWith("10.")) score += 10;
                        if (isCgnat) score -= 80;
                        ranked.Add(Tuple.Create(score, new NetworkAdapterInfo { InterfaceName = ni.Name, IpAddress = ip }));
                    }
                }
            }
            catch { }
            var found = ranked.OrderByDescending(x => x.Item1).Select(x => x.Item2).ToList();
            AllAdapters = found;
            TailscaleIp = tsIp;
            if (!string.IsNullOrEmpty(SelectedLanIp) && found.Any(a => a.IpAddress == SelectedLanIp))
                LanIpAddress = SelectedLanIp;
            else
            {
                var nonTs = found.FirstOrDefault(a => !a.IpAddress.StartsWith("100."));
                LanIpAddress = nonTs != null ? nonTs.IpAddress : (found.FirstOrDefault() != null ? found[0].IpAddress : "127.0.0.1");
            }
        }

        public string ActiveBaseUrl
        {
            get
            {
                switch (ConnectionMode)
                {
                    case PhoneConnectionMode.Tailscale:
                        return "http://" + (TailscaleIp ?? LanIpAddress) + ":" + ListeningPort;
                    case PhoneConnectionMode.Online:
                        return !string.IsNullOrEmpty(PublicTunnelUrl) ? PublicTunnelUrl.TrimEnd('/') : ("http://" + LanIpAddress + ":" + ListeningPort);
                    default:
                        return "http://" + LanIpAddress + ":" + ListeningPort;
                }
            }
        }

        public string ActivePairingUrl
        {
            get
            {
                string baseUrl = ActiveBaseUrl;
                return baseUrl.EndsWith("/") ? (baseUrl + "?pair=" + OneTimePairingCode) : (baseUrl + "/?pair=" + OneTimePairingCode);
            }
        }

        public int PendingApprovalCount
        {
            get { lock (ConnectedDevices) return ConnectedDevices.Count(d => d.ApprovalState == PhoneDeviceApprovalState.Pending); }
        }

        public void StartIfEnabled()
        {
            if (!IsEnabled) return;
            Start();
        }

        public void SetEnabled(bool enabled)
        {
            IsEnabled = enabled;
            Defaults.Set(PrefEnabled, enabled);
            Defaults.Flush();
            if (enabled) Start();
            else Stop();
            NotifyChanged();
        }

        public void SetConnectionMode(PhoneConnectionMode mode)
        {
            ConnectionMode = mode;
            string raw = mode == PhoneConnectionMode.LAN ? "lan" : mode == PhoneConnectionMode.Tailscale ? "tailscale" : "online";
            Defaults.Set(PrefMode, raw);
            Defaults.Flush();
            if (IsEnabled)
            {
                if (mode == PhoneConnectionMode.Online) StartOnlineTunnel();
                else StopOnlineTunnel();
            }
            NotifyChanged();
        }

        public void SetSelectedLanIp(string ip)
        {
            SelectedLanIp = ip ?? "";
            Defaults.Set(PrefSelectedIp, SelectedLanIp);
            Defaults.Flush();
            RefreshNetworks();
            NotifyChanged();
        }

        public void SetRequireApproval(bool require)
        {
            RequireApprovalForNewDevices = require;
            Defaults.Set(PrefRequireApproval, require);
            Defaults.Flush();
            NotifyChanged();
        }

        public void SetKeepAwake(bool keepAwake)
        {
            KeepAwake = keepAwake;
            Defaults.Set(PrefKeepAwake, keepAwake);
            Defaults.Flush();
            WinPowerAssertion.SetKeepAwake(IsEnabled && KeepAwake);
            NotifyChanged();
        }

        public void RotateTokenAndUrl()
        {
            PairingToken = GenerateSecureToken();
            Defaults.Set(PrefToken, Dpapi.Protect(PairingToken));
            OneTimePairingCode = GenerateSecureToken();
            SixDigitPIN = GenerateSixDigitPIN();
            int nextEpoch = (int)Defaults.Num(PrefRelayEpoch, 0) + 1;
            Defaults.Set(PrefRelayEpoch, nextEpoch);
            lock (ConnectedDevices) ConnectedDevices.Clear();
            _approvedIds.Clear();
            Defaults.Remove(PrefApprovedIds);
            Defaults.Flush();
            if (IsEnabled && ConnectionMode == PhoneConnectionMode.Online) StartOnlineTunnel();
            NotifyChanged();
        }

        public void ApproveDevice(string id)
        {
            _approvedIds.Add(id);
            Defaults.Set(PrefApprovedIds, _approvedIds.ToList());
            Defaults.Flush();
            lock (ConnectedDevices)
            {
                var d = ConnectedDevices.FirstOrDefault(x => x.Id == id);
                if (d != null) d.ApprovalState = PhoneDeviceApprovalState.Approved;
            }
            NotifyChanged();
        }

        public void RejectDevice(string id)
        {
            _approvedIds.Remove(id);
            Defaults.Set(PrefApprovedIds, _approvedIds.ToList());
            Defaults.Flush();
            lock (ConnectedDevices)
            {
                var d = ConnectedDevices.FirstOrDefault(x => x.Id == id);
                if (d != null) d.ApprovalState = PhoneDeviceApprovalState.Rejected;
            }
            NotifyChanged();
        }

        public void Start()
        {
            if (_running) return;
            DotminiNet.EnableTls();
            RefreshNetworks();
            for (int port = 8470; port <= 8485; port++)
            {
                try
                {
                    var l = new TcpListener(IPAddress.Any, port) { ExclusiveAddressUse = false };
                    l.Start();
                    _listener = l;
                    ListeningPort = port;
                    _running = true;
                    var acceptThread = new Thread(AcceptLoop) { IsBackground = true, Name = "mobile-companion-accept" };
                    acceptThread.Start(l);
                    break;
                }
                catch (SocketException) { }
            }
            if (_running)
            {
                _sseTimer = new Timer(_ => TickBroadcast(), null, 180, 180);
                _shadowTimer = new Timer(_ => { var __ = PushShadowSnapshotAsync(false); }, null, 1000, 3500);
                if (KeepAwake) WinPowerAssertion.SetKeepAwake(true);
                if (ConnectionMode == PhoneConnectionMode.Online) StartOnlineTunnel();
            }
            NotifyChanged();
        }

        public void Stop()
        {
            _running = false;
            StopOnlineTunnel();
            WinPowerAssertion.SetKeepAwake(false);
            if (_sseTimer != null) { _sseTimer.Dispose(); _sseTimer = null; }
            if (_shadowTimer != null) { _shadowTimer.Dispose(); _shadowTimer = null; }
            try { if (_listener != null) _listener.Stop(); } catch { }
            _listener = null;
            lock (_sseClients)
            {
                foreach (var c in _sseClients) c.Close();
                _sseClients.Clear();
            }
            NotifyChanged();
        }

        public void TriggerShadowSync(bool force)
        {
            _lastBroadcastFp = "";
            if (_running && ConnectionMode == PhoneConnectionMode.Online && _relayWs != null)
            {
                var __ = PushShadowSnapshotAsync(force);
            }
        }

        void AcceptLoop(object state)
        {
            var listener = (TcpListener)state;
            while (_running && _listener == listener)
            {
                TcpClient client;
                try { client = listener.AcceptTcpClient(); }
                catch { break; }
                ThreadPool.QueueUserWorkItem(_ => HandleClient(client));
            }
        }

        // ── Dotmini CloudAI Relay Uplink (cloudai.dotmini.net) ─────────────────────────────────────

        static string NodeProof()
        {
            string secretPath = Path.Combine(Defaults.Dir, "companion_relay_node.secret");
            string secret = null;
            try { if (File.Exists(secretPath)) secret = File.ReadAllText(secretPath).Trim(); } catch { }
            if (string.IsNullOrEmpty(secret) || secret.Length < 32)
            {
                secret = GenerateSecureToken() + GenerateSecureToken();
                try { Defaults.WriteAtomic(secretPath, secret); } catch { }
            }
            string scope = AppDomain.CurrentDomain.BaseDirectory ?? "win";
            return Sha256Hex("dotmini-relay-node-v2:" + secret + "|" + scope);
        }

        static string UserHint()
        {
            var sess = DotminiAuth.Session;
            string ident = (sess != null && !string.IsNullOrEmpty(sess.UserId))
                ? (sess.UserId + "|" + (sess.Email ?? "").ToLowerInvariant())
                : ("winuser:" + Environment.UserName + "|" + Environment.MachineName);
            return Sha256Hex("dotmini-user-hint-v2:" + ident).Substring(0, 32);
        }

        public void StartOnlineTunnel()
        {
            StopOnlineTunnel();
            TunnelStatus = "starting";
            TunnelError = null;
            NotifyChanged();
            var cts = new CancellationTokenSource();
            _relayCts = cts;
            int port = ListeningPort;
            Task.Run(() => RelayLoop(port, cts.Token));
        }

        public void StopOnlineTunnel()
        {
            if (_relayCts != null) { try { _relayCts.Cancel(); } catch { } _relayCts = null; }
            var ws = _relayWs; _relayWs = null;
            if (ws != null) { try { ws.Abort(); } catch { } try { ws.Dispose(); } catch { } }
            PublicTunnelUrl = null;
            TunnelProvider = null;
            TunnelStatus = "stopped";
            NotifyChanged();
        }

        async Task RelayLoop(int port, CancellationToken ct)
        {
            DotminiNet.EnableTls();
            string proof = NodeProof();
            string hint = UserHint();
            string epoch = ((int)Defaults.Num(PrefRelayEpoch, 0)).ToString(CultureInfo.InvariantCulture);
            string bearer = null;
            try { bearer = await DotminiAuth.AccessToken(false); } catch { }

            foreach (var host in new[] { "cloudai.dotmini.net", "api.dotmini.net" })
            {
                if (ct.IsCancellationRequested || !IsEnabled || ConnectionMode != PhoneConnectionMode.Online) return;
                var ws = new ClientWebSocket();
                ws.Options.KeepAliveInterval = TimeSpan.FromSeconds(20);
                ws.Options.SetRequestHeader("User-Agent", DotminiNet.UserAgent);
                ws.Options.SetRequestHeader("X-Relay-Node-Proof", proof);
                ws.Options.SetRequestHeader("X-Relay-Epoch", epoch);
                ws.Options.SetRequestHeader("X-Relay-User-Hint", hint);
                if (!string.IsNullOrEmpty(bearer)) ws.Options.SetRequestHeader("Authorization", "Bearer " + bearer);

                bool connected = false;
                try
                {
                    using (var connectCts = CancellationTokenSource.CreateLinkedTokenSource(ct))
                    {
                        connectCts.CancelAfter(9000);
                        await ws.ConnectAsync(new Uri("wss://" + host + "/api/v2/mobile-relay/uplink"), connectCts.Token);
                    }
                    var regJson = DJ.Obj(await ReceiveWsText(ws, ct));
                    string prefix = DJ.Str(regJson, "poly_prefix");
                    if (DJ.Str(regJson, "type") != "registered" || string.IsNullOrEmpty(prefix)) { ws.Abort(); continue; }

                    connected = true;
                    _relayWs = ws;
                    PublicTunnelUrl = "https://" + host + prefix;
                    TunnelProvider = host;
                    TunnelStatus = "connected";
                    TunnelError = null;
                    NotifyChanged();

                    var __ = PushShadowSnapshotAsync(true);
                    var ping = new Timer(_ =>
                    {
                        if (_relayWs == ws) { var ___ = SendRelayText(ws, "{\"type\":\"ping\"}"); }
                    }, null, 20000, 20000);

                    try
                    {
                        while (ws.State == WebSocketState.Open && !ct.IsCancellationRequested)
                        {
                            string raw = await ReceiveWsText(ws, ct);
                            var msg = DJ.Obj(raw);
                            string mtype = DJ.Str(msg, "type");
                            if (mtype == "http_request")
                            {
                                var captured = msg;
                                var ___ = Task.Run(() => ForwardRelayHttp(captured, port, ws));
                            }
                            else if (mtype == "cloud_delta")
                            {
                                await HandleCloudDeltaAsync(msg, ws);
                            }
                            else if (mtype == "sync_shadow_ack")
                            {
                                var seq = DJ.Num(msg, "cloud_op_seq");
                                if (seq.HasValue && (long)seq.Value > _lastSyncedCloudOpSeq) _lastSyncedCloudOpSeq = (long)seq.Value;
                            }
                        }
                    }
                    finally { ping.Dispose(); }
                }
                catch (OperationCanceledException) { return; }
                catch (Exception ex) { TunnelError = ex.GetBaseException().Message; }
                finally
                {
                    if (_relayWs == ws) _relayWs = null;
                    try { ws.Dispose(); } catch { }
                }

                if (connected && !ct.IsCancellationRequested && IsEnabled && ConnectionMode == PhoneConnectionMode.Online)
                {
                    TunnelStatus = "starting";
                    NotifyChanged();
                    try { await Task.Delay(2000, ct); } catch { return; }
                    var __ = Task.Run(() => RelayLoop(port, ct));
                    return;
                }
            }

            if (!ct.IsCancellationRequested && IsEnabled && ConnectionMode == PhoneConnectionMode.Online)
            {
                TunnelStatus = "failed";
                if (string.IsNullOrEmpty(TunnelError)) TunnelError = "Unable to reach cloudai.dotmini.net. Retrying automatically…";
                NotifyChanged();
                try { await Task.Delay(5000, ct); } catch { return; }
                if (!ct.IsCancellationRequested && IsEnabled && ConnectionMode == PhoneConnectionMode.Online)
                {
                    var __ = Task.Run(() => RelayLoop(port, ct));
                }
            }
        }

        static async Task<string> ReceiveWsText(ClientWebSocket ws, CancellationToken ct)
        {
            var buf = new byte[65536];
            var ms = new MemoryStream();
            while (true)
            {
                var r = await ws.ReceiveAsync(new ArraySegment<byte>(buf), ct);
                if (r.MessageType == WebSocketMessageType.Close) throw new WebSocketException("relay closed");
                ms.Write(buf, 0, r.Count);
                if (r.EndOfMessage) return Encoding.UTF8.GetString(ms.ToArray());
            }
        }

        async Task SendRelayText(ClientWebSocket ws, string text)
        {
            if (ws == null) return;
            await _relaySendLock.WaitAsync();
            try
            {
                if (ws.State == WebSocketState.Open)
                    await ws.SendAsync(new ArraySegment<byte>(Encoding.UTF8.GetBytes(text)), WebSocketMessageType.Text, true, CancellationToken.None);
            }
            catch { }
            finally { _relaySendLock.Release(); }
        }

        async Task ForwardRelayHttp(Dictionary<string, object> payload, int port, ClientWebSocket ws)
        {
            string id = DJ.Str(payload, "id");
            if (string.IsNullOrEmpty(id)) return;
            string method = (DJ.Str(payload, "method") ?? "GET").ToUpperInvariant();
            string target = DJ.Str(payload, "target") ?? "/";
            if (!target.StartsWith("/")) target = "/" + target;
            // SSE stream cannot be buffered via request/response relay: return an immediate state event burst
            if (method == "GET" && target.StartsWith("/api/stream", StringComparison.OrdinalIgnoreCase))
            {
                string fp;
                string sseBody = "retry: 2500\ndata: " + JsonSer.Serialize(BuildStateObject(out fp)) + "\n\n";
                var sseObj = new Dictionary<string, object> {
                    { "type", "http_response" }, { "id", id }, { "status", 200 },
                    { "headers", new Dictionary<string, object> { { "Content-Type", "text/event-stream; charset=utf-8" }, { "Cache-Control", "no-cache" } } },
                    { "body_b64", Convert.ToBase64String(Encoding.UTF8.GetBytes(sseBody)) }
                };
                await SendRelayText(ws, JsonSer.Serialize(sseObj));
                return;
            }
            bool failed = false;
            try
            {
                using (var req = new HttpRequestMessage(new HttpMethod(method), "http://127.0.0.1:" + port + target))
                {
                    var hdrs = DJ.Child(payload, "headers");
                    string ctype = null;
                    if (hdrs != null)
                        foreach (var kv in hdrs)
                        {
                            string lk = kv.Key.ToLowerInvariant();
                            if (lk == "host" || lk == "content-length" || lk == "connection") continue;
                            if (lk == "content-type") { ctype = Convert.ToString(kv.Value, CultureInfo.InvariantCulture); continue; }
                            req.Headers.TryAddWithoutValidation(kv.Key, Convert.ToString(kv.Value, CultureInfo.InvariantCulture));
                        }
                    req.Headers.TryAddWithoutValidation("X-Dotmini-Relay", "1");
                    string b64 = DJ.Str(payload, "body_b64");
                    if (!string.IsNullOrEmpty(b64))
                    {
                        req.Content = new ByteArrayContent(Convert.FromBase64String(b64));
                        if (ctype != null) req.Content.Headers.TryAddWithoutValidation("Content-Type", ctype);
                    }
                    using (var resp = await LoopHttp.SendAsync(req))
                    {
                        var body = await resp.Content.ReadAsByteArrayAsync();
                        var outHdrs = new Dictionary<string, object>();
                        var setCookies = new List<string>();
                        foreach (var h in resp.Headers.Concat(resp.Content.Headers))
                        {
                            string lk = h.Key.ToLowerInvariant();
                            if (lk == "set-cookie") setCookies.AddRange(h.Value);
                            else if (lk != "content-length" && lk != "connection" && lk != "transfer-encoding")
                                outHdrs[h.Key] = string.Join(", ", h.Value);
                        }
                        var obj = new Dictionary<string, object> {
                            { "type", "http_response" }, { "id", id }, { "status", (int)resp.StatusCode }, { "headers", outHdrs }
                        };
                        if (setCookies.Count > 0) obj["set_cookies"] = setCookies;
                        if (body.Length > 0) obj["body_b64"] = Convert.ToBase64String(body);
                        await SendRelayText(ws, JsonSer.Serialize(obj));
                    }
                }
            }
            catch
            {
                failed = true;
            }
            // C# 5 forbids await inside a catch block: send the 502 after it
            if (failed)
            {
                var errObj = new Dictionary<string, object> {
                    { "type", "http_response" }, { "id", id }, { "status", 502 },
                    { "headers", new Dictionary<string, object> { { "Content-Type", "text/plain; charset=utf-8" } } },
                    { "body_b64", Convert.ToBase64String(Encoding.UTF8.GetBytes("Windows companion unreachable")) }
                };
                await SendRelayText(ws, JsonSer.Serialize(errObj));
            }
        }

        // ── Shadow Sync & Wake Reconciliation ("sync_shadow" <-> "cloud_delta" / "sync_reconciled") ──

        async Task PushShadowSnapshotAsync(bool force)
        {
            var ws = _relayWs;
            if (ws == null || ws.State != WebSocketState.Open) return;
            try
            {
                string fp;
                var stateObj = BuildStateObject(out fp);
                bool heavy = force || (DateTime.UtcNow - _lastHeavyPushAt).TotalSeconds > 120;
                if (!force && !heavy && fp == _lastShadowFp) return;

                var payload = new Dictionary<string, object> {
                    { "type", "sync_shadow" },
                    { "pairing_token_hash", Sha256Hex(PairingToken) },
                    { "pin_hash", Sha256Hex("mc-pin:" + SixDigitPIN) },
                    { "mac_name", Environment.MachineName },
                    { "active_model_id", AIConfig.Model ?? "" },
                    { "active_provider_id", AIConfig.Provider ?? "" },
                    { "active_key_mode", AIConfig.Mode ?? "cloud" },
                    { "mac_op_seq", _lastSyncedCloudOpSeq },
                    { "state", stateObj }
                };

                if (heavy)
                {
                    _lastHeavyPushAt = DateTime.UtcNow;
                    payload["models"] = BuildAvailableModels();
                    var files = SearchWorkspaceFiles("", 100);
                    payload["files_manifest"] = files;
                    var cache = new Dictionary<string, string>();
                    foreach (var f in files.Take(8))
                    {
                        string rel = Convert.ToString(f["path"]);
                        var read = ReadWorkspaceFileSafe(rel);
                        object okObj;
                        if (read.TryGetValue("ok", out okObj) && okObj is bool && (bool)okObj)
                        {
                            string content = Convert.ToString(read["content"]) ?? "";
                            if (Encoding.UTF8.GetByteCount(content) <= 24000) cache[rel] = content;
                        }
                    }
                    payload["file_cache"] = cache;
                    payload["git_status"] = HandleGitStatus();
                    payload["pwa_html_template"] = BuildCompanionHtml("__MC_TOKEN_PLACEHOLDER__");
                }

                _lastShadowFp = fp;
                await SendRelayText(ws, JsonSer.Serialize(payload));
            }
            catch { }
        }

        async Task HandleCloudDeltaAsync(Dictionary<string, object> json, ClientWebSocket ws)
        {
            var seqNum = DJ.Num(json, "cloud_op_seq");
            long cloudSeq = seqNum.HasValue ? (long)seqNum.Value : 0;

            var selModel = DJ.Child(json, "selected_model");
            if (selModel != null)
            {
                string mid = DJ.Str(selModel, "modelId");
                if (!string.IsNullOrEmpty(mid))
                    SelectRemoteModel(DJ.Str(selModel, "mode") ?? "cloud", DJ.Str(selModel, "provider") ?? "omni", mid);
            }

            var appliedIds = new List<string>();
            var ops = DJ.Arr(json, "pending_mac_ops");
            if (ops != null)
            {
                foreach (var item in ops.OfType<Dictionary<string, object>>())
                {
                    string opId = DJ.Str(item, "id") ?? "";
                    string kind = DJ.Str(item, "kind") ?? "";
                    var p = DJ.Child(item, "payload") ?? new Dictionary<string, object>();
                    if (kind == "model_select")
                    {
                        string mid = DJ.Str(p, "modelId");
                        if (!string.IsNullOrEmpty(mid)) SelectRemoteModel(DJ.Str(p, "mode") ?? "cloud", DJ.Str(p, "provider") ?? "omni", mid);
                    }
                    else if (kind == "workspace_switch" || kind == "session_switch")
                    {
                        string sid = DJ.Str(p, "sessionId"), path = DJ.Str(p, "path");
                        InvokeOnUI(() => AgentStore.SwitchChat(sid, path));
                    }
                    else if (kind == "session_new")
                    {
                        string path = DJ.Str(p, "projectPath");
                        InvokeOnUI(() => AgentStore.NewChat(path ?? AppState.Shared.WorkspaceFolder));
                    }
                    else if (kind == "terminal")
                    {
                        string cmd = DJ.Str(p, "command");
                        if (!string.IsNullOrWhiteSpace(cmd)) ExecuteTerminalCommand(cmd);
                    }
                    else if (kind == "git")
                    {
                        string act = DJ.Str(p, "action");
                        if (!string.IsNullOrEmpty(act)) HandleGitAction(act, p);
                    }
                    if (!string.IsNullOrEmpty(opId)) appliedIds.Add(opId);
                }
            }

            var cloudMsgs = DJ.Arr(json, "messages");
            if (cloudMsgs != null && cloudMsgs.Count > 0)
            {
                InvokeOnUI(() =>
                {
                    bool changed = false;
                    foreach (var item in cloudMsgs.OfType<Dictionary<string, object>>())
                    {
                        string mid = DJ.Str(item, "id");
                        if (string.IsNullOrEmpty(mid) || _appliedCloudMsgIds.Contains(mid)) continue;
                        _appliedCloudMsgIds.Add(mid);
                        string sid = DJ.Str(item, "sessionId");
                        if (!string.IsNullOrEmpty(sid) && AgentStore.ActiveId != sid) AgentStore.SwitchChat(sid, DJ.Str(item, "workspacePath"));
                        var sess = AgentStore.Active ?? AgentStore.NewChat(AppState.Shared.WorkspaceFolder);
                        if (sess.Messages.Any(x => x.Id == mid)) continue;
                        string role = (DJ.Str(item, "role") ?? "assistant") == "user" ? "user" : "assistant";
                        string content = DJ.Str(item, "content") ?? "";
                        string thought = DJ.Str(item, "thought") ?? "";
                        string full = string.IsNullOrWhiteSpace(thought) ? content : ("<think>" + thought + "</think>\n\n" + content);
                        var tsNum = DJ.Num(item, "timestampMs");
                        DateTime tm = tsNum.HasValue ? new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddMilliseconds(tsNum.Value).ToLocalTime() : DateTime.Now;
                        sess.Messages.Add(new ChatMessage
                        {
                            Id = mid,
                            Role = role,
                            Content = full,
                            Time = tm,
                            Model = DJ.Str(item, "modelLabel")
                        });
                        sess.Updated = DateTime.Now;
                        changed = true;
                    }
                    if (changed) { AgentStore.Save(); AgentStore.Notify(); }
                });
            }

            if (cloudSeq > _lastSyncedCloudOpSeq) _lastSyncedCloudOpSeq = cloudSeq;
            var ack = new Dictionary<string, object> {
                { "type", "sync_reconciled" },
                { "acked_op_seq", _lastSyncedCloudOpSeq },
                { "applied_mac_op_ids", appliedIds }
            };
            await SendRelayText(ws, JsonSer.Serialize(ack));
            await PushShadowSnapshotAsync(true);
        }

        // ── Embedded HTTP + SSE Server ─────────────────────────────────────────────────────────────

        void HandleClient(TcpClient tcp)
        {
            bool keepAliveSse = false;
            try
            {
                var ns = tcp.GetStream();
                ns.ReadTimeout = 10000;
                var raw = new MemoryStream();
                var tmp = new byte[8192];
                int hdrEnd = -1;
                while (hdrEnd < 0 && raw.Length < 128 * 1024)
                {
                    int n = ns.Read(tmp, 0, tmp.Length);
                    if (n <= 0) break;
                    raw.Write(tmp, 0, n);
                    hdrEnd = FindHeaderEnd(raw.GetBuffer(), (int)raw.Length);
                }
                if (hdrEnd < 0) return;

                var all = raw.ToArray();
                string head = Encoding.ASCII.GetString(all, 0, hdrEnd);
                var lines = head.Split(new[] { "\r\n" }, StringSplitOptions.None);
                var first = lines[0].Split(' ');
                if (first.Length < 2) return;
                string method = first[0].ToUpperInvariant();
                string rawTarget = first[1];
                string path = rawTarget;
                var query = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                int qIdx = rawTarget.IndexOf('?');
                if (qIdx >= 0)
                {
                    path = rawTarget.Substring(0, qIdx);
                    foreach (var part in rawTarget.Substring(qIdx + 1).Split('&'))
                    {
                        int eq = part.IndexOf('=');
                        if (eq > 0) query[Uri.UnescapeDataString(part.Substring(0, eq))] = Uri.UnescapeDataString(part.Substring(eq + 1).Replace('+', ' '));
                    }
                }

                var hdrs = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                foreach (var l in lines.Skip(1))
                {
                    int c = l.IndexOf(':');
                    if (c > 0) hdrs[l.Substring(0, c).Trim()] = l.Substring(c + 1).Trim();
                }

                int cl = 0; string clStr; if (hdrs.TryGetValue("Content-Length", out clStr)) int.TryParse(clStr, out cl);
                cl = Math.Min(cl, 24 * 1024 * 1024);
                var bodyMs = new MemoryStream();
                int bodyStart = hdrEnd + 4;
                bodyMs.Write(all, bodyStart, all.Length - bodyStart);
                while (bodyMs.Length < cl)
                {
                    int n = ns.Read(tmp, 0, Math.Min(tmp.Length, cl - (int)bodyMs.Length));
                    if (n <= 0) break;
                    bodyMs.Write(tmp, 0, n);
                }

                string remoteIp = ((IPEndPoint)tcp.Client.RemoteEndPoint).Address.ToString();
                if (remoteIp.StartsWith("::ffff:")) remoteIp = remoteIp.Substring(7);

                bool handledSse;
                byte[] resp = ProcessHttpRequest(method, path, rawTarget, query, hdrs, bodyMs.ToArray(), remoteIp, tcp, ns, out handledSse);
                if (handledSse) { keepAliveSse = true; return; }
                if (resp != null)
                {
                    ns.Write(resp, 0, resp.Length);
                    ns.Flush();
                }
            }
            catch { }
            finally
            {
                if (!keepAliveSse)
                {
                    try { tcp.Close(); } catch { }
                }
            }
        }

        static int FindHeaderEnd(byte[] b, int len)
        {
            for (int i = 0; i + 3 < len; i++) if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) return i;
            return -1;
        }

        string ExtractCookieToken(Dictionary<string, string> hdrs)
        {
            string cookie;
            if (!hdrs.TryGetValue("Cookie", out cookie) || string.IsNullOrEmpty(cookie)) return "";
            foreach (var part in cookie.Split(';'))
            {
                var tr = part.Trim();
                if (tr.StartsWith("mc_token=")) return tr.Substring(9).Trim();
            }
            return "";
        }

        byte[] ProcessHttpRequest(string method, string path, string rawTarget, Dictionary<string, string> query,
            Dictionary<string, string> hdrs, byte[] body, string remoteIp, TcpClient tcp, NetworkStream ns, out bool handledSse)
        {
            handledSse = false;
            bool isForwarded = hdrs.ContainsKey("X-Dotmini-Relay") || hdrs.ContainsKey("Cf-Connecting-Ip") || hdrs.ContainsKey("X-Forwarded-For");
            bool isLocalPc = !isForwarded && (remoteIp == "127.0.0.1" || remoteIp == "::1");

            if (method == "GET" && path == "/api/icon/provider")
            {
                string id; query.TryGetValue("id", out id);
                return MakeSvgProviderIcon(id);
            }

            if (method == "POST" && path == "/api/pair/verify-pin")
            {
                var o = DJ.Obj(Encoding.UTF8.GetString(body)) ?? new Dictionary<string, object>();
                string supplied = new string((DJ.Str(o, "pin") ?? "").Where(char.IsDigit).ToArray());
                string err;
                if (VerifyPin(supplied, remoteIp, hdrs, out err))
                {
                    bool viaHttps = string.Equals(Hdr(hdrs, "X-Forwarded-Proto"), "https", StringComparison.OrdinalIgnoreCase);
                    string sc = "mc_token=" + PairingToken + "; Path=/; SameSite=Lax; HttpOnly" + (viaHttps ? "; Secure" : "");
                    return MakeJson(new Dictionary<string, object> { { "ok", true }, { "token", PairingToken } }, "200 OK", sc);
                }
                return MakeJson(new Dictionary<string, object> { { "ok", false }, { "error", err } }, "401 Unauthorized");
            }

            string qPair; query.TryGetValue("pair", out qPair);
            string qTok; query.TryGetValue("token", out qTok);
            string hTok = Hdr(hdrs, "X-Companion-Token");
            string cTok = ExtractCookieToken(hdrs);
            string suppliedTok = !string.IsNullOrEmpty(hTok) ? hTok : (!string.IsNullOrEmpty(cTok) ? cTok : (qTok ?? ""));

            bool matchedPair = ConstantTimeEquals(qPair, OneTimePairingCode);
            bool matchedSession = ConstantTimeEquals(suppliedTok, PairingToken);
            if (!matchedPair && !matchedSession && !isLocalPc)
            {
                return MakeHttp("401 Unauthorized", "text/html; charset=utf-8", Encoding.UTF8.GetBytes(BuildPinUnlockHtml()));
            }
            if (matchedPair)
            {
                OneTimePairingCode = GenerateSecureToken();
                NotifyChanged();
            }

            // Record & check device approval
            var dev = RecordConnectedDevice(hdrs, remoteIp, isLocalPc);
            if (dev.ApprovalState == PhoneDeviceApprovalState.Pending)
            {
                bool viaHttps = string.Equals(Hdr(hdrs, "X-Forwarded-Proto"), "https", StringComparison.OrdinalIgnoreCase);
                string sc = "mc_token=" + PairingToken + "; Path=/; SameSite=Lax; HttpOnly" + (viaHttps ? "; Secure" : "");
                if (method == "GET" && path == "/") return MakeHttp("403 Forbidden", "text/html; charset=utf-8", Encoding.UTF8.GetBytes(BuildPendingApprovalHtml(dev)), sc);
                return MakeJson(new Dictionary<string, object> { { "ok", false }, { "pendingApproval", true }, { "error", "Approve this phone on your Windows PC." } }, "403 Forbidden", sc);
            }
            if (dev.ApprovalState == PhoneDeviceApprovalState.Rejected)
            {
                return MakeJson(new Dictionary<string, object> { { "ok", false }, { "error", "Access denied." } }, "403 Forbidden");
            }

            if (path.StartsWith("/preview/"))
            {
                return HandlePreviewReverseProxy(method, rawTarget, hdrs, body);
            }

            switch (method + " " + path)
            {
                case "GET /":
                    bool viaHttps = string.Equals(Hdr(hdrs, "X-Forwarded-Proto"), "https", StringComparison.OrdinalIgnoreCase);
                    string cookieHdr = "mc_token=" + PairingToken + "; Path=/; SameSite=Lax; HttpOnly" + (viaHttps ? "; Secure" : "");
                    return MakeHttp("200 OK", "text/html; charset=utf-8", Encoding.UTF8.GetBytes(BuildCompanionHtml(PairingToken)), cookieHdr);

                case "GET /manifest.json":
                    var mani = new Dictionary<string, object> {
                        { "name", Environment.MachineName + " · MicroCode" },
                        { "short_name", "MicroCode" },
                        { "start_url", "/" },
                        { "display", "standalone" },
                        { "background_color", "#0d0d0f" },
                        { "theme_color", "#141417" },
                        { "icons", new[] { new Dictionary<string, object> { { "src", "/apple-touch-icon.png" }, { "sizes", "180x180" }, { "type", "image/png" }, { "purpose", "any maskable" } } } }
                    };
                    return MakeHttp("200 OK", "application/manifest+json; charset=utf-8", Encoding.UTF8.GetBytes(JsonSer.Serialize(mani)));

                case "GET /sw.js":
                    return MakeHttp("200 OK", "application/javascript; charset=utf-8", Encoding.UTF8.GetBytes(BuildServiceWorkerJs()));

                case "GET /apple-touch-icon.png":
                    return MakeHttp("200 OK", "image/svg+xml; charset=utf-8", Encoding.UTF8.GetBytes(
                        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"180\" height=\"180\" viewBox=\"0 0 180 180\"><rect width=\"180\" height=\"180\" rx=\"38\" fill=\"#141417\"/><path d=\"M52 126V54l38 36 38-36v72\" fill=\"none\" stroke=\"#ededf0\" stroke-width=\"14\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/></svg>"));

                case "GET /api/state":
                    return MakeJson(BuildStateObject());

                case "GET /api/stream":
                    string jsonStr = JsonSer.Serialize(BuildStateObject());
                    if (hdrs.ContainsKey("X-Dotmini-Relay"))
                    {
                        byte[] frame = Encoding.UTF8.GetBytes("retry: 1100\ndata: " + jsonStr + "\n\n");
                        return MakeHttp("200 OK", "text/event-stream; charset=utf-8", frame);
                    }
                    handledSse = true;
                    string hdrStr = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream; charset=utf-8\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: *\r\n\r\ndata: " + jsonStr + "\n\n";
                    byte[] initBytes = Encoding.UTF8.GetBytes(hdrStr);
                    ns.Write(initBytes, 0, initBytes.Length);
                    ns.Flush();
                    var client = new SseClient { Tcp = tcp, Stream = ns };
                    lock (_sseClients) _sseClients.Add(client);
                    while (_running && !client.Closed) Thread.Sleep(400);
                    return null;

                case "GET /api/models":
                    return MakeJson(new Dictionary<string, object> { { "ok", true }, { "models", BuildAvailableModels() } });

                case "POST /api/model/select":
                    var mObj = DJ.Obj(Encoding.UTF8.GetString(body));
                    if (mObj != null)
                    {
                        SelectRemoteModel(DJ.Str(mObj, "mode") ?? "cloud", DJ.Str(mObj, "provider") ?? "omni", DJ.Str(mObj, "modelId") ?? "");
                        TriggerShadowSync(false);
                        return MakeJson(new Dictionary<string, object> { { "ok", true } });
                    }
                    return MakeJson(new Dictionary<string, object> { { "ok", false } }, "400 Bad Request");

                case "POST /api/send":
                    var sObj = DJ.Obj(Encoding.UTF8.GetString(body)) ?? new Dictionary<string, object>();
                    string prompt = DJ.Str(sObj, "prompt") ?? "";
                    var attPaths = SaveUploadedAttachments(DJ.Arr(sObj, "attachments"));
                    DispatchRemotePrompt(prompt, attPaths);
                    TriggerShadowSync(true);
                    return MakeJson(new Dictionary<string, object> { { "ok", true } });

                case "POST /api/stop":
                    InvokeOnUI(() => { if (AgentStore.CurrentView != null) AgentStore.CurrentView.StopRun(); });
                    TriggerShadowSync(false);
                    return MakeJson(new Dictionary<string, object> { { "ok", true } });

                case "POST /api/plan/approve":
                    InvokeOnUI(() => { if (AgentStore.CurrentView != null) AgentStore.CurrentView.ApproveLatestPlan(true); });
                    return MakeJson(new Dictionary<string, object> { { "ok", true } });

                case "POST /api/plan/reject":
                    InvokeOnUI(() => { if (AgentStore.CurrentView != null) AgentStore.CurrentView.ApproveLatestPlan(false); });
                    return MakeJson(new Dictionary<string, object> { { "ok", true } });

                case "POST /api/tool/approve":
                    InvokeOnUI(() => { if (AgentStore.CurrentView != null) AgentStore.CurrentView.ApprovePendingTool(true); });
                    return MakeJson(new Dictionary<string, object> { { "ok", true } });

                case "POST /api/tool/reject":
                    InvokeOnUI(() => { if (AgentStore.CurrentView != null) AgentStore.CurrentView.ApprovePendingTool(false); });
                    return MakeJson(new Dictionary<string, object> { { "ok", true } });

                case "POST /api/workspace/switch":
                    var wObj = DJ.Obj(Encoding.UTF8.GetString(body)) ?? new Dictionary<string, object>();
                    string wPath = DJ.Str(wObj, "path"), wSid = DJ.Str(wObj, "sessionId");
                    InvokeOnUI(() => AgentStore.SwitchChat(wSid, wPath));
                    TriggerShadowSync(true);
                    return MakeJson(new Dictionary<string, object> { { "ok", true } });

                case "POST /api/session/switch":
                    var swObj = DJ.Obj(Encoding.UTF8.GetString(body)) ?? new Dictionary<string, object>();
                    InvokeOnUI(() => AgentStore.SwitchChat(DJ.Str(swObj, "sessionId")));
                    TriggerShadowSync(false);
                    return MakeJson(new Dictionary<string, object> { { "ok", true } });

                case "POST /api/session/new":
                    var nwObj = DJ.Obj(Encoding.UTF8.GetString(body)) ?? new Dictionary<string, object>();
                    string reqProj = DJ.Str(nwObj, "projectPath");
                    InvokeOnUI(() => AgentStore.NewChat(!string.IsNullOrEmpty(reqProj) ? reqProj : AppState.Shared.WorkspaceFolder));
                    TriggerShadowSync(false);
                    return MakeJson(new Dictionary<string, object> { { "ok", true } });

                case "GET /api/files/search":
                    string fq; query.TryGetValue("q", out fq);
                    return MakeJson(new Dictionary<string, object> { { "ok", true }, { "files", SearchWorkspaceFiles(fq ?? "", 50) } });

                case "GET /api/files/read":
                    string rp; query.TryGetValue("path", out rp);
                    return MakeJson(ReadWorkspaceFileSafe(rp ?? ""));

                case "GET /api/git/status":
                    return MakeJson(HandleGitStatus());

                case "GET /api/git/diff":
                    string dp; query.TryGetValue("path", out dp);
                    return MakeJson(HandleGitDiff(dp ?? ""));

                case "POST /api/git/action":
                    var gaObj = DJ.Obj(Encoding.UTF8.GetString(body)) ?? new Dictionary<string, object>();
                    return MakeJson(HandleGitAction(DJ.Str(gaObj, "action") ?? "", gaObj));

                case "GET /api/terminal/scripts":
                    return MakeJson(new Dictionary<string, object> { { "ok", true }, { "scripts", DiscoverQuickScripts() } });

                case "POST /api/terminal/exec":
                    var tObj = DJ.Obj(Encoding.UTF8.GetString(body)) ?? new Dictionary<string, object>();
                    return MakeJson(ExecuteTerminalCommand(DJ.Str(tObj, "command") ?? ""));

                case "GET /api/preview/ports":
                    return MakeJson(BuildPreviewPortsPayload());

                default:
                    return MakeJson(new Dictionary<string, object> { { "ok", false }, { "error", "Not found" } }, "404 Not Found");
            }
        }

        // ── Auth, PIN & Device Tracking ────────────────────────────────────────────────────────────

        bool VerifyPin(string supplied, string remoteIp, Dictionary<string, string> hdrs, out string err)
        {
            string fwd = Hdr(hdrs, "Cf-Connecting-Ip") ?? Hdr(hdrs, "X-Forwarded-For") ?? remoteIp;
            lock (_pinAttempts)
            {
                PinAttemptState st;
                if (_pinAttempts.TryGetValue(fwd, out st) && st.Count >= 5 && (DateTime.UtcNow - st.LastAttempt).TotalSeconds < 60)
                {
                    err = "Too many PIN attempts. Wait 60 seconds and try again.";
                    return false;
                }
            }
            if (supplied.Length == 6 && ConstantTimeEquals(supplied, SixDigitPIN))
            {
                lock (_pinAttempts) _pinAttempts.Remove(fwd);
                SixDigitPIN = GenerateSixDigitPIN();
                NotifyChanged();
                err = null;
                return true;
            }
            lock (_pinAttempts)
            {
                PinAttemptState st;
                if (!_pinAttempts.TryGetValue(fwd, out st)) _pinAttempts[fwd] = st = new PinAttemptState();
                st.Count++; st.LastAttempt = DateTime.UtcNow;
            }
            err = "Incorrect 6-digit PIN.";
            return false;
        }

        ConnectedPhoneDevice RecordConnectedDevice(Dictionary<string, string> hdrs, string remoteIp, bool isLocalPc)
        {
            string ua = Hdr(hdrs, "User-Agent") ?? "";
            string fwd = Hdr(hdrs, "Cf-Connecting-Ip") ?? Hdr(hdrs, "X-Forwarded-For");
            string effIp = !string.IsNullOrEmpty(fwd) ? fwd.Split(',')[0].Trim() : remoteIp;
            string via = (!string.IsNullOrEmpty(fwd) || effIp == "127.0.0.1") ? "Online Tunnel" : effIp.StartsWith("100.") ? "Tailscale VPN" : "Same Wi-Fi / LAN";
            string name = ua.Contains("iPhone") ? "iPhone (iOS)" : ua.Contains("iPad") ? "iPad (iPadOS)" : ua.Contains("Android") ? "Android Phone" : "Mobile Browser";
            string id = name + "-" + effIp;
            lock (ConnectedDevices)
            {
                var cur = ConnectedDevices.FirstOrDefault(x => x.Id == id);
                if (cur != null) { cur.LastSeenAt = DateTime.Now; cur.ConnectionVia = via; return cur; }
                var st = (isLocalPc || !RequireApprovalForNewDevices || _approvedIds.Contains(id))
                    ? PhoneDeviceApprovalState.Approved : PhoneDeviceApprovalState.Pending;
                var created = new ConnectedPhoneDevice
                {
                    Id = id, Name = name, IpAddress = effIp, ConnectionVia = via,
                    FirstConnectedAt = DateTime.Now, LastSeenAt = DateTime.Now, ApprovalState = st
                };
                ConnectedDevices.Insert(0, created);
                NotifyChanged();
                return created;
            }
        }

        // ── State Builder, Models, Chat Dispatch ───────────────────────────────────────────────────

        void TickBroadcast()
        {
            if (!_running) return;
            lock (_sseClients)
            {
                if (_sseClients.Count == 0) return;
            }
            string fp;
            var obj = BuildStateObject(out fp);
            if (fp == _lastBroadcastFp) return;
            _lastBroadcastFp = fp;
            byte[] frame = Encoding.UTF8.GetBytes("data: " + JsonSer.Serialize(obj) + "\n\n");
            lock (_sseClients)
            {
                for (int i = _sseClients.Count - 1; i >= 0; i--)
                {
                    var c = _sseClients[i];
                    try { lock (c.WriteLock) { c.Stream.Write(frame, 0, frame.Length); c.Stream.Flush(); } }
                    catch { c.Close(); _sseClients.RemoveAt(i); }
                }
            }
        }

        Dictionary<string, object> BuildStateObject()
        {
            string unused;
            return BuildStateObject(out unused);
        }

        Dictionary<string, object> BuildStateObject(out string fp)
        {
            Dictionary<string, object> res = null;
            string fpOut = "";
            Func<Dictionary<string, object>> build = () =>
            {
                var ws = AppState.Shared.WorkspaceFolder;
                var sess = AgentStore.Active;
                var av = AgentStore.CurrentView;
                bool isLoading = av != null && av.IsRunning;
                var msgs = new List<Dictionary<string, object>>();
                if (sess != null)
                {
                    foreach (var m in sess.Messages.Skip(Math.Max(0, sess.Messages.Count - 30)))
                    {
                        var steps = m.Steps.Select(st => new Dictionary<string, object> {
                            { "name", st.Name ?? "" }, { "target", st.Target ?? "" }, { "ok", st.Ok }, { "result", Trunc(st.Result ?? "", 800) }
                        }).ToList();
                        msgs.Add(new Dictionary<string, object> {
                            { "id", m.Id }, { "role", m.Role ?? "assistant" },
                            { "content", m.Content ?? "" }, { "thought", m.Thinking ?? "" },
                            { "toolCount", steps.Count }, { "tools", steps },
                            { "modelLabel", !string.IsNullOrEmpty(m.Model) ? m.Model : AIConfig.ModelDisplayName },
                            { "providerId", AIConfig.Provider },
                            { "planState", m.PlanState ?? "" }
                        });
                    }
                }
                var workspaces = new List<Dictionary<string, object>>();
                var byProj = AgentStore.Sessions.GroupBy(x => x.ProjectPath ?? "__general__");
                foreach (var grp in byProj)
                {
                    string gPath = grp.Key;
                    string gName = gPath == "__general__" ? "General" : Path.GetFileName(gPath.TrimEnd('\\'));
                    workspaces.Add(new Dictionary<string, object> {
                        { "id", gPath }, { "name", gName }, { "path", gPath }, { "lang", "code" }, { "langLabel", "Code" },
                        { "active", string.Equals(gPath, ws ?? "__general__", StringComparison.OrdinalIgnoreCase) },
                        { "chatCount", grp.Count() },
                        { "chats", grp.Take(30).Select(c => new Dictionary<string, object> {
                            { "id", c.Id }, { "name", c.Name ?? "Chat" }, { "active", sess != null && c.Id == sess.Id }, { "messageCount", c.Messages.Count }
                        }).ToList() }
                    });
                }
                if (!string.IsNullOrEmpty(ws) && !workspaces.Any(x => string.Equals(Convert.ToString(x["path"]), ws, StringComparison.OrdinalIgnoreCase)))
                {
                    workspaces.Insert(0, new Dictionary<string, object> {
                        { "id", ws }, { "name", Path.GetFileName(ws.TrimEnd('\\')) }, { "path", ws },
                        { "lang", "code" }, { "langLabel", "Code" }, { "active", true }, { "chatCount", 0 }, { "chats", new object[0] }
                    });
                }

                string wsTitle = !string.IsNullOrEmpty(ws) ? Path.GetFileName(ws.TrimEnd('\\')) : "Workspace";
                var d = new Dictionary<string, object> {
                    { "macName", Environment.MachineName },
                    { "os", "windows" },
                    { "workspace", wsTitle },
                    { "workspacePath", ws ?? "" },
                    { "workspaceLang", "code" },
                    { "sessionTitle", sess != null ? (sess.Name ?? "Chat") : "New Chat" },
                    { "activeChatId", sess != null ? sess.Id : "" },
                    { "modelLabel", AIConfig.BadgeTitle + " · " + AIConfig.ModelDisplayName },
                    { "providerId", AIConfig.Provider },
                    { "isLoading", isLoading },
                    { "phase", isLoading ? "Running agent step…" : "Ready" },
                    { "currentTool", "" },
                    { "stepCount", sess != null && sess.Messages.Count > 0 ? sess.Messages.Last().Steps.Count : 0 },
                    { "queueCount", av != null ? av.QueuedCount : 0 },
                    { "workspaces", workspaces },
                    { "messages", msgs },
                    { "macOnline", true },
                    { "cloudMode", false },
                    { "executionMode", "pc" }
                };
                if (av != null && !string.IsNullOrEmpty(av.PendingApprovalToolName))
                {
                    d["pendingTool"] = new Dictionary<string, object> {
                        { "id", "win-tool" }, { "toolName", av.PendingApprovalToolName }, { "description", av.PendingApprovalDescription ?? "" }
                    };
                }
                var pendingPlan = sess != null ? sess.Messages.LastOrDefault(x => x.PlanState == "pending") : null;
                if (pendingPlan != null)
                {
                    d["plan"] = new Dictionary<string, object> { { "state", "pending" }, { "title", sess.Name ?? "Plan" }, { "totalSteps", 1 } };
                }
                var lastMsg = msgs.Count > 0 ? msgs[msgs.Count - 1] : null;
                fpOut = (ws ?? "") + "|" + (sess != null ? sess.Id : "") + "|" + msgs.Count + "|" + (lastMsg != null ? Convert.ToString(lastMsg["content"]).Length.ToString() : "0") + "|" + isLoading + "|" + (av != null ? av.PendingApprovalToolName : "");
                return d;
            };
            var app = Application.Current;
            if (app != null && !app.Dispatcher.CheckAccess())
                app.Dispatcher.Invoke(() => { res = build(); });
            else
                res = build();
            fp = fpOut;
            return res ?? new Dictionary<string, object>();
        }

        List<Dictionary<string, object>> BuildAvailableModels()
        {
            var list = new List<Dictionary<string, object>>();
            DotminiCloud.EnsureFresh();
            string activeMode = AIConfig.Mode;
            string activeId = AIConfig.Model;
            foreach (var cm in DotminiCloud.Models.Take(40))
            {
                list.Add(new Dictionary<string, object> {
                    { "id", cm.Id }, { "name", cm.Name }, { "mode", "cloud" }, { "provider", cm.Provider },
                    { "providerIconId", cm.Provider }, { "selected", activeMode == "cloud" && cm.Id == activeId }
                });
            }
            foreach (var p in AIConfig.Catalog)
            {
                if (string.IsNullOrEmpty(AIConfig.KeyFor(p.Id))) continue;
                foreach (var m in p.Models)
                {
                    list.Add(new Dictionary<string, object> {
                        { "id", m }, { "name", AIConfig.FormatModelName(m) }, { "mode", "direct" }, { "provider", p.Id },
                        { "providerIconId", p.Id }, { "selected", activeMode == "direct" && AIConfig.SelectedProvider == p.Id && m == activeId }
                    });
                }
            }
            list.Add(new Dictionary<string, object> {
                { "id", AIConfig.ModelFor("local") }, { "name", "Local LLM · " + AIConfig.ModelFor("local") },
                { "mode", "local" }, { "provider", "local" }, { "providerIconId", "ollama" },
                { "selected", activeMode == "local" }
            });
            return list;
        }

        void SelectRemoteModel(string mode, string provider, string modelId)
        {
            InvokeOnUI(() =>
            {
                AIConfig.Mode = mode;
                if (mode == "cloud") AIConfig.SetModelFor("omni", modelId);
                else if (mode == "local") AIConfig.SetModelFor("local", modelId);
                else { AIConfig.SelectedProvider = provider; AIConfig.SetModelFor(provider, modelId); }
                Defaults.Flush();
                AppState.Shared.Notify("agentBar");
            });
        }

        List<string> SaveUploadedAttachments(System.Collections.ArrayList atts)
        {
            var outPaths = new List<string>();
            if (atts == null || atts.Count == 0) return outPaths;
            string dir = Path.Combine(Defaults.Dir, "mobile-uploads");
            try { Directory.CreateDirectory(dir); } catch { }
            foreach (var item in atts.OfType<Dictionary<string, object>>())
            {
                try
                {
                    string name = Path.GetFileName(DJ.Str(item, "name") ?? "upload.bin");
                    string b64 = DJ.Str(item, "dataBase64") ?? "";
                    if (b64.Length == 0) continue;
                    string dst = Path.Combine(dir, Guid.NewGuid().ToString("N").Substring(0, 8) + "_" + name);
                    File.WriteAllBytes(dst, Convert.FromBase64String(b64));
                    outPaths.Add(dst);
                }
                catch { }
            }
            return outPaths;
        }

        void DispatchRemotePrompt(string prompt, List<string> attachments)
        {
            InvokeOnUI(() =>
            {
                string fullPrompt = prompt ?? "";
                if (attachments != null && attachments.Count > 0)
                    fullPrompt = (fullPrompt.Length > 0 ? fullPrompt + "\n\n" : "") + string.Join("\n", attachments.Select(p => "[Uploaded from Mobile: " + p + "]"));
                if (AgentStore.CurrentView != null)
                {
                    AgentStore.CurrentView.RunPrompt(fullPrompt, false);
                }
                else
                {
                    AppState.Shared.SwitchToMode(EditorMode.AIAgent);
                    AppState.Shared.Notify("agent:send:" + fullPrompt);
                }
            });
        }

        // ── Workspace Files, Git, Terminal, Preview ────────────────────────────────────────────────

        List<Dictionary<string, object>> SearchWorkspaceFiles(string q, int limit)
        {
            var results = new List<Dictionary<string, object>>();
            string ws = AppState.Shared.WorkspaceFolder;
            if (string.IsNullOrEmpty(ws) || !Directory.Exists(ws)) return results;
            string ql = (q ?? "").ToLowerInvariant();
            try
            {
                foreach (var file in Directory.EnumerateFiles(ws, "*", SearchOption.AllDirectories))
                {
                    string rel = file.Substring(ws.Length).TrimStart('\\', '/').Replace('\\', '/');
                    if (rel.StartsWith(".git/") || rel.Contains("/node_modules/") || rel.Contains("/bin/") || rel.Contains("/obj/")) continue;
                    if (ql.Length == 0 || rel.ToLowerInvariant().Contains(ql))
                    {
                        results.Add(new Dictionary<string, object> {
                            { "name", Path.GetFileName(rel) },
                            { "path", rel },
                            { "ext", Path.GetExtension(rel).TrimStart('.').ToLowerInvariant() }
                        });
                        if (results.Count >= limit) break;
                    }
                }
            }
            catch { }
            return results;
        }

        Dictionary<string, object> ReadWorkspaceFileSafe(string rel)
        {
            string ws = AppState.Shared.WorkspaceFolder;
            if (string.IsNullOrEmpty(ws) || string.IsNullOrEmpty(rel))
                return new Dictionary<string, object> { { "ok", false }, { "error", "No workspace open" } };
            try
            {
                string full = Path.GetFullPath(Path.Combine(ws, rel.Replace('/', '\\')));
                if (!full.StartsWith(Path.GetFullPath(ws), StringComparison.OrdinalIgnoreCase) || !File.Exists(full))
                    return new Dictionary<string, object> { { "ok", false }, { "error", "File not found" } };
                var fi = new FileInfo(full);
                if (fi.Length > 256 * 1024) return new Dictionary<string, object> { { "ok", false }, { "error", "File too large (" + (fi.Length / 1024) + " KB)" } };
                return new Dictionary<string, object> { { "ok", true }, { "path", rel }, { "content", File.ReadAllText(full, Encoding.UTF8) } };
            }
            catch (Exception ex) { return new Dictionary<string, object> { { "ok", false }, { "error", ex.Message } }; }
        }

        Dictionary<string, object> HandleGitStatus()
        {
            string ws = AppState.Shared.WorkspaceFolder;
            if (string.IsNullOrEmpty(ws)) return new Dictionary<string, object> { { "ok", false }, { "error", "No workspace" } };
            string branch = RunProcess("git", "rev-parse --abbrev-ref HEAD", ws).Trim();
            string status = RunProcess("git", "status --porcelain", ws);
            var changed = new List<Dictionary<string, object>>();
            foreach (var raw in status.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
            {
                if (raw.Length < 4) continue;
                changed.Add(new Dictionary<string, object> { { "status", raw.Substring(0, 2).Trim() }, { "path", raw.Substring(3).Trim() } });
            }
            return new Dictionary<string, object> { { "ok", true }, { "branch", string.IsNullOrEmpty(branch) ? "HEAD" : branch }, { "changed", changed } };
        }

        Dictionary<string, object> HandleGitDiff(string relPath)
        {
            string ws = AppState.Shared.WorkspaceFolder ?? Environment.CurrentDirectory;
            string args = string.IsNullOrEmpty(relPath) ? "diff" : ("diff -- \"" + relPath.Replace("\"", "") + "\"");
            return new Dictionary<string, object> { { "ok", true }, { "diff", RunProcess("git", args, ws) } };
        }

        Dictionary<string, object> HandleGitAction(string action, Dictionary<string, object> body)
        {
            string ws = AppState.Shared.WorkspaceFolder;
            if (string.IsNullOrEmpty(ws)) return new Dictionary<string, object> { { "ok", false }, { "error", "No workspace" } };
            string outText = "";
            if (action == "pull") outText = RunProcess("git", "pull", ws);
            else if (action == "push") outText = RunProcess("git", "push", ws);
            else if (action == "stage_all") outText = RunProcess("git", "add -A", ws);
            else if (action == "commit")
            {
                string msg = (DJ.Str(body, "message") ?? "Update from Mobile Connect").Replace("\"", "\\\"");
                RunProcess("git", "add -A", ws);
                outText = RunProcess("git", "commit -m \"" + msg + "\"", ws);
            }
            return new Dictionary<string, object> { { "ok", true }, { "output", outText } };
        }

        List<Dictionary<string, object>> DiscoverQuickScripts()
        {
            var list = new List<Dictionary<string, object>>();
            string ws = AppState.Shared.WorkspaceFolder;
            if (string.IsNullOrEmpty(ws)) return list;
            string pkg = Path.Combine(ws, "package.json");
            if (File.Exists(pkg))
            {
                var o = DJ.Obj(File.ReadAllText(pkg));
                var sc = DJ.Child(o, "scripts");
                if (sc != null) foreach (var kv in sc) list.Add(new Dictionary<string, object> { { "label", "npm run " + kv.Key }, { "command", "npm run " + kv.Key } });
            }
            if (File.Exists(Path.Combine(ws, "build.cmd"))) list.Add(new Dictionary<string, object> { { "label", "build.cmd" }, { "command", "build.cmd" } });
            if (File.Exists(Path.Combine(ws, "go.mod"))) list.Add(new Dictionary<string, object> { { "label", "go test ./..." }, { "command", "go test ./..." } });
            if (File.Exists(Path.Combine(ws, "Cargo.toml"))) list.Add(new Dictionary<string, object> { { "label", "cargo test" }, { "command", "cargo test" } });
            return list;
        }

        Dictionary<string, object> ExecuteTerminalCommand(string cmd)
        {
            if (string.IsNullOrWhiteSpace(cmd)) return new Dictionary<string, object> { { "ok", false }, { "error", "Empty command" } };
            string ws = AppState.Shared.WorkspaceFolder ?? Environment.CurrentDirectory;
            string res = RunProcess("cmd.exe", "/c " + cmd, ws);
            return new Dictionary<string, object> { { "ok", true }, { "output", res } };
        }

        Dictionary<string, object> BuildPreviewPortsPayload()
        {
            return new Dictionary<string, object> {
                { "ok", true }, { "ports", new object[0] }, { "localPath", "/preview/local/" }
            };
        }

        byte[] HandlePreviewReverseProxy(string method, string rawTarget, Dictionary<string, string> hdrs, byte[] body)
        {
            string rest = rawTarget.Length > 9 ? rawTarget.Substring(9) : "";
            int slash = rest.IndexOf('/');
            string targetSeg = slash >= 0 ? rest.Substring(0, slash) : rest;
            string sub = slash >= 0 ? rest.Substring(slash) : "/";
            if (targetSeg == "local")
            {
                string ws = AppState.Shared.WorkspaceFolder;
                if (!string.IsNullOrEmpty(ws))
                {
                    string rel = sub.TrimStart('/').Split('?')[0];
                    if (rel.Length == 0) rel = "index.html";
                    string full = Path.GetFullPath(Path.Combine(ws, rel.Replace('/', '\\')));
                    if (full.StartsWith(Path.GetFullPath(ws), StringComparison.OrdinalIgnoreCase) && File.Exists(full))
                        return MakeHttp("200 OK", MimeFromExt(full), File.ReadAllBytes(full));
                }
                return MakeHttp("404 Not Found", "text/plain", Encoding.UTF8.GetBytes("No local index.html"));
            }
            int port;
            if (!int.TryParse(targetSeg, out port) || port < 1 || port > 65535)
                return MakeHttp("400 Bad Request", "text/plain", Encoding.UTF8.GetBytes("Invalid port"));
            try
            {
                var req = new HttpRequestMessage(new HttpMethod(method), "http://127.0.0.1:" + port + sub);
                if (body != null && body.Length > 0 && method != "GET" && method != "HEAD") req.Content = new ByteArrayContent(body);
                var resp = LoopHttp.SendAsync(req).Result;
                var b = resp.Content.ReadAsByteArrayAsync().Result;
                string ct = resp.Content.Headers.ContentType != null ? resp.Content.Headers.ContentType.ToString() : "application/octet-stream";
                return MakeHttp(((int)resp.StatusCode) + " " + resp.ReasonPhrase, ct, b);
            }
            catch (Exception ex) { return MakeHttp("502 Bad Gateway", "text/plain", Encoding.UTF8.GetBytes(ex.GetBaseException().Message)); }
        }

        // ── Helpers ────────────────────────────────────────────────────────────────────────────────

        static string RunProcess(string file, string args, string cwd)
        {
            try
            {
                var p = new Process
                {
                    StartInfo = new ProcessStartInfo(file, args)
                    {
                        WorkingDirectory = cwd,
                        UseShellExecute = false,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        CreateNoWindow = true
                    }
                };
                p.Start();
                string stdout = p.StandardOutput.ReadToEnd();
                string stderr = p.StandardError.ReadToEnd();
                p.WaitForExit(15000);
                return (stdout + "\n" + stderr).Trim();
            }
            catch (Exception ex) { return ex.Message; }
        }

        static void InvokeOnUI(Action a)
        {
            var app = Application.Current;
            if (app == null || app.Dispatcher.CheckAccess()) { a(); return; }
            app.Dispatcher.Invoke(a);
        }

        static string Hdr(Dictionary<string, string> h, string key) { string v; return h != null && h.TryGetValue(key, out v) ? v : null; }
        static string Trunc(string s, int max) { return s.Length <= max ? s : s.Substring(0, max) + "…"; }
        static string MimeFromExt(string f)
        {
            string e = Path.GetExtension(f).ToLowerInvariant();
            if (e == ".html" || e == ".htm") return "text/html; charset=utf-8";
            if (e == ".js") return "application/javascript; charset=utf-8";
            if (e == ".css") return "text/css; charset=utf-8";
            if (e == ".json") return "application/json; charset=utf-8";
            if (e == ".svg") return "image/svg+xml";
            if (e == ".png") return "image/png";
            return "text/plain; charset=utf-8";
        }

        byte[] MakeJson(object obj, string status = "200 OK", string setCookie = null)
        {
            return MakeHttp(status, "application/json; charset=utf-8", Encoding.UTF8.GetBytes(JsonSer.Serialize(obj)), setCookie);
        }

        static byte[] MakeHttp(string status, string contentType, byte[] body, string setCookie = null)
        {
            var sb = new StringBuilder();
            sb.Append("HTTP/1.1 ").Append(status).Append("\r\n")
              .Append("Content-Type: ").Append(contentType).Append("\r\n")
              .Append("Content-Length: ").Append(body.Length).Append("\r\n")
              .Append("Cache-Control: no-store, no-cache, must-revalidate\r\n")
              .Append("Access-Control-Allow-Origin: *\r\n");
            if (!string.IsNullOrEmpty(setCookie)) sb.Append("Set-Cookie: ").Append(setCookie).Append("\r\n");
            sb.Append("Connection: close\r\n\r\n");
            var head = Encoding.ASCII.GetBytes(sb.ToString());
            var all = new byte[head.Length + body.Length];
            Buffer.BlockCopy(head, 0, all, 0, head.Length);
            Buffer.BlockCopy(body, 0, all, head.Length, body.Length);
            return all;
        }

        static byte[] MakeSvgProviderIcon(string id)
        {
            string lbl = (id ?? "MC").Trim().ToUpperInvariant();
            if (lbl.Length > 2) lbl = lbl.Substring(0, 2);
            if (lbl.Length == 0) lbl = "MC";
            string svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"40\" height=\"40\" viewBox=\"0 0 40 40\"><rect width=\"40\" height=\"40\" rx=\"10\" fill=\"#1b1b20\" stroke=\"#303038\"/><text x=\"20\" y=\"25\" text-anchor=\"middle\" fill=\"#ededf0\" font-family=\"Segoe UI,sans-serif\" font-size=\"14\" font-weight=\"600\">" + WebUtility.HtmlEncode(lbl) + "</text></svg>";
            return MakeHttp("200 OK", "image/svg+xml; charset=utf-8", Encoding.UTF8.GetBytes(svg));
        }

        static string BuildServiceWorkerJs()
        {
            return "const MC_SHELL_CACHE = 'mc-shell-v2';\n" +
                "self.addEventListener('install', (e) => { self.skipWaiting(); });\n" +
                "self.addEventListener('activate', (e) => { e.waitUntil(self.clients.claim()); });\n" +
                "self.addEventListener('fetch', (event) => {\n" +
                "  const req = event.request; if (req.method !== 'GET') return;\n" +
                "  const u = new URL(req.url);\n" +
                "  if (u.pathname === '/' || u.pathname === '/manifest.json' || u.pathname === '/apple-touch-icon.png' || u.pathname === '/api/icon/provider') {\n" +
                "    event.respondWith(fetch(req).then((resp) => { if (resp && resp.status === 200) { const c = resp.clone(); caches.open(MC_SHELL_CACHE).then((ch) => ch.put(req, c)).catch(() => {}); } return resp; }).catch(() => caches.match(req)));\n" +
                "  }\n" +
                "});\n";
        }

        static string BuildPinUnlockHtml()
        {
            return "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1,maximum-scale=1\"><title>MicroCode Companion</title>" +
                "<style>body{background:#09090b;color:#f4f4f5;font-family:-apple-system,Segoe UI,sans-serif;display:flex;align-items:center;justify-content:center;min-height:92vh;margin:0;padding:24px;text-align:center}" +
                ".card{width:100%;max-width:360px;background:#121215;border:1px solid rgba(255,255,255,.1);border-radius:14px;padding:26px}" +
                "input{width:100%;box-sizing:border-box;background:#09090b;color:#fff;border:1px solid rgba(255,255,255,.16);border-radius:9px;padding:10px;font-size:20px;font-family:monospace;letter-spacing:.26em;text-align:center;outline:none;margin-bottom:8px}" +
                "button{width:100%;background:#f4f4f5;color:#09090b;border:none;border-radius:9px;padding:10px;font-size:13.5px;font-weight:600;cursor:pointer}#err{color:#f87171;font-size:12px;margin-top:8px}</style></head>" +
                "<body><div class=\"card\"><h3>Unlock MicroCode Mobile</h3><p style=\"color:#a1a1aa;font-size:13px\">Enter the 6-digit Pairing PIN from Settings &rarr; Connect with Phone:</p>" +
                "<input id=\"pinBox\" type=\"tel\" inputmode=\"numeric\" maxlength=\"7\" placeholder=\"000 000\"><button onclick=\"unlock()\">Unlock</button><div id=\"err\"></div></div>" +
                "<script>async function unlock(){const pin=document.getElementById('pinBox').value.replace(/\\D/g,'');const err=document.getElementById('err');if(pin.length!==6){err.textContent='Enter 6 digits';return;}const r=await fetch('/api/pair/verify-pin',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({pin})});const j=await r.json();if(j&&j.ok)location.href='/';else err.textContent=(j&&j.error)||'Invalid PIN';}</script></body></html>";
        }

        static string BuildPendingApprovalHtml(ConnectedPhoneDevice d)
        {
            return "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><meta http-equiv=\"refresh\" content=\"3\"><title>Waiting Approval</title>" +
                "<style>body{background:#09090b;color:#f4f4f5;font-family:-apple-system,Segoe UI,sans-serif;display:flex;align-items:center;justify-content:center;min-height:90vh;margin:0;text-align:center;padding:24px}.card{max-width:340px;background:#121215;border:1px solid rgba(255,255,255,.1);border-radius:14px;padding:24px}</style></head>" +
                "<body><div class=\"card\"><h3>Approval Requested</h3><p style=\"color:#a1a1aa;font-size:13px\">Click <b>Approve</b> for <b>" + WebUtility.HtmlEncode(d.Name) + "</b> (" + WebUtility.HtmlEncode(d.IpAddress) + ") inside MicroCode on your PC.</p></div></body></html>";
        }

        static string BuildCompanionHtml(string tokenValue)
        {
            return "<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover\">" +
                "<meta name=\"apple-mobile-web-app-capable\" content=\"yes\"><meta name=\"theme-color\" content=\"#141417\"><link rel=\"manifest\" href=\"/manifest.json\"><link rel=\"apple-touch-icon\" href=\"/apple-touch-icon.png\">" +
                "<title>MicroCode AI</title><style>" +
                ":root{--bg:#0d0d0f;--panel:#141417;--surface:#1b1b20;--border:rgba(255,255,255,.08);--text:#ededf0;--secondary:#9898a0;--muted:#686870;--green:#22c55e;--mono:ui-monospace,Consolas,monospace;--sans:-apple-system,Segoe UI,Inter,sans-serif}" +
                "*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font-family:var(--sans);display:flex;flex-direction:column;height:100dvh;overflow:hidden}" +
                "header{padding:max(8px,env(safe-area-inset-top)) 10px 8px;background:var(--panel);border-bottom:1px solid var(--border);display:flex;align-items:center;justify-content:space-between;gap:6px}" +
                ".pill{background:var(--surface);border:1px solid var(--border);color:var(--text);border-radius:7px;padding:5px 9px;font-size:12px;cursor:pointer;display:inline-flex;align-items:center;gap:6px;max-width:45vw;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}" +
                "#chat{flex:1;overflow-y:auto;padding:12px;display:flex;flex-direction:column;gap:10px}" +
                ".turn-user{align-self:flex-end;background:#24242b;border:1px solid var(--border);padding:10px 13px;border-radius:12px;max-width:86%;font-size:14px;white-space:pre-wrap;word-break:break-word}" +
                ".turn-assistant{align-self:flex-start;background:var(--panel);border:1px solid var(--border);padding:11px 13px;border-radius:12px;max-width:94%;font-size:14px;line-height:1.5;white-space:pre-wrap;word-break:break-word}" +
                ".hdr{display:flex;align-items:center;gap:6px;font-size:11px;color:var(--secondary);margin-bottom:5px}" +
                ".card{background:var(--surface);border:1px solid var(--border);border-radius:10px;padding:10px 12px;margin:0 12px 6px;display:flex;align-items:center;justify-content:space-between;gap:8px;font-size:12px}" +
                "footer{padding:8px 10px max(10px,env(safe-area-inset-bottom));background:var(--panel);border-top:1px solid var(--border);display:flex;gap:6px;align-items:flex-end}" +
                "textarea{flex:1;background:var(--surface);color:var(--text);border:1px solid var(--border);border-radius:10px;padding:9px 11px;font-size:14px;resize:none;font-family:inherit;outline:none;max-height:120px}" +
                ".btn{background:var(--text);color:var(--bg);border:none;border-radius:9px;padding:8px 13px;font-weight:600;font-size:13px;cursor:pointer}" +
                ".btn-sec{background:var(--surface);color:var(--text);border:1px solid var(--border);border-radius:8px;padding:5px 9px;font-size:11.5px;cursor:pointer}" +
                ".modal{position:fixed;inset:0;background:rgba(0,0,0,.65);display:none;align-items:flex-end;justify-content:center;z-index:50}" +
                ".sheet{width:100%;max-width:560px;max-height:76vh;background:var(--panel);border-top:1px solid var(--border);border-radius:14px 14px 0 0;padding:14px;overflow-y:auto;display:flex;flex-direction:column;gap:8px}" +
                "</style></head><body>" +
                "<header><div style=\"display:flex;align-items:center;gap:6px;min-width:0\">" +
                "<span id=\"connDot\" style=\"width:8px;height:8px;border-radius:50%;background:#22c55e;flex-shrink:0\"></span>" +
                "<button class=\"pill\" onclick=\"openWsModal()\"><span id=\"wsLbl\">Workspace</span></button>" +
                "</div><div style=\"display:flex;align-items:center;gap:6px\">" +
                "<button class=\"pill\" onclick=\"openModelModal()\"><span id=\"modelLbl\">Model</span></button>" +
                "<button class=\"btn-sec\" onclick=\"openToolsModal()\">Tools</button></div></header>" +
                "<div id=\"banners\"></div><div id=\"chat\"></div>" +
                "<footer><input id=\"fileInp\" type=\"file\" multiple style=\"display:none\" onchange=\"stageFiles(this.files)\"><button class=\"btn-sec\" onclick=\"document.getElementById('fileInp').click()\">+</button>" +
                "<textarea id=\"promptInput\" rows=\"1\" placeholder=\"Message MicroCode…\"></textarea>" +
                "<button id=\"stopBtn\" class=\"btn-sec\" style=\"display:none\" onclick=\"api('/api/stop',{})\">Stop</button>" +
                "<button id=\"sendBtn\" class=\"btn\" onclick=\"sendPrompt()\">Send</button></footer>" +
                "<div id=\"wsModal\" class=\"modal\" onclick=\"if(event.target===this)this.style.display='none'\"><div class=\"sheet\"><div style=\"display:flex;justify-content:space-between;align-items:center\"><b>Workspaces &amp; Chats</b><button class=\"btn-sec\" onclick=\"api('/api/session/new',{}).then(()=>{document.getElementById('wsModal').style.display='none';pollState();})\">+ New Chat</button></div><div id=\"wsBody\"></div></div></div>" +
                "<div id=\"modelModal\" class=\"modal\" onclick=\"if(event.target===this)this.style.display='none'\"><div class=\"sheet\"><b>Select Model</b><div id=\"modelBody\"></div></div></div>" +
                "<div id=\"toolsModal\" class=\"modal\" onclick=\"if(event.target===this)this.style.display='none'\"><div class=\"sheet\"><b>PC Tools (Git · Terminal · Files)</b>" +
                "<div style=\"display:flex;gap:6px\"><input id=\"cmdInp\" placeholder=\"Command (e.g. git status)\" style=\"flex:1;background:var(--surface);color:var(--text);border:1px solid var(--border);border-radius:8px;padding:7px\"><button class=\"btn-sec\" onclick=\"runTerm()\">Run</button></div>" +
                "<pre id=\"toolOut\" style=\"background:#09090b;padding:10px;border-radius:8px;font-family:var(--mono);font-size:11.5px;white-space:pre-wrap;margin:0\"></pre>" +
                "<div style=\"display:flex;gap:6px\"><button class=\"btn-sec\" onclick=\"gitAct('pull')\">git pull</button><button class=\"btn-sec\" onclick=\"gitAct('push')\">git push</button><button class=\"btn-sec\" onclick=\"searchFiles()\">Browse Files</button></div></div></div>" +
                "<script>" +
                "const TOKEN = \"" + tokenValue + "\";" +
                "const CACHE_KEY='mc_cached_state_v1', OUTBOX_KEY='mc_outbox_queue_v1';" +
                "let sseConnected=false, failCount=0, lastKey='', lastState=null, staged=[];" +
                "function esc(s){return String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}" +
                "async function api(p,b){const sep=p.includes('?')?'&':'?';const r=await fetch(p+sep+'token='+encodeURIComponent(TOKEN),{method:b?'POST':'GET',headers:{'Content-Type':'application/json','X-Companion-Token':TOKEN},body:b?JSON.stringify(b):undefined});return r.json();}" +
                "function loadOutbox(){try{return JSON.parse(localStorage.getItem(OUTBOX_KEY)||'[]')||[];}catch(_){return[];}}" +
                "function saveOutbox(x){try{localStorage.setItem(OUTBOX_KEY,JSON.stringify(x||[]));}catch(_){}}" +
                "async function flushOutbox(){const q=loadOutbox();if(!q.length)return;const rem=[];for(let i=0;i<q.length;i++){try{const res=await api('/api/send',q[i]);if(!res||!res.ok)rem.push(q[i]);}catch(_){for(let j=i;j<q.length;j++)rem.push(q[j]);break;}}saveOutbox(rem);pollState();}" +
                "function stageFiles(files){for(const f of files){const fr=new FileReader();fr.onload=()=>{const b64=String(fr.result||'').split(',')[1]||'';staged.push({name:f.name,mimeType:f.type||'application/octet-stream',dataBase64:b64});};fr.readAsDataURL(f);}}" +
                "function applyState(s){lastState=s;failCount=0;try{localStorage.setItem(CACHE_KEY,JSON.stringify(s));}catch(_){}document.getElementById('connDot').style.background='#22c55e';" +
                "document.getElementById('wsLbl').textContent=(s.workspace||'Workspace')+' · '+(s.sessionTitle||'Chat');document.getElementById('modelLbl').textContent=s.modelLabel||'Model';" +
                "document.getElementById('stopBtn').style.display=s.isLoading?'inline-block':'none';" +
                "let bHtml='';if(s.pendingTool)bHtml+='<div class=\"card\"><span>Approve <b>'+esc(s.pendingTool.toolName)+'</b>?</span><div style=\"display:flex;gap:6px\"><button class=\"btn-sec\" onclick=\"api(\\'/api/tool/reject\\',{})\">Deny</button><button class=\"btn\" onclick=\"api(\\'/api/tool/approve\\',{})\">Allow</button></div></div>';" +
                "if(s.plan&&s.plan.state==='pending')bHtml+='<div class=\"card\"><span>Plan Ready</span><div style=\"display:flex;gap:6px\"><button class=\"btn-sec\" onclick=\"api(\\'/api/plan/reject\\',{})\">Reject</button><button class=\"btn\" onclick=\"api(\\'/api/plan/approve\\',{})\">Proceed</button></div></div>';" +
                "document.getElementById('banners').innerHTML=bHtml;" +
                "const q=loadOutbox();const key=JSON.stringify(s.messages||[])+'|'+JSON.stringify(q);if(key!==lastKey){lastKey=key;const msgs=(s.messages||[]).slice();for(const x of q)msgs.push({role:'user',content:x.prompt+'\\n[queued offline]'});" +
                "const el=document.getElementById('chat');el.innerHTML=msgs.map(m=>m.role==='user'?('<div class=\"turn-user\">'+esc(m.content)+'</div>'):('<div class=\"turn-assistant\"><div class=\"hdr\"><span>'+esc(m.modelLabel||s.modelLabel||'')+'</span></div>'+esc(m.content)+'</div>')).join('');el.scrollTop=el.scrollHeight;}}" +
                "async function sendPrompt(){const inp=document.getElementById('promptInput');const t=inp.value.trim();if(!t&&!staged.length)return;const atts=staged.slice();staged=[];inp.value='';try{const r=await api('/api/send',{prompt:t,attachments:atts});if(!r||!r.ok)throw 0;pollState();}catch(_){const q=loadOutbox();q.push({prompt:t,attachments:atts});saveOutbox(q);if(lastState)applyState(lastState);}}" +
                "async function pollState(){try{const s=await api('/api/state');applyState(s);if(loadOutbox().length)flushOutbox();}catch(_){failCount++;if(!sseConnected&&failCount>=3)document.getElementById('connDot').style.background='#f59e0b';}}" +
                "function connectSSE(){if(typeof EventSource==='undefined')return;try{const es=new EventSource('/api/stream?token='+encodeURIComponent(TOKEN));es.onopen=()=>{sseConnected=true;flushOutbox();};es.onmessage=(e)=>{try{applyState(JSON.parse(e.data));}catch(_){}};es.onerror=()=>{sseConnected=false;es.close();setTimeout(connectSSE,1100);};}catch(_){}}" +
                "function openWsModal(){document.getElementById('wsModal').style.display='flex';const wb=document.getElementById('wsBody');const ws=(lastState&&lastState.workspaces)||[];wb.innerHTML=ws.map(w=>'<div><b>'+esc(w.name)+'</b>'+(w.chats||[]).map(c=>'<div style=\"padding:6px;border-bottom:1px solid var(--border);cursor:pointer\" onclick=\"api(\\'/api/session/switch\\',{sessionId:\\''+esc(c.id)+'\\'}).then(()=>{document.getElementById(\\'wsModal\\').style.display=\\'none\\';pollState();})\">'+esc(c.name)+'</div>').join('')+'</div>').join('');}" +
                "async function openModelModal(){document.getElementById('modelModal').style.display='flex';const res=await api('/api/models');const ms=(res&&res.models)||[];document.getElementById('modelBody').innerHTML=ms.map(m=>'<div style=\"padding:8px;border-bottom:1px solid var(--border);cursor:pointer\" onclick=\"api(\\'/api/model/select\\',{mode:\\''+esc(m.mode)+'\\',provider:\\''+esc(m.provider)+'\\',modelId:\\''+esc(m.id)+'\\'}).then(()=>{document.getElementById(\\'modelModal\\').style.display=\\'none\\';pollState();})\"><b>'+esc(m.name)+'</b> <span style=\"color:var(--secondary);font-size:11px\">('+esc(m.provider)+')</span></div>').join('');}" +
                "function openToolsModal(){document.getElementById('toolsModal').style.display='flex';}" +
                "async function runTerm(){const c=document.getElementById('cmdInp').value;const r=await api('/api/terminal/exec',{command:c});document.getElementById('toolOut').textContent=(r&&r.output)||'';}" +
                "async function gitAct(a){const r=await api('/api/git/action',{action:a});document.getElementById('toolOut').textContent=(r&&r.output)||'Done';}" +
                "async function searchFiles(){const r=await api('/api/files/search?q=');document.getElementById('toolOut').textContent=((r&&r.files)||[]).map(f=>f.path).join('\\n');}" +
                "if('serviceWorker'in navigator)navigator.serviceWorker.register('/sw.js').catch(()=>{});" +
                "window.addEventListener('online',flushOutbox);try{const cr=localStorage.getItem(CACHE_KEY);if(cr)applyState(JSON.parse(cr));}catch(_){}" +
                "connectSSE();pollState();setInterval(()=>{if(!document.hidden&&!sseConnected)pollState();},1500);" +
                "</script></body></html>";
        }
    }
}
