// Native code editor: a WPF TextBox does all editing (caret, selection, undo, IME, clipboard) with transparent glyphs,
// while a layer underneath paints syntax colours and the current-line highlight, and a gutter paints line numbers
// (port of SyntaxHighlightedCodeView + LineNumberRulerView).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using MicroCode.Core;
using MicroCode.UI;

namespace MicroCode.Editor
{
    public class CodeEditorView : Grid
    {
        public readonly TextBox Box;
        readonly HighlightLayer _layer;
        readonly GutterView _gutter;
        internal Highlighter Hl;
        internal Syntax Syn;
        internal readonly List<int> LineStarts = new List<int> { 0 };
        internal readonly List<int> LineStates = new List<int> { 0 };
        internal string Text = "";
        internal Typeface Face;
        internal double FontPx, LineHeight, CharWidth;
        internal Point Origin;           // un-scrolled position of character 0 inside the TextBox
        internal int CaretLine;
        bool _suppress;

        public event Action<string> TextEdited;
        public event Action CaretMoved;

        static Style _boxStyle;

        readonly FontFamily _family;
        public CodeEditorView(string text, string language, double fontSize) : this(text, language, fontSize, UIFonts.Code("editorFontFamily", "SF Mono")) { }

        public CodeEditorView(string text, string language, double fontSize, FontFamily family)
        {
            _family = family;
            Syn = Theme.Current.Syntax;
            Hl = Highlighter.For(language);
            ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            Background = Theme.B(Syn.Background);
            ClipToBounds = true;

            _gutter = new GutterView(this);
            SetColumn(_gutter, 0);
            Children.Add(_gutter);

            var area = new Grid { ClipToBounds = true };
            SetColumn(area, 1);
            Children.Add(area);
            _layer = new HighlightLayer(this);
            area.Children.Add(_layer);

            if (_boxStyle == null)
            {
                _boxStyle = (Style)System.Windows.Markup.XamlReader.Parse(@"<Style TargetType='TextBox' xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'>
  <Setter Property='FocusVisualStyle' Value='{x:Null}'/>
  <Setter Property='Template'><Setter.Value><ControlTemplate TargetType='TextBox'>
    <ScrollViewer x:Name='PART_ContentHost' Focusable='False' HorizontalScrollBarVisibility='Auto' VerticalScrollBarVisibility='Auto' CanContentScroll='True'/>
  </ControlTemplate></Setter.Value></Setter></Style>");
            }
            Box = new TextBox
            {
                Style = _boxStyle,
                AcceptsReturn = true, AcceptsTab = true, TextWrapping = TextWrapping.NoWrap,
                Background = Brushes.Transparent, BorderThickness = new Thickness(0), Foreground = Brushes.Transparent,
                Padding = new Thickness(8, 8, 8, 8), FontFamily = family,
                IsInactiveSelectionHighlightEnabled = true, IsUndoEnabled = true, UndoLimit = 500,
                SelectionOpacity = 1
            };
            TextOptions.SetTextFormattingMode(Box, TextFormattingMode.Ideal);
            area.Children.Add(Box);
            SetFont(fontSize);
            ApplySyntaxTheme();

            _suppress = true;
            Box.Text = text ?? "";
            _suppress = false;
            Text = Box.Text;
            Reindex();

            Box.TextChanged += delegate
            {
                Text = Box.Text;
                Reindex();
                Redraw();
                if (!_suppress && TextEdited != null) TextEdited(Text);
            };
            Box.SelectionChanged += delegate
            {
                int line = LineOf(Box.CaretIndex);
                if (line != CaretLine) { CaretLine = line; Redraw(); }
                if (CaretMoved != null) CaretMoved();
            };
            Box.AddHandler(ScrollViewer.ScrollChangedEvent, new ScrollChangedEventHandler(delegate { Redraw(); }));
            Box.LayoutUpdated += delegate { Calibrate(); };
            Box.PreviewKeyDown += OnKey;
        }

        public void SetFont(double size)
        {
            FontPx = size;
            Box.FontSize = size;
            Face = new Typeface(_family, FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
            LineHeight = Math.Round(_family.LineSpacing * size, 2);
            _gutter.Visibility = Defaults.Bool("showLineNumbers", true) ? Visibility.Visible : Visibility.Collapsed;
            var ft = new FormattedText("0000000000", CultureInfo.InvariantCulture, FlowDirection.LeftToRight, Face, size, Brushes.White, 1.0);
            CharWidth = ft.WidthIncludingTrailingWhitespace / 10.0;
            _gutter.InvalidateMeasure();
            Redraw();
        }

        bool _transparent;
        /// <summary>SyntaxHighlightedCodeView(isTransparent: true): no editor/gutter fill and the current-line highlight only while
        /// focused, so the editor sits on its container (Cell Mode cards).</summary>
        public bool Transparent
        {
            get { return _transparent; }
            set
            {
                _transparent = value;
                Background = value ? Brushes.Transparent : Theme.B(Syn.Background);
                Box.GotKeyboardFocus -= OnFocusRedraw; Box.LostKeyboardFocus -= OnFocusRedraw;
                if (value) { Box.GotKeyboardFocus += OnFocusRedraw; Box.LostKeyboardFocus += OnFocusRedraw; }
                Redraw();
            }
        }
        void OnFocusRedraw(object s, KeyboardFocusChangedEventArgs e) { Redraw(); }

        public int LineCount { get { return LineStarts.Count; } }
        public double LineHeightPx { get { return LineHeight; } }

        /// <summary>Width of the longest line in the editor font (decides whether a horizontal scrollbar will show).</summary>
        public double LongestLineWidth
        {
            get
            {
                int longest = 0;
                for (int l = 0; l < LineStarts.Count; l++)
                {
                    int s = LineStarts[l], e = l + 1 < LineStarts.Count ? LineStarts[l + 1] - 1 : Text.Length;
                    longest = Math.Max(longest, e - s);
                }
                return longest * CharWidth + 16;
            }
        }

        public void ApplySyntaxTheme()
        {
            Syn = Theme.Current.Syntax;
            Background = _transparent ? Brushes.Transparent : Theme.B(Syn.Background);
            Box.CaretBrush = Theme.B(Syn.Cursor);
            Box.SelectionBrush = Theme.B(Syn.Selection);
            _layer.Cache.Clear();
            Redraw();
        }

        public void SetLanguage(string lang)
        {
            Hl = Highlighter.For(lang);
            Reindex();
            Redraw();
        }

        public void Redraw()
        {
            _layer.InvalidateVisual();
            _gutter.InvalidateVisual();
            _gutter.InvalidateMeasure();
        }

        void Calibrate()
        {
            if (Text.Length == 0 && Box.ActualWidth <= 0) return;
            try
            {
                var r = Box.GetRectFromCharacterIndex(0);
                if (r.IsEmpty || double.IsInfinity(r.X)) return;
                var o = new Point(r.X + Box.HorizontalOffset, r.Y + Box.VerticalOffset);
                double lh = LineHeight;
                if (LineStarts.Count > 1)
                {
                    var r2 = Box.GetRectFromCharacterIndex(LineStarts[1]);
                    if (!r2.IsEmpty && r2.Y > r.Y) lh = r2.Y - r.Y;
                }
                if (Math.Abs(o.X - Origin.X) > 0.01 || Math.Abs(o.Y - Origin.Y) > 0.01 || Math.Abs(lh - LineHeight) > 0.01)
                {
                    Origin = o; LineHeight = lh; Redraw();
                }
            }
            catch { }
        }

        internal int LineOf(int index)
        {
            int lo = 0, hi = LineStarts.Count - 1;
            while (lo < hi)
            {
                int mid = (lo + hi + 1) / 2;
                if (LineStarts[mid] <= index) lo = mid; else hi = mid - 1;
            }
            return lo;
        }

        internal string LineText(int line)
        {
            int s = LineStarts[line];
            int e = line + 1 < LineStarts.Count ? LineStarts[line + 1] - 1 : Text.Length;
            if (e > s && e <= Text.Length && Text[e - 1] == '\r') e--;
            return e > s ? Text.Substring(s, e - s) : "";
        }

        readonly List<Span> _scratch = new List<Span>();

        void Reindex()
        {
            LineStarts.Clear(); LineStarts.Add(0);
            for (int i = 0; i < Text.Length; i++) if (Text[i] == '\n') LineStarts.Add(i + 1);
            LineStates.Clear();
            int st = 0;
            for (int l = 0; l < LineStarts.Count; l++)
            {
                LineStates.Add(st);
                if (LineStarts.Count > 20000) continue; // huge files: skip multi-line state tracking
                _scratch.Clear();
                st = Hl.Tokenize(LineText(l), st, _scratch);
            }
            CaretLine = LineOf(Box.CaretIndex);
        }

        // MARK: - Editing behaviours (auto-indent, soft tabs)
        void OnKey(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Enter && Keyboard.Modifiers == ModifierKeys.None)
            {
                int line = LineOf(Box.CaretIndex);
                string cur = LineText(line);
                int ws = 0; while (ws < cur.Length && (cur[ws] == ' ' || cur[ws] == '\t')) ws++;
                string indent = cur.Substring(0, ws);
                int col = Box.CaretIndex - LineStarts[line];
                string before = cur.Substring(0, Math.Min(col, cur.Length)).TrimEnd();
                if (before.EndsWith("{") || before.EndsWith("[") || before.EndsWith("(") || (before.EndsWith(":") && (Hl.Language == "python" || Hl.Language == "yaml"))) indent += "    ";
                Box.SelectedText = "\n" + indent;
                Box.CaretIndex = Box.SelectionStart + Box.SelectionLength;
                Box.SelectionLength = 0;
                e.Handled = true;
            }
            else if (e.Key == Key.Tab && (Keyboard.Modifiers == ModifierKeys.None || Keyboard.Modifiers == ModifierKeys.Shift))
            {
                bool outdent = Keyboard.Modifiers == ModifierKeys.Shift;
                int a = LineOf(Box.SelectionStart), b = LineOf(Box.SelectionStart + Math.Max(0, Box.SelectionLength - 1));
                if (!outdent && a == b && Box.SelectionLength == 0)
                {
                    Box.SelectedText = "    ";
                    Box.CaretIndex = Box.SelectionStart + 4; Box.SelectionLength = 0;
                }
                else
                {
                    int start = LineStarts[a];
                    int end = b + 1 < LineStarts.Count ? LineStarts[b + 1] - 1 : Text.Length;
                    var lines = Text.Substring(start, end - start).Split('\n');
                    for (int i = 0; i < lines.Length; i++)
                    {
                        if (outdent)
                        {
                            int k = 0; while (k < 4 && k < lines[i].Length && lines[i][k] == ' ') k++;
                            if (k == 0 && lines[i].StartsWith("\t")) k = 1;
                            lines[i] = lines[i].Substring(k);
                        }
                        else lines[i] = "    " + lines[i];
                    }
                    string joined = string.Join("\n", lines);
                    Box.Select(start, end - start);
                    Box.SelectedText = joined;
                    Box.Select(start, joined.Length);
                }
                e.Handled = true;
            }
        }

        /// <summary>Takes text that changed outside the editor (a collaborator, the agent) without raising TextEdited: only the
        /// changed middle is replaced, so undo keeps working and a caret after the change moves with the text.</summary>
        public void ReplaceText(string text)
        {
            text = text ?? "";
            string old = Box.Text;
            if (old == text) return;
            int pre = 0, max = Math.Min(old.Length, text.Length);
            while (pre < max && old[pre] == text[pre]) pre++;
            int suf = 0;
            while (suf < old.Length - pre && suf < text.Length - pre && old[old.Length - 1 - suf] == text[text.Length - 1 - suf]) suf++;
            int caret = Box.CaretIndex, selLen = Box.SelectionLength;
            int delta = text.Length - old.Length;
            _suppress = true;
            try
            {
                Box.Select(pre, old.Length - pre - suf);
                Box.SelectedText = text.Substring(pre, text.Length - pre - suf);
            }
            finally { _suppress = false; }
            int len = Box.Text.Length;
            if (caret + selLen <= pre) Box.Select(caret, selLen);                                        // wholly before the change
            else if (caret >= old.Length - suf) Box.Select(Math.Min(len, caret + delta), Math.Min(selLen, Math.Max(0, len - caret - delta))); // wholly after
            else Box.Select(Math.Min(len, pre + (text.Length - pre - suf)), 0);                           // inside it: end of the new text
        }

        /// <summary>collabApplyRemoteOperation: patches a collaborator's ot1 operation into the text in place (never re-assigning
        /// the document), maps the caret and selection through it (text inserted at the caret stays after it) and keeps the lines
        /// in view where they were. Does not raise TextEdited. False when the operation does not fit the current text.</summary>
        public bool ApplyOperation(MicroCode.Views.TextOperation op)
        {
            string text = Box.Text;
            if (op == null || text.Length != op.BaseLength) return false;
            if (op.IsNoop) return true;
            // splices in base coordinates
            var splices = new List<Tuple<int, int, string>>();
            int pos = 0;
            foreach (var c in op.Components)
            {
                if (c.Kind == MicroCode.Views.TextOperation.Kind.Retain) pos += c.Count;
                else if (c.Kind == MicroCode.Views.TextOperation.Kind.Insert) splices.Add(Tuple.Create(pos, 0, c.Text));
                else { splices.Add(Tuple.Create(pos, c.Count, "")); pos += c.Count; }
            }
            int caret = Box.SelectionStart, selEnd = Box.SelectionStart + Box.SelectionLength;
            int newStart = op.TransformIndex(caret), newEnd = op.TransformIndex(selEnd);
            // scroll anchor: lines added / removed above the first visible line
            int firstVisible = 0;
            try { int fl = Box.GetFirstVisibleLineIndex(); if (fl >= 0) firstVisible = Box.GetCharacterIndexFromLineIndex(fl); } catch (ArgumentOutOfRangeException) { firstVisible = 0; }
            int lineDelta = 0;
            foreach (var sp in splices.Where(s => s.Item1 < firstVisible))
                lineDelta += sp.Item3.Count(ch => ch == '\n') - text.Substring(sp.Item1, Math.Min(sp.Item2, Math.Max(0, firstVisible - sp.Item1))).Count(ch => ch == '\n');
            double vOff = Box.VerticalOffset;
            _suppress = true;
            try
            {
                for (int i = splices.Count - 1; i >= 0; i--)
                {
                    var sp = splices[i];
                    Box.Select(sp.Item1, sp.Item2);
                    Box.SelectedText = sp.Item3;
                }
            }
            finally { _suppress = false; }
            int len = Box.Text.Length;
            newStart = Math.Max(0, Math.Min(len, newStart)); newEnd = Math.Max(newStart, Math.Min(len, newEnd));
            Box.Select(newStart, newEnd - newStart);
            if (lineDelta != 0 && LineHeight > 0) Box.ScrollToVerticalOffset(Math.Max(0, vOff + lineDelta * LineHeight));
            else Box.ScrollToVerticalOffset(vOff);
            return true;
        }

        public void Focus2() { Box.Focus(); Keyboard.Focus(Box); }

        public void GoToLine(int line)
        {
            line = Math.Max(0, Math.Min(LineStarts.Count - 1, line));
            Box.CaretIndex = LineStarts[line];
            Box.ScrollToLine(line);
            Focus2();
        }
    }

