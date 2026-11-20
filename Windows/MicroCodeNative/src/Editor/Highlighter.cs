// Line-based incremental lexer producing ThemeManager token kinds (keyword, string, number, comment, type, function,
// property, annotation, preprocessor, punctuation...). Multi-line constructs carry a state between lines.
using System;
using System.Collections.Generic;

namespace MicroCode.Editor
{
    public struct Span
    {
        public int Start, Length;
        public string Kind;
        public Span(int s, int l, string k) { Start = s; Length = l; Kind = k; }
    }

    public class Highlighter
    {
        // states
        const int Normal = 0, BlockComment = 1, TripleDouble = 2, TripleSingle = 3, Template = 4, MarkupComment = 5, RawBlock = 6;

        enum Family { CLike, Python, Ruby, Shell, PowerShell, Sql, Markup, Css, Json, Yaml, Markdown, Lua, Plain, Batch, Haskell }

        readonly Family _fam;
        readonly HashSet<string> _kw, _types, _consts;
        readonly bool _hashComment, _backtickStrings, _capsAreTypes, _atAnnotations, _hashPreprocessor, _swiftMultiline;
        public readonly string Language;

        static HashSet<string> Set(string words) { return new HashSet<string>(words.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries)); }

        static readonly Dictionary<string, Highlighter> Cache = new Dictionary<string, Highlighter>();

        public static Highlighter For(string lang)
        {
            lang = (lang ?? "text").ToLowerInvariant();
            Highlighter h;
            if (!Cache.TryGetValue(lang, out h)) { h = new Highlighter(lang); Cache[lang] = h; }
            return h;
        }

