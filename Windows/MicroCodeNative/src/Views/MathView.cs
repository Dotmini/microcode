// Native TeX / LaTeX math — port of TeXMathEngine + TeXMath2DNodeView (AIAgentMarkdownAndCodeViews.swift): a recursive-descent
// LaTeX parser that lays out boxes directly — stacked fractions, radicals with index, sub/superscripts, big operators with limits,
// \left…\right delimiters, matrices / cases / aligned, accents, \text (Thai-capable) — drawn with Cambria Math. No WebView.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using MicroCode.Core;
using MicroCode.UI;

namespace MicroCode.Views
{
    abstract class MBox
    {
        public double W, A, D; // advance width, height above baseline, depth below baseline
        public abstract void Draw(DrawingContext dc, double x, double y); // y = baseline
    }

    sealed class SpaceBox : MBox
    {
        public SpaceBox(double w) { W = w; }
        public override void Draw(DrawingContext dc, double x, double y) { }
    }

    sealed class GlyphBox : MBox
    {
        readonly FormattedText _ft;
        readonly double _top;
        static readonly Dictionary<string, double[]> Ink = new Dictionary<string, double[]>();

        public GlyphBox(string s, Typeface tf, double size, Brush fg)
        {
            _ft = new FormattedText(s, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, tf, size, fg, 1.0);
            W = _ft.WidthIncludingTrailingWhitespace;
            _top = _ft.Baseline;
            string key = tf.FontFamily.Source + "|" + tf.Weight + "|" + size.ToString("0.##", CultureInfo.InvariantCulture) + "|" + s;
            double[] ink;
            if (!Ink.TryGetValue(key, out ink))
            {
                var b = _ft.BuildGeometry(new Point(0, 0)).Bounds;
                ink = b.IsEmpty ? new[] { 0.0, 0.0 } : new[] { Math.Max(0, _top - b.Top), Math.Max(0, b.Bottom - _top) };
                if (Ink.Count > 4000) Ink.Clear();
                Ink[key] = ink;
            }
            A = ink[0]; D = ink[1];
        }

        public override void Draw(DrawingContext dc, double x, double y) { dc.DrawText(_ft, new Point(x, y - _top)); }
    }

    sealed class HBox : MBox
    {
        public readonly List<MBox> Kids = new List<MBox>();
        public void Add(MBox b) { Kids.Add(b); W += b.W; A = Math.Max(A, b.A); D = Math.Max(D, b.D); }
        public override void Draw(DrawingContext dc, double x, double y) { foreach (var k in Kids) { k.Draw(dc, x, y); x += k.W; } }
    }

    /// <summary>Moves a box up (positive) or down relative to the baseline.</summary>
    sealed class RaiseBox : MBox
    {
        readonly MBox _b; readonly double _up;
        public RaiseBox(MBox b, double up) { _b = b; _up = up; W = b.W; A = b.A + up; D = b.D - up; }
        public override void Draw(DrawingContext dc, double x, double y) { _b.Draw(dc, x, y - _up); }
    }

    sealed class ScriptBox : MBox
    {
        readonly MBox _b, _sup, _sub; readonly double _u, _v, _gap;
        public ScriptBox(MBox b, MBox sup, MBox sub, double size)
        {
            _b = b; _sup = sup; _sub = sub; _gap = 0.04 * size;
            _u = sup == null ? 0 : Math.Max(0.38 * size, b.A - 0.30 * size);
            _v = sub == null ? 0 : Math.Max(sup != null ? 0.26 * size : 0.17 * size, b.D * 0.7);
            if (sup != null && sub != null)
            {
                double clear = (_u - sup.D) - (sub.A - _v);
                if (clear < 0.14 * size) _v += 0.14 * size - clear;
            }
            W = b.W + _gap + Math.Max(sup != null ? sup.W : 0, sub != null ? sub.W : 0) + 0.02 * size;
            A = Math.Max(b.A, sup != null ? _u + sup.A : 0);
            D = Math.Max(b.D, sub != null ? _v + sub.D : 0);
        }
        public override void Draw(DrawingContext dc, double x, double y)
        {
            _b.Draw(dc, x, y);
            if (_sup != null) _sup.Draw(dc, x + _b.W + _gap, y - _u);
            if (_sub != null) _sub.Draw(dc, x + _b.W + _gap * 0.5, y + _v);
        }
    }

    sealed class FracBox : MBox
    {
        readonly MBox _n, _d; readonly double _t, _axis, _nb, _db, _pad; readonly Brush _fg;
        public FracBox(MBox num, MBox den, double size, bool display, bool bar, Brush fg)
        {
            _n = num; _d = den; _fg = fg;
            _axis = 0.25 * size;
            _t = bar ? Math.Max(1.0, 0.055 * size) : 0;
            double gap = display ? 0.15 * size : 0.10 * size;
            if (!bar) gap += 0.06 * size;
            _nb = _axis + _t / 2 + gap + num.D;
            _db = _axis - _t / 2 - gap - den.A;
            _pad = 0.1 * size;
            W = Math.Max(num.W, den.W) + 2 * _pad;
            A = _nb + num.A; D = -_db + den.D;
        }
        public override void Draw(DrawingContext dc, double x, double y)
        {
            _n.Draw(dc, x + (W - _n.W) / 2, y - _nb);
            _d.Draw(dc, x + (W - _d.W) / 2, y - _db);
            if (_t > 0) dc.DrawRectangle(_fg, null, new Rect(x + _pad * 0.6, y - _axis - _t / 2, W - _pad * 1.2, _t));
        }
    }

    sealed class SqrtBox : MBox
    {
        readonly MBox _r, _idx; readonly double _t, _top, _depth, _signW, _idxX, _idxUp, _size; readonly Pen _pen;
        public SqrtBox(MBox rad, MBox idx, double size, Brush fg)
        {
            _r = rad; _idx = idx; _size = size;
            _t = Math.Max(1.0, 0.055 * size);
            _pen = new Pen(fg, _t) { LineJoin = PenLineJoin.Round, StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Flat };
            _top = Math.Max(rad.A, 0.62 * size) + 0.13 * size + _t;
            _depth = Math.Max(rad.D, 0.12 * size) + 0.06 * size;
            _signW = 0.5 * size + 0.08 * (_top + _depth);
            _idxX = 0;
            if (idx != null)
            {
                _idxUp = (_top + _depth) * 0.42 - _depth + idx.D;
                _idxX = Math.Max(0, idx.W - _signW * 0.45);
            }
            W = _idxX + _signW + rad.W + 0.12 * size;
            A = Math.Max(_top + _t / 2, idx != null ? _idxUp + idx.A : 0);
            D = _depth;
        }
        public override void Draw(DrawingContext dc, double x, double y)
        {
            double sx = x + _idxX, s = _size;
            var g = new StreamGeometry();
            using (var c = g.Open())
            {
                c.BeginFigure(new Point(sx, y - 0.24 * s), false, false);
                c.LineTo(new Point(sx + 0.12 * s, y - 0.31 * s), true, true);
                c.LineTo(new Point(sx + _signW * 0.42, y + _depth - _t), true, true);
                c.LineTo(new Point(sx + _signW, y - _top + _t / 2), true, true);
                c.LineTo(new Point(sx + _signW + _r.W + 0.08 * s, y - _top + _t / 2), true, true);
            }
            g.Freeze();
            dc.DrawGeometry(null, _pen, g);
            if (_idx != null) _idx.Draw(dc, sx + _signW * 0.45 - _idx.W, y - _idxUp);
            _r.Draw(dc, sx + _signW + 0.04 * s, y);
        }
    }

