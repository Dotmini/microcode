// Port of CollaborativeThreeWayMerger (CollaborationService.swift): deterministic line-based 3-way merge used when a
// collaborator's edit was made against an older revision. Non-overlapping concurrent edits are all kept, identical edits
// are deduplicated, two pure insertions at the same place are both kept, and overlapping edits resolve to the incoming
// side — never "<<<<<<<" markers in live source.
using System;
using System.Collections.Generic;
using System.Linq;

namespace MicroCode.Views
{
    public static class CollabMerge
    {
        public class Hunk
        {
            public int BaseStart, BaseEnd; // [start, end) in base lines
            public List<string> Replacement;
            public bool IsPureInsertion { get { return BaseStart == BaseEnd; } }
        }

        public class Result { public string Merged; public bool DidAutoMerge; }

        public static Result Merge(string baseText, string current, string incoming)
        {
            if (incoming == current) return new Result { Merged = current };
            if (baseText == current) return new Result { Merged = incoming };
            if (baseText == incoming) return new Result { Merged = current, DidAutoMerge = true };
            var b = baseText.Split('\n'); var c = current.Split('\n'); var n = incoming.Split('\n');
            // guard against pathological diff cost on very large generated files
            if (b.Length + c.Length + n.Length > 12000) return new Result { Merged = incoming };
            var ha = ComputeHunks(b, c);
            var hb = ComputeHunks(b, n);
            var output = new List<string>();
            int cursor = 0, i = 0, j = 0;
            Action<int, int> copyBase = (from, to) => { for (int k = from; k < to; k++) output.Add(b[k]); };
            while (i < ha.Count || j < hb.Count)
            {
                if (i < ha.Count && j < hb.Count)
                {
                    var a = ha[i]; var x = hb[j];
                    if (Before(a, x)) { copyBase(cursor, a.BaseStart); output.AddRange(a.Replacement); cursor = a.BaseEnd; i++; }
                    else if (Before(x, a)) { copyBase(cursor, x.BaseStart); output.AddRange(x.Replacement); cursor = x.BaseEnd; j++; }
                    else if (a.IsPureInsertion && x.IsPureInsertion && a.BaseStart == x.BaseStart)
                    {
                        copyBase(cursor, a.BaseStart);
                        output.AddRange(a.Replacement);
                        if (!a.Replacement.SequenceEqual(x.Replacement)) output.AddRange(x.Replacement);
                        cursor = a.BaseEnd; i++; j++;
                    }
                    else
                    {
                        // transitive overlapping cluster [spanStart, spanEnd): the incoming side wins
                        int spanStart = Math.Min(a.BaseStart, x.BaseStart), spanEnd = Math.Max(a.BaseEnd, x.BaseEnd);
                        int endI = i + 1, endJ = j + 1;
                        bool expanded = true;
                        while (expanded)
                        {
                            expanded = false;
                            while (endI < ha.Count && ha[endI].BaseStart < spanEnd) { spanEnd = Math.Max(spanEnd, ha[endI].BaseEnd); endI++; expanded = true; }
                            while (endJ < hb.Count && hb[endJ].BaseStart < spanEnd) { spanEnd = Math.Max(spanEnd, hb[endJ].BaseEnd); endJ++; expanded = true; }
                        }
                        copyBase(cursor, spanStart);
                        int pos = spanStart;
                        for (int k = j; k < endJ; k++) { copyBase(pos, hb[k].BaseStart); output.AddRange(hb[k].Replacement); pos = hb[k].BaseEnd; }
                        copyBase(pos, spanEnd);
                        cursor = spanEnd; i = endI; j = endJ;
                    }
                }
                else if (i < ha.Count) { var a = ha[i]; copyBase(cursor, a.BaseStart); output.AddRange(a.Replacement); cursor = a.BaseEnd; i++; }
                else { var x = hb[j]; copyBase(cursor, x.BaseStart); output.AddRange(x.Replacement); cursor = x.BaseEnd; j++; }
            }
            copyBase(cursor, b.Length);
            string merged = string.Join("\n", output);
            return new Result { Merged = merged, DidAutoMerge = merged != incoming };
        }

        static bool Before(Hunk first, Hunk second)
        {
            if (first.BaseEnd < second.BaseStart) return true;
            // touching hunks are disjoint unless both are pure insertions at the same offset
            if (first.BaseEnd == second.BaseStart) return !(first.IsPureInsertion && second.IsPureInsertion);
            return false;
        }

        /// <summary>Hunks between base and target from an LCS line alignment (the kept lines are the anchors); equal-length
        /// replaced runs are split into one-line hunks so a one-line change on each side of a block does not overlap.</summary>
        public static List<Hunk> ComputeHunks(string[] b, string[] t)
        {
            var anchors = Lcs(b, t);
            var hunks = new List<Hunk>();
            int prevB = -1, prevT = -1;
            Action<int, int, int, int> add = (bs, be, ts, te) =>
            {
                int bl = be - bs, tl = te - ts;
                if (bl > 1 && bl == tl)
                    for (int o = 0; o < bl; o++) hunks.Add(new Hunk { BaseStart = bs + o, BaseEnd = bs + o + 1, Replacement = new List<string> { t[ts + o] } });
                else hunks.Add(new Hunk { BaseStart = bs, BaseEnd = be, Replacement = t.Skip(ts).Take(te - ts).ToList() });
            };
            foreach (var pr in anchors)
            {
                int bs = prevB + 1, ts = prevT + 1;
                if (bs < pr.Item1 || ts < pr.Item2) add(bs, pr.Item1, ts, pr.Item2);
                prevB = pr.Item1; prevT = pr.Item2;
            }
            if (prevB + 1 < b.Length || prevT + 1 < t.Length) add(prevB + 1, b.Length, prevT + 1, t.Length);
            return hunks;
        }

        /// <summary>Longest common subsequence of lines as (baseIndex, targetIndex) pairs; common prefix/suffix are trimmed
        /// first so typical edits cost little.</summary>
        static List<Tuple<int, int>> Lcs(string[] a, string[] b)
        {
            int pre = 0;
            while (pre < a.Length && pre < b.Length && a[pre] == b[pre]) pre++;
            int suf = 0;
            while (suf < a.Length - pre && suf < b.Length - pre && a[a.Length - 1 - suf] == b[b.Length - 1 - suf]) suf++;
            int n = a.Length - pre - suf, m = b.Length - pre - suf;
            var result = new List<Tuple<int, int>>();
            for (int k = 0; k < pre; k++) result.Add(Tuple.Create(k, k));
            // very large changed middles keep only the prefix/suffix anchors (one big hunk) instead of an n*m table
            if (n > 0 && m > 0 && (long)n * m <= 4000000)
            {
                var dp = new int[n + 1, m + 1];
                for (int x = n - 1; x >= 0; x--)
                    for (int y = m - 1; y >= 0; y--)
                        dp[x, y] = a[pre + x] == b[pre + y] ? dp[x + 1, y + 1] + 1 : Math.Max(dp[x + 1, y], dp[x, y + 1]);
                int p = 0, q = 0;
                while (p < n && q < m)
                {
                    if (a[pre + p] == b[pre + q]) { result.Add(Tuple.Create(pre + p, pre + q)); p++; q++; }
                    else if (dp[p + 1, q] >= dp[p, q + 1]) p++;
                    else q++;
                }
            }
            for (int k = suf; k > 0; k--) result.Add(Tuple.Create(a.Length - k, b.Length - k));
            return result;
        }
    }
}
