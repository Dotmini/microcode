// Real-time co-editing protocol "ot1": operational transformation over plain text, wire-compatible with ot.js
// TextOperation and Mac CollabTextOperation.swift so the web portal, macOS and Windows clients share one algorithm.
//
// * Offsets and lengths are UTF-16 code units (C#, JavaScript, and Swift utf16 all count UTF-16 code units).
// * JSON form is an array: positive integer retains n units, negative integer deletes n units, string inserts text.
//   Example: [4, -2, "ab", 10].
// * Canonical form merges adjacent components of the same kind and always orders inserts before deletes.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Web.Script.Serialization;

namespace MicroCode.Views
{
    public enum CollabOTErrorKind
    {
        BaseLengthMismatch,
        OperationTooShort,
        OperationTooLong,
        InvalidJson,
        StaleBase,
        InvalidOperation
    }

    public class CollabOTException : Exception
    {
        public readonly CollabOTErrorKind Kind;
        public readonly int Expected;
        public readonly int Actual;

        public int CurrentRevision { get { return Expected; } }

        public CollabOTException(CollabOTErrorKind kind, string message, int expected = 0, int actual = 0)
            : base(message)
        {
            Kind = kind;
            Expected = expected;
            Actual = actual;
        }
    }

    public enum CollabOTComponentKind
    {
        Retain,
        Insert,
        Delete
    }

    public struct CollabOTComponent : IEquatable<CollabOTComponent>
    {
        public CollabOTComponentKind Kind;
        public int Count;
        public string Text;

        public static CollabOTComponent CreateRetain(int n)
        {
            return new CollabOTComponent { Kind = CollabOTComponentKind.Retain, Count = n, Text = null };
        }

        public static CollabOTComponent CreateInsert(string text)
        {
            return new CollabOTComponent { Kind = CollabOTComponentKind.Insert, Count = 0, Text = text };
        }

        public static CollabOTComponent CreateDelete(int n)
        {
            return new CollabOTComponent { Kind = CollabOTComponentKind.Delete, Count = n, Text = null };
        }

        public bool Equals(CollabOTComponent other)
        {
            return Kind == other.Kind && Count == other.Count && string.Equals(Text, other.Text, StringComparison.Ordinal);
        }

        public override bool Equals(object obj)
        {
            return obj is CollabOTComponent && Equals((CollabOTComponent)obj);
        }

        public override int GetHashCode()
        {
            unchecked
            {
                int h = (int)Kind * 397 ^ Count;
                if (Text != null) h = (h * 397) ^ StringComparer.Ordinal.GetHashCode(Text);
                return h;
            }
        }
    }

    public class CollabTextOperation : IEquatable<CollabTextOperation>
    {
        static readonly JavaScriptSerializer Js = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };

        readonly List<CollabOTComponent> _components = new List<CollabOTComponent>();
        int _baseLength;
        int _targetLength;

        public ReadOnlyCollection<CollabOTComponent> Components { get { return _components.AsReadOnly(); } }
        public int BaseLength { get { return _baseLength; } }
        public int TargetLength { get { return _targetLength; } }

        public bool IsNoop
        {
            get
            {
                if (_components.Count == 0) return true;
                if (_components.Count == 1 && _components[0].Kind == CollabOTComponentKind.Retain) return true;
                return false;
            }
        }

        // ── Builders (canonical form: adjacent components merged, insert before delete) ──

        public CollabTextOperation Retain(int n)
        {
            if (n <= 0) return this;
            _baseLength += n;
            _targetLength += n;
            int count = _components.Count;
            if (count > 0 && _components[count - 1].Kind == CollabOTComponentKind.Retain)
            {
                var last = _components[count - 1];
                last.Count += n;
                _components[count - 1] = last;
            }
            else
            {
                _components.Add(CollabOTComponent.CreateRetain(n));
            }
            return this;
        }

        public CollabTextOperation Insert(string text)
        {
            if (string.IsNullOrEmpty(text)) return this;
            _targetLength += text.Length;
            int count = _components.Count;
            if (count > 0 && _components[count - 1].Kind == CollabOTComponentKind.Insert)
            {
                var last = _components[count - 1];
                last.Text = last.Text + text;
                _components[count - 1] = last;
            }
            else if (count > 0 && _components[count - 1].Kind == CollabOTComponentKind.Delete)
            {
                if (count >= 2 && _components[count - 2].Kind == CollabOTComponentKind.Insert)
                {
                    var prev = _components[count - 2];
                    prev.Text = prev.Text + text;
                    _components[count - 2] = prev;
                }
                else
                {
                    _components.Insert(count - 1, CollabOTComponent.CreateInsert(text));
                }
            }
            else
            {
                _components.Add(CollabOTComponent.CreateInsert(text));
            }
            return this;
        }

