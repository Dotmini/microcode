"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.NotebookCellOutput = exports.NotebookCellOutputItem = exports.NotebookData = exports.NotebookCellData = exports.NotebookCellKind = exports.ViewColumn = exports.StatusBarAlignment = exports.CodeLens = exports.Diagnostic = exports.DiagnosticSeverity = exports.Selection = exports.Range = exports.Position = exports.Uri = exports.EventEmitter = void 0;
exports.createMicroCodeShim = createMicroCodeShim;
const path = __importStar(require("path"));
class EventEmitter {
    constructor() {
        this.listeners = [];
        this.event = (listener) => {
            this.listeners.push(listener);
            return {
                dispose: () => {
                    const idx = this.listeners.indexOf(listener);
                    if (idx >= 0)
                        this.listeners.splice(idx, 1);
                }
            };
        };
    }
    fire(data) {
        for (const l of this.listeners) {
            try {
                l(data);
            }
            catch {
                // ignore listener errors
            }
        }
    }
    dispose() {
        this.listeners = [];
    }
}
exports.EventEmitter = EventEmitter;
class Uri {
    constructor(scheme, authority, path, query = '', fragment = '') {
        this.scheme = scheme;
        this.authority = authority;
        this.path = path;
        this.query = query;
        this.fragment = fragment;
    }
    get fsPath() {
        return this.path;
    }
    static file(filePath) {
        return new Uri('file', '', filePath);
    }
    static parse(value) {
        try {
            const u = new URL(value);
            return new Uri(u.protocol.replace(':', ''), u.host, u.pathname, u.search.replace(/^\?/, ''), u.hash.replace(/^#/, ''));
        }
        catch {
            return new Uri('file', '', value);
        }
    }
    static joinPath(base, ...segments) {
        return new Uri(base.scheme, base.authority, path.join(base.path, ...segments));
    }
    toString() {
        return `${this.scheme}://${this.authority}${this.path}`;
    }
}
exports.Uri = Uri;
class Position {
    constructor(line, character) {
        this.line = line;
        this.character = character;
    }
}
exports.Position = Position;
class Range {
    constructor(a, b, c, d) {
        if (typeof a === 'number' && typeof b === 'number') {
            this.start = new Position(a, b);
            this.end = new Position(c ?? a, d ?? b);
        }
        else {
            this.start = a;
            this.end = b;
        }
    }
}
exports.Range = Range;
class Selection extends Range {
    constructor(a, b, c, d) {
        super(a, b, c, d);
        this.anchor = this.start;
        this.active = this.end;
    }
    get isEmpty() {
        return (this.anchor.line === this.active.line &&
            this.anchor.character === this.active.character);
    }
}
exports.Selection = Selection;
var DiagnosticSeverity;
(function (DiagnosticSeverity) {
    DiagnosticSeverity[DiagnosticSeverity["Error"] = 0] = "Error";
    DiagnosticSeverity[DiagnosticSeverity["Warning"] = 1] = "Warning";
    DiagnosticSeverity[DiagnosticSeverity["Information"] = 2] = "Information";
    DiagnosticSeverity[DiagnosticSeverity["Hint"] = 3] = "Hint";
})(DiagnosticSeverity || (exports.DiagnosticSeverity = DiagnosticSeverity = {}));
class Diagnostic {
    constructor(range, message, severity = DiagnosticSeverity.Error) {
        this.range = range;
        this.message = message;
        this.severity = severity;
    }
}
exports.Diagnostic = Diagnostic;
class CodeLens {
    constructor(range, command) {
        this.range = range;
        this.command = command;
    }
    get isResolved() {
        return Boolean(this.command);
    }
}
exports.CodeLens = CodeLens;
var StatusBarAlignment;
(function (StatusBarAlignment) {
    StatusBarAlignment[StatusBarAlignment["Left"] = 1] = "Left";
    StatusBarAlignment[StatusBarAlignment["Right"] = 2] = "Right";
})(StatusBarAlignment || (exports.StatusBarAlignment = StatusBarAlignment = {}));
var ViewColumn;
(function (ViewColumn) {
    ViewColumn[ViewColumn["Active"] = -1] = "Active";
    ViewColumn[ViewColumn["Beside"] = -2] = "Beside";
    ViewColumn[ViewColumn["One"] = 1] = "One";
    ViewColumn[ViewColumn["Two"] = 2] = "Two";
    ViewColumn[ViewColumn["Three"] = 3] = "Three";
})(ViewColumn || (exports.ViewColumn = ViewColumn = {}));
var NotebookCellKind;
(function (NotebookCellKind) {
    NotebookCellKind[NotebookCellKind["Markup"] = 1] = "Markup";
    NotebookCellKind[NotebookCellKind["Code"] = 2] = "Code";
})(NotebookCellKind || (exports.NotebookCellKind = NotebookCellKind = {}));
class NotebookCellData {
    constructor(kind, value, languageId) {
        this.kind = kind;
        this.value = value;
        this.languageId = languageId;
    }
}
exports.NotebookCellData = NotebookCellData;
class NotebookData {
    constructor(cells) {
        this.cells = cells;
    }
}
exports.NotebookData = NotebookData;
class NotebookCellOutputItem {
    constructor(data, mime) {
        this.data = data;
        this.mime = mime;
    }
    static text(value, mime = 'text/plain') {
        return new NotebookCellOutputItem(Buffer.from(value, 'utf8'), mime);
    }
    static json(value, mime = 'application/json') {
        return new NotebookCellOutputItem(Buffer.from(JSON.stringify(value), 'utf8'), mime);
    }
    static error(err) {
        return new NotebookCellOutputItem(Buffer.from(JSON.stringify(err), 'utf8'), 'application/vnd.code.notebook.error');
    }
}
exports.NotebookCellOutputItem = NotebookCellOutputItem;
class NotebookCellOutput {
    constructor(items, metadata) {
        this.items = items;
        this.metadata = metadata;
    }
}
exports.NotebookCellOutput = NotebookCellOutput;
function createMicroCodeShim(emit) {
    const registeredCommands = new Map();
    const configStore = new Map();
    const onDidSaveEmitter = new EventEmitter();
    const onDidOpenEmitter = new EventEmitter();
    const onDidChangeEmitter = new EventEmitter();
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
            registerCommand: (command, callback) => {
                registeredCommands.set(command, callback);
                emit('command/register', { command });
                return { dispose: () => registeredCommands.delete(command) };
            },
            executeCommand: (command, ...rest) => {
                const callback = registeredCommands.get(command);
                emit('command/executed', { command, argsCount: rest.length });
                return Promise.resolve(callback?.(...rest));
            },
            getCommands: () => Promise.resolve(Array.from(registeredCommands.keys()))
        },
        window: {
            activeTextEditor: undefined,
            showInformationMessage: (message, ...items) => {
                emit('window/info', { message, items });
                return Promise.resolve(items[0]);
            },
            showWarningMessage: (message, ...items) => {
                emit('window/warning', { message, items });
                return Promise.resolve(items[0]);
            },
            showErrorMessage: (message, ...items) => {
                emit('window/error', { message, items });
                return Promise.resolve(items[0]);
            },
            createOutputChannel: (name) => {
                return {
                    name,
                    append: (val) => emit('window/output', { name, value: val }),
                    appendLine: (val) => emit('window/output', { name, value: val + '\n' }),
                    clear: () => emit('window/outputClear', { name }),
                    show: () => emit('window/outputShow', { name }),
                    hide: () => { },
                    dispose: () => { }
                };
            },
            createStatusBarItem: (alignment = StatusBarAlignment.Left, priority = 0) => {
                const item = {
                    text: '',
                    tooltip: '',
                    color: undefined,
                    command: undefined,
                    show: () => emit('statusbar/show', { text: item.text, tooltip: item.tooltip, alignment, priority }),
                    hide: () => emit('statusbar/hide', {}),
                    dispose: () => emit('statusbar/dispose', {})
                };
                return item;
            },
            registerWebviewViewProvider: (viewId, provider) => {
                emit('webview/registerProvider', { viewId });
                return { dispose: () => { } };
            },
            createWebviewPanel: (viewType, title) => {
                const msgEmitter = new EventEmitter();
                const disposeEmitter = new EventEmitter();
                const webview = {
                    options: {},
                    html: '',
                    cspSource: 'microcode-webview:',
                    onDidReceiveMessage: msgEmitter.event,
                    postMessage: (message) => {
                        emit('webview/postMessage', { viewType, message });
                        return Promise.resolve(true);
                    },
                    asWebviewUri: (uri) => uri
                };
                emit('webview/createPanel', { viewType, title });
                return {
                    viewType,
                    title,
                    webview,
                    visible: true,
                    onDidDispose: disposeEmitter.event,
                    reveal: () => { },
                    dispose: () => disposeEmitter.fire()
                };
            },
            showTextDocument: (doc) => {
                emit('window/showTextDocument', { uri: doc?.uri?.toString?.() ?? String(doc) });
                return Promise.resolve(undefined);
            },
            showNotebookDocument: (doc) => {
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
            getConfiguration: (section) => {
                return {
                    get: (key, defaultValue) => {
                        const fullKey = section ? `${section}.${key}` : key;
                        return configStore.has(fullKey) ? configStore.get(fullKey) : defaultValue;
                    },
                    update: (key, value) => {
                        const fullKey = section ? `${section}.${key}` : key;
                        configStore.set(fullKey, value);
                        emit('workspace/configUpdate', { key: fullKey, value });
                        return Promise.resolve();
                    }
                };
            },
            openTextDocument: (uriOrOptions) => {
                return Promise.resolve({
                    uri: Uri.file(typeof uriOrOptions === 'string' ? uriOrOptions : 'untitled'),
                    fileName: typeof uriOrOptions === 'string' ? uriOrOptions : 'untitled',
                    languageId: uriOrOptions?.language ?? 'plaintext',
                    lineCount: 1,
                    getText: () => uriOrOptions?.content ?? '',
                    save: () => Promise.resolve(true)
                });
            },
            openNotebookDocument: (notebookType, content) => {
                return Promise.resolve({
                    uri: Uri.file(`untitled.mcn`),
                    notebookType,
                    cellCount: content?.cells?.length ?? 0,
                    getCells: () => []
                });
            },
            registerNotebookSerializer: (notebookType) => {
                emit('notebook/registerSerializer', { notebookType });
                return { dispose: () => { } };
            }
        },
        languages: {
            createDiagnosticCollection: (name = 'default') => {
                const store = new Map();
                return {
                    name,
                    set: (uri, diags) => {
                        if (diags) {
                            store.set(uri.toString(), diags);
                        }
                        else {
                            store.delete(uri.toString());
                        }
                        emit('diagnostics/publish', {
                            name,
                            uri: uri.toString(),
                            count: diags?.length ?? 0
                        });
                    },
                    delete: (uri) => store.delete(uri.toString()),
                    clear: () => store.clear(),
                    dispose: () => store.clear()
                };
            },
            registerCodeLensProvider: (selector, provider) => {
                emit('languages/registerCodeLens', { selector });
                return { dispose: () => { } };
            },
            registerCompletionItemProvider: (selector) => {
                emit('languages/registerCompletion', { selector });
                return { dispose: () => { } };
            },
            registerHoverProvider: (selector) => {
                emit('languages/registerHover', { selector });
                return { dispose: () => { } };
            }
        },
        notebooks: {
            createNotebookController: (id, notebookType, label) => {
                emit('notebook/createController', { id, notebookType, label });
                return {
                    id,
                    notebookType,
                    label,
                    supportedLanguages: [],
                    supportsExecutionOrder: true,
                    description: '',
                    executeHandler: () => { },
                    createNotebookCellExecution: (cell) => ({
                        cell,
                        executionOrder: 1,
                        start: () => { },
                        end: () => { },
                        clearOutput: () => Promise.resolve(),
                        replaceOutput: () => Promise.resolve(),
                        appendOutput: () => Promise.resolve()
                    }),
                    dispose: () => { }
                };
            }
        },
        lm: {
            registerMcpServerDefinitionProvider: (id, provider) => {
                emit('lm/registerMcpProvider', { id });
                return { dispose: () => { } };
            }
        }
    };
}
