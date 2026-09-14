"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createMicroCodeShim = exports.microcodeShim = void 0;

class Position {
    constructor(line, character) {
        this.line = line || 0;
        this.character = character || 0;
    }
    isEqual(other) { return other && this.line === other.line && this.character === other.character; }
    isBefore(other) { return other && (this.line < other.line || (this.line === other.line && this.character < other.character)); }
    isAfter(other) { return other && (this.line > other.line || (this.line === other.line && this.character > other.character)); }
    translate(lineDelta, charDelta) { return new Position(this.line + (lineDelta || 0), this.character + (charDelta || 0)); }
    with(change) { return new Position(change && change.line !== undefined ? change.line : this.line, change && change.character !== undefined ? change.character : this.character); }
}

class Range {
    constructor(startLineOrPos, startCharOrEndPos, endLine, endChar) {
        if (typeof startLineOrPos === 'number') {
            this.start = new Position(startLineOrPos, startCharOrEndPos);
            this.end = new Position(endLine, endChar);
        } else {
            this.start = startLineOrPos || new Position(0, 0);
            this.end = startCharOrEndPos || this.start;
        }
    }
    get isEmpty() { return this.start.isEqual(this.end); }
    get isSingleLine() { return this.start.line === this.end.line; }
    contains(posOrRange) { return true; }
    isEqual(other) { return other && this.start.isEqual(other.start) && this.end.isEqual(other.end); }
    union(other) { return this; }
    with(change) { return new Range(change && change.start || this.start, change && change.end || this.end); }
}

class Selection extends Range {
    constructor(anchorLine, anchorCharacter, activeLine, activeCharacter) {
        if (typeof anchorLine === 'object') {
            super(anchorLine.line, anchorLine.character, anchorCharacter.line, anchorCharacter.character);
            this.anchor = anchorLine;
            this.active = anchorCharacter;
        } else {
            super(anchorLine, anchorCharacter, activeLine, activeCharacter);
            this.anchor = new Position(anchorLine, anchorCharacter);
            this.active = new Position(activeLine, activeCharacter);
        }
    }
    get isReversed() { return this.anchor.isAfter(this.active); }
}

class Location {
    constructor(uri, rangeOrPosition) {
        this.uri = uri;
        this.range = rangeOrPosition instanceof Range ? rangeOrPosition : new Range(rangeOrPosition, rangeOrPosition);
    }
}

class RelativePattern {
    constructor(base, pattern) {
        this.base = base;
        this.pattern = pattern;
    }
}

class Uri {
    constructor(scheme, authority, path, query, fragment) {
        this.scheme = scheme || 'file';
        this.authority = authority || '';
        this.path = path || '';
        this.query = query || '';
        this.fragment = fragment || '';
        this.fsPath = path || '';
    }
    toString() { return `${this.scheme}://${this.authority}${this.path}`; }
    toJSON() { return { scheme: this.scheme, authority: this.authority, path: this.path, fsPath: this.fsPath }; }
    static file(path) { return new Uri('file', '', path); }
    static parse(uriStr) {
        try {
            const u = new URL(uriStr);
            return new Uri(u.protocol.replace(':', ''), u.host, u.pathname);
        } catch {
            return new Uri('file', '', uriStr);
        }
    }
    static joinPath(base, ...pathSegments) {
        const p = [base.path, ...pathSegments].join('/').replace(/\/+/g, '/');
        return new Uri(base.scheme, base.authority, p);
    }
}

class Disposable {
    constructor(callOnDispose) { this._call = callOnDispose; }
    dispose() { if (this._call) this._call(); }
    static from(...disposables) {
        return new Disposable(() => {
            for (const d of disposables) {
                if (d && typeof d.dispose === 'function') d.dispose();
            }
        });
    }
}