        public CollabTextOperation Delete(int n)
        {
            if (n <= 0) return this;
            _baseLength += n;
            int count = _components.Count;
            if (count > 0 && _components[count - 1].Kind == CollabOTComponentKind.Delete)
            {
                var last = _components[count - 1];
                last.Count += n;
                _components[count - 1] = last;
            }
            else
            {
                _components.Add(CollabOTComponent.CreateDelete(n));
            }
            return this;
        }

        // ── Apply & cursor transformation ──

        public string Apply(string document)
        {
            if (document == null) throw new ArgumentNullException("document");
            if (document.Length != _baseLength)
            {
                throw new CollabOTException(
                    CollabOTErrorKind.BaseLengthMismatch,
                    "Document length (" + document.Length + ") does not match operation baseLength (" + _baseLength + ").",
                    _baseLength,
                    document.Length);
            }
            var sb = new StringBuilder(_targetLength);
            int index = 0;
            for (int i = 0; i < _components.Count; i++)
            {
                var c = _components[i];
                switch (c.Kind)
                {
                    case CollabOTComponentKind.Retain:
                        sb.Append(document, index, c.Count);
                        index += c.Count;
                        break;
                    case CollabOTComponentKind.Insert:
                        sb.Append(c.Text);
                        break;
                    case CollabOTComponentKind.Delete:
                        index += c.Count;
                        break;
                }
            }
            return sb.ToString();
        }

        /// <summary>Maps a UTF-16 caret/selection offset in the base document to the target document.</summary>
        public int TransformIndex(int index, bool stickToInsertEnd = false)
        {
            int newIndex = index;
            int position = 0;
            for (int i = 0; i < _components.Count; i++)
            {
                if (position > index) break;
                var c = _components[i];
                switch (c.Kind)
                {
                    case CollabOTComponentKind.Retain:
                        position += c.Count;
                        break;
                    case CollabOTComponentKind.Insert:
                        if (position < index || stickToInsertEnd)
                        {
                            newIndex += c.Text.Length;
                        }
                        break;
                    case CollabOTComponentKind.Delete:
                        if (position < index)
                        {
                            newIndex -= Math.Min(c.Count, index - position);
                        }
                        position += c.Count;
                        break;
                }
            }
            return Math.Max(0, newIndex);
        }

        // ── Compose & Transform (ot.js algorithms) ──

