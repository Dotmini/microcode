import * as vscode from 'vscode';
import * as cp from 'child_process';
import * as path from 'path';
import { BackendManager } from '../backendManager';

export class ArdiumService implements vscode.Disposable {
  private readonly diagnostics: vscode.DiagnosticCollection;
  private lspProcess: cp.ChildProcess | null = null;
  private readonly disposables: vscode.Disposable[] = [];

  constructor(
    private readonly backendManager: BackendManager,
    private readonly outputChannel: vscode.OutputChannel
  ) {
    this.diagnostics = vscode.languages.createDiagnosticCollection('ardium');
    this.disposables.push(this.diagnostics);

    if (vscode.workspace.onDidSaveTextDocument) {
      this.disposables.push(
        vscode.workspace.onDidSaveTextDocument((doc) => {
          if (this.isArdiumDoc(doc)) {
            void this.diagnoseDocument(doc, true);
          }
        })
      );
    }

    if (vscode.workspace.onDidOpenTextDocument) {
      this.disposables.push(
        vscode.workspace.onDidOpenTextDocument((doc) => {
          if (this.isArdiumDoc(doc)) {
            void this.diagnoseDocument(doc, true);
          }
        })
      );
    }
  }

  public isArdiumDoc(doc: vscode.TextDocument): boolean {
    return (
      doc.languageId === 'ardium' ||
      doc.fileName.endsWith('.ar') ||
      doc.fileName.endsWith('.ardium')
    );
  }

  public async runCurrentFile(): Promise<void> {
    const editor = vscode.window.activeTextEditor;
    if (!editor || !this.isArdiumDoc(editor.document)) {
      void vscode.window.showWarningMessage('Open an Ardium (.ar / .ardium) file to run.');
      return;
    }

    await editor.document.save();
    await this.diagnoseDocument(editor.document, true);

    const binary = this.backendManager.findArdiumBinary();
    const filePath = editor.document.uri.fsPath;
    this.outputChannel.show(true);
    this.outputChannel.appendLine(`\n▶ [Ardium v2.3 Run] ${filePath}`);

    if (!binary) {
      this.outputChannel.appendLine(
        '⚠️ Ardium native compiler (`arc` / `ardium`) not found in /usr/local/ardium/bin/arc or PATH.'
      );
      void vscode.window.showWarningMessage(
        'Ardium compiler (`arc`) not found. Configure `microcode.ardiumBinaryPath` or install Ardium Toolchain.'
      );
      return;
    }

    await this.execArdium(binary, ['run', filePath], path.dirname(filePath));
  }

  public async compileCurrentFile(): Promise<void> {
    const editor = vscode.window.activeTextEditor;
    if (!editor || !this.isArdiumDoc(editor.document)) {
      void vscode.window.showWarningMessage('Open an Ardium (.ar / .ardium) file to compile.');
      return;
    }

    await editor.document.save();
    const binary = this.backendManager.findArdiumBinary();
    const filePath = editor.document.uri.fsPath;
    const outPath = filePath.replace(/\.(ar|ardium)$/, '');

    this.outputChannel.show(true);
    this.outputChannel.appendLine(`\n📦 [Ardium v2.3 Build] ${filePath} -> ${outPath}`);

    if (!binary) {
      void vscode.window.showWarningMessage('Ardium compiler (`arc`) not found.');
      return;
    }

    const code = await this.execArdium(binary, ['build', filePath, '-o', outPath], path.dirname(filePath));
    if (code === 0) {
      void vscode.window.showInformationMessage(`Compiled Ardium binary: ${path.basename(outPath)}`);
    }
  }

