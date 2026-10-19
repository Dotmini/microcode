import * as vscode from 'vscode';
import { TextDecoder, TextEncoder } from 'util';
import { BackendManager } from '../backendManager';
import { MicroCodeCellCodeLensProvider } from './cellCodeLens';

interface RawNotebookCell {
  kind: 'markup' | 'code';
  language: string;
  value: string;
}

interface RawNotebookJson {
  version: string;
  session_id?: string;
  cells: RawNotebookCell[];
}

export class MicroCodeNotebookSerializer implements vscode.NotebookSerializer {
  public async deserializeNotebook(content: Uint8Array): Promise<vscode.NotebookData> {
    const rawStr = new TextDecoder().decode(content).trim();
    if (!rawStr) {
      return new vscode.NotebookData([
        new vscode.NotebookCellData(
          vscode.NotebookCellKind.Markup,
          '# MicroCode Polyglot Notebook (`.mcn`)\nZero-copy Rosetta Shared Memory across **Ardium v2.3**, **Python**, **Rust**, and **SQL**.',
          'markdown'
        ),
        new vscode.NotebookCellData(
          vscode.NotebookCellKind.Code,
          'fn main() {\n    @owned let buf = alloc(64);\n    print("Hello from Ardium Polyglot Cell!\\n");\n}',
          'ardium'
        )
      ]);
    }

    try {
      const parsed = JSON.parse(rawStr) as RawNotebookJson;
      const cells = (parsed.cells ?? []).map(
        (c) =>
          new vscode.NotebookCellData(
            c.kind === 'markup' ? vscode.NotebookCellKind.Markup : vscode.NotebookCellKind.Code,
            c.value,
            c.language
          )
      );
      return new vscode.NotebookData(cells);
    } catch {
      return new vscode.NotebookData([
        new vscode.NotebookCellData(vscode.NotebookCellKind.Code, rawStr, 'ardium')
      ]);
    }
  }

  public async serializeNotebook(data: vscode.NotebookData): Promise<Uint8Array> {
    const payload: RawNotebookJson = {
      version: '2.5.27',
      session_id: 'vscode_polyglot',
      cells: data.cells.map((cell) => ({
        kind: cell.kind === vscode.NotebookCellKind.Markup ? 'markup' : 'code',
        language: cell.languageId,
        value: cell.value
      }))
    };
    return new TextEncoder().encode(JSON.stringify(payload, null, 2) + '\n');
  }
}

export class MicroCodePolyglotController implements vscode.Disposable {
  private readonly controller: vscode.NotebookController;
  private executionOrder = 0;

  constructor(
    private readonly backendManager: BackendManager,
    private readonly cellRunner: MicroCodeCellCodeLensProvider
  ) {
    this.controller = vscode.notebooks.createNotebookController(
      'microcode-polyglot-kernel',
      'microcode-polyglot-notebook',
      'MicroCode Polyglot & Rosetta SHM Kernel'
    );
    this.controller.supportedLanguages = [
      'ardium',
      'python',
      'rust',
      'sql',
      'javascript',
      'typescript'
    ];
    this.controller.supportsExecutionOrder = true;
    this.controller.description = 'Ardium v2.3 · Python · Rust · SQL (Rosetta Shared Memory)';
    this.controller.executeHandler = this.executeCells.bind(this);
  }

  private async executeCells(cells: vscode.NotebookCell[]): Promise<void> {
    for (const cell of cells) {
      await this.executeSingleCell(cell);
    }
  }

  private async executeSingleCell(cell: vscode.NotebookCell): Promise<void> {
    const execution = this.controller.createNotebookCellExecution(cell);
    execution.executionOrder = ++this.executionOrder;
    execution.start(Date.now());

    try {
      const code = cell.document.getText();
      const lang = cell.document.languageId;
      const result = await this.cellRunner.runCodeSnippet(code, lang);

      const items: vscode.NotebookCellOutputItem[] = [];
      if (result.stdout) {
        items.push(vscode.NotebookCellOutputItem.text(result.stdout, 'text/plain'));
      }
      if (result.stderr) {
        items.push(vscode.NotebookCellOutputItem.text(result.stderr, 'text/plain'));
      }
      if (items.length === 0) {
        items.push(vscode.NotebookCellOutputItem.text('✓ Executed (no stdout)', 'text/plain'));
      }

      await execution.replaceOutput([new vscode.NotebookCellOutput(items)]);
      execution.end(result.exitCode === 0, Date.now());
    } catch (err: any) {
      await execution.replaceOutput([
        new vscode.NotebookCellOutput([
          vscode.NotebookCellOutputItem.error({
            name: 'MicroCodePolyglotError',
            message: err?.message ?? String(err)
          })
        ])
      ]);
      execution.end(false, Date.now());
    }
  }

  public async createSampleNotebook(): Promise<void> {
    const data = new vscode.NotebookData([
      new vscode.NotebookCellData(
        vscode.NotebookCellKind.Markup,
        '# ⚡ MicroCode Polyglot Notebook (`.mcn`)\nExecute **Ardium v2.3**, **Python**, **Rust**, and **SQL** cells side-by-side.',
        'markdown'
      ),
      new vscode.NotebookCellData(
        vscode.NotebookCellKind.Code,
        'fn main() {\n    @owned let buffer = alloc(256);\n    poke(buffer + 0, 42);\n    print("Ardium v2.3 RAII buffer value: ");\n    print(peek(buffer + 0));\n    print("\\n");\n}',
        'ardium'
      ),
      new vscode.NotebookCellData(
        vscode.NotebookCellKind.Code,
        'import platform\nprint(f"Python {platform.python_version()} connected to MicroCode Polyglot runtime!")',
        'python'
      ),
      new vscode.NotebookCellData(
        vscode.NotebookCellKind.Code,
        'println!("Rust native cell compiled and executed by MicroCode!");',
        'rust'
      )
    ]);

    const doc = await vscode.workspace.openNotebookDocument('microcode-polyglot-notebook', data);
    await vscode.window.showNotebookDocument(doc);
  }

  public dispose(): void {
    this.controller.dispose();
  }
}
