// Port of CollabTextOperation.swift — collaboration protocol "ot1": operational transformation over plain text, wire-compatible
// with ot.js TextOperation so the web portal, macOS and Windows clients share one algorithm.
//   • Offsets and lengths are UTF-16 code units — exactly C# string indices.
//   • JSON form is an array: a positive integer retains n units, a negative integer deletes n units, a string inserts it.
//     Example: [4, -2, "ab", 10].
//   • The host is authoritative (OTServerDocument): it orders operations into revisions, transforms late operations against
//     everything committed since the client's base revision, and broadcasts the result. Clients (OTClient) keep at most one
//     operation in flight plus a composed buffer, like the ot.js Client.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

namespace MicroCode.Views
{
    public class OTException : Exception
    {
        public OTException(string message) : base(message) { }
    }

    public sealed class TextOperation
    {
        public enum Kind { Retain, Insert, Delete }

        public struct Component
        {
            public Kind Kind;
            public int Count;     // retain / delete
            public string Text;   // insert
            public static Component Retain(int n) { return new Component { Kind = Kind.Retain, Count = n }; }
            public static Component Insert(string s) { return new Component { Kind = Kind.Insert, Text = s }; }
            public static Component Delete(int n) { return new Component { Kind = Kind.Delete, Count = n }; }
        }

        readonly List<Component> _ops = new List<Component>();
        public IList<Component> Components { get { return _ops.AsReadOnly(); } }
        /// <summary>Length of the document this operation applies to.</summary>
        public int BaseLength { get; private set; }
        /// <summary>Length of the document after applying it.</summary>
        public int TargetLength { get; private set; }

        public bool IsNoop { get { return _ops.Count == 0 || (_ops.Count == 1 && _ops[0].Kind == Kind.Retain); } }

        // ── builders (canonical form: adjacent components merged, insert before delete) ──

        /// <summary>No document, component or running length may exceed this (a hostile op such as
        /// [2147483647,2147483647,4] would otherwise wrap the int lengths and slip past every size check).</summary>
        public const int MaxLength = 8000000;

        static int Add(int a, int b)
        {
            long r = (long)a + b;
            if (r > MaxLength) throw new OTException("operation too large");
            return (int)r;
        }

        public TextOperation Retain(int n)
        {
            if (n <= 0) return this;
            BaseLength = Add(BaseLength, n); TargetLength = Add(TargetLength, n);
            if (_ops.Count > 0 && _ops[_ops.Count - 1].Kind == Kind.Retain) _ops[_ops.Count - 1] = Component.Retain(_ops[_ops.Count - 1].Count + n);
            else _ops.Add(Component.Retain(n));
            return this;
        }

        public TextOperation Insert(string text)
        {
            if (string.IsNullOrEmpty(text)) return this;
            TargetLength = Add(TargetLength, text.Length);
            int count = _ops.Count;
            if (count > 0 && _ops[count - 1].Kind == Kind.Insert) _ops[count - 1] = Component.Insert(_ops[count - 1].Text + text);
            else if (count > 0 && _ops[count - 1].Kind == Kind.Delete)
            {
                if (count >= 2 && _ops[count - 2].Kind == Kind.Insert) _ops[count - 2] = Component.Insert(_ops[count - 2].Text + text);
                else _ops.Insert(count - 1, Component.Insert(text));
            }
            else _ops.Add(Component.Insert(text));
            return this;
        }

        public TextOperation Delete(int n)
        {
            if (n <= 0) return this;
            BaseLength = Add(BaseLength, n);
            if (_ops.Count > 0 && _ops[_ops.Count - 1].Kind == Kind.Delete) _ops[_ops.Count - 1] = Component.Delete(_ops[_ops.Count - 1].Count + n);
            else _ops.Add(Component.Delete(n));
            return this;
        }

        // ── apply ──