        /// <summary>Returns an operation equivalent to applying this operation then other.</summary>
        public CollabTextOperation Compose(CollabTextOperation other)
        {
            if (other == null) throw new ArgumentNullException("other");
            if (_targetLength != other._baseLength)
            {
                throw new CollabOTException(
                    CollabOTErrorKind.BaseLengthMismatch,
                    "Cannot compose: targetLength (" + _targetLength + ") != other.baseLength (" + other._baseLength + ").",
                    _targetLength,
                    other._baseLength);
            }

            var result = new CollabTextOperation();
            int ia = 0, ib = 0;
            CollabOTComponent? a = _components.Count > 0 ? _components[0] : (CollabOTComponent?)null;
            CollabOTComponent? b = other._components.Count > 0 ? other._components[0] : (CollabOTComponent?)null;

            while (a.HasValue || b.HasValue)
            {
                if (a.HasValue && a.Value.Kind == CollabOTComponentKind.Delete)
                {
                    result.Delete(a.Value.Count);
                    ia++;
                    a = ia < _components.Count ? _components[ia] : (CollabOTComponent?)null;
                    continue;
                }
                if (b.HasValue && b.Value.Kind == CollabOTComponentKind.Insert)
                {
                    result.Insert(b.Value.Text);
                    ib++;
                    b = ib < other._components.Count ? other._components[ib] : (CollabOTComponent?)null;
                    continue;
                }
                if (!a.HasValue || !b.HasValue)
                {
                    throw new CollabOTException(CollabOTErrorKind.OperationTooShort, "Operation too short during Compose.");
                }

                var ca = a.Value;
                var cb = b.Value;
                if (ca.Kind == CollabOTComponentKind.Retain && cb.Kind == CollabOTComponentKind.Retain)
                {
                    int m = Math.Min(ca.Count, cb.Count);
                    result.Retain(m);
                    if (ca.Count > cb.Count)
                    {
                        a = CollabOTComponent.CreateRetain(ca.Count - cb.Count);
                        ib++; b = ib < other._components.Count ? other._components[ib] : (CollabOTComponent?)null;
                    }
                    else if (ca.Count == cb.Count)
                    {
                        ia++; a = ia < _components.Count ? _components[ia] : (CollabOTComponent?)null;
                        ib++; b = ib < other._components.Count ? other._components[ib] : (CollabOTComponent?)null;
                    }
                    else
                    {
                        b = CollabOTComponent.CreateRetain(cb.Count - ca.Count);
                        ia++; a = ia < _components.Count ? _components[ia] : (CollabOTComponent?)null;
                    }
                }
                else if (ca.Kind == CollabOTComponentKind.Retain && cb.Kind == CollabOTComponentKind.Delete)
                {
                    int m = Math.Min(ca.Count, cb.Count);
                    result.Delete(m);
                    if (ca.Count > cb.Count)
                    {
                        a = CollabOTComponent.CreateRetain(ca.Count - cb.Count);
                        ib++; b = ib < other._components.Count ? other._components[ib] : (CollabOTComponent?)null;
                    }
                    else if (ca.Count == cb.Count)
                    {
                        ia++; a = ia < _components.Count ? _components[ia] : (CollabOTComponent?)null;
                        ib++; b = ib < other._components.Count ? other._components[ib] : (CollabOTComponent?)null;
                    }
                    else
                    {
                        b = CollabOTComponent.CreateDelete(cb.Count - ca.Count);
                        ia++; a = ia < _components.Count ? _components[ia] : (CollabOTComponent?)null;
                    }
                }
                else if (ca.Kind == CollabOTComponentKind.Insert && cb.Kind == CollabOTComponentKind.Retain)
                {
                    int len = ca.Text.Length;
                    if (len > cb.Count)
                    {
                        result.Insert(ca.Text.Substring(0, cb.Count));
                        a = CollabOTComponent.CreateInsert(ca.Text.Substring(cb.Count));
                        ib++; b = ib < other._components.Count ? other._components[ib] : (CollabOTComponent?)null;
                    }
                    else if (len == cb.Count)
                    {
                        result.Insert(ca.Text);
                        ia++; a = ia < _components.Count ? _components[ia] : (CollabOTComponent?)null;
                        ib++; b = ib < other._components.Count ? other._components[ib] : (CollabOTComponent?)null;
                    }
                    else
                    {
                        result.Insert(ca.Text);
                        b = CollabOTComponent.CreateRetain(cb.Count - len);
                        ia++; a = ia < _components.Count ? _components[ia] : (CollabOTComponent?)null;
                    }
                }
                else if (ca.Kind == CollabOTComponentKind.Insert && cb.Kind == CollabOTComponentKind.Delete)
                {
                    int len = ca.Text.Length;
                    if (len > cb.Count)
                    {
                        a = CollabOTComponent.CreateInsert(ca.Text.Substring(cb.Count));
                        ib++; b = ib < other._components.Count ? other._components[ib] : (CollabOTComponent?)null;
                    }
                    else if (len == cb.Count)
                    {
                        ia++; a = ia < _components.Count ? _components[ia] : (CollabOTComponent?)null;
                        ib++; b = ib < other._components.Count ? other._components[ib] : (CollabOTComponent?)null;
                    }
                    else
                    {
                        b = CollabOTComponent.CreateDelete(cb.Count - len);
                        ia++; a = ia < _components.Count ? _components[ia] : (CollabOTComponent?)null;
                    }
                }
                else
                {
                    throw new CollabOTException(CollabOTErrorKind.OperationTooShort, "Unexpected component pair during Compose.");
                }
            }
            return result;
        }

