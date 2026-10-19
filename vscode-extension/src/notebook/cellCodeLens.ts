import * as vscode from 'vscode';
import * as cp from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { BackendManager } from '../backendManager';

export interface ParsedCodeCell {
  title: string;
  startLine: number;
  endLine: number;
  code: string;
  languageId: string;
}

export class MicroCodeCellCodeLensProvider implements vscode.CodeLensProvider {
  constructor(
    private readonly backendManager: BackendManager,
    private readonly outputChannel: vscode.OutputChannel
  ) {}

  public provideCodeLenses(document: vscode.TextDocument): vscode.CodeLens[] {
    const enabled = vscode.workspace
      .getConfiguration('microcode')
      .get<boolean>('enableInlineCells', true);
    if (!enabled) {
      return [];
    }

    const cells = this.parseCells(document);
    const lenses: vscode.CodeLens[] = [];

    for (const cell of cells) {
      const range = new vscode.Range(cell.startLine, 0, cell.startLine, 0);
      lenses.push(
        new vscode.CodeLens(range, {
          title: `$(play) Run MicroCode Cell (${cell.title})`,
          command: 'microcode.runCell',
          tooltip: 'Execute this cell in MicroCode Polyglot Runtime',
          arguments: [cell]
        }),
        new vscode.CodeLens(range, {
          title: '$(terminal) Open in Playground',
          command: 'microcode.openPlayground',
          tooltip: 'Open this cell in MicroCode Playground',
          arguments: [cell.code, cell.languageId]
        })
      );
    }

    return lenses;
  }

  public parseCells(document: vscode.TextDocument): ParsedCodeCell[] {
    const text = document.getText();
    const lines = text.split(/\r?\n/);
    const markerRegex = /^\s*(?:#|\/\/|--)\s*%%(?:\s*(.*))?$/;

    const markerIndices: Array<{ line: number; title: string }> = [];
    for (let i = 0; i < lines.length; i++) {
      const m = lines[i].match(markerRegex);
      if (m) {
        markerIndices.push({
          line: i,
          title: (m[1] || `Cell ${markerIndices.length + 1}`).trim()
        });
      }
    }

    const cells: ParsedCodeCell[] = [];
    for (let idx = 0; idx < markerIndices.length; idx++) {
      const startLine = markerIndices[idx].line;
      const endLine = idx + 1 < markerIndices.length ? markerIndices[idx + 1].line - 1 : lines.length - 1;
      const bodyLines = lines.slice(startLine + 1, endLine + 1);
      cells.push({
        title: markerIndices[idx].title,
        startLine,
        endLine,
        code: bodyLines.join('\n').trim(),
        languageId: document.languageId
      });
    }

    return cells;
  }

  public async executeCell(cellOrUndefined?: ParsedCodeCell): Promise<void> {
    let targetCell = cellOrUndefined;

    if (!targetCell) {
      const editor = vscode.window.activeTextEditor;
      if (!editor) {
        void vscode.window.showWarningMessage('No active editor to run cell.');
        return;
      }
      const cells = this.parseCells(editor.document);
      const cursorLine = editor.selection.active.line;
      targetCell = cells.find((c) => cursorLine >= c.startLine && cursorLine <= c.endLine);

      if (!targetCell) {
        const selectedText = editor.document.getText(editor.selection).trim();
        targetCell = {
          title: 'Selection / Current Buffer',
          startLine: editor.selection.start.line,
          endLine: editor.selection.end.line,
          code: selectedText || editor.document.getText(),
          languageId: editor.document.languageId
        };
      }
    }

    const startTime = Date.now();
    this.outputChannel.show(true);
    this.outputChannel.appendLine(
      `\n─── MicroCode Cell [${targetCell.title}] (${targetCell.languageId}) ───`
    );

    const result = await this.runCodeSnippet(targetCell.code, targetCell.languageId);
    const elapsedMs = Date.now() - startTime;

    if (result.stdout) {
      this.outputChannel.append(result.stdout.endsWith('\n') ? result.stdout : `${result.stdout}\n`);
    }
    if (result.stderr) {
      this.outputChannel.append(result.stderr.endsWith('\n') ? result.stderr : `${result.stderr}\n`);
    }
    this.outputChannel.appendLine(
      result.exitCode === 0
        ? `[OK] Completed in ${elapsedMs}ms`
        : `[FAIL] Exit ${result.exitCode} in ${elapsedMs}ms`
    );
  }

  public async runCodeSnippet(
    code: string,
    languageId: string
  ): Promise<{ stdout: string; stderr: string; exitCode: number }> {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'microcode-cell-'));
    const cleanup = () => {
      try {
        fs.rmSync(tmpDir, { recursive: true, force: true });
      } catch {
        // ignore cleanup error
      }
    };