        public string Apply(string document)
        {
            document = document ?? "";
            if (document.Length != BaseLength) throw new OTException("base length mismatch: expected " + BaseLength + ", got " + document.Length);
            var sb = new StringBuilder(TargetLength);
            int index = 0;
            foreach (var c in _ops)
            {
                switch (c.Kind)
                {
                    case Kind.Retain: sb.Append(document, index, c.Count); index += c.Count; break;
                    case Kind.Insert: sb.Append(c.Text); break;
                    case Kind.Delete: index += c.Count; break;
                }
            }
            return sb.ToString();
        }

        /// <summary>Maps a caret / selection offset in the base document to the target document. Text inserted exactly at the
        /// offset leaves it in place (remote typing appears after your caret) unless stickToInsertEnd.</summary>
        public int TransformIndex(int index, bool stickToInsertEnd = false)
        {
            int newIndex = index, position = 0;
            foreach (var c in _ops)
            {
                if (position > index) break;
                switch (c.Kind)
                {
                    case Kind.Retain: position += c.Count; break;
                    case Kind.Insert: if (position < index || stickToInsertEnd) newIndex += c.Text.Length; break;
                    case Kind.Delete: if (position < index) newIndex -= Math.Min(c.Count, index - position); position += c.Count; break;
                }
            }
            return Math.Max(0, newIndex);
        }

        // ── compose / transform (ot.js algorithms) ──

        /// <summary>An operation equivalent to applying this, then other.</summary>
        public TextOperation Compose(TextOperation other)
        {
            if (TargetLength != other.BaseLength) throw new OTException("compose: base length mismatch: expected " + TargetLength + ", got " + other.BaseLength);
            var result = new TextOperation();
            int ia = 0, ib = 0;
            Component? a = _ops.Count > 0 ? _ops[0] : (Component?)null;
            Component? b = other._ops.Count > 0 ? other._ops[0] : (Component?)null;
            Action nextA = () => { ia++; a = ia < _ops.Count ? _ops[ia] : (Component?)null; };
            Action nextB = () => { ib++; b = ib < other._ops.Count ? other._ops[ib] : (Component?)null; };
            while (a.HasValue || b.HasValue)
            {
                if (a.HasValue && a.Value.Kind == Kind.Delete) { result.Delete(a.Value.Count); nextA(); continue; }
                if (b.HasValue && b.Value.Kind == Kind.Insert) { result.Insert(b.Value.Text); nextB(); continue; }
                if (!a.HasValue || !b.HasValue) throw new OTException("compose: operation too short");
                var ca = a.Value; var cb = b.Value;
                if (ca.Kind == Kind.Retain && cb.Kind == Kind.Retain)
                {
                    int x = ca.Count, y = cb.Count;
                    result.Retain(Math.Min(x, y));
                    if (x > y) { a = Component.Retain(x - y); nextB(); } else if (x == y) { nextA(); nextB(); } else { b = Component.Retain(y - x); nextA(); }
                }
                else if (ca.Kind == Kind.Retain && cb.Kind == Kind.Delete)
                {
                    int x = ca.Count, y = cb.Count;
                    result.Delete(Math.Min(x, y));
                    if (x > y) { a = Component.Retain(x - y); nextB(); } else if (x == y) { nextA(); nextB(); } else { b = Component.Delete(y - x); nextA(); }
                }
                else if (ca.Kind == Kind.Insert && cb.Kind == Kind.Retain)
                {
                    int len = ca.Text.Length, y = cb.Count;
                    if (len > y) { result.Insert(ca.Text.Substring(0, y)); a = Component.Insert(ca.Text.Substring(y)); nextB(); }
                    else if (len == y) { result.Insert(ca.Text); nextA(); nextB(); }
                    else { result.Insert(ca.Text); b = Component.Retain(y - len); nextA(); }
                }
                else if (ca.Kind == Kind.Insert && cb.Kind == Kind.Delete)
                {
                    int len = ca.Text.Length, y = cb.Count;
                    if (len > y) { a = Component.Insert(ca.Text.Substring(y)); nextB(); }
                    else if (len == y) { nextA(); nextB(); }
                    else { b = Component.Delete(y - len); nextA(); }
                }
                else throw new OTException("compose: operation too short");
            }
            return result;
        }