    /// <summary>Stacked limits for display big operators (\sum_{i=1}^{n}, \lim_{x\to0}).</summary>
    sealed class LimitsBox : MBox
    {
        readonly MBox _op, _sup, _sub; readonly double _gap;
        public LimitsBox(MBox op, MBox sup, MBox sub, double size)
        {
            _op = op; _sup = sup; _sub = sub; _gap = 0.12 * size;
            W = Math.Max(op.W, Math.Max(sup != null ? sup.W : 0, sub != null ? sub.W : 0));
            A = op.A + (sup != null ? _gap + sup.D + sup.A : 0);
            D = op.D + (sub != null ? _gap + sub.A + sub.D : 0);
        }
        public override void Draw(DrawingContext dc, double x, double y)
        {
            _op.Draw(dc, x + (W - _op.W) / 2, y);
            if (_sup != null) _sup.Draw(dc, x + (W - _sup.W) / 2, y - _op.A - _gap - _sup.D);
            if (_sub != null) _sub.Draw(dc, x + (W - _sub.W) / 2, y + _op.D + _gap + _sub.A);
        }
    }

    /// <summary>Stretchy delimiter drawn as a path so ( [ { | ⟨ ⌊ ⌈ scale cleanly to any height.</summary>
    sealed class DelimBox : MBox
    {
        readonly string _k; readonly Pen _pen; readonly Brush _fg; readonly double _size;
        public DelimBox(string kind, double a, double d, double size, Brush fg)
        {
            _k = kind; _fg = fg; _size = size;
            double h = a + d;
            double thick = Math.Max(1.0, 0.06 * size + 0.012 * h);
            _pen = new Pen(fg, thick) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
            A = a; D = d;
            switch (kind)
            {
                case ".": W = 0; break;
                case "|": case "‖": W = (kind == "|" ? 0.28 : 0.42) * size; break;
                case "{": case "}": W = 0.46 * size + 0.03 * h; break;
                case "(": case ")": W = 0.36 * size + 0.04 * h; break;
                default: W = 0.34 * size + 0.02 * h; break;
            }
        }
        public override void Draw(DrawingContext dc, double x, double y)
        {
            if (_k == ".") return;
            double top = y - A, bot = y + D, h = A + D, m = 0.07 * _size, l = x + m, r = x + W - m, cx = x + W / 2, mid = (top + bot) / 2;
            var g = new StreamGeometry();
            using (var c = g.Open())
            {
                switch (_k)
                {
                    case "(":
                        c.BeginFigure(new Point(r, top), false, false);
                        c.BezierTo(new Point(l - 0.02 * _size, top + h * 0.22), new Point(l - 0.02 * _size, bot - h * 0.22), new Point(r, bot), true, true);
                        break;
                    case ")":
                        c.BeginFigure(new Point(l, top), false, false);
                        c.BezierTo(new Point(r + 0.02 * _size, top + h * 0.22), new Point(r + 0.02 * _size, bot - h * 0.22), new Point(l, bot), true, true);
                        break;
                    case "[":
                        c.BeginFigure(new Point(r, top), false, false); c.LineTo(new Point(l, top), true, true); c.LineTo(new Point(l, bot), true, true); c.LineTo(new Point(r, bot), true, true);
                        break;
                    case "]":
                        c.BeginFigure(new Point(l, top), false, false); c.LineTo(new Point(r, top), true, true); c.LineTo(new Point(r, bot), true, true); c.LineTo(new Point(l, bot), true, true);
                        break;
                    case "⌊": c.BeginFigure(new Point(l, top), false, false); c.LineTo(new Point(l, bot), true, true); c.LineTo(new Point(r, bot), true, true); break;
                    case "⌋": c.BeginFigure(new Point(r, top), false, false); c.LineTo(new Point(r, bot), true, true); c.LineTo(new Point(l, bot), true, true); break;
                    case "⌈": c.BeginFigure(new Point(l, bot), false, false); c.LineTo(new Point(l, top), true, true); c.LineTo(new Point(r, top), true, true); break;
                    case "⌉": c.BeginFigure(new Point(r, bot), false, false); c.LineTo(new Point(r, top), true, true); c.LineTo(new Point(l, top), true, true); break;
                    case "⟨": c.BeginFigure(new Point(r, top), false, false); c.LineTo(new Point(l, mid), true, true); c.LineTo(new Point(r, bot), true, true); break;
                    case "⟩": c.BeginFigure(new Point(l, top), false, false); c.LineTo(new Point(r, mid), true, true); c.LineTo(new Point(l, bot), true, true); break;
                    case "|": c.BeginFigure(new Point(cx, top), false, false); c.LineTo(new Point(cx, bot), true, true); break;
                    case "‖":
                        c.BeginFigure(new Point(cx - 0.07 * _size, top), false, false); c.LineTo(new Point(cx - 0.07 * _size, bot), true, true);
                        c.BeginFigure(new Point(cx + 0.07 * _size, top), false, false); c.LineTo(new Point(cx + 0.07 * _size, bot), true, true);
                        break;
                    case "{":
                        c.BeginFigure(new Point(r, top), false, false);
                        c.BezierTo(new Point(cx - 0.02 * _size, top), new Point(cx + 0.02 * _size, top + h * 0.1), new Point(cx, mid - h * 0.12), true, true);
                        c.BezierTo(new Point(cx, mid - 0.02 * h), new Point(cx - 0.05 * _size, mid), new Point(l, mid), true, true);
                        c.BezierTo(new Point(cx - 0.05 * _size, mid), new Point(cx, mid + 0.02 * h), new Point(cx, mid + h * 0.12), true, true);
                        c.BezierTo(new Point(cx + 0.02 * _size, bot - h * 0.1), new Point(cx - 0.02 * _size, bot), new Point(r, bot), true, true);
                        break;
                    case "}":
                        c.BeginFigure(new Point(l, top), false, false);
                        c.BezierTo(new Point(cx + 0.02 * _size, top), new Point(cx - 0.02 * _size, top + h * 0.1), new Point(cx, mid - h * 0.12), true, true);
                        c.BezierTo(new Point(cx, mid - 0.02 * h), new Point(cx + 0.05 * _size, mid), new Point(r, mid), true, true);
                        c.BezierTo(new Point(cx + 0.05 * _size, mid), new Point(cx, mid + 0.02 * h), new Point(cx, mid + h * 0.12), true, true);
                        c.BezierTo(new Point(cx - 0.02 * _size, bot - h * 0.1), new Point(cx + 0.02 * _size, bot), new Point(l, bot), true, true);
                        break;
                    default:
                        c.BeginFigure(new Point(cx, top), false, false); c.LineTo(new Point(cx, bot), true, true);
                        break;
                }
            }
            g.Freeze();
            dc.DrawGeometry(null, _pen, g);
        }
    }