    try {
      const lang = languageId.toLowerCase();
      if (lang === 'ardium' || lang === 'ar') {
        const arcBin = this.backendManager.findArdiumBinary();
        if (!arcBin) {
          return {
            stdout: '',
            stderr: 'Ardium compiler (`arc`) not found. Install Ardium Toolchain or set `microcode.ardiumBinaryPath`.',
            exitCode: 1
          };
        }
        const file = path.join(tmpDir, 'cell.ar');
        fs.writeFileSync(file, code, 'utf8');
        return await this.spawnCollect(arcBin, ['run', file], tmpDir);
      }

      if (lang === 'python' || lang === 'py') {
        const file = path.join(tmpDir, 'cell.py');
        fs.writeFileSync(file, code, 'utf8');
        return await this.spawnCollect('python3', [file], tmpDir);
      }

      if (lang === 'javascript' || lang === 'typescript' || lang === 'js' || lang === 'ts') {
        const file = path.join(tmpDir, 'cell.js');
        fs.writeFileSync(file, code, 'utf8');
        return await this.spawnCollect('node', [file], tmpDir);
      }

      if (lang === 'swift') {
        const file = path.join(tmpDir, 'cell.swift');
        fs.writeFileSync(file, code, 'utf8');
        return await this.spawnCollect('swift', [file], tmpDir);
      }

      if (lang === 'go') {
        const file = path.join(tmpDir, 'main.go');
        const wrapped = code.includes('package ') ? code : `package main\nimport "fmt"\nfunc main() {\n${code}\n}\n`;
        fs.writeFileSync(file, wrapped, 'utf8');
        return await this.spawnCollect('go', ['run', file], tmpDir);
      }

      if (lang === 'c') {
        const file = path.join(tmpDir, 'cell.c');
        const bin = path.join(tmpDir, 'cell_c_bin');
        fs.writeFileSync(file, code, 'utf8');
        const comp = await this.spawnCollect('clang', ['-O2', file, '-o', bin], tmpDir);
        if (comp.exitCode !== 0) {
          return comp;
        }
        return await this.spawnCollect(bin, [], tmpDir);
      }

      if (lang === 'cpp' || lang === 'c++') {
        const file = path.join(tmpDir, 'cell.cpp');
        const bin = path.join(tmpDir, 'cell_cpp_bin');
        fs.writeFileSync(file, code, 'utf8');
        const comp = await this.spawnCollect('clang++', ['-std=c++20', '-O2', file, '-o', bin], tmpDir);
        if (comp.exitCode !== 0) {
          return comp;
        }
        return await this.spawnCollect(bin, [], tmpDir);
      }

      if (lang === 'rust' || lang === 'rs') {
        const file = path.join(tmpDir, 'cell.rs');
        const bin = path.join(tmpDir, 'cell_bin');
        const wrapped = code.includes('fn main') ? code : `fn main() {\n${code}\n}\n`;
        fs.writeFileSync(file, wrapped, 'utf8');
        const compileRes = await this.spawnCollect('rustc', [file, '-o', bin], tmpDir);
        if (compileRes.exitCode !== 0) {
          return compileRes;
        }
        return await this.spawnCollect(bin, [], tmpDir);
      }

      if (lang === 'sql') {
        const status = this.backendManager.getStatus();
        if (status.backendOnline) {
          try {
            const resp = await this.backendManager.requestJson<any>('/api/sql/execute', 'POST', {
              sql: code,
              session_id: 'vscode_polyglot'
            });
            return {
              stdout: JSON.stringify(resp, null, 2),
              stderr: '',
              exitCode: 0
            };
          } catch (err: any) {
            return { stdout: '', stderr: err?.message ?? String(err), exitCode: 1 };
          }
        }
        return await this.spawnCollect('sqlite3', ['-header', '-column', ':memory:', code], tmpDir);
      }

      // Fallback shell execution
      const file = path.join(tmpDir, 'cell.sh');
      fs.writeFileSync(file, code, 'utf8');
      return await this.spawnCollect('/bin/zsh', [file], tmpDir);
    } finally {
      cleanup();
    }
  }

  private spawnCollect(
    cmd: string,
    args: string[],
    cwd: string
  ): Promise<{ stdout: string; stderr: string; exitCode: number }> {
    return new Promise((resolve) => {
      const proc = cp.spawn(cmd, args, {
        cwd,
        env: {
          ...process.env,
          DYLD_LIBRARY_PATH: `/usr/local/ardium/lib:${process.env.DYLD_LIBRARY_PATH ?? ''}`,
          ARDIUM_LIB_PATH: '/usr/local/ardium/lib',
          ARDIUM_STDLIB: '/usr/local/ardium/stdlib'
        }
      });

      const outChunks: Buffer[] = [];
      const errChunks: Buffer[] = [];
      proc.stdout.on('data', (d: Buffer) => outChunks.push(d));
      proc.stderr.on('data', (d: Buffer) => errChunks.push(d));
      proc.on('close', (code) => {
        resolve({
          stdout: Buffer.concat(outChunks).toString('utf8'),
          stderr: Buffer.concat(errChunks).toString('utf8'),
          exitCode: code ?? 1
        });
      });
      proc.on('error', (err) => {
        resolve({
          stdout: '',
          stderr: err.message,
          exitCode: 1
        });
      });
    });
  }
}