        /// <summary>ot.js transform(a, b): (a', b') with apply(apply(S, a), b') == apply(apply(S, b), a'). When both insert at
        /// the same offset, a's text goes first — every side must use the same order (client operation first, host second).</summary>
        public static Tuple<TextOperation, TextOperation> Transform(TextOperation lhs, TextOperation rhs)
        {
            if (lhs.BaseLength != rhs.BaseLength) throw new OTException("transform: base length mismatch: " + lhs.BaseLength + " vs " + rhs.BaseLength);
            var aPrime = new TextOperation(); var bPrime = new TextOperation();
            int ia = 0, ib = 0;
            Component? a = lhs._ops.Count > 0 ? lhs._ops[0] : (Component?)null;
            Component? b = rhs._ops.Count > 0 ? rhs._ops[0] : (Component?)null;
            Action nextA = () => { ia++; a = ia < lhs._ops.Count ? lhs._ops[ia] : (Component?)null; };
            Action nextB = () => { ib++; b = ib < rhs._ops.Count ? rhs._ops[ib] : (Component?)null; };
            while (a.HasValue || b.HasValue)
            {
                if (a.HasValue && a.Value.Kind == Kind.Insert) { aPrime.Insert(a.Value.Text); bPrime.Retain(a.Value.Text.Length); nextA(); continue; }
                if (b.HasValue && b.Value.Kind == Kind.Insert) { aPrime.Retain(b.Value.Text.Length); bPrime.Insert(b.Value.Text); nextB(); continue; }
                if (!a.HasValue || !b.HasValue) throw new OTException("transform: operation too short");
                var ca = a.Value; var cb = b.Value;
                int x = ca.Count, y = cb.Count;
                if (ca.Kind == Kind.Retain && cb.Kind == Kind.Retain)
                {
                    int m = Math.Min(x, y);
                    aPrime.Retain(m); bPrime.Retain(m);
                    if (x > y) { a = Component.Retain(x - y); nextB(); } else if (x == y) { nextA(); nextB(); } else { b = Component.Retain(y - x); nextA(); }
                }
                else if (ca.Kind == Kind.Delete && cb.Kind == Kind.Delete)
                {
                    if (x > y) { a = Component.Delete(x - y); nextB(); } else if (x == y) { nextA(); nextB(); } else { b = Component.Delete(y - x); nextA(); }
                }
                else if (ca.Kind == Kind.Delete && cb.Kind == Kind.Retain)
                {
                    aPrime.Delete(Math.Min(x, y));
                    if (x > y) { a = Component.Delete(x - y); nextB(); } else if (x == y) { nextA(); nextB(); } else { b = Component.Retain(y - x); nextA(); }
                }
                else if (ca.Kind == Kind.Retain && cb.Kind == Kind.Delete)
                {
                    bPrime.Delete(Math.Min(x, y));
                    if (x > y) { a = Component.Retain(x - y); nextB(); } else if (x == y) { nextA(); nextB(); } else { b = Component.Delete(y - x); nextA(); }
                }
                else throw new OTException("transform: operation too short");
            }
            return Tuple.Create(aPrime, bPrime);
        }

        // ── diff ──

        /// <summary>Single-splice operation turning old into new (common prefix + suffix). Never splits a surrogate pair, so
        /// every inserted string is valid Unicode on the wire.</summary>
        public static TextOperation FromDiff(string oldText, string newText)
        {
            oldText = oldText ?? ""; newText = newText ?? "";
            int prefix = 0, maxPrefix = Math.Min(oldText.Length, newText.Length);
            while (prefix < maxPrefix && oldText[prefix] == newText[prefix]) prefix++;
            if (prefix > 0 && char.IsHighSurrogate(oldText[prefix - 1])) prefix--;
            int suffix = 0, maxSuffix = Math.Min(oldText.Length, newText.Length) - prefix;
            while (suffix < maxSuffix && oldText[oldText.Length - 1 - suffix] == newText[newText.Length - 1 - suffix]) suffix++;
            if (suffix > 0 && char.IsLowSurrogate(oldText[oldText.Length - suffix])) suffix--;
            var op = new TextOperation();
            op.Retain(prefix);
            op.Insert(newText.Substring(prefix, newText.Length - suffix - prefix));
            op.Delete(oldText.Length - prefix - suffix);
            op.Retain(suffix);
            return op;
        }