class EventEmitter {
    constructor() { this.listeners = []; }
    get event() {
        return (listener) => {
            this.listeners.push(listener);
            return new Disposable(() => {
                const idx = this.listeners.indexOf(listener);
                if (idx >= 0) this.listeners.splice(idx, 1);
            });
        };
    }
    fire(data) {
        for (const l of this.listeners) {
            try { l(data); } catch (e) { console.error(e); }
        }
    }
    dispose() { this.listeners = []; }
}

class CancellationTokenSource {
    constructor() {
        this.token = { isCancellationRequested: false, onCancellationRequested: new EventEmitter().event };
    }
    cancel() { this.token.isCancellationRequested = true; }
    dispose() {}
}

class ThemeColor {
    constructor(id) { this.id = id; }
}

class ThemeIcon {
    constructor(id, color) { this.id = id; this.color = color; }
}

class CodeAction {
    constructor(title, kind) {
        this.title = title;
        this.kind = kind;
    }
}

class TextEdit {
    constructor(range, newText) {
        this.range = range;
        this.newText = newText;
    }
    static replace(range, newText) { return new TextEdit(range, newText); }
    static insert(position, newText) { return new TextEdit(new Range(position, position), newText); }
    static delete(range) { return new TextEdit(range, ''); }
}

class WorkspaceEdit {
    constructor() {
        this.entries = [];
    }
    replace(uri, range, newText) { this.entries.push({ uri, range, newText }); }
    insert(uri, position, newText) { this.entries.push({ uri, position, newText }); }
    delete(uri, range) { this.entries.push({ uri, range }); }
    has(uri) { return true; }
    set(uri, edits) { this.entries.push({ uri, edits }); }
}

class SnippetString {
    constructor(value) { this.value = value || ''; }
    appendText(string) { this.value += string; return this; }
    appendTabstop(number) { this.value += `$${number || 0}`; return this; }
    appendPlaceholder(value, number) { this.value += `\${${number || 0}:${value}}`; return this; }
    appendChoice(values, number) { this.value += `\${${number || 0}|${values.join(',')}|}`; return this; }
    appendVariable(name, defaultValue) { this.value += `\${${name}${defaultValue ? ':' + defaultValue : ''}}`; return this; }
}

class Hover {
    constructor(contents, range) {
        this.contents = Array.isArray(contents) ? contents : [contents];
        this.range = range;
    }
}

class Diagnostic {
    constructor(range, message, severity) {
        this.range = range;
        this.message = message;
        this.severity = severity !== undefined ? severity : DiagnosticSeverity.Error;
    }
}

class CodeLens {
    constructor(range, command) {
        this.range = range;
        this.command = command;
    }
    get isResolved() { return Boolean(this.command); }
}

class CompletionItem {
    constructor(label, kind) {
        this.label = label;
        this.kind = kind;
    }
}

const StatusBarAlignment = { Left: 1, Right: 2 };
const DiagnosticSeverity = { Error: 0, Warning: 1, Information: 2, Hint: 3 };
const OverviewRulerLane = { Left: 1, Center: 2, Right: 4, Full: 7 };
const DecorationRangeBehavior = {
    OpenOpen: 0,
    ClosedClosed: 1,
    OpenClosed: 2,
    ClosedOpen: 3,
    OpenBottom: 0
};
const ExtensionMode = { Production: 1, Development: 2, Test: 3 };
const LanguageStatusSeverity = { Information: 0, Warning: 1, Error: 2 };
class CodeActionKind {
    constructor(value) {
        this.value = value;
    }
    append(parts) {
        return new CodeActionKind(this.value ? `${this.value}.${parts}` : parts);
    }
    intersects(other) {
        return this.contains(other) || (other && other.contains && other.contains(this));
    }
    contains(other) {
        if (!other) return false;
        const val = typeof other === 'string' ? other : other.value;
        return this.value === val || (Boolean(val) && val.startsWith(this.value + '.'));
    }
    toString() {
        return this.value;
    }
}
CodeActionKind.Empty = new CodeActionKind('');
CodeActionKind.QuickFix = new CodeActionKind('quickfix');
CodeActionKind.Refactor = new CodeActionKind('refactor');
CodeActionKind.RefactorExtract = new CodeActionKind('refactor.extract');
CodeActionKind.RefactorInline = new CodeActionKind('refactor.inline');
CodeActionKind.RefactorMove = new CodeActionKind('refactor.move');
CodeActionKind.RefactorRewrite = new CodeActionKind('refactor.rewrite');
CodeActionKind.Source = new CodeActionKind('source');
CodeActionKind.SourceOrganizeImports = new CodeActionKind('source.organizeImports');
CodeActionKind.SourceFixAll = new CodeActionKind('source.fixAll');
const ViewColumn = { Active: -1, Beside: -2, One: 1, Two: 2, Three: 3 };
const EndOfLine = { LF: 1, CRLF: 2 };
const LogLevel = { Off: 0, Trace: 1, Debug: 2, Info: 3, Warning: 4, Error: 5 };