        /// <summary>
        /// ot.js transform(a, b): returns (a', b') such that apply(apply(S, a), b') == apply(apply(S, b), a').
        /// When both insert at the same offset, lhs's text goes first (client op first, host op second).
        /// </summary>
        public static Tuple<CollabTextOperation, CollabTextOperation> Transform(CollabTextOperation lhs, CollabTextOperation rhs)
        {
            if (lhs == null) throw new ArgumentNullException("lhs");
            if (rhs == null) throw new ArgumentNullException("rhs");
            if (lhs._baseLength != rhs._baseLength)
            {
                throw new CollabOTException(
                    CollabOTErrorKind.BaseLengthMismatch,
                    "Cannot transform: lhs.baseLength (" + lhs._baseLength + ") != rhs.baseLength (" + rhs._baseLength + ").",
                    lhs._baseLength,
                    rhs._baseLength);
            }

            var aPrime = new CollabTextOperation();
            var bPrime = new CollabTextOperation();
            int ia = 0, ib = 0;
            CollabOTComponent? a = lhs._components.Count > 0 ? lhs._components[0] : (CollabOTComponent?)null;
            CollabOTComponent? b = rhs._components.Count > 0 ? rhs._components[0] : (CollabOTComponent?)null;

            while (a.HasValue || b.HasValue)
            {
                if (a.HasValue && a.Value.Kind == CollabOTComponentKind.Insert)
                {
                    aPrime.Insert(a.Value.Text);
                    bPrime.Retain(a.Value.Text.Length);
                    ia++;
                    a = ia < lhs._components.Count ? lhs._components[ia] : (CollabOTComponent?)null;
                    continue;
                }
                if (b.HasValue && b.Value.Kind == CollabOTComponentKind.Insert)
                {
                    aPrime.Retain(b.Value.Text.Length);
                    bPrime.Insert(b.Value.Text);
                    ib++;
                    b = ib < rhs._components.Count ? rhs._components[ib] : (CollabOTComponent?)null;
                    continue;
                }
                if (!a.HasValue || !b.HasValue)
                {
                    throw new CollabOTException(CollabOTErrorKind.OperationTooShort, "Operation too short during Transform.");
                }

                var ca = a.Value;
                var cb = b.Value;
                if (ca.Kind == CollabOTComponentKind.Retain && cb.Kind == CollabOTComponentKind.Retain)
                {
                    int m = Math.Min(ca.Count, cb.Count);
                    aPrime.Retain(m);
                    bPrime.Retain(m);
                    if (ca.Count > cb.Count)
                    {
                        a = CollabOTComponent.CreateRetain(ca.Count - cb.Count);
                        ib++; b = ib < rhs._components.Count ? rhs._components[ib] : (CollabOTComponent?)null;
                    }
                    else if (ca.Count == cb.Count)
                    {
                        ia++; a = ia < lhs._components.Count ? lhs._components[ia] : (CollabOTComponent?)null;
                        ib++; b = ib < rhs._components.Count ? rhs._components[ib] : (CollabOTComponent?)null;
                    }
                    else
                    {
                        b = CollabOTComponent.CreateRetain(cb.Count - ca.Count);
                        ia++; a = ia < lhs._components.Count ? lhs._components[ia] : (CollabOTComponent?)null;
                    }
                }
                else if (ca.Kind == CollabOTComponentKind.Delete && cb.Kind == CollabOTComponentKind.Delete)
                {
                    if (ca.Count > cb.Count)
                    {
                        a = CollabOTComponent.CreateDelete(ca.Count - cb.Count);
                        ib++; b = ib < rhs._components.Count ? rhs._components[ib] : (CollabOTComponent?)null;
                    }
                    else if (ca.Count == cb.Count)
                    {
                        ia++; a = ia < lhs._components.Count ? lhs._components[ia] : (CollabOTComponent?)null;
                        ib++; b = ib < rhs._components.Count ? rhs._components[ib] : (CollabOTComponent?)null;
                    }
                    else
                    {
                        b = CollabOTComponent.CreateDelete(cb.Count - ca.Count);
                        ia++; a = ia < lhs._components.Count ? lhs._components[ia] : (CollabOTComponent?)null;
                    }
                }
                else if (ca.Kind == CollabOTComponentKind.Delete && cb.Kind == CollabOTComponentKind.Retain)
                {
                    int m = Math.Min(ca.Count, cb.Count);
                    aPrime.Delete(m);
                    if (ca.Count > cb.Count)
                    {
                        a = CollabOTComponent.CreateDelete(ca.Count - cb.Count);
                        ib++; b = ib < rhs._components.Count ? rhs._components[ib] : (CollabOTComponent?)null;
                    }
                    else if (ca.Count == cb.Count)
                    {
                        ia++; a = ia < lhs._components.Count ? lhs._components[ia] : (CollabOTComponent?)null;
                        ib++; b = ib < rhs._components.Count ? rhs._components[ib] : (CollabOTComponent?)null;
                    }
                    else
                    {
                        b = CollabOTComponent.CreateRetain(cb.Count - ca.Count);
                        ia++; a = ia < lhs._components.Count ? lhs._components[ia] : (CollabOTComponent?)null;
                    }
                }
                else if (ca.Kind == CollabOTComponentKind.Retain && cb.Kind == CollabOTComponentKind.Delete)
                {
                    int m = Math.Min(ca.Count, cb.Count);
                    bPrime.Delete(m);
                    if (ca.Count > cb.Count)
                    {
                        a = CollabOTComponent.CreateRetain(ca.Count - cb.Count);
                        ib++; b = ib < rhs._components.Count ? rhs._components[ib] : (CollabOTComponent?)null;
                    }
                    else if (ca.Count == cb.Count)
                    {
                        ia++; a = ia < lhs._components.Count ? lhs._components[ia] : (CollabOTComponent?)null;
                        ib++; b = ib < rhs._components.Count ? rhs._components[ib] : (CollabOTComponent?)null;
                    }
                    else
                    {
                        b = CollabOTComponent.CreateDelete(cb.Count - ca.Count);
                        ia++; a = ia < lhs._components.Count ? lhs._components[ia] : (CollabOTComponent?)null;
                    }
                }
                else
                {
                    throw new CollabOTException(CollabOTErrorKind.OperationTooShort, "Unexpected component pair during Transform.");
                }
            }
            return Tuple.Create(aPrime, bPrime);
        }