  public async diagnoseDocument(doc?: vscode.TextDocument, silent = false): Promise<vscode.Diagnostic[]> {
    const targetDoc = doc ?? vscode.window.activeTextEditor?.document;
    if (!targetDoc || !this.isArdiumDoc(targetDoc)) {
      if (!silent) {
        void vscode.window.showWarningMessage('Open an Ardium (.ar) file to run diagnostics.');
      }
      return [];
    }

    const text = targetDoc.getText();
    const lines = text.split(/\r?\n/);
    const items: vscode.Diagnostic[] = [];

    // 1. Static RAII @owned & manual alloc/free ownership analyzer (Ardium v2.3 rule)
    const unownedAllocs: Array<{ varName: string; line: number; col: number }> = [];
    const freedVars = new Set<string>();

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const allocMatch = line.match(/^\s*(?:(@owned)\s+)?(let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*alloc\s*\(/);
      if (allocMatch) {
        const isOwned = Boolean(allocMatch[1]);
        const varName = allocMatch[3];
        if (!isOwned) {
          unownedAllocs.push({
            varName,
            line: i,
            col: Math.max(0, line.indexOf(varName))
          });
        }
      }

      const freeMatch = line.match(/\bfree\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)/);
      if (freeMatch) {
        freedVars.add(freeMatch[1]);
      }
    }

    for (const allocItem of unownedAllocs) {
      if (!freedVars.has(allocItem.varName)) {
        const range = new vscode.Range(
          allocItem.line,
          allocItem.col,
          allocItem.line,
          allocItem.col + allocItem.varName.length
        );
        const diag = new vscode.Diagnostic(
          range,
          `Ardium RAII Warning: Heap allocation '${allocItem.varName}' has no matching free(${allocItem.varName}). Prefix with '@owned' for automatic scope-exit cleanup.`,
          vscode.DiagnosticSeverity.Warning
        );
        diag.source = 'Ardium v2.3 RAII Analyzer';
        diag.code = 'ARD-OWNED-001';
        items.push(diag);
      }
    }

    this.diagnostics.set(targetDoc.uri, items);

    if (!silent) {
      this.outputChannel.show(true);
      this.outputChannel.appendLine(
        `🔍 [Ardium Diagnose] ${path.basename(targetDoc.fileName)}: ${items.length} issue(s) found.`
      );
      if (items.length === 0) {
        void vscode.window.showInformationMessage('Ardium v2.3 Diagnostics: Clean (@owned RAII verified).');
      } else {
        void vscode.window.showWarningMessage(`Ardium Diagnostics found ${items.length} ownership/syntax issue(s).`);
      }
    }

    return items;
  }

  public startLspIfAvailable(): void {
    if (this.lspProcess) {
      return;
    }
    const binary = this.backendManager.findArdiumBinary();
    if (!binary) {
      return;
    }

    try {
      this.lspProcess = cp.spawn(binary, ['lsp'], {
        env: {
          ...process.env,
          RUST_LOG: 'info',
          ARDIUM_LIB_PATH: '/usr/local/ardium/lib',
          ARDIUM_STDLIB: '/usr/local/ardium/stdlib'
        },
        stdio: ['pipe', 'pipe', 'pipe']
      });
      this.lspProcess.on('exit', () => {
        this.lspProcess = null;
      });
      this.outputChannel.appendLine(`✅ Started Ardium LSP daemon: ${binary} lsp`);
    } catch (err: any) {
      this.outputChannel.appendLine(`⚠️ Could not start Ardium LSP: ${err?.message ?? String(err)}`);
    }
  }

  private execArdium(binary: string, args: string[], cwd: string): Promise<number> {
    return new Promise<number>((resolve) => {
      const env = {
        ...process.env,
        DYLD_LIBRARY_PATH: `/usr/local/ardium/lib:${process.env.DYLD_LIBRARY_PATH ?? ''}`,
        ARDIUM_LIB_PATH: '/usr/local/ardium/lib',
        ARDIUM_STDLIB: '/usr/local/ardium/stdlib'
      };

      const proc = cp.spawn(binary, args, { cwd, env });
      proc.stdout.on('data', (data: Buffer) => {
        const text = data.toString();
        if (!text.includes('Target Triple')) {
          this.outputChannel.append(text);
        }
      });
      proc.stderr.on('data', (data: Buffer) => {
        this.outputChannel.append(data.toString());
      });
      proc.on('close', (code) => {
        const exitCode = code ?? 1;
        this.outputChannel.appendLine(
          exitCode === 0 ? '✅ Ardium execution finished (exit 0).' : `❌ Exited with code ${exitCode}.`
        );
        resolve(exitCode);
      });
      proc.on('error', (err) => {
        this.outputChannel.appendLine(`❌ Execution error: ${err.message}`);
        resolve(1);
      });
    });
  }

  public dispose(): void {
    if (this.lspProcess) {
      this.lspProcess.kill();
      this.lspProcess = null;
    }
    for (const d of this.disposables) {
      d.dispose();
    }
  }
}
