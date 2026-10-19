import * as path from 'path';

export type HostEvent = (method: string, params: Record<string, unknown>) => void;

export class EventEmitter<T = any> {
  private listeners: Array<(e: T) => any> = [];
  public readonly event = (listener: (e: T) => any) => {
    this.listeners.push(listener);
    return {
      dispose: () => {
        const idx = this.listeners.indexOf(listener);
        if (idx >= 0) this.listeners.splice(idx, 1);
      }
    };
  };
  public fire(data: T): void {
    for (const l of this.listeners) {
      try {
        l(data);
      } catch {
        // ignore listener errors
      }
    }
  }
  public dispose(): void {
    this.listeners = [];
  }
}

export class Uri {
  constructor(
    public readonly scheme: string,
    public readonly authority: string,
    public readonly path: string,
    public readonly query: string = '',
    public readonly fragment: string = ''
  ) {}

  get fsPath(): string {
    return this.path;
  }

  static file(filePath: string): Uri {
    return new Uri('file', '', filePath);
  }

  static parse(value: string): Uri {
    try {
      const u = new URL(value);
      return new Uri(
        u.protocol.replace(':', ''),
        u.host,
        u.pathname,
        u.search.replace(/^\?/, ''),
        u.hash.replace(/^#/, '')
      );
    } catch {
      return new Uri('file', '', value);
    }
  }

  static joinPath(base: Uri, ...segments: string[]): Uri {
    return new Uri(base.scheme, base.authority, path.join(base.path, ...segments));
  }

  toString(): string {
    return `${this.scheme}://${this.authority}${this.path}`;
  }
}

export class Position {
  constructor(public readonly line: number, public readonly character: number) {}
}

export class Range {
  public readonly start: Position;
  public readonly end: Position;
  constructor(
    a: Position | number,
    b: Position | number,
    c?: number,
    d?: number
  ) {
    if (typeof a === 'number' && typeof b === 'number') {
      this.start = new Position(a, b);
      this.end = new Position(c ?? a, d ?? b);
    } else {
      this.start = a as Position;
      this.end = b as Position;
    }
  }
}

export class Selection extends Range {
  public readonly anchor: Position;
  public readonly active: Position;
  constructor(
    a: Position | number,
    b: Position | number,
    c?: number,
    d?: number
  ) {
    super(a as any, b as any, c, d);
    this.anchor = this.start;
    this.active = this.end;
  }
  get isEmpty(): boolean {
    return (
      this.anchor.line === this.active.line &&
      this.anchor.character === this.active.character
    );
  }
}

export enum DiagnosticSeverity {
  Error = 0,
  Warning = 1,
  Information = 2,
  Hint = 3
}

export class Diagnostic {
  public source?: string;
  public code?: string | number;
  constructor(
    public range: Range,
    public message: string,
    public severity: DiagnosticSeverity = DiagnosticSeverity.Error
  ) {}
}

export class CodeLens {
  constructor(public range: Range, public command?: any) {}
  get isResolved(): boolean {
    return Boolean(this.command);
  }
}

export enum StatusBarAlignment {
  Left = 1,
  Right = 2
}

export enum ViewColumn {
  Active = -1,
  Beside = -2,
  One = 1,
  Two = 2,
  Three = 3
}

export enum NotebookCellKind {
  Markup = 1,
  Code = 2
}

export class NotebookCellData {
  public outputs?: any[];
  public metadata?: Record<string, any>;
  constructor(
    public kind: NotebookCellKind,
    public value: string,
    public languageId: string
  ) {}
}

export class NotebookData {
  public metadata?: Record<string, any>;
  constructor(public cells: NotebookCellData[]) {}
}

export class NotebookCellOutputItem {
  constructor(public readonly data: Uint8Array, public readonly mime: string) {}
  static text(value: string, mime = 'text/plain'): NotebookCellOutputItem {
    return new NotebookCellOutputItem(Buffer.from(value, 'utf8'), mime);
  }
  static json(value: any, mime = 'application/json'): NotebookCellOutputItem {
    return new NotebookCellOutputItem(Buffer.from(JSON.stringify(value), 'utf8'), mime);
  }
  static error(err: Error | { name: string; message: string; stack?: string }): NotebookCellOutputItem {
    return new NotebookCellOutputItem(
      Buffer.from(JSON.stringify(err), 'utf8'),
      'application/vnd.code.notebook.error'
    );
  }
}

export class NotebookCellOutput {
  constructor(
    public items: NotebookCellOutputItem[],
    public metadata?: Record<string, any>
  ) {}
}

export function createMicroCodeShim(emit: HostEvent) {
  const registeredCommands = new Map<string, (...args: any[]) => any>();
  const configStore = new Map<string, any>();
  const onDidSaveEmitter = new EventEmitter<any>();
  const onDidOpenEmitter = new EventEmitter<any>();
  const onDidChangeEmitter = new EventEmitter<any>();

  return {
    EventEmitter,
    Uri,
    Position,
    Range,
    Selection,
    DiagnosticSeverity,
    Diagnostic,
    CodeLens,
    StatusBarAlignment,
    ViewColumn,
    NotebookCellKind,
    NotebookCellData,
    NotebookData,
    NotebookCellOutputItem,
    NotebookCellOutput,

    commands: {
      registerCommand: (command: string, callback: (...args: any[]) => any) => {
        registeredCommands.set(command, callback);
        emit('command/register', { command });
        return { dispose: () => registeredCommands.delete(command) };
      },
      executeCommand: (command: string, ...rest: any[]) => {
        const callback = registeredCommands.get(command);
        emit('command/executed', { command, argsCount: rest.length });
        return Promise.resolve(callback?.(...rest));
      },
      getCommands: () => Promise.resolve(Array.from(registeredCommands.keys()))
    },

    window: {
      activeTextEditor: undefined,
      showInformationMessage: (message: string, ...items: string[]) => {
        emit('window/info', { message, items });
        return Promise.resolve(items[0]);
      },
      showWarningMessage: (message: string, ...items: string[]) => {
        emit('window/warning', { message, items });
        return Promise.resolve(items[0]);
      },
      showErrorMessage: (message: string, ...items: string[]) => {
        emit('window/error', { message, items });
        return Promise.resolve(items[0]);
      },
      createOutputChannel: (name: string) => {
        return {
          name,
          append: (val: string) => emit('window/output', { name, value: val }),
          appendLine: (val: string) => emit('window/output', { name, value: val + '\n' }),
          clear: () => emit('window/outputClear', { name }),
          show: () => emit('window/outputShow', { name }),
          hide: () => {},
          dispose: () => {}
        };
      },
      createStatusBarItem: (alignment: StatusBarAlignment = StatusBarAlignment.Left, priority = 0) => {
        const item = {
          text: '',
          tooltip: '',
          color: undefined as string | undefined,
          command: undefined as string | undefined,
          show: () => emit('statusbar/show', { text: item.text, tooltip: item.tooltip, alignment, priority }),
          hide: () => emit('statusbar/hide', {}),
          dispose: () => emit('statusbar/dispose', {})
        };
        return item;
      },
      registerWebviewViewProvider: (viewId: string, provider: any) => {
        emit('webview/registerProvider', { viewId });
        return { dispose: () => {} };
      },
      createWebviewPanel: (viewType: string, title: string) => {
        const msgEmitter = new EventEmitter<any>();
        const disposeEmitter = new EventEmitter<void>();
        const webview = {
          options: {},
          html: '',
          cspSource: 'microcode-webview:',
          onDidReceiveMessage: msgEmitter.event,
          postMessage: (message: any) => {
            emit('webview/postMessage', { viewType, message });
            return Promise.resolve(true);
          },
          asWebviewUri: (uri: Uri) => uri
        };
        emit('webview/createPanel', { viewType, title });
        return {
          viewType,
          title,
          webview,
          visible: true,
          onDidDispose: disposeEmitter.event,
          reveal: () => {},
          dispose: () => disposeEmitter.fire()
        };
      },
      showTextDocument: (doc: any) => {
        emit('window/showTextDocument', { uri: doc?.uri?.toString?.() ?? String(doc) });
        return Promise.resolve(undefined);
      },
      showNotebookDocument: (doc: any) => {
        emit('window/showNotebookDocument', { notebookType: doc?.notebookType });
        return Promise.resolve(undefined);
      }
    },

    workspace: {
      workspaceFolders: [
        {
          uri: Uri.file(process.cwd()),
          name: path.basename(process.cwd()),
          index: 0
        }
      ],
      onDidSaveTextDocument: onDidSaveEmitter.event,
      onDidOpenTextDocument: onDidOpenEmitter.event,
      onDidChangeTextDocument: onDidChangeEmitter.event,
      getConfiguration: (section?: string) => {
        return {
          get: (key: string, defaultValue?: any) => {
            const fullKey = section ? `${section}.${key}` : key;
            return configStore.has(fullKey) ? configStore.get(fullKey) : defaultValue;
          },
          update: (key: string, value: any) => {
            const fullKey = section ? `${section}.${key}` : key;
            configStore.set(fullKey, value);
            emit('workspace/configUpdate', { key: fullKey, value });
            return Promise.resolve();
          }
        };
      },
      openTextDocument: (uriOrOptions: any) => {
        return Promise.resolve({
          uri: Uri.file(typeof uriOrOptions === 'string' ? uriOrOptions : 'untitled'),
          fileName: typeof uriOrOptions === 'string' ? uriOrOptions : 'untitled',
          languageId: uriOrOptions?.language ?? 'plaintext',
          lineCount: 1,
          getText: () => uriOrOptions?.content ?? '',
          save: () => Promise.resolve(true)
        });
      },
      openNotebookDocument: (notebookType: string, content?: NotebookData) => {
        return Promise.resolve({
          uri: Uri.file(`untitled.mcn`),
          notebookType,
          cellCount: content?.cells?.length ?? 0,
          getCells: () => []
        });
      },
      registerNotebookSerializer: (notebookType: string) => {
        emit('notebook/registerSerializer', { notebookType });
        return { dispose: () => {} };
      }
    },

    languages: {
      createDiagnosticCollection: (name = 'default') => {
        const store = new Map<string, readonly Diagnostic[]>();
        return {
          name,
          set: (uri: Uri, diags: readonly Diagnostic[] | undefined) => {
            if (diags) {
              store.set(uri.toString(), diags);
            } else {
              store.delete(uri.toString());
            }
            emit('diagnostics/publish', {
              name,
              uri: uri.toString(),
              count: diags?.length ?? 0
            });
          },
          delete: (uri: Uri) => store.delete(uri.toString()),
          clear: () => store.clear(),
          dispose: () => store.clear()
        };
      },
      registerCodeLensProvider: (selector: any, provider: any) => {
        emit('languages/registerCodeLens', { selector });
        return { dispose: () => {} };
      },
      registerCompletionItemProvider: (selector: any) => {
        emit('languages/registerCompletion', { selector });
        return { dispose: () => {} };
      },
      registerHoverProvider: (selector: any) => {
        emit('languages/registerHover', { selector });
        return { dispose: () => {} };
      }
    },

    notebooks: {
      createNotebookController: (id: string, notebookType: string, label: string) => {
        emit('notebook/createController', { id, notebookType, label });
        return {
          id,
          notebookType,
          label,
          supportedLanguages: [],
          supportsExecutionOrder: true,
          description: '',
          executeHandler: () => {},
          createNotebookCellExecution: (cell: any) => ({
            cell,
            executionOrder: 1,
            start: () => {},
            end: () => {},
            clearOutput: () => Promise.resolve(),
            replaceOutput: () => Promise.resolve(),
            appendOutput: () => Promise.resolve()
          }),
          dispose: () => {}
        };
      }
    },

    lm: {
      registerMcpServerDefinitionProvider: (id: string, provider: any) => {
        emit('lm/registerMcpProvider', { id });
        return { dispose: () => {} };
      }
    }
  };
}