        // ── Diff ──

        /// <summary>
        /// Single-splice operation turning oldText into newText (common prefix + suffix).
        /// Never splits a UTF-16 surrogate pair, so every inserted string is valid Unicode on the wire.
        /// </summary>
        public static CollabTextOperation FromDiff(string oldText, string newText)
        {
            oldText = oldText ?? "";
            newText = newText ?? "";
            int aLen = oldText.Length;
            int bLen = newText.Length;
            int prefix = 0;
            int maxPrefix = Math.Min(aLen, bLen);
            while (prefix < maxPrefix && oldText[prefix] == newText[prefix]) prefix++;
            if (prefix > 0 && char.IsHighSurrogate(oldText[prefix - 1]))
            {
                prefix--;
            }

            int suffix = 0;
            int maxSuffix = Math.Min(aLen, bLen) - prefix;
            while (suffix < maxSuffix && oldText[aLen - 1 - suffix] == newText[bLen - 1 - suffix]) suffix++;
            if (suffix > 0 && char.IsLowSurrogate(oldText[aLen - suffix]))
            {
                suffix--;
            }

            int deleted = aLen - prefix - suffix;
            string inserted = newText.Substring(prefix, bLen - prefix - suffix);
            var op = new CollabTextOperation();
            op.Retain(prefix);
            op.Insert(inserted);
            op.Delete(deleted);
            op.Retain(suffix);
            return op;
        }

        // ── JSON ──

        public List<object> ToJson()
        {
            var arr = new List<object>(_components.Count);
            for (int i = 0; i < _components.Count; i++)
            {
                var c = _components[i];
                switch (c.Kind)
                {
                    case CollabOTComponentKind.Retain: arr.Add(c.Count); break;
                    case CollabOTComponentKind.Insert: arr.Add(c.Text); break;
                    case CollabOTComponentKind.Delete: arr.Add(-c.Count); break;
                }
            }
            return arr;
        }

        public string ToJsonString()
        {
            return Js.Serialize(ToJson());
        }

        public static CollabTextOperation FromJsonString(string json)
        {
            if (string.IsNullOrEmpty(json)) throw new CollabOTException(CollabOTErrorKind.InvalidJson, "Empty operation JSON.");
            object raw;
            try { raw = Js.DeserializeObject(json); }
            catch (ArgumentException ex) { throw new CollabOTException(CollabOTErrorKind.InvalidJson, ex.Message); }
            catch (InvalidOperationException ex) { throw new CollabOTException(CollabOTErrorKind.InvalidJson, ex.Message); }
            return FromJson(raw);
        }