    /// <summary>matrix / pmatrix / bmatrix / vmatrix / cases / aligned / array grids, centred on the math axis.</summary>
    sealed class GridBox : MBox
    {
        readonly List<List<MBox>> _rows; readonly double[] _colW, _rowA, _rowD; readonly double[] _colX; readonly char[] _align; readonly double _rowGap;
        public GridBox(List<List<MBox>> rows, char[] align, double[] gapsBefore, double size)
        {
            _rows = rows; _align = align;
            int cols = rows.Count == 0 ? 0 : rows.Max(r => r.Count);
            _colW = new double[cols]; _rowA = new double[rows.Count]; _rowD = new double[rows.Count]; _colX = new double[cols];
            _rowGap = 0.32 * size;
            for (int r = 0; r < rows.Count; r++)
            {
                _rowA[r] = 0.72 * size; _rowD[r] = 0.26 * size;
                for (int c = 0; c < rows[r].Count; c++)
                {
                    var b = rows[r][c];
                    _colW[c] = Math.Max(_colW[c], b.W);
                    _rowA[r] = Math.Max(_rowA[r], b.A); _rowD[r] = Math.Max(_rowD[r], b.D);
                }
            }
            double xx = 0;
            for (int c = 0; c < cols; c++) { if (c > 0) xx += gapsBefore != null && c < gapsBefore.Length ? gapsBefore[c] : 0.9 * size; _colX[c] = xx; xx += _colW[c]; }
            W = xx;
            double total = 0;
            for (int r = 0; r < rows.Count; r++) total += _rowA[r] + _rowD[r] + (r > 0 ? _rowGap : 0);
            double axis = 0.25 * size;
            A = total / 2 + axis; D = total / 2 - axis;
        }
        public override void Draw(DrawingContext dc, double x, double y)
        {
            double top = y - A;
            for (int r = 0; r < _rows.Count; r++)
            {
                if (r > 0) top += _rowGap;
                double baseY = top + _rowA[r];
                for (int c = 0; c < _rows[r].Count; c++)
                {
                    var b = _rows[r][c];
                    char al = c < _align.Length ? _align[c] : 'c';
                    double off = al == 'l' ? 0 : al == 'r' ? _colW[c] - b.W : (_colW[c] - b.W) / 2;
                    b.Draw(dc, x + _colX[c] + off, baseY);
                }
                top = baseY + _rowD[r];
            }
        }
    }

    sealed class AccentBox : MBox
    {
        readonly MBox _b; readonly string _k; readonly Pen _pen; readonly Brush _fg; readonly double _s, _lift;
        public AccentBox(MBox b, string kind, double size, Brush fg)
        {
            _b = b; _k = kind; _fg = fg; _s = size;
            _pen = new Pen(fg, Math.Max(1.0, 0.05 * size)) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
            _lift = Math.Max(b.A, 0.45 * size) + 0.08 * size;
            W = b.W; D = b.D;
            A = kind == "underline" ? b.A : _lift + 0.22 * size;
            if (kind == "underline") D = b.D + 0.14 * size;
        }
        public override void Draw(DrawingContext dc, double x, double y)
        {
            _b.Draw(dc, x, y);
            double s = _s, wide = _k == "widehat" || _k == "widetilde" || _k == "overline" || _k == "overrightarrow" ? 1 : 0;
            double w = wide > 0 ? Math.Max(_b.W - 0.04 * s, 0.4 * s) : Math.Min(Math.Max(_b.W * 0.8, 0.32 * s), 0.5 * s);
            double cx = x + _b.W / 2 + (wide > 0 ? 0 : 0.04 * s), l = cx - w / 2, r = cx + w / 2, by = y - _lift, ty = by - 0.16 * s;
            var g = new StreamGeometry();
            using (var c = g.Open())
            {
                switch (_k)
                {
                    case "hat": case "widehat": case "check":
                        if (_k == "check") { c.BeginFigure(new Point(l, ty), false, false); c.LineTo(new Point(cx, by), true, true); c.LineTo(new Point(r, ty), true, true); }
                        else { c.BeginFigure(new Point(l, by), false, false); c.LineTo(new Point(cx, ty), true, true); c.LineTo(new Point(r, by), true, true); }
                        break;
                    case "tilde": case "widetilde":
                        c.BeginFigure(new Point(l, by - 0.02 * s), false, false);
                        c.BezierTo(new Point(l + w * 0.3, ty - 0.04 * s), new Point(l + w * 0.6, by + 0.04 * s), new Point(r, ty + 0.02 * s), true, true);
                        break;
                    case "bar": case "overline":
                        c.BeginFigure(new Point(l, by - 0.04 * s), false, false); c.LineTo(new Point(r, by - 0.04 * s), true, true);
                        break;
                    case "vec": case "overrightarrow":
                        double ay = by - 0.06 * s;
                        c.BeginFigure(new Point(l, ay), false, false); c.LineTo(new Point(r, ay), true, true);
                        c.BeginFigure(new Point(r - 0.12 * s, ay - 0.08 * s), false, false); c.LineTo(new Point(r, ay), true, true); c.LineTo(new Point(r - 0.12 * s, ay + 0.08 * s), true, true);
                        break;
                    case "underline":
                        double uy = y + _b.D + 0.08 * s;
                        c.BeginFigure(new Point(x, uy), false, false); c.LineTo(new Point(x + _b.W, uy), true, true);
                        break;
                    case "breve":
                        c.BeginFigure(new Point(l, ty), false, false); c.BezierTo(new Point(l, by), new Point(r, by), new Point(r, ty), true, true);
                        break;
                    case "acute": c.BeginFigure(new Point(cx - 0.05 * s, by), false, false); c.LineTo(new Point(cx + 0.08 * s, ty), true, true); break;
                    case "grave": c.BeginFigure(new Point(cx + 0.05 * s, by), false, false); c.LineTo(new Point(cx - 0.08 * s, ty), true, true); break;
                }
            }
            g.Freeze();
            dc.DrawGeometry(null, _pen, g);
            if (_k == "dot" || _k == "ddot")
            {
                double rr = 0.045 * s, dy = by - 0.06 * s;
                if (_k == "dot") dc.DrawEllipse(_fg, null, new Point(cx, dy), rr, rr);
                else { dc.DrawEllipse(_fg, null, new Point(cx - 0.09 * s, dy), rr, rr); dc.DrawEllipse(_fg, null, new Point(cx + 0.09 * s, dy), rr, rr); }
            }
        }
    }