        Highlighter(string lang)
        {
            Language = lang;
            _consts = Set("true false nil null None True False undefined NaN Infinity self super this Self");
            _types = new HashSet<string>();
            _capsAreTypes = true;
            switch (lang)
            {
                case "swift":
                    _fam = Family.CLike; _atAnnotations = true; _hashPreprocessor = true; _swiftMultiline = true;
                    _kw = Set("import let var func class struct enum protocol extension return if else guard switch case default for in while repeat break continue fallthrough where throw throws rethrows try catch do defer as is init deinit subscript typealias associatedtype static private fileprivate internal public open final override mutating nonmutating lazy weak unowned inout some any async await actor nonisolated isolated convenience required optional dynamic indirect get set willSet didSet operator precedencegroup infix prefix postfix macro consuming borrowing");
                    _types = Set("Int Double Float String Bool Character Array Dictionary Set Optional Void Any AnyObject Error Never Result URL Data Date UUID CGFloat CGPoint CGSize CGRect View Text Image Color Button VStack HStack ZStack");
                    break;
                case "javascript": case "typescript": case "vue": case "svelte":
                    _fam = Family.CLike; _backtickStrings = true; _atAnnotations = true;
                    _kw = Set("var let const function return if else for while do switch case default break continue new delete typeof instanceof in of class extends super import export from as async await yield try catch finally throw this void with static get set debugger interface type enum implements namespace declare abstract private protected public readonly keyof infer is satisfies module require");
                    _types = Set("string number boolean any unknown never object symbol bigint Array Promise Map Set Record Partial Object Function Date RegExp Error JSON Math console window document");
                    break;
                case "java": case "kotlin": case "scala": case "groovy": case "dart":
                    _fam = Family.CLike; _atAnnotations = true;
                    _kw = Set("package import class interface enum extends implements public private protected static final abstract native synchronized transient volatile strictfp return if else for while do switch case default break continue new throw throws try catch finally this super instanceof assert void var val fun object companion data sealed open override lateinit inline suspend when is in out by init constructor typealias internal def trait extends with match yield lazy implicit async await late required factory library part mixin dynamic covariant external operator");
                    _types = Set("int long short byte char float double boolean String Integer Long Double Boolean Object List Map Set Int Unit Any Nothing");
                    break;
                case "c": case "cpp": case "objective-c": case "objective-cpp": case "csharp": case "zig": case "d": case "solidity": case "vala": case "haxe": case "ardium":
                    _fam = Family.CLike; _hashPreprocessor = lang != "csharp"; _atAnnotations = lang.StartsWith("objective");
                    _kw = Set("auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while class namespace template typename public private protected virtual override final new delete operator friend using try catch throw this nullptr constexpr noexcept static_cast dynamic_cast reinterpret_cast const_cast explicit mutable concept requires co_await co_return co_yield bool true false interface implementation end property synthesize self super id instancetype nonatomic strong weak assign copy readonly readwrite async await var get set value ref out in params base sealed abstract internal readonly event delegate lock foreach is as checked unchecked fixed unsafe stackalloc partial where yield record init required pub fn let mut const comptime defer errdefer contract function returns memory storage calldata payable view pure emit modifier mapping address uint import from module");
                    _types = Set("int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t size_t string vector map set unique_ptr shared_ptr NSString NSArray NSDictionary NSObject String Int32 Int64 Task List Dictionary");
                    break;
                case "go":
                    _fam = Family.CLike; _backtickStrings = true; _capsAreTypes = false;
                    _kw = Set("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var");
                    _types = Set("int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 float32 float64 string bool byte rune error any complex64 complex128 uintptr");
                    break;
                case "rust":
                    _fam = Family.CLike; _hashPreprocessor = false;
                    _kw = Set("as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return static struct super trait type unsafe use where while macro_rules union");
                    _types = Set("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Option Result Box Rc Arc HashMap HashSet Self");
                    _consts = Set("true false None Some Ok Err self Self");
                    break;
                case "php": case "perl": case "graphql": case "fortran": case "pascal": case "ocaml": case "fsharp": case "elixir": case "clojure": case "nim": case "assembly":
                    _fam = Family.CLike; _hashComment = lang == "perl" || lang == "graphql" || lang == "elixir" || lang == "nim";
                    _kw = Set("function return if else elseif for foreach while do switch case default break continue new class interface trait extends implements public private protected static abstract final namespace use echo print require include try catch finally throw my our sub local package def defmodule defp end fn query mutation fragment type input enum schema let in match with module open val begin then program procedure var");
                    break;
                case "python": case "julia": case "r":
                    _fam = Family.Python; _hashComment = true; _atAnnotations = true;
                    _kw = Set("and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case function end using module struct mutable begin let local quote macro abstract type primitive where do repeat next library require");
                    _types = Set("int float str bool list dict set tuple bytes object type Exception range len print");
                    break;
                case "ruby":
                    _fam = Family.Ruby; _hashComment = true;
                    _kw = Set("alias and begin break case class def defined? do else elsif end ensure for if in module next not or redo rescue retry return self super then undef unless until when while yield require attr_accessor attr_reader puts");
                    break;
                case "shell":
                    _fam = Family.Shell; _hashComment = true; _capsAreTypes = false;
                    _kw = Set("if then else elif fi case esac for while until do done in function return local export readonly declare set unset shift exit echo source alias cd test");
                    break;
                case "powershell":
                    _fam = Family.PowerShell; _hashComment = true; _capsAreTypes = false;
                    _kw = Set("begin break catch class continue data define do dynamicparam else elseif end exit filter finally for foreach from function if in param process return switch throw trap try until using var while workflow");
                    break;
                case "batch":
                    _fam = Family.Batch; _capsAreTypes = false;
                    _kw = Set("echo set if else goto call exit for in do not exist defined errorlevel setlocal endlocal pause rem shift start cd pushd popd");
                    break;
                case "sql":
                    _fam = Family.Sql; _capsAreTypes = false;
                    _kw = Set("select from where insert into values update set delete create table drop alter add column index primary key foreign references join left right inner outer on group by order having limit offset as and or not null is in like between distinct union all case when then else end exists view trigger procedure function returns begin commit rollback transaction default unique check");
                    break;
                case "lua":
                    _fam = Family.Lua; _capsAreTypes = false;
                    _kw = Set("and break do else elseif end for function goto if in local not or repeat return then until while");
                    break;
                case "haskell":
                    _fam = Family.Haskell;
                    _kw = Set("case class data default deriving do else foreign if import in infix infixl infixr instance let module newtype of then type where");
                    break;
                case "html": case "xml":
                    _fam = Family.Markup; _kw = new HashSet<string>(); break;
                case "css":
                    _fam = Family.Css; _kw = Set("important media import keyframes font-face supports"); break;
                case "json":
                    _fam = Family.Json; _kw = new HashSet<string>(); break;
                case "yaml": case "toml":
                    _fam = Family.Yaml; _hashComment = true; _kw = new HashSet<string>(); break;
                case "markdown":
                    _fam = Family.Markdown; _kw = new HashSet<string>(); break;
                default:
                    _fam = Family.Plain; _kw = new HashSet<string>(); break;
            }
        }