        public static CollabTextOperation FromJson(object raw)
        {
            if (raw == null || raw is string || raw is IDictionary)
            {
                throw new CollabOTException(CollabOTErrorKind.InvalidJson, "Operation JSON must be an array.");
            }
            var seq = raw as IEnumerable;
            if (seq == null)
            {
                throw new CollabOTException(CollabOTErrorKind.InvalidJson, "Operation JSON must be an array.");
            }
            var op = new CollabTextOperation();
            foreach (var item in seq)
            {
                if (item is string)
                {
                    op.Insert((string)item);
                }
                else if (IsNumber(item))
                {
                    double d = Convert.ToDouble(item, CultureInfo.InvariantCulture);
                    if (double.IsNaN(d) || double.IsInfinity(d) || d <= int.MinValue || d > int.MaxValue)
                    {
                        throw new CollabOTException(CollabOTErrorKind.InvalidJson, "Operation component number out of range.");
                    }
                    int value = (int)d;
                    if ((double)value != d || value == 0)
                    {
                        throw new CollabOTException(CollabOTErrorKind.InvalidJson, "Operation component number must be a non-zero integer.");
                    }
                    if (value > 0) op.Retain(value);
                    else op.Delete(-value);
                }
                else
                {
                    throw new CollabOTException(CollabOTErrorKind.InvalidJson, "Invalid operation component.");
                }
            }
            return op;
        }

        static bool IsNumber(object item)
        {
            return item is int || item is long || item is short || item is byte || item is sbyte
                || item is uint || item is ulong || item is ushort
                || item is decimal || item is double || item is float;
        }

        public bool Equals(CollabTextOperation other)
        {
            if (ReferenceEquals(other, null)) return false;
            if (ReferenceEquals(this, other)) return true;
            if (_baseLength != other._baseLength || _targetLength != other._targetLength || _components.Count != other._components.Count) return false;
            for (int i = 0; i < _components.Count; i++)
            {
                if (!_components[i].Equals(other._components[i])) return false;
            }
            return true;
        }

        public override bool Equals(object obj)
        {
            return Equals(obj as CollabTextOperation);
        }

