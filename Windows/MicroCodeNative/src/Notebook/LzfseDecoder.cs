// Decoder for Apple's LZFSE container (NSData.compressed(using: .lzfse)), written from the published LZFSE reference
// (lzfse_decode_base.c, lzfse_fse.h, lzvn_decode_base.c). The Mac app saves .mic notebooks with it; this lets Windows open them.
// Handles stored (bvx-), FSE-compressed v1/v2 (bvx1/bvx2) and LZVN (bvxn) blocks. Malformed input throws InvalidDataException.
using System;
using System.Collections.Generic;
using System.IO;

namespace MicroCode.Views
{
    public static class LzfseDecoder
    {
        const uint MagicEnd = 0x24787662, MagicStored = 0x2d787662, MagicV1 = 0x31787662, MagicV2 = 0x32787662, MagicLzvn = 0x6e787662;
        const int LSymbols = 20, MSymbols = 20, DSymbols = 64, LitSymbols = 256;
        const int LStates = 64, MStates = 64, DStates = 256, LitStates = 1024;
        const int LiteralsPerBlock = 4 * 10000;

        static readonly byte[] LExtra = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 3, 5, 8 };
        static readonly int[] LBase = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 20, 28, 60 };
        static readonly byte[] MExtra = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 5, 8, 11 };
        static readonly int[] MBase = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 24, 56, 312 };
        static readonly byte[] DExtra =
        {
            0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6, 6, 7, 7, 7, 7,
            8, 8, 8, 8, 9, 9, 9, 9, 10, 10, 10, 10, 11, 11, 11, 11, 12, 12, 12, 12, 13, 13, 13, 13, 14, 14, 14, 14, 15, 15, 15, 15
        };
        static readonly int[] DBase =
        {
            0, 1, 2, 3, 4, 6, 8, 10, 12, 16, 20, 24, 28, 36, 44, 52, 60, 76, 92, 108, 124, 156, 188, 220, 252, 316, 380, 444, 508, 636,
            764, 892, 1020, 1276, 1532, 1788, 2044, 2556, 3068, 3580, 4092, 5116, 6140, 7164, 8188, 10236, 12284, 14332, 16380, 20476,
            24572, 28668, 32764, 40956, 49148, 57340, 65532, 81916, 98300, 114684, 131068, 163836, 196604, 229372
        };

        static Exception Bad(string why) { return new InvalidDataException("Invalid LZFSE data: " + why); }
        static uint U32(byte[] b, int at) { if (at < 0 || at + 4 > b.Length) throw Bad("truncated"); return BitConverter.ToUInt32(b, at); }
        static ulong U64(byte[] b, int at) { if (at < 0 || at + 8 > b.Length) throw Bad("truncated"); return BitConverter.ToUInt64(b, at); }

        public static byte[] Decode(byte[] src)
        {
            var dst = new List<byte>(Math.Max(1024, src.Length * 4));
            int p = 0;
            while (true)
            {
                uint magic = U32(src, p);
                if (magic == MagicEnd) return dst.ToArray();
                if (magic == MagicStored)
                {
                    int n = checked((int)U32(src, p + 4));
                    if (p + 8 + n > src.Length) throw Bad("stored block truncated");
                    for (int i = 0; i < n; i++) dst.Add(src[p + 8 + i]);
                    p += 8 + n;
                }
                else if (magic == MagicLzvn)
                {
                    int raw = checked((int)U32(src, p + 4)), payload = checked((int)U32(src, p + 8));
                    if (p + 12 + payload > src.Length) throw Bad("LZVN block truncated");
                    int before = dst.Count;
                    Lzvn(src, p + 12, p + 12 + payload, dst, before + raw);
                    if (dst.Count != before + raw) throw Bad("LZVN block size mismatch");
                    p += 12 + payload;
                }
                else if (magic == MagicV1 || magic == MagicV2) p = FseBlock(src, p, magic, dst);
                else throw Bad("unknown block 0x" + magic.ToString("x8"));
            }
        }

        // ── FSE-compressed block ────────────────────────────────────────────
        class Header
        {
            public int NRaw, NLiterals, NMatches, NLitPayload, NLmdPayload, LitBits, LmdBits, LState, MState, DState;
            public int[] LitState = new int[4];
            public ushort[] LFreq = new ushort[LSymbols], MFreq = new ushort[MSymbols], DFreq = new ushort[DSymbols], LitFreq = new ushort[LitSymbols];
        }

        static int Field(ulong v, int offset, int nbits) { return nbits == 32 ? (int)(uint)(v >> offset) : (int)((v >> offset) & ((1UL << nbits) - 1)); }

        static readonly sbyte[] FreqNBits = { 2, 3, 2, 5, 2, 3, 2, 8, 2, 3, 2, 5, 2, 3, 2, 14, 2, 3, 2, 5, 2, 3, 2, 8, 2, 3, 2, 5, 2, 3, 2, 14 };
        static readonly sbyte[] FreqValue = { 0, 2, 1, 4, 0, 3, 1, -1, 0, 2, 1, 5, 0, 3, 1, -1, 0, 2, 1, 6, 0, 3, 1, -1, 0, 2, 1, 7, 0, 3, 1, -1 };

        static int FreqDecode(uint bits, out int nbits)
        {
            uint b = bits & 31;
            nbits = FreqNBits[b];
            if (nbits == 8) return 8 + (int)((bits >> 4) & 0xf);
            if (nbits == 14) return 24 + (int)((bits >> 4) & 0x3ff);
            return FreqValue[b];
        }

        static int FseBlock(byte[] src, int p, uint magic, List<byte> dst)
        {
            var h = new Header();
            int headerSize;
            h.NRaw = checked((int)U32(src, p + 4));
            if (magic == MagicV2)
            {
                ulong v0 = U64(src, p + 8), v1 = U64(src, p + 16), v2 = U64(src, p + 24);
                headerSize = Field(v2, 0, 32);
                if (p + headerSize > src.Length || headerSize < 32) throw Bad("v2 header truncated");
                h.NLiterals = Field(v0, 0, 20); h.NLitPayload = Field(v0, 20, 20); h.NMatches = Field(v0, 40, 20); h.LitBits = Field(v0, 60, 3) - 7;
                for (int i = 0; i < 4; i++) h.LitState[i] = Field(v1, 10 * i, 10);
                h.NLmdPayload = Field(v1, 40, 20); h.LmdBits = Field(v1, 60, 3) - 7;
                h.LState = Field(v2, 32, 10); h.MState = Field(v2, 42, 10); h.DState = Field(v2, 52, 10);
                // frequency tables: variable-length codes packed LSB-first after the fixed fields
                int s = p + 32, end = p + headerSize;
                if (s != end)
                {
                    uint accum = 0; int accumBits = 0;
                    for (int i = 0; i < LSymbols + MSymbols + DSymbols + LitSymbols; i++)
                    {
                        while (s < end && accumBits + 8 <= 32) { accum |= (uint)src[s] << accumBits; accumBits += 8; s++; }
                        int nb; int v = FreqDecode(accum, out nb);
                        if (nb > accumBits) throw Bad("frequency table");
                        SetFreq(h, i, v);
                        accum >>= nb; accumBits -= nb;
                    }
                    if (accumBits >= 8 || s != end) throw Bad("frequency table length");
                }
            }
            else
            {
                // v1: fixed struct of 32-bit counts, 16-bit states and 16-bit frequency tables
                // 770 bytes of fields, padded to the struct's 4-byte alignment (sizeof(lzfse_compressed_block_header_v1) == 772)
                headerSize = 772;
                if (p + headerSize > src.Length) throw Bad("v1 header truncated");
                int q = p + 8;
                q += 4; // n_payload_bytes
                h.NLiterals = (int)U32(src, q); q += 4; h.NMatches = (int)U32(src, q); q += 4;
                h.NLitPayload = (int)U32(src, q); q += 4; h.NLmdPayload = (int)U32(src, q); q += 4;
                h.LitBits = BitConverter.ToInt32(src, q); q += 4;
                for (int i = 0; i < 4; i++) { h.LitState[i] = BitConverter.ToUInt16(src, q); q += 2; }
                h.LmdBits = BitConverter.ToInt32(src, q); q += 4;
                h.LState = BitConverter.ToUInt16(src, q); q += 2; h.MState = BitConverter.ToUInt16(src, q); q += 2; h.DState = BitConverter.ToUInt16(src, q); q += 2;
                for (int i = 0; i < LSymbols + MSymbols + DSymbols + LitSymbols; i++) { SetFreq(h, i, BitConverter.ToUInt16(src, q)); q += 2; }
            }
            if (h.NLiterals > LiteralsPerBlock || h.NLiterals % 4 != 0 || h.LitBits < -7 || h.LitBits > 0 || h.LmdBits < -7 || h.LmdBits > 0) throw Bad("block header");
            if (h.LitState[0] >= LitStates || h.LitState[1] >= LitStates || h.LitState[2] >= LitStates || h.LitState[3] >= LitStates) throw Bad("literal state");
            if (h.LState >= LStates || h.MState >= MStates || h.DState >= DStates) throw Bad("LMD state");
            int payload = p + headerSize;
            if (payload + h.NLitPayload + h.NLmdPayload > src.Length) throw Bad("block payload truncated");

            var litTable = LiteralTable(LitStates, h.LitFreq);
            var lTable = ValueTable(LStates, h.LFreq, LExtra, LBase);
            var mTable = ValueTable(MStates, h.MFreq, MExtra, MBase);
            var dTable = ValueTable(DStates, h.DFreq, DExtra, DBase);

            // literals: four interleaved FSE states, bits read backwards from the end of the literal payload
            var literals = new byte[LiteralsPerBlock + 64];
            var lin = new BitIn(src, payload, payload + h.NLitPayload, h.LitBits);
            int s0 = h.LitState[0], s1 = h.LitState[1], s2 = h.LitState[2], s3 = h.LitState[3];
            for (int i = 0; i < h.NLiterals; i += 4)
            {
                lin.Flush();
                literals[i] = DecodeLit(ref s0, litTable, lin);
                literals[i + 1] = DecodeLit(ref s1, litTable, lin);
                literals[i + 2] = DecodeLit(ref s2, litTable, lin);
                literals[i + 3] = DecodeLit(ref s3, litTable, lin);
            }

            // L, M, D triples
            int lmdStart = payload + h.NLitPayload;
            var lmd = new BitIn(src, lmdStart, lmdStart + h.NLmdPayload, h.LmdBits);
            int ls = h.LState, ms = h.MState, ds = h.DState, lit = 0, D = -1;
            int blockStart = dst.Count;
            for (int n = 0; n < h.NMatches; n++)
            {
                lmd.Flush();
                int L = DecodeValue(ref ls, lTable, lmd);
                int M = DecodeValue(ref ms, mTable, lmd);
                int nd = DecodeValue(ref ds, dTable, lmd);
                if (nd != 0) D = nd;
                if (lit + L > h.NLiterals || lit + L > literals.Length) throw Bad("literal overrun");
                for (int i = 0; i < L; i++) dst.Add(literals[lit + i]);
                lit += L;
                if (M > 0)
                {
                    if (D <= 0 || D > dst.Count) throw Bad("match distance");
                    int from = dst.Count - D;
                    for (int i = 0; i < M; i++) dst.Add(dst[from + i]);
                }
                if (dst.Count - blockStart > h.NRaw) throw Bad("block expands past its size");
            }
            if (dst.Count - blockStart != h.NRaw) throw Bad("block size mismatch");
            return payload + h.NLitPayload + h.NLmdPayload;
        }

        static void SetFreq(Header h, int i, int v)
        {
            if (i < LSymbols) h.LFreq[i] = (ushort)v;
            else if (i < LSymbols + MSymbols) h.MFreq[i - LSymbols] = (ushort)v;
            else if (i < LSymbols + MSymbols + DSymbols) h.DFreq[i - LSymbols - MSymbols] = (ushort)v;
            else h.LitFreq[i - LSymbols - MSymbols - DSymbols] = (ushort)v;
        }

        static int Clz(uint x) { if (x == 0) return 32; int n = 0; while ((x & 0x80000000u) == 0) { n++; x <<= 1; } return n; }

        struct LitEntry { public int K, Delta; public byte Symbol; }
        struct ValEntry { public int TotalBits, ValueBits, Delta, VBase; }

        static LitEntry[] LiteralTable(int nstates, ushort[] freq)
        {
            var t = new LitEntry[nstates];
            int nclz = Clz((uint)nstates), sum = 0, at = 0;
            for (int i = 0; i < freq.Length; i++)
            {
                int f = freq[i];
                if (f == 0) continue;
                sum += f;
                if (sum > nstates) throw Bad("literal frequencies");
                int k = Clz((uint)f) - nclz, j0 = ((2 * nstates) >> k) - f;
                for (int j = 0; j < f; j++)
                {
                    var e = new LitEntry { Symbol = (byte)i };
                    if (j < j0) { e.K = k; e.Delta = ((f + j) << k) - nstates; }
                    else { e.K = k - 1; e.Delta = (j - j0) << (k - 1); }
                    t[at++] = e;
                }
            }
            return t;
        }

        static ValEntry[] ValueTable(int nstates, ushort[] freq, byte[] vbits, int[] vbase)
        {
            var t = new ValEntry[nstates];
            int nclz = Clz((uint)nstates), sum = 0, at = 0;
            for (int i = 0; i < freq.Length; i++)
            {
                int f = freq[i];
                if (f == 0) continue;
                sum += f;
                if (sum > nstates) throw Bad("value frequencies");
                int k = Clz((uint)f) - nclz, j0 = ((2 * nstates) >> k) - f;
                for (int j = 0; j < f; j++)
                {
                    var e = new ValEntry { ValueBits = vbits[i], VBase = vbase[i] };
                    if (j < j0) { e.TotalBits = k + e.ValueBits; e.Delta = ((f + j) << k) - nstates; }
                    else { e.TotalBits = k - 1 + e.ValueBits; e.Delta = (j - j0) << (k - 1); }
                    t[at++] = e;
                }
            }
            return t;
        }

        static byte DecodeLit(ref int state, LitEntry[] table, BitIn input)
        {
            if (state < 0 || state >= table.Length) throw Bad("literal state");
            var e = table[state];
            state = e.Delta + (int)input.Pull(e.K);
            return e.Symbol;
        }

        static int DecodeValue(ref int state, ValEntry[] table, BitIn input)
        {
            if (state < 0 || state >= table.Length) throw Bad("LMD state");
            var e = table[state];
            uint bits = (uint)input.Pull(e.TotalBits);
            state = e.Delta + (int)(bits >> e.ValueBits);
            return e.VBase + (int)(e.ValueBits == 0 ? 0 : bits & ((1u << e.ValueBits) - 1));
        }

        /// <summary>fse_in_stream64: bits are consumed from the end of the payload towards its start; the accumulator keeps 56..63 bits.</summary>
        class BitIn
        {
            readonly byte[] _b;
            readonly int _start;
            int _pos;
            ulong _accum;
            int _nbits;

            public BitIn(byte[] b, int start, int end, int n)
            {
                _b = b; _start = start; _pos = end;
                if (n != 0)
                {
                    if (_pos < start + 8) throw Bad("bit stream too short");
                    _pos -= 8; _accum = BitConverter.ToUInt64(b, _pos); _nbits = n + 64;
                }
                else
                {
                    if (_pos < start + 7) throw Bad("bit stream too short");
                    _pos -= 7; _accum = 0;
                    for (int i = 0; i < 7; i++) _accum |= (ulong)b[_pos + i] << (8 * i);
                    _nbits = 56;
                }
                if (_nbits < 56 || _nbits >= 64 || (_accum >> _nbits) != 0) throw Bad("bit stream header");
            }

            public void Flush()
            {
                int nbits = (63 - _nbits) & ~7;
                int pos = _pos - (nbits >> 3);
                if (pos < _start) throw Bad("bit stream underrun");
                _pos = pos;
                if (nbits == 0) return;
                ulong incoming = 0;
                for (int i = 0; i < 8 && pos + i < _b.Length; i++) incoming |= (ulong)_b[pos + i] << (8 * i);
                _accum = (_accum << nbits) | (incoming & ((1UL << nbits) - 1));
                _nbits += nbits;
            }

            public ulong Pull(int n)
            {
                if (n < 0 || n > _nbits) throw Bad("bit stream overrun");
                _nbits -= n;
                ulong result = _accum >> _nbits;
                _accum = _nbits == 0 ? 0 : _accum & ((1UL << _nbits) - 1);
                return result;
            }
        }

        // ── LZVN block (used by Apple for small inputs) ─────────────────────
        static void Lzvn(byte[] src, int p, int end, List<byte> dst, int dstLimit)
        {
            int D = 0;
            while (p < end)
            {
                int opc = src[p];
                int L = 0, M = 0, len;
                switch (Kind(opc))
                {
                    case 'e': return;                                   // end of stream (followed by 7 zero bytes)
                    case 'n': p += 1; continue;                         // nop
                    case 's': len = 2; L = (opc >> 6) & 3; M = ((opc >> 3) & 7) + 3; Need(p, len + L, end); D = ((opc & 7) << 8) | src[p + 1]; break;
                    case 'p': len = 1; L = (opc >> 6) & 3; M = ((opc >> 3) & 7) + 3; Need(p, len + L, end); break;
                    case 'l': len = 3; L = (opc >> 6) & 3; M = ((opc >> 3) & 7) + 3; Need(p, len + L, end); D = src[p + 1] | (src[p + 2] << 8); break;
                    case 'm':
                        len = 3; L = (opc >> 3) & 3; Need(p, len + L, end);
                        int opc23 = src[p + 1] | (src[p + 2] << 8);
                        M = (((opc & 7) << 2) | (opc23 & 3)) + 3; D = opc23 >> 2; break;
                    case 'L': len = 1; L = opc & 15; Need(p, len + L, end); break;
                    case 'B': len = 2; Need(p, 2, end); L = src[p + 1] + 16; Need(p, len + L, end); break;
                    case 'M': len = 1; M = opc & 15; break;
                    case 'N': len = 2; Need(p, 2, end); M = src[p + 1] + 16; break;
                    default: throw Bad("LZVN opcode 0x" + opc.ToString("x2"));
                }
                for (int i = 0; i < L; i++) dst.Add(src[p + len + i]);
                p += len + L;
                if (M > 0)
                {
                    if (D <= 0 || D > dst.Count) throw Bad("LZVN match distance");
                    int from = dst.Count - D;
                    for (int i = 0; i < M; i++) dst.Add(dst[from + i]);
                }
                if (dst.Count > dstLimit) throw Bad("LZVN output overrun");
            }
            throw Bad("LZVN stream has no end marker");
        }

        static void Need(int p, int n, int end) { if (p + n > end) throw Bad("LZVN truncated"); }

        /// <summary>LZVN opcode classes from lzvn_decode_base.c's jump table.</summary>
        static char Kind(int opc)
        {
            if (opc == 0x06) return 'e';
            if (opc == 0x0e || opc == 0x16) return 'n';
            if (opc >= 0xa0 && opc <= 0xbf) return 'm';             // 101LLMMM medium distance
            if (opc == 0xe0) return 'B';                             // large literal
            if (opc > 0xe0 && opc <= 0xef) return 'L';               // small literal
            if (opc == 0xf0) return 'N';                             // large match
            if (opc > 0xf0) return 'M';                              // small match
            if ((opc >= 0x70 && opc <= 0x7f) || (opc >= 0xd0 && opc <= 0xdf)) return '?';
            int low = opc & 7;
            if (low == 7) return 'l';                                // LLMMM111 large distance
            if (low == 6) return (opc >> 3) >= 8 ? 'p' : '?';         // LLMMM110 previous distance (0x06/0x0e/0x16 handled above)
            return 's';                                              // LLMMMDDD small distance
        }
    }
}