        static bool IsIdStart(char c) { return char.IsLetter(c) || c == '_' || c == '$'; }
        static bool IsId(char c) { return char.IsLetterOrDigit(c) || c == '_' || c == '$'; }

        /// <summary>Tokenize one line given the state at its start; returns the state at its end.</summary>
        public int Tokenize(string s, int state, List<Span> spans)
        {
            switch (_fam)
            {
                case Family.Plain: return 0;
                case Family.Markup: return Markup(s, state, spans);
                case Family.Markdown: return Markdown(s, state, spans);
                case Family.Json: return Code(s, state, spans, true);
                default: return Code(s, state, spans, false);
            }
        }

        int Code(string s, int state, List<Span> spans, bool json)
        {
            int i = 0, n = s.Length;
            // continue multi-line constructs
            if (state == BlockComment)
            {
                int e = s.IndexOf("*/", StringComparison.Ordinal);
                if (_fam == Family.Lua) e = s.IndexOf("]]", StringComparison.Ordinal);
                if (_fam == Family.Haskell) e = s.IndexOf("-}", StringComparison.Ordinal);
                if (e < 0) { spans.Add(new Span(0, n, "comment")); return BlockComment; }
                spans.Add(new Span(0, e + 2, "comment")); i = e + 2; state = Normal;
            }
            else if (state == TripleDouble || state == TripleSingle)
            {
                string q = state == TripleDouble ? "\"\"\"" : "'''";
                int e = s.IndexOf(q, StringComparison.Ordinal);
                if (e < 0) { spans.Add(new Span(0, n, "string")); return state; }
                spans.Add(new Span(0, e + 3, "string")); i = e + 3; state = Normal;
            }
            else if (state == Template)
            {
                int e = FindClose(s, 0, '`');
                if (e < 0) { spans.Add(new Span(0, n, "string")); return Template; }
                spans.Add(new Span(0, e + 1, "string")); i = e + 1; state = Normal;
            }

            bool lineStart = true;
            string prevWord = null;
            char prevSig = '\0';
            while (i < n)
            {
                char c = s[i];
                if (c == ' ' || c == '\t') { i++; continue; }
                char c1 = i + 1 < n ? s[i + 1] : '\0';

                // comments
                if (_fam == Family.CLike || _fam == Family.Css || json)
                {
                    if (c == '/' && c1 == '/' && _fam != Family.Css) { spans.Add(new Span(i, n - i, "comment")); return Normal; }
                    if (c == '/' && c1 == '*')
                    {
                        int e = s.IndexOf("*/", i + 2, StringComparison.Ordinal);
                        if (e < 0) { spans.Add(new Span(i, n - i, "comment")); return BlockComment; }
                        spans.Add(new Span(i, e + 2 - i, "comment")); i = e + 2; continue;
                    }
                }
                if ((_hashComment || _fam == Family.Python || _fam == Family.Ruby || _fam == Family.Shell || _fam == Family.PowerShell || _fam == Family.Yaml) && c == '#')
                {
                    if (!(_fam == Family.Shell && c1 == '!' && i == 0)) { spans.Add(new Span(i, n - i, "comment")); return Normal; }
                    spans.Add(new Span(i, n - i, "preprocessor")); return Normal;
                }
                if ((_fam == Family.Sql || _fam == Family.Lua || _fam == Family.Haskell) && c == '-' && c1 == '-')
                {
                    if (_fam == Family.Lua && i + 3 < n && s[i + 2] == '[' && s[i + 3] == '[')
                    {
                        int e = s.IndexOf("]]", i + 4, StringComparison.Ordinal);
                        if (e < 0) { spans.Add(new Span(i, n - i, "comment")); return BlockComment; }
                        spans.Add(new Span(i, e + 2 - i, "comment")); i = e + 2; continue;
                    }
                    spans.Add(new Span(i, n - i, "comment")); return Normal;
                }
                if (_fam == Family.Haskell && c == '{' && c1 == '-')
                {
                    int e = s.IndexOf("-}", i + 2, StringComparison.Ordinal);
                    if (e < 0) { spans.Add(new Span(i, n - i, "comment")); return BlockComment; }
                    spans.Add(new Span(i, e + 2 - i, "comment")); i = e + 2; continue;
                }
                if (_fam == Family.Batch && lineStart && (s.Substring(i).StartsWith("rem ", StringComparison.OrdinalIgnoreCase) || s.Substring(i).StartsWith("::")))
                { spans.Add(new Span(i, n - i, "comment")); return Normal; }
                if (_fam == Family.PowerShell && c == '<' && c1 == '#')
                {
                    int e = s.IndexOf("#>", i + 2, StringComparison.Ordinal);
                    if (e < 0) { spans.Add(new Span(i, n - i, "comment")); return BlockComment; }
                    spans.Add(new Span(i, e + 2 - i, "comment")); i = e + 2; continue;
                }

                // preprocessor (#if, #include) for C-like
                if (_hashPreprocessor && c == '#' && lineStart)
                {
                    int e = i + 1; while (e < n && IsId(s[e])) e++;
                    spans.Add(new Span(i, e - i, "preprocessor")); i = e; lineStart = false; continue;
                }
                lineStart = false;

                // strings
                if (c == '"' || c == '\'' || (c == '`' && _backtickStrings))
                {
                    if ((_fam == Family.Python || _swiftMultiline) && c != '`' && i + 2 < n && s[i + 1] == c && s[i + 2] == c)
                    {
                        string q = new string(c, 3);
                        int e = s.IndexOf(q, i + 3, StringComparison.Ordinal);
                        if (e < 0) { spans.Add(new Span(i, n - i, "string")); return c == '"' ? TripleDouble : TripleSingle; }
                        spans.Add(new Span(i, e + 3 - i, "string")); i = e + 3; continue;
                    }
                    if (c == '\'' && (_fam == Family.CLike && (Language == "swift" || Language == "rust")) && !(i + 2 < n && s[i + 2] == '\''))
                    {
                        // Swift has no single-quoted strings; Rust lifetimes 'a
                        if (Language == "rust") { int e2 = i + 1; while (e2 < n && IsId(s[e2])) e2++; spans.Add(new Span(i, e2 - i, "type")); i = e2; continue; }
                    }
                    int end = FindClose(s, i + 1, c);
                    if (end < 0)
                    {
                        spans.Add(new Span(i, n - i, "string"));
                        if (c == '`') return Template;
                        return Normal;
                    }
                    string kind = "string";
                    if (json)
                    {
                        int k = end + 1; while (k < n && (s[k] == ' ' || s[k] == '\t')) k++;
                        if (k < n && s[k] == ':') kind = "property";
                    }
                    spans.Add(new Span(i, end + 1 - i, kind));
                    i = end + 1; prevSig = c; continue;
                }

                // numbers
                if (char.IsDigit(c) || (c == '.' && char.IsDigit(c1) && !(i > 0 && IsId(s[i - 1]))))
                {
                    int e = i;
                    if (c == '0' && (c1 == 'x' || c1 == 'X' || c1 == 'b' || c1 == 'B' || c1 == 'o')) { e += 2; while (e < n && (Uri.IsHexDigit(s[e]) || s[e] == '_')) e++; }
                    else
                    {
                        while (e < n && (char.IsDigit(s[e]) || s[e] == '_' || s[e] == '.')) { if (s[e] == '.' && e + 1 < n && s[e + 1] == '.') break; e++; }
                        if (e < n && (s[e] == 'e' || s[e] == 'E')) { e++; if (e < n && (s[e] == '+' || s[e] == '-')) e++; while (e < n && char.IsDigit(s[e])) e++; }
                        while (e < n && char.IsLetter(s[e])) e++; // suffixes 10f, 1u64
                    }
                    spans.Add(new Span(i, e - i, "number")); i = e; prevSig = '0'; continue;
                }

                // annotations / attributes / decorators
                if (c == '@' && _atAnnotations && i + 1 < n && IsIdStart(c1))
                {
                    int e = i + 1; while (e < n && IsId(s[e])) e++;
                    spans.Add(new Span(i, e - i, "annotation")); i = e; continue;
                }
                if (Language == "rust" && c == '#' && (c1 == '[' || c1 == '!'))
                {
                    int e = s.IndexOf(']', i); if (e < 0) e = n - 1;
                    spans.Add(new Span(i, e + 1 - i, "annotation")); i = e + 1; continue;
                }
                if ((_fam == Family.Shell || _fam == Family.PowerShell || Language == "php" || Language == "perl") && c == '$')
                {
                    int e = i + 1; if (e < n && s[e] == '{') { int cl = s.IndexOf('}', e); e = cl < 0 ? n : cl + 1; } else while (e < n && (IsId(s[e]) || s[e] == ':')) e++;
                    spans.Add(new Span(i, e - i, "property")); i = e; continue;
                }

                // identifiers
                if (IsIdStart(c))
                {
                    int e = i + 1; while (e < n && (IsId(s[e]) || (_fam == Family.Css && s[e] == '-') || (_fam == Family.Ruby && (s[e] == '?' || s[e] == '!') && e == i + 1 + 0 && false))) e++;
                    if (_fam == Family.Css) { while (e < n && (IsId(s[e]) || s[e] == '-')) e++; }
                    string w = s.Substring(i, e - i);
                    int k = e; while (k < n && s[k] == ' ') k++;
                    char next = k < n ? s[k] : '\0';
                    string kind = null;
                    bool sqlLike = _fam == Family.Sql || _fam == Family.Batch || _fam == Family.PowerShell;
                    string wl = sqlLike ? w.ToLowerInvariant() : w;
                    if (_fam == Family.Css)
                    {
                        if (next == ':' && prevSig != ':') kind = "property";
                        else if (_kw.Contains(w)) kind = "keyword";
                    }
                    else if (_fam == Family.Yaml)
                    {
                        if (next == ':' || next == '=') kind = "property";
                        else if (_consts.Contains(w)) kind = "keyword";
                    }
                    else if (json)
                    {
                        if (w == "true" || w == "false" || w == "null") kind = "keyword";
                    }
                    else if (prevSig == '.' && w != "self" && w != "init" && w != "super") kind = next == '(' ? "function" : "property";
                    else if (_kw.Contains(wl)) kind = "keyword";
                    else if (_consts.Contains(w)) kind = "keyword";
                    else if (_types.Contains(w)) kind = "type";
                    else if (next == '(' || (Language == "rust" && next == '!')) kind = "function";
                    else if (_capsAreTypes && char.IsUpper(w[0]) && w.Length > 1) kind = "type";
                    else if (prevWord == "func" || prevWord == "def" || prevWord == "fn" || prevWord == "function") kind = "function";
                    else if (prevWord == "class" || prevWord == "struct" || prevWord == "enum" || prevWord == "protocol" || prevWord == "interface" || prevWord == "extension" || prevWord == "type" || prevWord == "trait" || prevWord == "impl") kind = "type";
                    if (kind != null) spans.Add(new Span(i, e - i, kind));
                    prevWord = w; prevSig = 'a';
                    i = e; continue;
                }

                // punctuation & operators
                if ("{}[]();,".IndexOf(c) >= 0) spans.Add(new Span(i, 1, "punctuation"));
                prevSig = c;
                i++;
            }
            return Normal;
        }