        public override int GetHashCode()
        {
            unchecked
            {
                int h = (_baseLength * 397) ^ _targetLength;
                for (int i = 0; i < _components.Count; i++) h = (h * 31) ^ _components[i].GetHashCode();
                return h;
            }
        }
    }

    /// <summary>
    /// Client half of ot1 (ot.js Client state machine): at most one operation awaits the host's ack;
    /// later local edits compose into Buffer. Remote operations are transformed against both before touching local text.
    /// </summary>
    public class CollabOTClient
    {
        public int Revision { get; private set; }
        public CollabTextOperation Outstanding { get; private set; }
        public CollabTextOperation Buffer { get; private set; }
        public bool IsSynchronized { get { return Outstanding == null; } }

        public CollabOTClient(int revision)
        {
            Revision = revision;
        }

        /// <summary>A local edit. Returns the operation to send now (null while another is in flight).</summary>
        public CollabTextOperation ApplyLocal(CollabTextOperation op)
        {
            if (op == null || op.IsNoop) return null;
            if (Outstanding == null)
            {
                Outstanding = op;
                return op;
            }
            if (Buffer != null) Buffer = Buffer.Compose(op);
            else Buffer = op;
            return null;
        }

        /// <summary>Host acknowledged our outstanding operation as newRevision. Returns the buffered op to send next.</summary>
        public CollabTextOperation Acknowledge(int newRevision)
        {
            Revision = newRevision;
            Outstanding = Buffer;
            Buffer = null;
            return Outstanding;
        }

        /// <summary>Another participant's operation committed as newRevision. Returns it transformed for local text.</summary>
        public CollabTextOperation ApplyRemote(CollabTextOperation op, int newRevision)
        {
            Revision = newRevision;
            var remote = op;
            if (Outstanding != null)
            {
                var t = CollabTextOperation.Transform(Outstanding, remote);
                Outstanding = t.Item1;
                remote = t.Item2;
            }
            if (Buffer != null)
            {
                var t = CollabTextOperation.Transform(Buffer, remote);
                Buffer = t.Item1;
                remote = t.Item2;
            }
            return remote;
        }

        /// <summary>Drops all local state after the host sent a full snapshot (resync).</summary>
        public void Reset(int newRevision)
        {
            Revision = newRevision;
            Outstanding = null;
            Buffer = null;
        }
    }

    /// <summary>
    /// Host half of ot1: the authoritative document and the bounded operation log late clients are transformed against.
    /// </summary>
    public class CollabOTServerDocument
    {
        public class Commit
        {
            public int Revision { get; private set; }
            public CollabTextOperation Operation { get; private set; }
            public string AuthorId { get; private set; }
            public string OpId { get; private set; }

            public Commit(int revision, CollabTextOperation operation, string authorId, string opId)
            {
                Revision = revision;
                Operation = operation;
                AuthorId = authorId;
                OpId = opId;
            }
        }

        readonly List<Commit> _history = new List<Commit>();
        public string Content { get; private set; }
        public int Revision { get; private set; }
        public ReadOnlyCollection<Commit> History { get { return _history.AsReadOnly(); } }
        public readonly int MaxHistory;

        public CollabOTServerDocument(string content, int revision, int maxHistory = 1000)
        {
            Content = content ?? "";
            Revision = revision;
            MaxHistory = Math.Max(16, maxHistory);
        }

        /// <summary>Commits a client operation made against baseRevision. A retransmitted opId returns the original commit.</summary>
        public Commit Receive(CollabTextOperation op, int baseRevision, string authorId, string opId)
        {
            if (op == null) throw new CollabOTException(CollabOTErrorKind.InvalidOperation, "Null operation.");
            if (!string.IsNullOrEmpty(opId))
            {
                for (int i = _history.Count - 1; i >= 0; i--)
                {
                    if (_history[i].OpId == opId && _history[i].AuthorId == authorId) return _history[i];
                }
            }
            if (baseRevision > Revision)
            {
                throw new CollabOTException(CollabOTErrorKind.InvalidOperation, "Base revision " + baseRevision + " exceeds current revision " + Revision + ".", Revision, baseRevision);
            }
            int oldest = Revision - _history.Count;
            if (baseRevision < oldest)
            {
                throw new CollabOTException(CollabOTErrorKind.StaleBase, "Base revision " + baseRevision + " fell out of history (oldest " + oldest + ", current " + Revision + ").", Revision, baseRevision);
            }

            var transformed = op;
            for (int i = 0; i < _history.Count; i++)
            {
                var c = _history[i];
                if (c.Revision > baseRevision)
                {
                    try
                    {
                        transformed = CollabTextOperation.Transform(transformed, c.Operation).Item1;
                    }
                    catch (CollabOTException ex)
                    {
                        throw new CollabOTException(CollabOTErrorKind.InvalidOperation, ex.Message);
                    }
                }
            }

            string next;
            try
            {
                next = transformed.Apply(Content);
            }
            catch (CollabOTException ex)
            {
                throw new CollabOTException(CollabOTErrorKind.InvalidOperation, ex.Message);
            }
            return CommitOp(transformed, next, authorId, opId);
        }

        /// <summary>Records a change that did not arrive as an operation (host editor, disk write, legacy edit). Returns null if unchanged.</summary>
        public Commit ReplaceContent(string newContent, string authorId)
        {
            newContent = newContent ?? "";
            if (newContent == Content) return null;
            var op = CollabTextOperation.FromDiff(Content, newContent);
            return CommitOp(op, newContent, authorId, null);
        }

        /// <summary>Operations committed after baseRevision, or null if they are no longer retained in History.</summary>
        public List<Commit> OperationsSince(int baseRevision)
        {
            if (baseRevision > Revision || baseRevision < Revision - _history.Count) return null;
            var list = new List<Commit>();
            for (int i = 0; i < _history.Count; i++)
            {
                if (_history[i].Revision > baseRevision) list.Add(_history[i]);
            }
            return list;
        }

        Commit CommitOp(CollabTextOperation op, string next, string authorId, string opId)
        {
            Revision += 1;
            Content = next;
            var entry = new Commit(Revision, op, authorId, opId);
            _history.Add(entry);
            if (_history.Count > MaxHistory)
            {
                _history.RemoveRange(0, _history.Count - MaxHistory);
            }
            return entry;
        }
    }
}
