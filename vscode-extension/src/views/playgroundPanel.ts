import * as vscode from 'vscode';
import { MicroCodeCellCodeLensProvider } from '../notebook/cellCodeLens';
import { WorkstationEngine } from './workstationEngine';

export class MicroCodePlaygroundPanel {
  private static currentPanel: MicroCodePlaygroundPanel | undefined;

  public static show(
    cellRunner: MicroCodeCellCodeLensProvider,
    initialCode?: string,
    initialLanguage?: string,
    engine?: WorkstationEngine
  ): void {
    const column = vscode.window.activeTextEditor ? vscode.ViewColumn.Beside : vscode.ViewColumn.One;

    if (MicroCodePlaygroundPanel.currentPanel) {
      MicroCodePlaygroundPanel.currentPanel.panel.reveal(column);
      if (initialCode) {
        MicroCodePlaygroundPanel.currentPanel.updateCode(initialCode, initialLanguage ?? 'ardium');
      }
      return;
    }

    const panel = vscode.window.createWebviewPanel(
      'microcodePlayground',
      'MicroCode Playground',
      column,
      { enableScripts: true, retainContextWhenHidden: true }
    );

    MicroCodePlaygroundPanel.currentPanel = new MicroCodePlaygroundPanel(
      panel,
      cellRunner,
      initialCode,
      initialLanguage,
      engine
    );
  }

  private constructor(
    private readonly panel: vscode.WebviewPanel,
    private readonly cellRunner: MicroCodeCellCodeLensProvider,
    initialCode?: string,
    initialLanguage?: string,
    private readonly engine?: WorkstationEngine
  ) {
    const defaultCode =
      initialCode ||
      `// MicroCode Polyglot Playground — Ardium v2.3
fn main() {
    @owned let buf = alloc(128);
    poke(buf + 0, 2026);
    print("Ardium v2.3 @owned buffer[0] = ");
    print(peek(buf + 0));
    print("\\n");
}`;
    const defaultLang = initialLanguage || 'ardium';

    this.panel.webview.html = this.getHtml(defaultCode, defaultLang);

    this.panel.webview.onDidReceiveMessage(async (msg) => {
      if (msg.type === 'execute') {
        const language = String(msg.language ?? 'ardium');
        const code = String(msg.code ?? '');
        if (language === 'html') {
          void this.panel.webview.postMessage({
            type: 'htmlResult',
            html: code,
            elapsed: 1
          });
          return;
        }
        const start = Date.now();
        const res = await this.cellRunner.runCodeSnippet(code, language);
        const elapsed = Date.now() - start;
        void this.panel.webview.postMessage({
          type: 'result',
          stdout: res.stdout,
          stderr: res.stderr,
          exitCode: res.exitCode,
          elapsed
        });
      } else if (msg.type === 'saveAsCell' && this.engine) {
        const lang = String(msg.language ?? 'ardium');
        const code = String(msg.code ?? '');
        const cell = this.engine.createCell(`Playground (${lang.toUpperCase()})`, lang, code);
        void vscode.window.showInformationMessage(`Saved to .microcode/cells/${cell.id}.json`);
      }
    });

    this.panel.onDidDispose(() => {
      MicroCodePlaygroundPanel.currentPanel = undefined;
    });
  }

  public updateCode(code: string, language: string): void {
    void this.panel.webview.postMessage({
      type: 'setCode',
      code,
      language
    });
  }