const CompletionItemKind = {
    Text: 0, Method: 1, Function: 2, Constructor: 3, Field: 4, Variable: 5,
    Class: 6, Interface: 7, Module: 8, Property: 9, Unit: 10, Value: 11,
    Enum: 12, Keyword: 13, Snippet: 14, Color: 15, File: 16, Reference: 17,
    Folder: 18, EnumMember: 19, Constant: 20, Struct: 21, Event: 22, Operator: 23, TypeParameter: 24
};
const SymbolKind = {
    File: 0, Module: 1, Namespace: 2, Package: 3, Class: 4, Method: 5, Property: 6,
    Field: 7, Constructor: 8, Enum: 9, Interface: 10, Function: 11, Variable: 12,
    Constant: 13, String: 14, Number: 15, Boolean: 16, Array: 17, Object: 18,
    Key: 19, Null: 20, EnumMember: 21, Struct: 22, Event: 23, Operator: 24, TypeParameter: 25
};
const ProgressLocation = { SourceControl: 1, Window: 10, Notification: 15 };
const IndentAction = { None: 0, Indent: 1, IndentOutdent: 2, Outdent: 3 };

if (!process.env.VSCODE_NLS_CONFIG) {
    process.env.VSCODE_NLS_CONFIG = JSON.stringify({ locale: 'en' });
}

const BUILTIN_DEFAULTS = {
    'search.exclude': { '**/node_modules': true, '**/bower_components': true, '**/*.code-search': true },
    'files.exclude': { '**/.git': true, '**/.svn': true, '**/.hg': true, '**/CVS': true, '**/.DS_Store': true, '**/Thumbs.db': true },
    'editor.tabSize': 4,
    'editor.insertSpaces': true,
    'editor.fontSize': 14,
    'editor.fontFamily': 'Menlo, Monaco, monospace',
    'editor.codeActionsOnSave': {},
    'editor.defaultFormatter': null,
    'files.autoSave': 'off',
    'files.eol': '\n'
};

