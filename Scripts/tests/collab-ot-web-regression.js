// ot1 web client regression: runs the exact `OT` object embedded in the collaboration web portal
// (CollaborationService.swift) through algebra checks, Thai/emoji diffs and randomized multi-client convergence.
"use strict";
const fs = require("fs");
const src = fs.readFileSync(process.argv[2], "utf8");
const start = src.indexOf("const OT = {");
const end = src.indexOf("// Per-file client state", start);
if (start < 0 || end < 0) { console.log("FAIL could not find OT object in portal source"); process.exit(1); }
const OT = new Function(src.slice(start, end) + "\nreturn OT;")();

let failures = 0;
function check(cond, name) { if (cond) console.log("PASS " + name); else { failures++; console.log("FAIL " + name); } }

check(OT.apply([3, "XY", -2, 1], "abcdef") === "abcXYf", "apply");
const thai = "สวัสดี 👋🏽 world", edited = "สวัสดีครับ 👋 world!";
check(OT.apply(OT.fromDiff(thai, edited), thai) === edited, "diff Thai + emoji");
const swap = OT.fromDiff("a😀b", "a😃b");
check(swap.some(c => c === "😃"), "diff never splits a surrogate pair");
{
  const [a1, b1] = OT.transform([2, "A", 3], [2, "B", 3]);
  const viaA = OT.apply(b1, OT.apply([2, "A", 3], "hello"));
  const viaB = OT.apply(a1, OT.apply([2, "B", 3], "hello"));
  check(viaA === viaB && viaA === "heABllo", "same-offset inserts converge, client first (matches Swift)");
}
check(OT.transformIndex([2, "XX", 3], 2) === 2 && OT.transformIndex([2, "XX", 3], 4) === 6, "caret mapping");
check(JSON.stringify(OT.compose([2, "A", 3], OT.fromDiff("heAllo", "heAllo!"))) === JSON.stringify([2, "A", 3, "!"]), "compose");

// Host log (same algorithm as CollabOTServerDocument).
function makeServer(content) { return { content, revision: 1, history: [] }; }
function serverReceive(srv, op, base, author, opId) {
  const dup = srv.history.find(h => h.opId === opId);
  if (dup) return dup;
  let t = op;
  for (const h of srv.history) if (h.revision > base) t = OT.transform(t, h.op)[0];
  srv.content = OT.apply(t, srv.content);
  srv.revision += 1;
  const commit = { revision: srv.revision, op: t, author, opId };
  srv.history.push(commit);
  return commit;
}
function serverReplace(srv, text) {
  if (text === srv.content) return null;
  const op = OT.fromDiff(srv.content, text);
  srv.content = text; srv.revision += 1;
  const commit = { revision: srv.revision, op, author: "host", opId: null };
  srv.history.push(commit);
  return commit;
}
const alphabet = ["a", "b", "\n", "ก", "่", "😀", " "];
function rnd(n) { return Math.floor(Math.random() * n); }
function randomEdit(text) {
  const pos = rnd(text.length + 1);
  let out;
  if (rnd(10) < 6 || !text.length) {
    let s = ""; for (let i = 0, k = 1 + rnd(3); i < k; i++) s += alphabet[rnd(alphabet.length)];
    out = text.slice(0, pos) + s + text.slice(pos);
  } else {
    out = text.slice(0, pos) + text.slice(Math.min(text.length, pos + 1 + rnd(4)));
  }
  return /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?:^|[^\uD800-\uDBFF])[\uDC00-\uDFFF]/.test(out) ? text + "q" : out;
}

let converged = true;
for (let round = 0; round < 300 && converged; round++) {
  const start = "fn main() {\n  สวัสดี\n}\n";
  const srv = makeServer(start);
  const clients = [0, 1, 2].map(i => ({ id: "c" + i, text: start, rev: 1, outstanding: null, outId: null, buffer: null, inbox: [], n: 0 }));
  const toHost = [];
  const send = (c) => { c.outId = c.id + "-" + (++c.n); toHost.push({ c, op: c.outstanding, base: c.rev, opId: c.outId }); };
  const local = (c) => {
    const next = randomEdit(c.text);
    const op = OT.fromDiff(c.text, next);
    c.text = next;
    if (OT.isNoop(op)) return;
    if (!c.outstanding) { c.outstanding = op; send(c); } else c.buffer = c.buffer ? OT.compose(c.buffer, op) : op;
  };
  const deliver = (c) => {
    const m = c.inbox.shift();
    if (m.revision <= c.rev) return;
    if (m.opId && m.opId === c.outId) {
      c.rev = m.revision; c.outstanding = c.buffer; c.buffer = null;
      if (c.outstanding) send(c); else c.outId = null;
      return;
    }
    let r = m.op;
    if (c.outstanding) { const t = OT.transform(c.outstanding, r); c.outstanding = t[0]; r = t[1]; }
    if (c.buffer) { const t = OT.transform(c.buffer, r); c.buffer = t[0]; r = t[1]; }
    c.text = OT.apply(r, c.text); c.rev = m.revision;
  };
  const hostStep = () => {
    const { c, op, base, opId } = toHost.shift();
    const commit = serverReceive(srv, op, base, c.id, opId);
    clients.forEach(k => k.inbox.push(commit));
  };
  for (let step = 0; step < 60; step++) {
    const a = rnd(4);
    if (a === 0) local(clients[rnd(3)]);
    else if (a === 1 && toHost.length) hostStep();
    else { const c = clients[rnd(3)]; if (c.inbox.length) deliver(c); }
    if (step % 5 === 0) { const commit = serverReplace(srv, randomEdit(srv.content)); if (commit) clients.forEach(k => k.inbox.push(commit)); }
  }
  let guard = 0;
  while ((toHost.length || clients.some(c => c.inbox.length)) && guard++ < 10000) {
    if (toHost.length) hostStep();
    clients.forEach(c => { if (c.inbox.length) deliver(c); });
  }
  if (!clients.every(c => c.text === srv.content && !c.outstanding)) { converged = false; console.log("diverged in round " + round); }
}
check(converged, "300 random 3-client + host sessions converge (web OT)");

if (failures) { console.log(failures + " failure(s)"); process.exit(1); }
console.log("ALL PASS");