        static int FindClose(string s, int from, char q)
        {
            for (int i = from; i < s.Length; i++)
            {
                if (s[i] == '\\') { i++; continue; }
                if (s[i] == q) return i;
            }
            return -1;
        }

        int Markup(string s, int state, List<Span> spans)
        {
            int i = 0, n = s.Length;
            if (state == MarkupComment)
            {
                int e = s.IndexOf("-->", StringComparison.Ordinal);
                if (e < 0) { spans.Add(new Span(0, n, "comment")); return MarkupComment; }
                spans.Add(new Span(0, e + 3, "comment")); i = e + 3;
            }
            while (i < n)
            {
                if (string.CompareOrdinal(s, i, "<!--", 0, 4) == 0)
                {
                    int e = s.IndexOf("-->", i + 4, StringComparison.Ordinal);
                    if (e < 0) { spans.Add(new Span(i, n - i, "comment")); return MarkupComment; }
                    spans.Add(new Span(i, e + 3 - i, "comment")); i = e + 3; continue;
                }
                char c = s[i];
                if (c == '<')
                {
                    int e = i + 1; if (e < n && (s[e] == '/' || s[e] == '!' || s[e] == '?')) e++;
                    int ns = e; while (e < n && (IsId(s[e]) || s[e] == '-' || s[e] == ':' || s[e] == '.')) e++;
                    spans.Add(new Span(i, 1, "punctuation"));
                    if (e > ns) spans.Add(new Span(ns, e - ns, "tag"));
                    i = e;
                    // attributes until '>'
                    while (i < n && s[i] != '>')
                    {
                        char a = s[i];
                        if (a == '"' || a == '\'')
                        {
                            int ce = s.IndexOf(a, i + 1); if (ce < 0) ce = n - 1;
                            spans.Add(new Span(i, ce + 1 - i, "string")); i = ce + 1; continue;
                        }
                        if (IsIdStart(a))
                        {
                            int ae = i; while (ae < n && (IsId(s[ae]) || s[ae] == '-' || s[ae] == ':')) ae++;
                            spans.Add(new Span(i, ae - i, "attribute")); i = ae; continue;
                        }
                        i++;
                    }
                    if (i < n) { spans.Add(new Span(i, 1, "punctuation")); i++; }
                    continue;
                }
                if (c == '&')
                {
                    int e = s.IndexOf(';', i); if (e > i && e - i < 10) { spans.Add(new Span(i, e + 1 - i, "escape")); i = e + 1; continue; }
                }
                i++;
            }
            return Normal;
        }