    /// <summary>Paints syntax-coloured text and the current-line highlight beneath the transparent TextBox glyphs.</summary>
    class HighlightLayer : FrameworkElement
    {
        readonly CodeEditorView _ed;
        internal readonly Dictionary<string, Brush> Cache = new Dictionary<string, Brush>();
        readonly List<Span> _spans = new List<Span>();

        public HighlightLayer(CodeEditorView ed) { _ed = ed; IsHitTestVisible = false; SnapsToDevicePixels = true; }

        Brush BrushFor(string kind)
        {
            Brush b;
            if (!Cache.TryGetValue(kind, out b)) { b = Theme.B(_ed.Syn.Get(kind)); Cache[kind] = b; }
            return b;
        }

        protected override void OnRender(DrawingContext dc)
        {
            var ed = _ed;
            double w = ActualWidth, h = ActualHeight;
            if (w <= 0 || h <= 0) return;
            double dip = VisualTreeHelper.GetDpi(this).PixelsPerDip;
            double vOff = ed.Box.VerticalOffset, hOff = ed.Box.HorizontalOffset, lh = ed.LineHeight;
            if (lh <= 0) return;
            double oy = ed.Origin.Y, ox = ed.Origin.X;
            int first = Math.Max(0, (int)Math.Floor((vOff - oy) / lh));
            int last = Math.Min(ed.LineStarts.Count - 1, (int)Math.Ceiling((vOff + h - oy) / lh));
            // current line highlight (ThemeManager editorLineHighlight)
            if (ed.Box.SelectionLength == 0 && ed.CaretLine >= first && ed.CaretLine <= last && (!ed.Transparent || ed.Box.IsKeyboardFocused))
            {
                double y = oy + ed.CaretLine * lh - vOff;
                dc.DrawRectangle(Theme.B(ed.Syn.LineHighlight), null, new Rect(0, Math.Round(y), w, Math.Round(lh)));
            }
            var fg = BrushFor("__fg"); // unknown token kinds resolve to the editor foreground
            dc.PushClip(new RectangleGeometry(new Rect(0, 0, w, h)));
            for (int line = first; line <= last; line++)
            {
                string text = ed.LineText(line);
                if (text.Length == 0) continue;
                if (text.Length > 4000) text = text.Substring(0, 4000);
                double y = oy + line * lh - vOff;
                _spans.Clear();
                int state = line < ed.LineStates.Count ? ed.LineStates[line] : 0;
                ed.Hl.Tokenize(text, state, _spans);
                if (text.IndexOf('\t') < 0)
                {
                    var ft = new FormattedText(text, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, ed.Face, ed.FontPx, fg, dip);
                    foreach (var sp in _spans)
                    {
                        int s = Math.Max(0, sp.Start), l = Math.Min(sp.Length, text.Length - s);
                        if (l <= 0) continue;
                        ft.SetForegroundBrush(BrushFor(sp.Kind), s, l);
                        if (ed.Syn.Italic.Contains(sp.Kind)) ft.SetFontStyle(FontStyles.Italic, s, l);
                    }
                    dc.DrawText(ft, new Point(ox - hOff, y));
                }
                else
                {
                    // tab stops: ask the TextBox where each run starts so colours line up with its own tab layout
                    int lineStart = ed.LineStarts[line];
                    int pos = 0;
                    var runs = new List<Span>();
                    foreach (var sp in _spans) { if (sp.Start > pos) runs.Add(new Span(pos, sp.Start - pos, null)); runs.Add(sp); pos = sp.Start + sp.Length; }
                    if (pos < text.Length) runs.Add(new Span(pos, text.Length - pos, null));
                    foreach (var r in runs)
                    {
                        if (r.Length <= 0 || r.Start >= text.Length) continue;
                        int len = Math.Min(r.Length, text.Length - r.Start);
                        string seg = text.Substring(r.Start, len);
                        // split on tabs; each piece positioned from the TextBox
                        int k = 0;
                        while (k < seg.Length)
                        {
                            if (seg[k] == '\t') { k++; continue; }
                            int e = seg.IndexOf('\t', k); if (e < 0) e = seg.Length;
                            Rect rc;
                            try { rc = ed.Box.GetRectFromCharacterIndex(lineStart + r.Start + k); } catch { rc = Rect.Empty; }
                            if (!rc.IsEmpty && !double.IsInfinity(rc.X))
                            {
                                var ft = new FormattedText(seg.Substring(k, e - k), CultureInfo.InvariantCulture, FlowDirection.LeftToRight, ed.Face, ed.FontPx, r.Kind == null ? fg : BrushFor(r.Kind), dip);
                                if (r.Kind != null && ed.Syn.Italic.Contains(r.Kind)) ft.SetFontStyle(FontStyles.Italic);
                                dc.DrawText(ft, new Point(rc.X, y));
                            }
                            k = e;
                        }
                    }
                }
            }
            dc.Pop();
        }
    }

