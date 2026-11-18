---
name: microcode-arc-lang
description: Arc programming language 3.x (formerly Ardium) - syntax, types, error handling, standard built-ins and the `arc` CLI (run, check, test, build). Use when writing, running, testing or fixing Arc code or `.ar` files, or when the user mentions Arc or Ardium.
license: MIT
metadata:
  owner: MicroCode
  source: "Arc LANGUAGE_REFERENCE.md, Arc 3.1.0"
---

# Arc 3.x (formerly Ardium)

Arc is statically typed and compiles to native code (Arc → C → clang). Immutable by default, type inference,
no implicit conversions, `?T` optionals instead of null, `!T` results instead of exceptions, garbage collected.

## Before writing code
1. Check the toolchain: `arc --version` (expect `arc 3.x`). Use `arc`, never the old `ardium` 2.x CLI.
2. Source files end in **`.ar`** (not `.arc`).
3. Validate before running: `arc check file.ar` (type-checks, stops at the first error; fix and re-check).
4. In MicroCode, `ardium_run` runs code with the same `arc`. Programs still running after 120 s are stopped,
   so start servers or watchers in the terminal (`arc run server.ar`).

## CLI
```bash
arc run main.ar [args...]   # compile (cached) and run
arc check main.ar           # type-check only
arc test                    # run @test functions in tests/ and src/
arc test file.ar name       # tests whose name contains `name`
arc build main.ar -o app    # standalone executable (-O3)
arc new MyProject           # arc.toml, src/main.ar, tests/
arc doctor                  # check the toolchain
```
Inside a project (`arc.toml`), `arc run` / `arc build` use `src/main.ar`. Exit codes: compile error 1, panic 101.

## Syntax essentials
```rust
let name = "Arc"            // immutable
let mut count = 0           // mutable (also: var)
let ratio: float = 1        // explicit type
count += 1

fn add(a: int, b: int) -> int { return a + b }   // parameters always need types
fn main() { println(add(2, 3)) }                 // main takes no parameters; use args()

if x > 0 { } elif x == 0 { } else { }            // conditions must be bool
while n > 0 { n -= 1 }
loop { if done() { break } }
for i in 0..10 { }    for i in 1..=10 { }
for x in xs { }       for i, x in xs { }      for k, v in map { }
```
Types: `int` (64-bit), `float`, `bool`, `str` (UTF-8, immutable), `[T]`, `[K: V]` (insertion ordered),
`?T`, `!T`, `fn(A) -> R`. No implicit conversion: `float(a) * b`, `a as float`, `int(2.9)`, `str(42)`.
`str + str` only. `==` compares deeply.

## Structs, enums, match
```rust
struct Account { owner: str, balance: int }
impl Account {
    fn open(owner: str) -> Account { return Account { owner, balance: 0 } }
    fn describe(self) -> str { return f"{self.owner}: {self.balance}" }
    fn deposit(mut self, amount: int) { self.balance += amount }   // caller needs `let mut`
}

enum Shape { Circle(float), Rect(float, float), Empty }
let area = match shape {
    Shape::Circle(r) => 3.14159 * r * r,
    Rect(w, h) => w * h,          // enum name may be omitted
    Empty => 0.0,                 // match must be exhaustive (or `_`)
}
```
Structs, arrays, maps, enums and closures are reference types (`.copy()` for a copy). Self-referencing
structs use optionals: `struct Tree { value: int, left: ?Tree, right: ?Tree }`.

## Optionals and errors
```rust
fn find(xs: [str], t: str) -> ?int { for i, x in xs { if x == t { return i } }; return nil }
if let i = find(names, "ben") { println(i) }
let idx = find(names, "ben") ?? -1        // also .unwrap(), .unwrap_or(v), .is_some()

fn parse_port(s: str) -> !int {
    let n = parse_int(s) ?? -1
    if n < 1 || n > 65535 { return err(f"invalid port '{s}'") }
    return n
}
fn load(s: str) -> !int { let p = parse_port(s)?; return p }   // `?` propagates nil / err
match load("80") { ok(p) => println(p), err(msg) => println("failed:", msg) }
fn main() -> !void { ... }                 // an escaping error prints `error: ...`, exit 1
```

## Collections and strings
```rust
let mut xs = [5, 3, 8]      xs.push(1)  xs.pop()  xs.sort()  xs.len()  xs[1..3]
xs.map(|x| x * 2)  xs.filter(|x| x > 3)  xs.fold(0, |a, x| a + x)  xs.find(|x| x > 3)
let empty: [str] = []       // empty literals need a type
let mut ages = ["alice": 30]   ages["bob"] = 25   ages.get("zed") ?? 0   ages.contains("bob")
s.len() (bytes)  s.char_count()  s.split(",")  s.lines()  s.trim()  s.replace(a, b)  s.to_int()
f"{name} {pi:.2} [{n:5}] [{s:<6}] [{7:03}]"
```
Closures capture by copy: `let f = |x: int| x * 2`, `fn(int) -> int` as a type.

## Built-ins
`print/println/eprintln`, `str/int/float`, `parse_int/parse_float -> ?T`, `len`, math (`abs min max sqrt pow
floor ceil round sin cos exp log`), `read_line() -> ?str`, `read_file(path) -> ?str`, `write_file(path, s) -> bool`,
`append_file`, `file_exists`, `list_dir -> ![str]`, `make_dir`, `remove_file`, `args()`, `getenv(name) -> ?str`,
`exec(program, [args]) -> int` (no shell; returns the exit code only), `run(cmd) -> int` (via shell),
`time_ms()`, `sleep_ms`, `rand_int(lo, hi)`, `panic`, `assert`, `assert_eq`, `exit`.

## Tests and modules
```rust
@test
fn test_add() { assert_eq(add(2, 3), 5) }      // run with `arc test`
import "utils"                                  // loads utils.ar from the same folder (shared namespace)
```

## Not in Arc 3.1 — do not use
- Ardium 2 UI and system code: `import "CoreUI"`, `VStack`, `Button`, `@owned`, `GLOBAL(...)`, `malloc/peek/poke`.
  Old framework imports are skipped silently, so calls to their functions fail with "cannot find function".
- `extern fn` / C FFI (`extern` declarations are not supported by this compiler yet).
- Threads/channels, HTTP client, TCP, regex, user-defined generics, traits/interfaces.
- Capturing another program's output (`exec` returns only the exit code).
If a task needs one of these, say so and propose an alternative instead of inventing syntax.