        int Markdown(string s, int state, List<Span> spans)
        {
            int n = s.Length;
            string t = s.TrimStart();
            if (t.StartsWith("```")) { spans.Add(new Span(0, n, "string")); return state == RawBlock ? Normal : RawBlock; }
            if (state == RawBlock) { spans.Add(new Span(0, n, "string")); return RawBlock; }
            if (t.StartsWith("#")) { spans.Add(new Span(0, n, "keyword")); return Normal; }
            if (t.StartsWith(">")) { spans.Add(new Span(0, n, "comment")); return Normal; }
            int lead = n - t.Length;
            if (t.StartsWith("- ") || t.StartsWith("* ") || t.StartsWith("+ ")) spans.Add(new Span(lead, 1, "keyword"));
            for (int i = 0; i < n; i++)
            {
                char c = s[i];
                if (c == '`') { int e = s.IndexOf('`', i + 1); if (e > i) { spans.Add(new Span(i, e + 1 - i, "string")); i = e; } continue; }
                if (c == '[') { int e = s.IndexOf("](", i, StringComparison.Ordinal); int e2 = e > 0 ? s.IndexOf(')', e) : -1; if (e2 > 0) { spans.Add(new Span(i, e + 1 - i, "function")); spans.Add(new Span(e + 1, e2 - e, "comment")); i = e2; } continue; }
                if ((c == '*' || c == '_') && i + 1 < n && s[i + 1] == c) { int e = s.IndexOf(new string(c, 2), i + 2, StringComparison.Ordinal); if (e > 0) { spans.Add(new Span(i, e + 2 - i, "type")); i = e + 1; } continue; }
            }
            return Normal;
        }
    }
}