  private getHtml(initialCode: string, initialLang: string): string {
    const escapedCode = initialCode
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');

    return /* html */ `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<style>
  :root {
    --mc-bg: var(--vscode-editor-background, #141416);
    --mc-surface: rgba(255, 255, 255, 0.04);
    --mc-surface-hover: rgba(255, 255, 255, 0.08);
    --mc-border: rgba(255, 255, 255, 0.09);
    --mc-text: var(--vscode-foreground, #e5e5e7);
    --mc-text-muted: rgba(235, 235, 245, 0.45);
    --mc-accent: #0a84ff;
    --mc-green: #30d158;
    --mc-red: #ff453a;
    --mc-orange: #ff9f0a;
    --mc-font-sans: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
    --mc-font-mono: "SF Mono", "JetBrains Mono", Menlo, Monaco, Consolas, monospace;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: var(--mc-font-sans);
    color: var(--mc-text);
    background: var(--mc-bg);
    height: 100vh;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }
  .mc-toolbar {
    height: 38px;
    padding: 0 12px;
    border-bottom: 1px solid var(--mc-border);
    background: rgba(0, 0, 0, 0.18);
    display: flex;
    align-items: center;
    gap: 8px;
    flex-shrink: 0;
  }
  .mc-title {
    font-size: 11.5px;
    font-weight: 600;
    letter-spacing: 0.01em;
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .mc-select, .mc-btn {
    background: var(--mc-surface);
    color: var(--mc-text);
    border: 1px solid var(--mc-border);
    border-radius: 5px;
    padding: 4px 9px;
    font-family: var(--mc-font-sans);
    font-size: 11px;
    font-weight: 500;
    cursor: pointer;
    outline: none;
    display: inline-flex;
    align-items: center;
    gap: 5px;
  }
  .mc-select:hover, .mc-btn:hover {
    background: var(--mc-surface-hover);
  }
  .mc-btn.run {
    background: var(--mc-green);
    border-color: var(--mc-green);
    color: #07130a;
    font-weight: 600;
  }
  .mc-split {
    flex: 1;
    display: grid;
    grid-template-columns: 1fr 1fr;
    min-height: 0;
    overflow: hidden;
  }
  .mc-pane {
    display: flex;
    flex-direction: column;
    min-height: 0;
    overflow: hidden;
  }
  .mc-pane + .mc-pane {
    border-left: 1px solid var(--mc-border);
  }
  .mc-pane-header {
    height: 26px;
    padding: 0 10px;
    border-bottom: 1px solid var(--mc-border);
    background: rgba(255, 255, 255, 0.02);
    font-size: 10px;
    font-weight: 600;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    color: var(--mc-text-muted);
    display: flex;
    align-items: center;
    justify-content: space-between;
  }
  textarea {
    flex: 1;
    width: 100%;
    border: none;
    background: transparent;
    color: var(--mc-text);
    font-family: var(--mc-font-mono);
    font-size: 12.5px;
    line-height: 1.55;
    padding: 12px;
    resize: none;
    outline: none;
  }
  .mc-output {
    flex: 1;
    padding: 12px;
    font-family: var(--mc-font-mono);
    font-size: 12px;
    line-height: 1.5;
    white-space: pre-wrap;
    overflow-y: auto;
    background: rgba(0, 0, 0, 0.22);
  }
  iframe.mc-preview {
    flex: 1;
    width: 100%;
    border: none;
    background: #fff;
    display: none;
  }
  .mc-statusbar {
    height: 24px;
    padding: 0 12px;
    border-top: 1px solid var(--mc-border);
    background: rgba(0, 0, 0, 0.2);
    font-size: 10.5px;
    color: var(--mc-text-muted);
    display: flex;
    align-items: center;
    justify-content: space-between;
  }
  .mc-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    display: inline-block;
  }
</style>
</head>
<body>
  <div class="mc-toolbar">
    <div class="mc-title">
      <svg viewBox="0 0 16 16" width="13" height="13" fill="currentColor"><path d="M2 2.5A1.5 1.5 0 0 1 3.5 1h9A1.5 1.5 0 0 1 14 2.5v11a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 2 13.5v-11zM3.5 2.5v11h9v-11h-9zM6 5l4.5 3L6 11V5z"/></svg>
      <span>MicroCode Playground</span>
    </div>

    <select id="langSelect" class="mc-select">
      <option value="ardium" ${initialLang === 'ardium' ? 'selected' : ''}>Ardium v2.3 (.ar)</option>
      <option value="python" ${initialLang === 'python' ? 'selected' : ''}>Python 3</option>
      <option value="rust" ${initialLang === 'rust' ? 'selected' : ''}>Rust (rustc)</option>
      <option value="swift" ${initialLang === 'swift' ? 'selected' : ''}>Swift</option>
      <option value="typescript" ${initialLang === 'typescript' ? 'selected' : ''}>TypeScript</option>
      <option value="javascript" ${initialLang === 'javascript' ? 'selected' : ''}>JavaScript (Node)</option>
      <option value="go" ${initialLang === 'go' ? 'selected' : ''}>Go</option>
      <option value="c" ${initialLang === 'c' ? 'selected' : ''}>C (clang)</option>
      <option value="cpp" ${initialLang === 'cpp' ? 'selected' : ''}>C++20 (clang++)</option>
      <option value="sql" ${initialLang === 'sql' ? 'selected' : ''}>SQL (SQLite)</option>
      <option value="sh" ${initialLang === 'sh' ? 'selected' : ''}>Shell (zsh)</option>
      <option value="html" ${initialLang === 'html' ? 'selected' : ''}>HTML / Live DOM</option>
    </select>

    <label style="display:inline-flex; align-items:center; gap:5px; font-size:11px; color:var(--mc-text-muted); cursor:pointer;">
      <input type="checkbox" id="chkAutoRun" />
      <span>Auto-Run</span>
    </label>

    <div style="margin-left:auto; display:flex; gap:6px;">
      <button class="mc-btn" id="btnSaveCell">Save to Cell</button>
      <button class="mc-btn" id="btnClear">Clear</button>
      <button class="mc-btn run" id="btnRun">
        <svg viewBox="0 0 16 16" width="10" height="10" fill="currentColor"><path d="M4 2.5l9 5.5-9 5.5V2.5z"/></svg>
        <span>Run ⌘↵</span>
      </button>
    </div>
  </div>

  <div class="mc-split">
    <div class="mc-pane">
      <div class="mc-pane-header">
        <span>SOURCE BUFFER</span>
        <span id="lineCounter">1 line</span>
      </div>
      <textarea id="codeArea" spellcheck="false">${escapedCode}</textarea>
    </div>
    <div class="mc-pane">
      <div class="mc-pane-header">
        <span>EXECUTION STREAM / VIEWPORT</span>
        <span id="exitBadge">Idle</span>
      </div>
      <div id="outputArea" class="mc-output">Press Run (⌘↵) to execute in-memory.</div>
      <iframe id="htmlPreview" class="mc-preview" sandbox="allow-scripts"></iframe>
    </div>
  </div>

  <div class="mc-statusbar">
    <div style="display:flex; align-items:center; gap:6px;">
      <span id="statusDot" class="mc-dot" style="background:#30d158;"></span>
      <span id="statusText">Ready</span>
    </div>
    <span id="timingText">0 ms</span>
  </div>

  <script>
    const vscode = acquireVsCodeApi();
    let debounceTimer = null;

    const TEMPLATES = {
      ardium: '// MicroCode Polyglot Playground — Ardium v2.3\\nfn main() {\\n    @owned let buf = alloc(128);\\n    poke(buf + 0, 2026);\\n    print("Ardium v2.3 @owned buffer[0] = ");\\n    print(peek(buf + 0));\\n    print("\\\\n");\\n}',
      python: 'import sys, platform\\nprint(f"Python {sys.version.split()[0]} on {platform.machine()}")\\nprint([x * x for x in range(1, 8)])',
      rust: 'fn main() {\\n    let nums: Vec<i32> = (1..=6).map(|x| x * x).collect();\\n    println!("Rust vector squares: {:?}", nums);\\n}',
      swift: 'import Foundation\\nprint("Swift Native Runtime Ready: \\(Date())")',
      typescript: 'interface Metric { name: string; latencyMs: number }\\nconst m: Metric = { name: "ardium_jit", latencyMs: 1.4 };\\nconsole.log(JSON.stringify(m, null, 2));',
      javascript: 'console.log("Node.js", process.version, "PID:", process.pid);',
      go: 'package main\\nimport "fmt"\\nfunc main() { fmt.Println("Go Playground Ready") }',
      c: '#include <stdio.h>\\nint main(void) { printf("C17 Native Clang Ready\\\\n"); return 0; }',
      cpp: '#include <iostream>\\n#include <vector>\\nint main() { std::cout << "C++20 Ready\\\\n"; return 0; }',
      sql: 'CREATE TABLE items (id INT, title TEXT);\\nINSERT INTO items VALUES (1, \\'MicroCode\\'), (2, \\'Ardium v2.3\\');\\nSELECT * FROM items;',
      sh: 'uname -a && sw_vers',
      html: '<!DOCTYPE html><html><body style="font-family:system-ui;padding:20px;background:#111;color:#eee;"><h2>MicroCode Live DOM Preview</h2><p>Interactive HTML/JS canvas ready.</p></body></html>'
    };

    function updateLineCount() {
      const lines = document.getElementById('codeArea').value.split('\\n').length;
      document.getElementById('lineCounter').textContent = lines + (lines === 1 ? ' line' : ' lines');
    }

    function runCode() {
      const code = document.getElementById('codeArea').value;
      const language = document.getElementById('langSelect').value;
      document.getElementById('statusText').textContent = 'Executing...';
      document.getElementById('statusDot').style.background = '#ff9f0a';
      vscode.postMessage({ type: 'execute', code, language });
    }

    document.getElementById('btnRun').addEventListener('click', runCode);
    document.getElementById('btnClear').addEventListener('click', () => {
      document.getElementById('outputArea').textContent = '';
    });
    document.getElementById('btnSaveCell').addEventListener('click', () => {
      vscode.postMessage({
        type: 'saveAsCell',
        code: document.getElementById('codeArea').value,
        language: document.getElementById('langSelect').value
      });
    });

    document.getElementById('langSelect').addEventListener('change', (e) => {
      const lang = e.target.value;
      if (TEMPLATES[lang]) {
        document.getElementById('codeArea').value = TEMPLATES[lang];
        updateLineCount();
      }
      if (document.getElementById('chkAutoRun').checked) {
        runCode();
      }
    });

    document.getElementById('codeArea').addEventListener('input', () => {
      updateLineCount();
      if (document.getElementById('chkAutoRun').checked) {
        clearTimeout(debounceTimer);
        debounceTimer = setTimeout(runCode, 450);
      }
    });

    document.getElementById('codeArea').addEventListener('keydown', (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
        e.preventDefault();
        runCode();
      }
    });

    window.addEventListener('message', (event) => {
      const msg = event.data;
      const outEl = document.getElementById('outputArea');
      const iframeEl = document.getElementById('htmlPreview');
      if (msg.type === 'result') {
        iframeEl.style.display = 'none';
        outEl.style.display = 'block';
        const ok = msg.exitCode === 0;
        document.getElementById('statusDot').style.background = ok ? '#30d158' : '#ff453a';
        document.getElementById('statusText').textContent = ok ? 'Completed' : 'Execution Error';
        document.getElementById('exitBadge').textContent = 'Exit ' + msg.exitCode;
        document.getElementById('timingText').textContent = msg.elapsed + ' ms';
        outEl.textContent = [msg.stdout, msg.stderr].filter(Boolean).join('\\n') || '(No stdout)';
      } else if (msg.type === 'htmlResult') {
        outEl.style.display = 'none';
        iframeEl.style.display = 'block';
        iframeEl.srcdoc = msg.html;
        document.getElementById('statusDot').style.background = '#30d158';
        document.getElementById('statusText').textContent = 'Live DOM Rendered';
        document.getElementById('exitBadge').textContent = 'DOM OK';
        document.getElementById('timingText').textContent = msg.elapsed + ' ms';
      } else if (msg.type === 'setCode') {
        document.getElementById('codeArea').value = msg.code;
        document.getElementById('langSelect').value = msg.language;
        updateLineCount();
      }
    });

    updateLineCount();
  </script>
</body>
</html>`;
  }
}