        // ── JSON ──

        public List<object> ToJson()
        {
            return _ops.Select(c => c.Kind == Kind.Retain ? (object)c.Count : c.Kind == Kind.Insert ? (object)c.Text : (object)(-c.Count)).ToList();
        }

        /// <summary>From the JSON array (as JavaScriptSerializer decodes it). Throws OTException on anything that is not a
        /// string or a non-zero integer (booleans and fractions are rejected, like the Swift decoder).</summary>
        public static TextOperation FromJson(object raw)
        {
            System.Collections.IEnumerable items = raw as object[];
            if (items == null) items = raw as System.Collections.ArrayList;
            if (items == null || raw is string) throw new OTException("invalid operation JSON");
            var op = new TextOperation();
            foreach (var item in items)
            {
                var s = item as string;
                if (s != null) { op.Insert(s); continue; }
                if (item is bool || item == null) throw new OTException("invalid operation JSON");
                long value;
                if (item is int) value = (int)item;
                else if (item is long) value = (long)item;
                else if (item is decimal || item is double || item is float)
                {
                    double d = Convert.ToDouble(item, CultureInfo.InvariantCulture);
                    if (double.IsNaN(d) || double.IsInfinity(d) || d != Math.Floor(d) || Math.Abs(d) > MaxLength) throw new OTException("invalid operation JSON");
                    value = (long)d;
                }
                else throw new OTException("invalid operation JSON");
                if (value == 0 || value > MaxLength || value < -MaxLength) throw new OTException("invalid operation JSON");
                if (value > 0) op.Retain((int)value); else op.Delete((int)(-value));
            }
            return op;
        }

        public override bool Equals(object obj)
        {
            var o = obj as TextOperation;
            if (o == null || o._ops.Count != _ops.Count || o.BaseLength != BaseLength || o.TargetLength != TargetLength) return false;
            for (int i = 0; i < _ops.Count; i++)
                if (_ops[i].Kind != o._ops[i].Kind || _ops[i].Count != o._ops[i].Count || _ops[i].Text != o._ops[i].Text) return false;
            return true;
        }

        public override int GetHashCode() { return BaseLength * 31 + TargetLength; }
    }

    public static class OTEditorPatch
    {
        /// <summary>The op to patch into an editor that should hold previous but already holds current (keystrokes typed after
        /// the op was committed): those keystrokes are transformed over it, client first, so neither side is lost.</summary>
        public static TextOperation Rebase(string previous, string current, TextOperation op)
        {
            if (current == previous) return op;
            var local = TextOperation.FromDiff(previous, current);
            return TextOperation.Transform(local, op).Item2;
        }
    }

    /// <summary>Client half of ot1 (ot.js Client): at most one operation awaits the host's ack; later local edits compose into
    /// the buffer. Remote operations are transformed against both before they touch the local text.</summary>
    public sealed class OTClient
    {
        public int Revision { get; private set; }
        public TextOperation Outstanding { get; private set; }
        public TextOperation Buffer { get; private set; }

        public OTClient(int revision) { Revision = revision; }

        public bool IsSynchronized { get { return Outstanding == null; } }

        /// <summary>A local edit. Returns the operation to send now (null while another one is in flight).</summary>
        public TextOperation ApplyLocal(TextOperation op)
        {
            if (op.IsNoop) return null;
            if (Outstanding == null) { Outstanding = op; return op; }
            Buffer = Buffer != null ? Buffer.Compose(op) : op;
            return null;
        }