    /// <summary>LineNumberRulerView: monospaced-digit numbers (font size - 2), right aligned with 10pt padding, separator hairline.</summary>
    class GutterView : FrameworkElement
    {
        readonly CodeEditorView _ed;
        public GutterView(CodeEditorView ed) { _ed = ed; SnapsToDevicePixels = true; }

        double NumSize { get { return Math.Max(9, _ed.FontPx - 2); } }
        Typeface Tf(bool bold) { return new Typeface(UIFonts.UI, FontStyles.Normal, bold ? FontWeights.Medium : FontWeights.Normal, FontStretches.Normal); }

        protected override Size MeasureOverride(Size availableSize)
        {
            int digits = Math.Max(3, (_ed.LineStarts.Count).ToString().Length);
            var ft = new FormattedText(new string('8', digits), CultureInfo.InvariantCulture, FlowDirection.LeftToRight, Tf(false), NumSize, Brushes.White, 1.0);
            return new Size(Math.Ceiling(ft.Width) + 20, 0);
        }

        protected override void OnRender(DrawingContext dc)
        {
            var ed = _ed;
            double w = ActualWidth, h = ActualHeight;
            if (!ed.Transparent) dc.DrawRectangle(Theme.B(ed.Syn.Gutter), null, new Rect(0, 0, w, h));
            else dc.DrawRectangle(Brushes.Transparent, null, new Rect(0, 0, w, h));
            var sep = Theme.B(Theme.WithAlpha(Theme.Current.IsDark ? Colors.White : Colors.Black, 0.2 * 0.5));
            dc.DrawRectangle(sep, null, new Rect(w - 1, 0, 1, h));
            double lh = ed.LineHeight;
            if (lh <= 0) return;
            double dip = VisualTreeHelper.GetDpi(this).PixelsPerDip;
            double vOff = ed.Box.VerticalOffset, oy = ed.Origin.Y;
            int first = Math.Max(0, (int)Math.Floor((vOff - oy) / lh));
            int last = Math.Min(ed.LineStarts.Count - 1, (int)Math.Ceiling((vOff + h - oy) / lh));
            var normal = Theme.B(ed.Syn.GutterText);
            var current = Theme.B(Theme.WithAlpha(ed.Syn.Foreground, 0.86));
            // baseline-align numbers with the editor text
            var probeCode = new FormattedText("0", CultureInfo.InvariantCulture, FlowDirection.LeftToRight, ed.Face, ed.FontPx, normal, dip);
            for (int line = first; line <= last; line++)
            {
                bool cur = line == ed.CaretLine;
                var ft = new FormattedText((line + 1).ToString(), CultureInfo.InvariantCulture, FlowDirection.LeftToRight, Tf(cur), NumSize, cur ? current : normal, dip);
                double y = oy + line * lh - vOff + (probeCode.Baseline - ft.Baseline);
                dc.DrawText(ft, new Point(w - ft.Width - 10, y));
            }
        }
    }
}
