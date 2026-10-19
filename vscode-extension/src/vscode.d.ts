declare module 'vscode' {
  export interface Disposable {
    dispose(): any;
  }

  export class EventEmitter<T> {
    readonly event: Event<T>;
    fire(data: T): void;
    dispose(): void;
  }

  export type Event<T> = (listener: (e: T) => any, thisArgs?: any, disposables?: Disposable[]) => Disposable;

  export class Uri {
    readonly scheme: string;
    readonly authority: string;
    readonly path: string;
    readonly query: string;
    readonly fragment: string;
    readonly fsPath: string;
    static file(path: string): Uri;
    static parse(value: string, strict?: boolean): Uri;
    static joinPath(base: Uri, ...pathSegments: string[]): Uri;
    toString(skipEncoding?: boolean): string;
  }

  export class Position {
    readonly line: number;
    readonly character: number;
    constructor(line: number, character: number);
  }

  export class Range {
    readonly start: Position;
    readonly end: Position;
    constructor(start: Position, end: Position);
    constructor(startLine: number, startCharacter: number, endLine: number, endCharacter: number);
  }

  export class Selection extends Range {
    readonly anchor: Position;
    readonly active: Position;
    readonly isEmpty: boolean;
    constructor(anchor: Position, active: Position);
    constructor(anchorLine: number, anchorCharacter: number, activeLine: number, activeCharacter: number);
  }

  export enum DiagnosticSeverity {
    Error = 0,
    Warning = 1,
    Information = 2,
    Hint = 3
  }

  export class Diagnostic {
    range: Range;
    message: string;
    severity: DiagnosticSeverity;
    source?: string;
    code?: string | number;
    constructor(range: Range, message: string, severity?: DiagnosticSeverity);
  }

  export interface DiagnosticCollection extends Disposable {
    readonly name: string;
    set(uri: Uri, diagnostics: readonly Diagnostic[] | undefined): void;
    delete(uri: Uri): void;
    clear(): void;
  }

  export interface Command {
    title: string;
    command: string;
    tooltip?: string;
    arguments?: any[];
  }

  export class CodeLens {
    range: Range;
    command?: Command;
    readonly isResolved: boolean;
    constructor(range: Range, command?: Command);
  }

  export interface CancellationToken {
    readonly isCancellationRequested: boolean;
    readonly onCancellationRequested: Event<any>;
  }

  export interface TextLine {
    readonly lineNumber: number;
    readonly text: string;
    readonly range: Range;
    readonly isEmptyOrWhitespace: boolean;
  }

  export interface TextDocument {
    readonly uri: Uri;
    readonly fileName: string;
    readonly languageId: string;
    readonly lineCount: number;
    getText(range?: Range): string;
    lineAt(line: number | Position): TextLine;
    save(): Thenable<boolean>;
  }

  export interface TextEditor {
    readonly document: TextDocument;
    selection: Selection;
    selections: readonly Selection[];
  }

  export interface OutputChannel extends Disposable {
    readonly name: string;
    append(value: string): void;
    appendLine(value: string): void;
    clear(): void;
    show(preserveFocus?: boolean): void;
    hide(): void;
  }

  export enum StatusBarAlignment {
    Left = 1,
    Right = 2
  }

  export interface StatusBarItem extends Disposable {
    text: string;
    tooltip?: string;
    color?: string;
    command?: string | Command;
    show(): void;
    hide(): void;
  }

  export enum ViewColumn {
    Active = -1,
    Beside = -2,
    One = 1,
    Two = 2,
    Three = 3
  }

  export interface WebviewOptions {
    readonly enableScripts?: boolean;
    readonly localResourceRoots?: readonly Uri[];
  }

  export interface Webview {
    options: WebviewOptions;
    html: string;
    readonly onDidReceiveMessage: Event<any>;
    postMessage(message: any): Thenable<boolean>;
    asWebviewUri(localResource: Uri): Uri;
    readonly cspSource: string;
  }

  export interface WebviewView {
    readonly webview: Webview;
    title?: string;
    description?: string;
    readonly onDidDispose: Event<void>;
  }

  export interface WebviewViewResolveContext<T = unknown> {
    readonly state: T | undefined;
  }

  export interface WebviewViewProvider {
    resolveWebviewView(
      webviewView: WebviewView,
      context: WebviewViewResolveContext,
      token: CancellationToken
    ): Thenable<void> | void;
  }

  export interface WebviewPanel extends Disposable {
    readonly viewType: string;
    title: string;
    readonly webview: Webview;
    readonly visible: boolean;
    readonly onDidDispose: Event<void>;
    reveal(viewColumn?: ViewColumn, preserveFocus?: boolean): void;
  }

  export interface WorkspaceFolder {
    readonly uri: Uri;
    readonly name: string;
    readonly index: number;
  }

  export interface WorkspaceConfiguration {
    get<T>(section: string): T | undefined;
    get<T>(section: string, defaultValue: T): T;
    update(section: string, value: any, configurationTarget?: boolean | number): Thenable<void>;
  }

  export interface CodeLensProvider<T extends CodeLens = CodeLens> {
    onDidChangeCodeLenses?: Event<void>;
    provideCodeLenses(document: TextDocument, token: CancellationToken): T[] | Thenable<T[]>;
  }

  export enum NotebookCellKind {
    Markup = 1,
    Code = 2
  }

  export class NotebookCellData {
    kind: NotebookCellKind;
    value: string;
    languageId: string;
    outputs?: NotebookCellOutput[];
    metadata?: { [key: string]: any };
    constructor(kind: NotebookCellKind, value: string, languageId: string);
  }

  export class NotebookData {
    cells: NotebookCellData[];
    metadata?: { [key: string]: any };
    constructor(cells: NotebookCellData[]);
  }

  export interface NotebookSerializer {
    deserializeNotebook(content: Uint8Array, token: CancellationToken): NotebookData | Thenable<NotebookData>;
    serializeNotebook(data: NotebookData, token: CancellationToken): Uint8Array | Thenable<Uint8Array>;
  }

  export class NotebookCellOutputItem {
    readonly mime: string;
    readonly data: Uint8Array;
    static text(value: string, mime?: string): NotebookCellOutputItem;
    static json(value: any, mime?: string): NotebookCellOutputItem;
    static error(value: Error | { name: string; message: string; stack?: string }): NotebookCellOutputItem;
    constructor(data: Uint8Array, mime: string);
  }

  export class NotebookCellOutput {
    items: NotebookCellOutputItem[];
    metadata?: { [key: string]: any };
    constructor(items: NotebookCellOutputItem[], metadata?: { [key: string]: any });
  }

  export interface NotebookCell {
    readonly index: number;
    readonly notebook: NotebookDocument;
    readonly kind: NotebookCellKind;
    readonly document: TextDocument;
  }

  export interface NotebookDocument {
    readonly uri: Uri;
    readonly notebookType: string;
    readonly cellCount: number;
    cellAt(index: number): NotebookCell;
    getCells(): NotebookCell[];
  }

  export interface NotebookCellExecution {
    readonly cell: NotebookCell;
    readonly token: CancellationToken;
    executionOrder: number | undefined;
    start(startTime?: number): void;
    end(success: boolean | undefined, endTime?: number): void;
    clearOutput(cell?: NotebookCell): Thenable<void>;
    replaceOutput(out: NotebookCellOutput | readonly NotebookCellOutput[], cell?: NotebookCell): Thenable<void>;
    appendOutput(out: NotebookCellOutput | readonly NotebookCellOutput[], cell?: NotebookCell): Thenable<void>;
  }

  export interface NotebookController extends Disposable {
    readonly id: string;
    readonly notebookType: string;
    supportedLanguages?: string[];
    label: string;
    description?: string;
    detail?: string;
    supportsExecutionOrder?: boolean;
    executeHandler: (
      cells: NotebookCell[],
      notebook: NotebookDocument,
      controller: NotebookController
    ) => void | Thenable<void>;
    createNotebookCellExecution(cell: NotebookCell): NotebookCellExecution;
  }

  export interface ExtensionContext {
    readonly subscriptions: Disposable[];
    readonly extensionPath: string;
    readonly extensionUri: Uri;
    readonly globalStorageUri?: Uri;
  }

  export namespace commands {
    export function registerCommand(command: string, callback: (...args: any[]) => any, thisArg?: any): Disposable;
    export function executeCommand<T = unknown>(command: string, ...rest: any[]): Thenable<T>;
  }

  export namespace window {
    export const activeTextEditor: TextEditor | undefined;
    export function showInformationMessage(message: string, ...items: string[]): Thenable<string | undefined>;
    export function showWarningMessage(message: string, ...items: string[]): Thenable<string | undefined>;
    export function showErrorMessage(message: string, ...items: string[]): Thenable<string | undefined>;
    export function createOutputChannel(name: string): OutputChannel;
    export function createStatusBarItem(alignment?: StatusBarAlignment, priority?: number): StatusBarItem;
    export function registerWebviewViewProvider(viewId: string, provider: WebviewViewProvider, options?: any): Disposable;
    export function createWebviewPanel(
      viewType: string,
      title: string,
      showOptions: ViewColumn | { viewColumn: ViewColumn; preserveFocus?: boolean },
      options?: WebviewOptions & { retainContextWhenHidden?: boolean }
    ): WebviewPanel;
    export function showTextDocument(document: TextDocument | Uri, column?: ViewColumn): Thenable<TextEditor>;
    export function showNotebookDocument(document: NotebookDocument, options?: any): Thenable<any>;
  }

  export namespace workspace {
    export const workspaceFolders: readonly WorkspaceFolder[] | undefined;
    export const onDidSaveTextDocument: Event<TextDocument>;
    export const onDidOpenTextDocument: Event<TextDocument>;
    export const onDidChangeTextDocument: Event<{ document: TextDocument }>;
    export function getConfiguration(section?: string): WorkspaceConfiguration;
    export function openTextDocument(uriOrOptions?: Uri | string | { language?: string; content?: string }): Thenable<TextDocument>;
    export function openNotebookDocument(notebookType: string, content?: NotebookData): Thenable<NotebookDocument>;
    export function registerNotebookSerializer(notebookType: string, serializer: NotebookSerializer, options?: any): Disposable;
  }

  export namespace languages {
    export function createDiagnosticCollection(name?: string): DiagnosticCollection;
    export function registerCodeLensProvider(
      selector: string | { language?: string; scheme?: string; pattern?: string } | Array<any>,
      provider: CodeLensProvider
    ): Disposable;
  }

  export namespace notebooks {
    export function createNotebookController(
      id: string,
      notebookType: string,
      label: string,
      handler?: (cells: NotebookCell[], notebook: NotebookDocument, controller: NotebookController) => void | Thenable<void>
    ): NotebookController;
  }

  export namespace lm {
    export function registerMcpServerDefinitionProvider(id: string, provider: any): Disposable;
  }
}