        /// <summary>The host acknowledged our outstanding operation as revision. Returns the buffered operation to send next.</summary>
        public TextOperation Acknowledge(int revision)
        {
            Revision = revision;
            Outstanding = Buffer;
            Buffer = null;
            return Outstanding;
        }

        /// <summary>Another participant's operation committed as revision: returned transformed for the local text.</summary>
        public TextOperation ApplyRemote(TextOperation op, int revision)
        {
            Revision = revision;
            var remote = op;
            if (Outstanding != null) { var t = TextOperation.Transform(Outstanding, remote); Outstanding = t.Item1; remote = t.Item2; }
            if (Buffer != null) { var t = TextOperation.Transform(Buffer, remote); Buffer = t.Item1; remote = t.Item2; }
            return remote;
        }

        /// <summary>Drops all local state after the host sent a full snapshot (resync).</summary>
        public void Reset(int revision) { Revision = revision; Outstanding = null; Buffer = null; }
    }

    /// <summary>Host half of ot1: the authoritative document and the operation log late clients are transformed against.</summary>
    public sealed class OTServerDocument
    {
        public sealed class Commit
        {
            public int Revision;
            public TextOperation Operation;
            public string AuthorId, OpId;
        }

        public enum ReceiveError { None, StaleBase, Invalid }

        public string Content { get; private set; }
        public int Revision { get; private set; }
        readonly List<Commit> _history = new List<Commit>();
        public IList<Commit> History { get { return _history.AsReadOnly(); } }
        public readonly int MaxHistory;

        public OTServerDocument(string content, int revision, int maxHistory = 1000)
        {
            Content = content ?? ""; Revision = revision; MaxHistory = Math.Max(16, maxHistory);
        }

        /// <summary>Commits a client operation made against baseRevision. A retransmitted opId returns the original commit.
        /// On failure returns null and sets error (StaleBase: the base fell out of the retained history — reload the file).</summary>
        public Commit Receive(TextOperation op, int baseRevision, string authorId, string opId, out ReceiveError error)
        {
            error = ReceiveError.None;
            if (!string.IsNullOrEmpty(opId))
            {
                var existing = _history.LastOrDefault(c => c.OpId == opId && c.AuthorId == authorId);
                if (existing != null) return existing;
            }
            if (baseRevision > Revision) { error = ReceiveError.Invalid; return null; }
            int oldest = Revision - _history.Count;
            if (baseRevision < oldest) { error = ReceiveError.StaleBase; return null; }
            var transformed = op;
            string next;
            try
            {
                foreach (var c in _history.Where(c => c.Revision > baseRevision)) transformed = TextOperation.Transform(transformed, c.Operation).Item1;
                next = transformed.Apply(Content);
            }
            catch (OTException) { error = ReceiveError.Invalid; return null; }
            return Record(transformed, next, authorId, opId);
        }

        /// <summary>Records a change that did not arrive as an operation (host editor, disk write, legacy full-text edit).
        /// Returns null when the text is unchanged.</summary>
        public Commit ReplaceContent(string newContent, string authorId)
        {
            newContent = newContent ?? "";
            if (newContent == Content) return null;
            return Record(TextOperation.FromDiff(Content, newContent), newContent, authorId, null);
        }

        /// <summary>Operations committed after baseRevision, or null if they are no longer retained.</summary>
        public List<Commit> OperationsSince(int baseRevision)
        {
            if (baseRevision > Revision || baseRevision < Revision - _history.Count) return null;
            return _history.Where(c => c.Revision > baseRevision).ToList();
        }

        Commit Record(TextOperation op, string next, string authorId, string opId)
        {
            Revision++;
            Content = next;
            var entry = new Commit { Revision = Revision, Operation = op, AuthorId = authorId, OpId = opId };
            _history.Add(entry);
            if (_history.Count > MaxHistory) _history.RemoveRange(0, _history.Count - MaxHistory);
            return entry;
        }
    }
}