    /// <summary>Recursive-descent LaTeX math parser that produces laid-out boxes.</summary>
    public static class TeX
    {
        static readonly Typeface MathFace = new Typeface(new FontFamily("Cambria Math"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
        static Typeface TextFace { get { return new Typeface(UIFonts.UI, FontStyles.Normal, FontWeights.Normal, FontStretches.Normal); } }
        static Typeface TextBold { get { return new Typeface(UIFonts.UI, FontStyles.Normal, FontWeights.Bold, FontStretches.Normal); } }
        static Typeface TextItalic { get { return new Typeface(UIFonts.UI, FontStyles.Italic, FontWeights.Normal, FontStretches.Normal); } }

        enum Cls { Ord, Op, Bin, Rel, Open, Close, Punct }

        class Ctx
        {
            public double Size; public bool Display; public int Level; public string Style = "it"; public Brush Fg;
            public Ctx With(string style) { return new Ctx { Size = Size, Display = Display, Level = Level, Style = style, Fg = Fg }; }
            public Ctx Script() { return new Ctx { Size = Level == 0 ? Size * 0.72 : Size * 0.8, Display = false, Level = Level + 1, Style = Style == "text" ? "it" : Style, Fg = Fg }; }
            public Ctx Text() { return new Ctx { Size = Size, Display = false, Level = Level, Style = Style, Fg = Fg }; }
            public Ctx FracPart() { return Display ? Text() : Script(); }
        }

        class Atom { public MBox Box; public Cls C; public bool Limits; public bool BigOp; }

        // symbol table (TeXMathEngine.commandSymbols): glyph, class
        static readonly Dictionary<string, KeyValuePair<string, Cls>> Sym = BuildSymbols();

        static Dictionary<string, KeyValuePair<string, Cls>> BuildSymbols()
        {
            var d = new Dictionary<string, KeyValuePair<string, Cls>>();
            Action<string, Cls, string> add = (names, c, glyphs) => { var n = names.Split(' '); var g = glyphs.Split(' '); for (int i = 0; i < n.Length; i++) d[n[i]] = new KeyValuePair<string, Cls>(g[i], c); };
            add("alpha beta gamma delta epsilon varepsilon zeta eta theta vartheta iota kappa varkappa lambda mu nu xi pi varpi rho varrho sigma varsigma tau upsilon phi varphi chi psi omega",
                Cls.Ord, "α β γ δ ϵ ε ζ η θ ϑ ι κ ϰ λ μ ν ξ π ϖ ρ ϱ σ ς τ υ ϕ φ χ ψ ω");
            add("Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega", Cls.Ord, "Γ Δ Θ Λ Ξ Π Σ Υ Φ Ψ Ω");
            add("AA angstrom hbar ell Re Im wp aleph infty partial nabla emptyset varnothing degree prime triangle Box square angle forall exists nexists neg lnot top bot backslash dots ldots cdots vdots ddots checkmark dagger ddagger clubsuit diamondsuit heartsuit spadesuit flat natural sharp",
                Cls.Ord, "Å Å ℏ ℓ ℜ ℑ ℘ ℵ ∞ ∂ ∇ ∅ ∅ ° ′ △ □ □ ∠ ∀ ∃ ∄ ¬ ¬ ⊤ ⊥ \\ … … ⋯ ⋮ ⋱ ✓ † ‡ ♣ ♢ ♡ ♠ ♭ ♮ ♯");
            add("pm mp times div cdot ast star oplus ominus otimes odot cup cap setminus land wedge lor vee bullet circ uplus sqcup sqcap",
                Cls.Bin, "± ∓ × ÷ ⋅ ∗ ⋆ ⊕ ⊖ ⊗ ⊙ ∪ ∩ ∖ ∧ ∧ ∨ ∨ ∙ ∘ ⊎ ⊔ ⊓");
            add("le leq leqslant ge geq geqslant ll gg ne neq approx sim simeq cong equiv propto in notin ni subset supset subseteq supseteq vdash models mid perp parallel to rightarrow longrightarrow leftarrow gets leftrightarrow Rightarrow implies Leftarrow Leftrightarrow iff mapsto uparrow downarrow nearrow searrow rightleftharpoons rightharpoonup longleftarrow Longrightarrow Longleftarrow longmapsto prec succ preceq succeq doteq coloneqq asymp",
                Cls.Rel, "≤ ≤ ⩽ ≥ ≥ ⩾ ≪ ≫ ≠ ≠ ≈ ∼ ≃ ≅ ≡ ∝ ∈ ∉ ∋ ⊂ ⊃ ⊆ ⊇ ⊢ ⊨ ∣ ⊥ ∥ → → ⟶ ← ← ↔ ⇒ ⟹ ⇐ ⇔ ⟺ ↦ ↑ ↓ ↗ ↘ ⇌ ⇀ ⟵ ⟹ ⟸ ⟼ ≺ ≻ ⪯ ⪰ ≐ ≔ ≍");
            add("sum prod coprod int iint iiint oint bigcup bigcap bigoplus bigotimes bigvee bigwedge bigsqcup",
                Cls.Op, "∑ ∏ ∐ ∫ ∬ ∭ ∮ ⋃ ⋂ ⨁ ⨂ ⋁ ⋀ ⨆");
            add("langle rangle lfloor rfloor lceil rceil lvert rvert lVert rVert vert Vert", Cls.Ord, "⟨ ⟩ ⌊ ⌋ ⌈ ⌉ | | ‖ ‖ | ‖");
            return d;
        }

        static readonly HashSet<string> Functions = new HashSet<string> { "sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh", "coth", "log", "ln", "lg", "exp", "det", "dim", "ker", "deg", "gcd", "arg", "hom", "Pr", "mod", "bmod", "lim", "liminf", "limsup", "max", "min", "sup", "inf", "argmax", "argmin" };
        static readonly HashSet<string> LimitFunctions = new HashSet<string> { "lim", "liminf", "limsup", "max", "min", "sup", "inf", "det", "Pr", "gcd", "argmax", "argmin" };
        static readonly HashSet<string> LimitOps = new HashSet<string> { "∑", "∏", "∐", "⋃", "⋂", "⨁", "⨂", "⋁", "⋀", "⨆" };

        // ── public entry ──
        /// <summary>Lays out a whole expression; top-level \\ makes centred rows (multi-line display equations).</summary>
        internal static MBox Layout(string tex, double size, bool display, Brush fg)
        {
            var p = new Parser(tex);
            var ctx = new Ctx { Size = size, Display = display, Fg = fg };
            var rows = new List<List<MBox>>();
            while (true)
            {
                var row = p.Row(ctx, false);
                rows.Add(new List<MBox> { row });
                if (p.AtRowBreak()) { p.SkipRowBreak(); continue; }
                if (p.AtEnd()) break;
                p.Skip(); // stray closer: ignore and continue
            }
            rows.RemoveAll(r => r[0].W <= 0 && rows.Count > 1);
            if (rows.Count == 1) return rows[0][0];
            return new GridBox(rows, new[] { 'c' }, null, size);
        }

        /// <summary>contains2DStructure: whether the expression needs 2-D layout (fractions, roots, matrices, big operators…).</summary>
        public static bool Is2D(string tex)
        {
            return System.Text.RegularExpressions.Regex.IsMatch(tex ?? "", @"\\(d?t?frac|binom|sqrt|sum|prod|int|iint|oint|lim|begin|left|over|under|hat|vec|bar|tilde|dot)\b|\^\{.{3,}|_\{.{3,}");
        }

        static string Letter(char ch, string style)
        {
            int c = ch;
            bool up = ch >= 'A' && ch <= 'Z', low = ch >= 'a' && ch <= 'z', dig = ch >= '0' && ch <= '9';
            Func<int, string> U = cp => char.ConvertFromUtf32(cp);
            switch (style)
            {
                case "it":
                    if (ch == 'h') return "ℎ";
                    if (up) return U(0x1D434 + c - 'A');
                    if (low) return U(0x1D44E + c - 'a');
                    if (c >= 0x3B1 && c <= 0x3C9) return U(0x1D6FC + c - 0x3B1);
                    return ch.ToString();
                case "bf":
                    if (up) return U(0x1D400 + c - 'A');
                    if (low) return U(0x1D41A + c - 'a');
                    if (dig) return U(0x1D7CE + c - '0');
                    return ch.ToString();
                case "bi":
                    if (up) return U(0x1D468 + c - 'A');
                    if (low) return U(0x1D482 + c - 'a');
                    if (dig) return U(0x1D7CE + c - '0');
                    return ch.ToString();
                case "bb":
                    if (up) { string ex = "CHNPQRZ"; string to = "ℂℍℕℙℚℝℤ"; int k = ex.IndexOf(ch); return k >= 0 ? to[k].ToString() : U(0x1D538 + c - 'A'); }
                    if (low) return U(0x1D552 + c - 'a');
                    if (dig) return U(0x1D7D8 + c - '0');
                    return ch.ToString();
                case "cal":
                    if (up) { string ex = "BEFHILMR"; string to = "ℬℰℱℋℐℒℳℛ"; int k = ex.IndexOf(ch); return k >= 0 ? to[k].ToString() : U(0x1D49C + c - 'A'); }
                    if (low) { string ex = "ego"; string to = "ℯℊℴ"; int k = ex.IndexOf(ch); return k >= 0 ? to[k].ToString() : U(0x1D4B6 + c - 'a'); }
                    return ch.ToString();
                case "frak":
                    if (up) { string ex = "CHIRZ"; string to = "ℭℌℑℜℨ"; int k = ex.IndexOf(ch); return k >= 0 ? to[k].ToString() : U(0x1D504 + c - 'A'); }
                    if (low) return U(0x1D51E + c - 'a');
                    return ch.ToString();
                case "sf":
                    if (up) return U(0x1D5A0 + c - 'A');
                    if (low) return U(0x1D5BA + c - 'a');
                    if (dig) return U(0x1D7E2 + c - '0');
                    return ch.ToString();
                case "tt":
                    if (up) return U(0x1D670 + c - 'A');
                    if (low) return U(0x1D68A + c - 'a');
                    if (dig) return U(0x1D7F6 + c - '0');
                    return ch.ToString();
                default: return ch.ToString(); // rm
            }
        }

        static MBox Glyph(string s, Ctx c) { return new GlyphBox(s, MathFace, c.Size, c.Fg); }
        static MBox TextGlyph(string s, Ctx c, Typeface tf) { return new GlyphBox(s, tf, c.Size * 0.95, c.Fg); }

        class Parser
        {
            readonly string s; int i;
            public Parser(string src) { s = (src ?? "").Trim(); i = 0; }

            public bool AtEnd() { SkipWs(); return i >= s.Length; }
            public bool AtRowBreak() { SkipWs(); return i + 1 < s.Length && s[i] == '\\' && s[i + 1] == '\\'; }
            public void SkipRowBreak() { i += 2; SkipWs(); if (i < s.Length && s[i] == '[') { int e = s.IndexOf(']', i); if (e > 0) i = e + 1; } }
            public void Skip() { if (i < s.Length) i++; }
            void SkipWs() { while (i < s.Length && char.IsWhiteSpace(s[i])) i++; }
            bool AtCell() { SkipWs(); return i < s.Length && s[i] == '&'; }

            string PeekCommand()
            {
                if (i >= s.Length || s[i] != '\\') return null;
                int j = i + 1;
                if (j < s.Length && !char.IsLetter(s[j])) return s[j].ToString();
                while (j < s.Length && char.IsLetter(s[j])) j++;
                return s.Substring(i + 1, j - i - 1);
            }

            string ReadCommand()
            {
                string c = PeekCommand();
                i += 1 + c.Length;
                return c;
            }

            /// <summary>Raw text of a {…} group (for \text, \begin, \operatorname).</summary>
            string RawGroup()
            {
                SkipWs();
                if (i >= s.Length) return "";
                if (s[i] != '{') { return s[i++].ToString(); }
                int depth = 0, start = i + 1;
                for (; i < s.Length; i++)
                {
                    if (s[i] == '\\') { i++; continue; }
                    if (s[i] == '{') depth++;
                    else if (s[i] == '}') { depth--; if (depth == 0) { i++; return s.Substring(start, i - start - 1); } }
                }
                return s.Substring(start);
            }

            string OptionalArg()
            {
                SkipWs();
                if (i < s.Length && s[i] == '[')
                {
                    int depth = 0, start = i + 1;
                    for (; i < s.Length; i++)
                    {
                        if (s[i] == '[') depth++;
                        else if (s[i] == ']') { depth--; if (depth == 0) { i++; return s.Substring(start, i - start - 1); } }
                    }
                }
                return null;
            }

            /// <summary>One argument: a {group} or a single token.</summary>
            public MBox Arg(Ctx c)
            {
                SkipWs();
                if (i >= s.Length) return new SpaceBox(0);
                if (s[i] == '{') { i++; var b = Row(c, true); if (i < s.Length && s[i] == '}') i++; return b; }
                var a = Atom1(c);
                return a != null ? a.Box : new SpaceBox(0);
            }

            /// <summary>A row of atoms up to } / & / \\ / \right / \end, with TeX inter-atom spacing.</summary>
            public HBox Row(Ctx c, bool inGroup) { return Row(c, inGroup, null); }

            public HBox Row(Ctx c, bool inGroup, Cls? start)
            {
                var row = new HBox();
                Cls? prev = start;
                while (true)
                {
                    SkipWs();
                    if (i >= s.Length) break;
                    char ch = s[i];
                    if (ch == '}') { if (inGroup) break; i++; continue; }
                    if (ch == '&') break;
                    if (AtRowBreak()) break;
                    string cmd = PeekCommand();
                    if (cmd == "right" || cmd == "end") break;
                    var a = Atom1(c);
                    if (a == null) continue;
                    a = Scripts(a, c);
                    // unary minus/plus at the start or after an operator/relation/open
                    if (a.C == Cls.Bin && (prev == null || prev == Cls.Bin || prev == Cls.Rel || prev == Cls.Open || prev == Cls.Op || prev == Cls.Punct)) a.C = Cls.Ord;
                    if (prev != null && c.Level == 0)
                    {
                        double sp = Space(prev.Value, a.C) * c.Size;
                        if (sp > 0) row.Add(new SpaceBox(sp));
                    }
                    row.Add(a.Box);
                    prev = a.C;
                }
                return row;
            }

            static double Space(Cls l, Cls r)
            {
                if (l == Cls.Rel || r == Cls.Rel) return (l == Cls.Open || r == Cls.Close || l == Cls.Rel && r == Cls.Rel) ? 0 : 5.0 / 18;
                if (l == Cls.Bin || r == Cls.Bin) return 4.0 / 18;
                if (l == Cls.Op && (r == Cls.Ord || r == Cls.Op)) return 3.0 / 18;
                if (l == Cls.Ord && r == Cls.Op) return 3.0 / 18;
                if (l == Cls.Punct) return 3.0 / 18;
                return 0;
            }

            Atom Scripts(Atom a, Ctx c)
            {
                MBox sup = null, sub = null;
                while (true)
                {
                    SkipWs();
                    if (i >= s.Length) break;
                    if (s[i] == '^' && sup == null) { i++; sup = Arg(c.Script()); continue; }
                    if (s[i] == '_' && sub == null) { i++; sub = Arg(c.Script()); continue; }
                    if (s[i] == '\'' ) { int n = 0; while (i < s.Length && s[i] == '\'') { n++; i++; } var pr = Glyph(n == 1 ? "′" : n == 2 ? "″" : "‴", c.Script()); sup = sup == null ? pr : Concat(pr, sup); continue; }
                    string cmd = PeekCommand();
                    if (cmd == "limits") { ReadCommand(); a.Limits = true; continue; }
                    if (cmd == "nolimits") { ReadCommand(); a.Limits = false; continue; }
                    break;
                }
                if (sup == null && sub == null) return a;
                bool stack = a.Limits && c.Display;
                return new Atom { Box = stack ? (MBox)new LimitsBox(a.Box, sup, sub, c.Size) : new ScriptBox(a.Box, sup, sub, c.Size), C = a.C };
            }

            static MBox Concat(MBox x, MBox y) { var h = new HBox(); h.Add(x); h.Add(y); return h; }

            Atom Ord(MBox b) { return new Atom { Box = b, C = Cls.Ord }; }

            Atom Atom1(Ctx c)
            {
                SkipWs();
                if (i >= s.Length) return null;
                char ch = s[i];
                if (ch == '{') { i++; var g = Row(c, true); if (i < s.Length && s[i] == '}') i++; return Ord(g); }
                if (ch == '\\') return Command(c);
                if (ch == '^' || ch == '_') { i++; return null; }
                if (ch == '~') { i++; return Ord(new SpaceBox(0.33 * c.Size)); }
                // surrogate pairs (already-styled math letters)
                if (char.IsHighSurrogate(ch) && i + 1 < s.Length) { string sp = s.Substring(i, 2); i += 2; return Ord(Glyph(sp, c)); }
                i++;
                if (c.Style == "text") return Ord(TextGlyph(ch.ToString(), c, TextFace));
                if (char.IsLetter(ch) && ch < 0x250 || (ch >= 0x3B1 && ch <= 0x3C9)) return Ord(Glyph(Letter(ch, c.Style), c));
                if (char.IsDigit(ch) || ch == '.')
                {
                    // whole number as one box for tight kerning
                    var sb = new StringBuilder(); sb.Append(c.Style == "bf" || c.Style == "bb" || c.Style == "sf" || c.Style == "tt" ? Letter(ch, c.Style) : ch.ToString());
                    while (i < s.Length && (char.IsDigit(s[i]) || (s[i] == '.' && i + 1 < s.Length && char.IsDigit(s[i + 1])))) { sb.Append(c.Style == "bf" || c.Style == "bb" ? Letter(s[i], c.Style) : s[i].ToString()); i++; }
                    return Ord(Glyph(sb.ToString(), c));
                }
                if (char.IsLetter(ch)) return Ord(TextGlyph(ch.ToString(), c, TextFace)); // Thai / other scripts typed directly in math
                switch (ch)
                {
                    case '+': return new Atom { Box = Glyph("+", c), C = Cls.Bin };
                    case '-': return new Atom { Box = Glyph("−", c), C = Cls.Bin };
                    case '*': return new Atom { Box = Glyph("∗", c), C = Cls.Bin };
                    case '/': return Ord(Glyph("/", c));
                    case '=': case '<': case '>': return new Atom { Box = Glyph(ch.ToString(), c), C = Cls.Rel };
                    case ':': return new Atom { Box = Glyph(":", c), C = Cls.Rel };
                    case ',': case ';': return new Atom { Box = Glyph(ch.ToString(), c), C = Cls.Punct };
                    case '(': case '[': return new Atom { Box = Glyph(ch.ToString(), c), C = Cls.Open };
                    case ')': case ']': return new Atom { Box = Glyph(ch.ToString(), c), C = Cls.Close };
                    case '!': case '?': return new Atom { Box = Glyph(ch.ToString(), c), C = Cls.Close };
                    case '|': return Ord(Glyph("|", c));
                    case '$': return null;
                    default: return Ord(Glyph(ch.ToString(), c));
                }
            }

            static readonly Dictionary<string, string> Delims = new Dictionary<string, string>
            {
                { "(", "(" }, { ")", ")" }, { "[", "[" }, { "]", "]" }, { "\\{", "{" }, { "\\}", "}" }, { "\\lbrace", "{" }, { "\\rbrace", "}" }, { "|", "|" }, { "\\|", "‖" },
                { "\\vert", "|" }, { "\\Vert", "‖" }, { "\\lvert", "|" }, { "\\rvert", "|" }, { "\\lVert", "‖" }, { "\\rVert", "‖" }, { "\\langle", "⟨" }, { "\\rangle", "⟩" }, { "<", "⟨" }, { ">", "⟩" },
                { "\\lfloor", "⌊" }, { "\\rfloor", "⌋" }, { "\\lceil", "⌈" }, { "\\rceil", "⌉" }, { ".", "." }, { "\\lbrack", "[" }, { "\\rbrack", "]" }
            };

            string ReadDelim()
            {
                SkipWs();
                if (i >= s.Length) return ".";
                if (s[i] == '\\') { string cmd = ReadCommand(); string k = "\\" + cmd; string d; return Delims.TryGetValue(k, out d) ? d : "."; }
                string one = s[i++].ToString(); string v;
                return Delims.TryGetValue(one, out v) ? v : one;
            }

            static MBox Stretch(string delim, MBox body, Ctx c, double minFactor)
            {
                double axis = 0.25 * c.Size;
                double half = Math.Max(Math.Max(body.A - axis, body.D + axis) + 0.08 * c.Size, 0.5 * c.Size * minFactor);
                return new DelimBox(delim, axis + half, half - axis, c.Size, c.Fg);
            }

            Atom Command(Ctx c)
            {
                string cmd = ReadCommand();
                KeyValuePair<string, Cls> sym;
                switch (cmd)
                {
                    // spacing
                    case ",": return Ord(new SpaceBox(3.0 / 18 * c.Size));
                    case ":": case ">": return Ord(new SpaceBox(4.0 / 18 * c.Size));
                    case ";": return Ord(new SpaceBox(5.0 / 18 * c.Size));
                    case "!": return Ord(new SpaceBox(-3.0 / 18 * c.Size));
                    case " ": return Ord(new SpaceBox(0.3 * c.Size));
                    case "quad": return Ord(new SpaceBox(c.Size));
                    case "qquad": return Ord(new SpaceBox(2 * c.Size));
                    case "{": return new Atom { Box = Glyph("{", c), C = Cls.Open };
                    case "}": return new Atom { Box = Glyph("}", c), C = Cls.Close };
                    case "|": return Ord(Glyph("‖", c));
                    case "%": case "#": case "&": case "_": case "$": return Ord(Glyph(cmd, c));
                    case "\\": return null;
                    // fractions
                    case "frac": case "dfrac": case "tfrac": case "cfrac":
                    {
                        var fc = cmd == "dfrac" ? c.Text() : cmd == "tfrac" ? c.Script() : c.FracPart();
                        if (cmd == "dfrac") fc.Display = true;
                        var num = Arg(fc); var den = Arg(fc);
                        return Ord(new FracBox(num, den, c.Size, c.Display || cmd == "dfrac", true, c.Fg));
                    }
                    case "binom": case "dbinom": case "tbinom":
                    {
                        var fc = cmd == "dbinom" ? c.Text() : c.FracPart();
                        var f = new FracBox(Arg(fc), Arg(fc), c.Size, c.Display, false, c.Fg);
                        var h = new HBox(); h.Add(Stretch("(", f, c, 1)); h.Add(f); h.Add(Stretch(")", f, c, 1));
                        return Ord(h);
                    }
                    case "sqrt":
                    {
                        string idx = OptionalArg();
                        MBox ib = idx != null ? Layout(idx, c.Script().Size * 0.85, false, c.Fg) : null;
                        return Ord(new SqrtBox(Arg(c), ib, c.Size, c.Fg));
                    }
                    case "left":
                    {
                        string l = ReadDelim();
                        var body = Row(c, false);
                        string r = ".";
                        if (PeekCommand() == "right") { ReadCommand(); r = ReadDelim(); }
                        var h = new HBox(); h.Add(Stretch(l, body, c, 1)); h.Add(body); h.Add(Stretch(r, body, c, 1));
                        return new Atom { Box = h, C = Cls.Ord };
                    }
                    case "right": return null;
                    case "big": case "Big": case "bigg": case "Bigg": case "bigl": case "bigr": case "Bigl": case "Bigr": case "biggl": case "biggr": case "Biggl": case "Biggr":
                    {
                        string d = ReadDelim();
                        double f = cmd.StartsWith("Bigg") ? 2.4 : cmd.StartsWith("bigg") ? 2.0 : cmd.StartsWith("Big") ? 1.6 : 1.25;
                        var dummy = new SpaceBox(0) { A = 0.75 * c.Size * f * 0.6 + 0.25 * c.Size, D = 0.75 * c.Size * f * 0.6 - 0.25 * c.Size };
                        bool open = d == "(" || d == "[" || d == "{" || d == "⟨" || d == "⌊" || d == "⌈" || cmd.EndsWith("l");
                        return new Atom { Box = Stretch(d, dummy, c, f), C = open ? Cls.Open : Cls.Close };
                    }
                    // fonts / text
                    case "text": case "textrm": case "mbox": case "textnormal": case "hbox":
                        return Ord(TextRun(RawGroup(), c, TextFace));
                    case "textbf": return Ord(TextRun(RawGroup(), c, TextBold));
                    case "textit": case "emph": return Ord(TextRun(RawGroup(), c, TextItalic));
                    case "texttt": return Ord(TextRun(RawGroup(), c, new Typeface(UIFonts.Mono, FontStyles.Normal, FontWeights.Normal, FontStretches.Normal)));
                    case "operatorname":
                    {
                        bool star = false;
                        if (i < s.Length && s[i] == '*') { star = true; i++; }
                        string name = RawGroup();
                        return new Atom { Box = TextRun(name, c, new Typeface(new FontFamily("Cambria Math"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal)), C = Cls.Op, Limits = star };
                    }
                    case "mathrm": case "rm": return Ord(Arg(c.With("rm")));
                    case "mathbf": case "bf": return Ord(Arg(c.With("bf")));
                    case "boldsymbol": case "bm": return Ord(Arg(c.With("bi")));
                    case "mathit": case "it": return Ord(Arg(c.With("it")));
                    case "mathbb": return Ord(Arg(c.With("bb")));
                    case "mathcal": case "mathscr": return Ord(Arg(c.With("cal")));
                    case "mathfrak": return Ord(Arg(c.With("frak")));
                    case "mathsf": return Ord(Arg(c.With("sf")));
                    case "mathtt": return Ord(Arg(c.With("tt")));
                    case "displaystyle": c.Display = true; return null;
                    case "textstyle": c.Display = false; return null;
                    case "scriptstyle": return null;
                    // accents
                    case "hat": case "widehat": case "bar": case "overline": case "vec": case "overrightarrow": case "tilde": case "widetilde": case "dot": case "ddot": case "check": case "breve": case "acute": case "grave": case "underline":
                        return Ord(new AccentBox(Arg(c), cmd, c.Size, c.Fg));
                    case "overbrace": case "underbrace":
                    {
                        var body = Arg(c);
                        return Ord(new AccentBox(body, cmd == "overbrace" ? "overline" : "underline", c.Size, c.Fg));
                    }
                    case "not":
                    {
                        var a = Atom1(c);
                        if (a == null) return null;
                        var h = new HBox(); h.Add(a.Box); var slash = Glyph("/", c); h.Add(new SpaceBox(-(a.Box.W + slash.W) / 2)); h.Add(slash); h.Add(new SpaceBox((a.Box.W - slash.W) / 2));
                        return new Atom { Box = h, C = a.C };
                    }
                    case "begin": return Environment(RawGroup(), c);
                    case "end": RawGroup(); return null;
                    case "label": case "tag": case "nonumber": case "notag": if (cmd == "label" || cmd == "tag") RawGroup(); return null;
                    case "color": case "textcolor": { RawGroup(); if (cmd == "textcolor") return Ord(Arg(c)); return null; }
                    case "mod": case "bmod": case "pmod":
                    {
                        if (cmd == "pmod") { var h = new HBox(); h.Add(new SpaceBox(0.6 * c.Size)); h.Add(Glyph("(", c)); h.Add(TextRun("mod", c, MathFace)); h.Add(new SpaceBox(0.3 * c.Size)); h.Add(Arg(c)); h.Add(Glyph(")", c)); return Ord(h); }
                        return new Atom { Box = TextRun("mod", c, MathFace), C = Cls.Bin };
                    }
                }
                if (Functions.Contains(cmd))
                    return new Atom { Box = TextRun(cmd == "argmax" ? "arg max" : cmd == "argmin" ? "arg min" : cmd == "limsup" ? "lim sup" : cmd == "liminf" ? "lim inf" : cmd, c, MathFace), C = Cls.Op, Limits = LimitFunctions.Contains(cmd) };
                if (Sym.TryGetValue(cmd, out sym))
                {
                    if (sym.Value == Cls.Op)
                    {
                        bool integral = sym.Key == "∫" || sym.Key == "∬" || sym.Key == "∭" || sym.Key == "∮";
                        double f = c.Display ? (integral ? 1.75 : 1.45) : 1.1;
                        var g = new GlyphBox(sym.Key, MathFace, c.Size * f, c.Fg);
                        double axis = 0.25 * c.Size, shift = axis - (g.A - g.D) / 2;
                        return new Atom { Box = new RaiseBox(g, shift), C = Cls.Op, Limits = LimitOps.Contains(sym.Key), BigOp = true };
                    }
                    string glyph = sym.Key;
                    if (c.Style == "it" && glyph.Length == 1 && glyph[0] >= 0x3B1 && glyph[0] <= 0x3C9) glyph = Letter(glyph[0], "it");
                    return new Atom { Box = Glyph(glyph, c), C = sym.Value };
                }
                // unknown command: show its name upright so nothing silently disappears
                return Ord(TextRun(cmd, c, MathFace));
            }

            static MBox TextRun(string text, Ctx c, Typeface tf)
            {
                var h = new HBox();
                if (string.IsNullOrEmpty(text)) return h;
                h.Add(new GlyphBox(text.Replace("~", " "), tf, tf.FontFamily.Source == "Cambria Math" ? c.Size : c.Size * 0.95, c.Fg));
                return h;
            }

            Atom Environment(string env, Ctx c)
            {
                string name = env.Trim().TrimEnd('*');
                string colSpec = null;
                if (name == "array" || name == "tabular") colSpec = RawGroup();
                var cellCtx = name == "smallmatrix" ? c.Script() : c.Text();
                bool alignedEnv = name == "aligned" || name == "align" || name == "split" || name == "alignat" || name == "eqnarray";
                if (name == "aligned" || name == "align" || name == "gathered" || name == "split" || name == "equation" || name == "multline" || name == "alignat") cellCtx = new Ctx { Size = c.Size, Display = c.Display, Level = c.Level, Style = c.Style, Fg = c.Fg };
                var rows = new List<List<MBox>>();
                var row = new List<MBox>();
                while (true)
                {
                    SkipWs();
                    if (i >= s.Length) break;
                    if (PeekCommand() == "end") { ReadCommand(); RawGroup(); break; }
                    var cell = Row(cellCtx, false, alignedEnv && row.Count % 2 == 1 ? (Cls?)Cls.Ord : null);
                    row.Add(cell);
                    if (AtCell()) { i++; continue; }
                    if (AtRowBreak()) { SkipRowBreak(); rows.Add(row); row = new List<MBox>(); continue; }
                    if (i < s.Length && PeekCommand() != "end") i++; // unexpected token
                }
                if (row.Count > 0 && !(row.Count == 1 && row[0].W <= 0)) rows.Add(row);
                if (rows.Count == 0) return null;
                int cols = rows.Max(rw => rw.Count);
                var align = new char[cols];
                var gaps = new double[cols];
                bool aligned = name == "aligned" || name == "align" || name == "split" || name == "alignat" || name == "eqnarray";
                for (int k = 0; k < cols; k++)
                {
                    if (aligned) { align[k] = k % 2 == 0 ? 'r' : 'l'; gaps[k] = k == 0 ? 0 : k % 2 == 1 ? 0 : 1.2 * c.Size; }
                    else if (name == "cases" || name == "dcases" || name == "rcases") { align[k] = 'l'; gaps[k] = 1.0 * c.Size; }
                    else if (colSpec != null) { string spec = new string(colSpec.Where(ch => ch == 'l' || ch == 'c' || ch == 'r').ToArray()); align[k] = k < spec.Length ? spec[k] : 'c'; gaps[k] = 0.9 * c.Size; }
                    else if (name == "gathered" || name == "equation" || name == "multline") { align[k] = 'c'; gaps[k] = 1 * c.Size; }
                    else { align[k] = 'c'; gaps[k] = 0.9 * c.Size; }
                }
                var grid = new GridBox(rows, align, gaps, c.Size);
                string l = ".", r = ".";
                switch (name)
                {
                    case "pmatrix": l = "("; r = ")"; break;
                    case "bmatrix": l = "["; r = "]"; break;
                    case "Bmatrix": l = "{"; r = "}"; break;
                    case "vmatrix": l = "|"; r = "|"; break;
                    case "Vmatrix": l = "‖"; r = "‖"; break;
                    case "cases": case "dcases": l = "{"; break;
                    case "rcases": r = "}"; break;
                }
                if (l == "." && r == ".") return Ord(grid);
                var h = new HBox();
                h.Add(new DelimBox(l, grid.A + 0.05 * c.Size, grid.D + 0.05 * c.Size, c.Size, c.Fg));
                if (l != ".") h.Add(new SpaceBox(0.08 * c.Size));
                h.Add(grid);
                if (r != ".") h.Add(new SpaceBox(0.08 * c.Size));
                h.Add(new DelimBox(r, grid.A + 0.05 * c.Size, grid.D + 0.05 * c.Size, c.Size, c.Fg));
                return Ord(h);
            }
        }
    }

    /// <summary>A rendered equation. Display mode centres multi-line equations; inline mode sits on the text baseline.</summary>
    public class MathView : FrameworkElement
    {
        readonly MBox _box;
        readonly double _padX, _padY;
        public readonly bool Failed;

        public MathView(string tex, double size, bool display, Brush fg)
        {
            _padX = display ? 2 : 1; _padY = display ? 4 : 1;
            try { _box = TeX.Layout(tex, size, display, fg); }
            catch
            {
                Failed = true;
                _box = new GlyphBox(tex ?? "", new Typeface(UIFonts.Mono, FontStyles.Normal, FontWeights.Normal, FontStretches.Normal), size * 0.85, fg);
            }
            SnapsToDevicePixels = false;
            UseLayoutRounding = false;
        }

        /// <summary>Distance from the element's bottom to the math baseline (used to sit inline equations on the text baseline).</summary>
        public double Descent { get { return _box.D + _padY; } }

        protected override Size MeasureOverride(Size available) { return new Size(Math.Max(0, _box.W + 2 * _padX), _box.A + _box.D + 2 * _padY); }

        protected override void OnRender(DrawingContext dc)
        {
            dc.DrawRectangle(Brushes.Transparent, null, new Rect(0, 0, ActualWidth, ActualHeight));
            _box.Draw(dc, _padX, _padY + _box.A);
        }
    }

    /// <summary>LaTeXBlockView: display equation card with hover "&lt;/&gt;" (view source) and Copy LaTeX.</summary>
    public static class MathBlock
    {
        public static FrameworkElement Create(string expression, double size)
        {
            var t = Theme.Current;
            string tex = (expression ?? "").Trim();
            double fs = Math.Max(14, Math.Min(18, size * 1.0));
            bool raw = false;
            var host = new Border { Padding = new Thickness(14, 12, 14, 12) };
            Action render = () =>
            {
                if (raw)
                {
                    var src = new TextBox { Text = tex, IsReadOnly = true, FontFamily = UIFonts.Mono, FontSize = 12, Foreground = t.Secondary, Background = Brushes.Transparent, BorderThickness = new Thickness(0), TextWrapping = TextWrapping.Wrap };
                    host.Child = src;
                }
                else
                {
                    var mv = new MathView(tex, fs, true, t.Primary) { HorizontalAlignment = HorizontalAlignment.Center };
                    host.Child = new ScrollViewer { Content = mv, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled, HorizontalContentAlignment = HorizontalAlignment.Center };
                }
            };
            render();
            var srcBtn = V.Button(V.Box(V.Mono("</>", 9, FontWeights.SemiBold, t.Secondary), V.P(5, 2), t.P(0.06), 4), null);
            srcBtn.ToolTip = "View LaTeX Source";
            Btn copyBtn = null;
            copyBtn = V.Button(V.Box(Sym.Icon("doc.on.doc", 10, t.Secondary, FontWeights.Medium), V.P(4, 3), Brushes.Transparent, 4), () =>
            {
                try { Clipboard.SetText(tex); } catch { }
                ((Border)copyBtn.Child).Child = Sym.Icon("checkmark", 10, t.SysGreen, FontWeights.Medium);
                var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
                timer.Tick += delegate { timer.Stop(); ((Border)copyBtn.Child).Child = Sym.Icon("doc.on.doc", 10, t.Secondary, FontWeights.Medium); };
                timer.Start();
            });
            copyBtn.ToolTip = "Copy LaTeX";
            copyBtn.Opacity = 0.65;
            srcBtn.Click += () =>
            {
                raw = !raw;
                ((TextBlock)((Border)srcBtn.Child).Child).Text = raw ? "TeX" : "</>";
                ((TextBlock)((Border)srcBtn.Child).Child).Foreground = raw ? t.Accent : t.Secondary;
                srcBtn.ToolTip = raw ? "Show Rendered Equation" : "View LaTeX Source";
                render();
            };
            srcBtn.Visibility = Visibility.Hidden;
            var tools = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 4, 4, 0) };
            tools.Children.Add(srcBtn); tools.Children.Add(copyBtn);
            var g = new Grid();
            g.Children.Add(host);
            g.Children.Add(tools);
            var card = new Border { Child = g, CornerRadius = new CornerRadius(8), Background = t.P(0.04), BorderBrush = t.P(0.10), BorderThickness = new Thickness(1), Margin = new Thickness(0, 4, 0, 4) };
            card.MouseEnter += delegate { srcBtn.Visibility = Visibility.Visible; copyBtn.Opacity = 1; };
            card.MouseLeave += delegate { if (!raw) srcBtn.Visibility = Visibility.Hidden; copyBtn.Opacity = 0.65; };
            return card;
        }
    }
}