let cachedExtensionDefaults = null;
function getConfigurationDefault(section, key) {
    const fullKey = section ? (key ? `${section}.${key}` : section) : key;
    if (fullKey && BUILTIN_DEFAULTS[fullKey] !== undefined) return BUILTIN_DEFAULTS[fullKey];
    if (key && BUILTIN_DEFAULTS[key] !== undefined) return BUILTIN_DEFAULTS[key];

    if (!cachedExtensionDefaults) {
        cachedExtensionDefaults = new Map();
        try {
            const fs = require('fs');
            const path = require('path');
            const extBase = path.join(process.env.HOME || '', 'Library/Application Support/MicroCode/Extensions');
            if (fs.existsSync(extBase)) {
                for (const f of fs.readdirSync(extBase)) {
                    const p = path.join(extBase, f, 'package.json');
                    if (fs.existsSync(p)) {
                        const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));
                        const configs = pkg.contributes && pkg.contributes.configuration;
                        const confList = Array.isArray(configs) ? configs : (configs ? [configs] : []);
                        for (const c of confList) {
                            if (c.properties) {
                                for (const [propKey, propVal] of Object.entries(c.properties)) {
                                    if (propVal && propVal.default !== undefined) {
                                        cachedExtensionDefaults.set(propKey, propVal.default);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch (e) {}
    }

    if (fullKey && cachedExtensionDefaults.has(fullKey)) return cachedExtensionDefaults.get(fullKey);
    if (key && cachedExtensionDefaults.has(key)) return cachedExtensionDefaults.get(key);
    return undefined;
}

function createMicroCodeShim(emit) {
    const emitter = emit || ((method, params) => {});
    const registeredCommands = new Map();

    const sampleDoc = {
        uri: Uri.file('/workspace/index.js'),
        fileName: '/workspace/index.js',
        isUntitled: false,
        languageId: 'javascript',
        version: 1,
        isDirty: false,
        isClosed: false,
        lineCount: 10,
        getText: () => 'console.log("MicroCode Extension Active");\n',
        lineAt: (line) => ({ text: 'console.log("MicroCode Extension Active");', lineNumber: line, range: new Range(line, 0, line, 38) }),
        offsetAt: () => 0,
        positionAt: () => new Position(0, 0)
    };

    const sampleEditor = {
        document: sampleDoc,
        selection: new Range(0, 0, 0, 0),
        selections: [new Range(0, 0, 0, 0)],
        visibleRanges: [new Range(0, 0, 10, 0)],
        options: { tabSize: 4, insertSpaces: true },
        edit: (cb) => { cb({ replace: () => {}, insert: () => {}, delete: () => {} }); return Promise.resolve(true); },
        setDecorations: () => {}
    };

    return {
        Position,
        Range,
        Selection,
        Location,
        RelativePattern,
        Uri,
        Disposable,
        EventEmitter,
        CancellationTokenSource,
        ThemeColor,
        ThemeIcon,
        CodeAction,
        TextEdit,
        WorkspaceEdit,
        SnippetString,
        Hover,
        Diagnostic,
        CodeLens,
        CompletionItem,
        StatusBarAlignment,
        DiagnosticSeverity,
        OverviewRulerLane,
        DecorationRangeBehavior,
        ExtensionMode,
        LanguageStatusSeverity,
        CodeActionKind,
        ViewColumn,
        EndOfLine,
        LogLevel,
        CompletionItemKind,
        SymbolKind,
        ProgressLocation,
        IndentAction,

        commands: {
            registerCommand: (command, callback) => {
                registeredCommands.set(command, callback);
                emitter('command/register', { command });
                return new Disposable(() => registeredCommands.delete(command));
            },
            executeCommand: (command, ...rest) => {
                const callback = registeredCommands.get(command);
                if (callback) {
                    try { return Promise.resolve(callback(...rest)); }
                    catch (err) { return Promise.reject(err); }
                }
                emitter('command/execute', { command, args: rest });
                return Promise.resolve();
            },
            getCommands: () => Promise.resolve(Array.from(registeredCommands.keys()))
        },

        window: {
            activeTextEditor: sampleEditor,
            visibleTextEditors: [sampleEditor],
            onDidChangeActiveTextEditor: new EventEmitter().event,
            onDidChangeTextEditorSelection: new EventEmitter().event,
            onDidChangeVisibleTextEditors: new EventEmitter().event,

            showInformationMessage: (message, ...items) => {
                emitter('window/info', { message });
                return Promise.resolve(items[0]);
            },
            showWarningMessage: (message, ...items) => {
                emitter('window/warn', { message });
                return Promise.resolve(items[0]);
            },
            showErrorMessage: (message, ...items) => {
                emitter('window/error', { message });
                return Promise.resolve(items[0]);
            },
            showQuickPick: (items, options) => {
                return Promise.resolve(Array.isArray(items) ? items[0] : undefined);
            },
            showInputBox: (options) => {
                return Promise.resolve(options && options.value ? options.value : '');
            },
            createOutputChannel: (name) => {
                return {
                    name,
                    append: (val) => emitter('window/output', { name, value: val }),
                    appendLine: (val) => emitter('window/output', { name, value: val + '\n' }),
                    clear: () => {},
                    show: () => {},
                    hide: () => {},
                    dispose: () => {}
                };
            },
            createStatusBarItem: (alignmentOrId, priorityOrAlignment, maybePriority) => {
                let alignment = StatusBarAlignment.Left;
                let priority = 0;
                let id = undefined;
                if (typeof alignmentOrId === 'string') {
                    id = alignmentOrId;
                    alignment = priorityOrAlignment || StatusBarAlignment.Left;
                    priority = maybePriority || 0;
                } else {
                    alignment = alignmentOrId || StatusBarAlignment.Left;
                    priority = priorityOrAlignment || 0;
                }
                return {
                    id,
                    alignment,
                    priority,
                    text: '',
                    tooltip: '',
                    command: '',
                    color: '',
                    show: () => {},
                    hide: () => {},
                    dispose: () => {}
                };
            },
            setStatusBarMessage: (text, hideAfterTimeout) => {
                return new Disposable(() => {});
            },
            withProgress: (options, task) => {
                const progress = { report: (val) => {} };
                return task(progress, new CancellationTokenSource().token);
            },
            createTerminal: (nameOrOptions) => {
                const name = typeof nameOrOptions === 'string' ? nameOrOptions : (nameOrOptions && nameOrOptions.name || 'Terminal');
                return {
                    name,
                    processId: Promise.resolve(1001),
                    sendText: (text) => emitter('terminal/input', { name, text }),
                    show: () => {},
                    hide: () => {},
                    dispose: () => {}
                };
            },
            createTextEditorDecorationType: (options) => ({ key: 'dec_' + Math.random(), dispose: () => {} })
        },

        workspace: {
            workspaceFolders: [{
                uri: Uri.file(process.cwd()),
                name: 'MicroCode Workspace',
                index: 0
            }],
            rootPath: process.cwd(),
            textDocuments: [sampleDoc],
            onDidOpenTextDocument: new EventEmitter().event,
            onDidCloseTextDocument: new EventEmitter().event,
            onDidChangeTextDocument: new EventEmitter().event,
            onDidSaveTextDocument: new EventEmitter().event,
            onWillSaveTextDocument: new EventEmitter().event,
            onDidChangeConfiguration: new EventEmitter().event,
            onDidChangeWorkspaceFolders: new EventEmitter().event,

            getConfiguration: (section, scope) => {
                return {
                    get: (key, defaultValue) => {
                        if (defaultValue !== undefined) return defaultValue;
                        const def = getConfigurationDefault(section, key);
                        if (def !== undefined) return def;
                        if (key && key.includes('exclude')) return {};
                        return defaultValue;
                    },
                    has: (key) => {
                        return getConfigurationDefault(section, key) !== undefined;
                    },
                    inspect: (key) => {
                        const def = getConfigurationDefault(section, key);
                        return { defaultValue: def, globalValue: def };
                    },
                    update: (key, value) => Promise.resolve()
                };
            },
            asRelativePath: (pathOrUri) => {
                const p = typeof pathOrUri === 'string' ? pathOrUri : pathOrUri.fsPath;
                return p.replace(process.cwd() + '/', '');
            },
            findFiles: (include, exclude, maxResults) => Promise.resolve([]),
            fs: {
                readFile: (uri) => Promise.resolve(Buffer.from('')),
                writeFile: (uri, content) => Promise.resolve(),
                stat: (uri) => Promise.resolve({ type: 1, ctime: Date.now(), mtime: Date.now(), size: 0 }),
                readDirectory: (uri) => Promise.resolve([])
            },
            openTextDocument: (optionsOrUri) => {
                const uri = typeof optionsOrUri === 'string' ? Uri.file(optionsOrUri) : (optionsOrUri && optionsOrUri.fsPath ? optionsOrUri : Uri.file('/workspace/file.js'));
                return Promise.resolve(Object.assign({}, sampleDoc, { uri, fileName: uri.fsPath }));
            },
            createFileSystemWatcher: () => ({
                onDidChange: new EventEmitter().event,
                onDidCreate: new EventEmitter().event,
                onDidDelete: new EventEmitter().event,
                dispose: () => {}
            })
        },

        languages: {
            registerCompletionItemProvider: () => new Disposable(() => {}),
            registerHoverProvider: () => new Disposable(() => {}),
            registerDefinitionProvider: () => new Disposable(() => {}),
            registerDocumentFormattingEditProvider: () => new Disposable(() => {}),
            registerDocumentRangeFormattingEditProvider: () => new Disposable(() => {}),
            registerCodeActionsProvider: () => new Disposable(() => {}),
            registerCodeLensProvider: () => new Disposable(() => {}),
            registerDocumentSymbolProvider: () => new Disposable(() => {}),
            registerWorkspaceSymbolProvider: () => new Disposable(() => {}),
            registerReferenceProvider: () => new Disposable(() => {}),
            registerRenameProvider: () => new Disposable(() => {}),
            registerSignatureHelpProvider: () => new Disposable(() => {}),
            registerColorProvider: () => new Disposable(() => {}),
            registerDocumentHighlightProvider: () => new Disposable(() => {}),
            registerFoldingRangeProvider: () => new Disposable(() => {}),
            registerSelectionRangeProvider: () => new Disposable(() => {}),
            registerCallHierarchyProvider: () => new Disposable(() => {}),
            registerTypeHierarchyProvider: () => new Disposable(() => {}),
            registerInlayHintsProvider: () => new Disposable(() => {}),
            registerInlineCompletionItemProvider: () => new Disposable(() => {}),
            createDiagnosticCollection: (name) => ({
                name: name || 'diagnostics',
                set: () => {},
                delete: () => {},
                clear: () => {},
                dispose: () => {}
            }),
            createLanguageStatusItem: (id, selector) => ({
                id,
                selector,
                text: '',
                detail: '',
                severity: LanguageStatusSeverity.Information,
                command: undefined,
                busy: false,
                dispose: () => {}
            }),
            getDiagnostics: () => [],
            setLanguageConfiguration: () => new Disposable(() => {})
        },

        extensions: {
            getExtension: (extensionId) => {
                try {
                    const fs = require('fs');
                    const path = require('path');
                    const extBase = path.join(process.env.HOME || '', 'Library/Application Support/MicroCode/Extensions');
                    if (fs.existsSync(extBase)) {
                        for (const f of fs.readdirSync(extBase)) {
                            if (f.toLowerCase() === extensionId.toLowerCase() || f.toLowerCase().endsWith('.' + extensionId.toLowerCase())) {
                                const p = path.join(extBase, f, 'package.json');
                                if (fs.existsSync(p)) {
                                    return {
                                        id: f,
                                        extensionPath: path.join(extBase, f),
                                        extensionUri: Uri.file(path.join(extBase, f)),
                                        isActive: true,
                                        packageJSON: JSON.parse(fs.readFileSync(p, 'utf8')),
                                        exports: {}
                                    };
                                }
                            }
                        }
                    }
                } catch (e) {}
                return undefined;
            },
            all: [],
            onDidChange: new EventEmitter().event
        },

        env: {
            appName: 'MicroCode',
            appRoot: process.cwd(),
            language: 'en',
            machineId: 'microcode-mac',
            sessionId: 'microcode-session',
            clipboard: {
                readText: () => Promise.resolve(''),
                writeText: () => Promise.resolve()
            },
            openExternal: (target) => Promise.resolve(true)
        }
    };
}

exports.createMicroCodeShim = createMicroCodeShim;
exports.microcodeShim = createMicroCodeShim((method, params) => {});
