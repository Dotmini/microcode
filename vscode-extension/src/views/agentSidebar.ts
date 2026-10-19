import * as vscode from 'vscode';
import * as path from 'path';
import { BackendManager } from '../backendManager';
import { WorkstationEngine } from './workstationEngine';

export class MicroCodeAgentSidebarProvider implements vscode.WebviewViewProvider {
  public static readonly viewType = 'microcode.agentSidebar';
  private view?: vscode.WebviewView;
  private fullPanel?: vscode.WebviewPanel;

  constructor(
    private readonly context: vscode.ExtensionContext,
    private readonly backendManager: BackendManager,
    private readonly engine: WorkstationEngine
  ) {}

  public resolveWebviewView(
    webviewView: vscode.WebviewView,
    _context: vscode.WebviewViewResolveContext,
    _token: vscode.CancellationToken
  ): void {
    this.view = webviewView;

    webviewView.webview.options = {
      enableScripts: true,
      localResourceRoots: [this.context.extensionUri]
    };

    webviewView.webview.html = this.getHtml(webviewView.webview, false);
    this.attachMessageHandler(webviewView.webview);
  }

  public openFullWorkstationPanel(): void {
    if (this.fullPanel) {
      this.fullPanel.reveal(vscode.ViewColumn.Beside);
      this.broadcastState();
      return;
    }

    this.fullPanel = vscode.window.createWebviewPanel(
      'microcode.fullWorkstation',
      'MicroCode Workstation',
      vscode.ViewColumn.Beside,
      {
        enableScripts: true,
        retainContextWhenHidden: true,
        localResourceRoots: [this.context.extensionUri]
      }
    );

    this.fullPanel.webview.html = this.getHtml(this.fullPanel.webview, true);
    this.attachMessageHandler(this.fullPanel.webview);

    this.fullPanel.onDidDispose(() => {
      this.fullPanel = undefined;
    });
  }

  private broadcastMessage(payload: unknown): void {
    if (this.view) {
      void this.view.webview.postMessage(payload);
    }
    if (this.fullPanel) {
      void this.fullPanel.webview.postMessage(payload);
    }
  }

  public broadcastState(): void {
    this.broadcastMessage({
      type: 'stateSync',
      state: this.engine.getFullState()
    });
  }

  private attachMessageHandler(webview: vscode.Webview): void {
    webview.onDidReceiveMessage(async (msg) => {
      switch (msg.type) {
        case 'init': {
          this.broadcastState();
          break;
        }
        case 'openFullWorkstation': {
          this.openFullWorkstationPanel();
          break;
        }
        case 'newSession': {
          this.engine.createNewSession();
          this.broadcastState();
          break;
        }
        case 'selectSession': {
          this.engine.selectSession(String(msg.sessionId ?? ''));
          this.broadcastState();
          break;
        }
        case 'deleteSession': {
          this.engine.deleteSession(String(msg.sessionId ?? ''));
          this.broadcastState();
          break;
        }
        case 'setPermissionMode': {
          this.engine.setPermissionMode(msg.mode === 'fullAuto' ? 'fullAuto' : 'review');
          this.broadcastState();
          break;
        }
        case 'sendChat': {
          const prompt = String(msg.prompt ?? '').trim();
          if (!prompt) {
            return;
          }
          const model = String(msg.model ?? 'omni-o1x-pro');
          const subAgent = String(msg.subAgent ?? 'coder');
          const includeEditor = Boolean(msg.includeEditor);

          let editorContext:
            | { fileName: string; languageId: string; code: string; filePath: string }
            | undefined;
          if (includeEditor && vscode.window.activeTextEditor) {
            const ed = vscode.window.activeTextEditor;
            const sel = ed.selection;
            const text =
              !sel.isEmpty ? ed.document.getText(sel) : ed.document.getText();
            editorContext = {
              fileName: path.basename(ed.document.fileName),
              filePath: ed.document.fileName,
              languageId: ed.document.languageId,
              code: text.slice(0, 6000)
            };
          }

          this.broadcastMessage({ type: 'chatBusy', busy: true });
          await this.engine.sendChatMessage(prompt, model, subAgent, editorContext);
          this.broadcastMessage({ type: 'chatBusy', busy: false });
          this.broadcastState();
          break;
        }
        case 'generatePlan': {
          const goal = String(msg.goal ?? '').trim();
          this.broadcastMessage({ type: 'chatBusy', busy: true });
          await this.engine.generateStructuredPlan(
            goal || 'Architect and verify workspace implementation plan'
          );
          this.broadcastMessage({ type: 'chatBusy', busy: false });
          this.broadcastState();
          break;
        }
        case 'approvePlan': {
          await this.engine.approvePlan();
          this.broadcastState();
          break;
        }
        case 'rejectPlan': {
          this.engine.rejectPlan();
          this.broadcastState();
          break;
        }
        case 'togglePlanStep': {
          this.engine.togglePlanStep(String(msg.stepId ?? ''));
          this.broadcastState();
          break;
        }
        case 'savePlanMarkdown': {
          this.engine.saveRawPlanMarkdown(String(msg.markdown ?? ''));
          this.broadcastState();
          break;
        }
        case 'resolveApproval': {
          await this.engine.resolveToolApproval(
            msg.decision as 'approve' | 'always' | 'reject'
          );
          this.broadcastState();
          break;
        }
        case 'toggleTaskLine': {
          this.engine.toggleTaskChecklistLine(Number(msg.lineIndex ?? 0));
          this.broadcastState();
          break;
        }
        case 'addTaskItem': {
          const text = String(msg.text ?? '').trim();
          if (text) {
            const current = this.engine.readTaskMarkdown();
            const updated = current.trimEnd() + `\n- [ ] ${text}\n`;
            this.engine.saveTaskMarkdown(updated);
            this.broadcastState();
          }
          break;
        }
        case 'saveTaskMarkdown': {
          this.engine.saveTaskMarkdown(String(msg.markdown ?? ''));
          this.broadcastState();
          break;
        }
        case 'saveAgentsSpec': {
          this.engine.saveAgentsSpec(String(msg.markdown ?? ''));
          this.broadcastState();
          break;
        }
        case 'saveWalkthrough': {
          this.engine.saveWalkthroughMarkdown(String(msg.markdown ?? ''));
          this.broadcastState();
          break;
        }
        case 'openFileLink': {
          const relOrAbs = String(msg.filePath ?? '').trim();
          if (!relOrAbs) {
            return;
          }
          const fullPath = path.isAbsolute(relOrAbs)
            ? relOrAbs
            : path.join(this.engine.getWorkspaceRoot(), relOrAbs);
          try {
            const doc = await vscode.workspace.openTextDocument(fullPath);
            await vscode.window.showTextDocument(doc, vscode.ViewColumn.One);
          } catch {
            void vscode.window.showWarningMessage(`File not found: ${fullPath}`);
          }
          break;
        }
        case 'createCell': {
          this.engine.createCell(
            String(msg.title ?? 'Untitled Cell'),
            String(msg.language ?? 'ardium'),
            String(
              msg.code ??
                'fn main() {\n    print("MicroCode Sovereign Cell Ready");\n}\n'
            )
          );
          this.broadcastState();
          break;
        }
        case 'saveCell': {
          this.engine.updateCell(
            String(msg.cellId ?? ''),
            String(msg.code ?? ''),
            msg.title ? String(msg.title) : undefined,
            msg.language ? String(msg.language) : undefined
          );
          this.broadcastState();
          break;
        }
        case 'runCell': {
          const cellId = String(msg.cellId ?? '');
          if (msg.code !== undefined) {
            this.engine.updateCell(
              cellId,
              String(msg.code),
              msg.title ? String(msg.title) : undefined,
              msg.language ? String(msg.language) : undefined
            );
          }
          this.broadcastMessage({ type: 'cellRunning', cellId });
          await this.engine.runCellById(cellId);
          this.broadcastState();
          break;
        }
        case 'deleteCell': {
          this.engine.deleteCell(String(msg.cellId ?? ''));
          this.broadcastState();
          break;
        }
        case 'openInPlayground': {
          await vscode.commands.executeCommand(
            'microcode.openPlayground',
            String(msg.code ?? ''),
            String(msg.language ?? 'ardium')
          );
          break;
        }
        case 'refreshDevices': {
          const devices = await this.engine.listDevices();
          this.broadcastMessage({ type: 'devicesList', devices });
          break;
        }
        case 'bootDevice': {
          await this.engine.bootDevice(
            String(msg.deviceId ?? ''),
            msg.platform === 'android' ? 'android' : 'ios'
          );
          const devices = await this.engine.listDevices();
          this.broadcastMessage({ type: 'devicesList', devices });
          this.broadcastState();
          break;
        }
        case 'captureDeviceScreen': {
          const res = await this.engine.captureDeviceScreenshot(
            String(msg.deviceId ?? ''),
            msg.platform === 'android' ? 'android' : 'ios'
          );
          this.broadcastMessage({
            type: 'deviceScreenshot',
            deviceId: msg.deviceId,
            base64Png: res.base64Png,
            error: res.error
          });
          this.broadcastState();
          break;
        }
        case 'sendHttpRequest': {
          let headersObj: Record<string, string> = {};
          try {
            headersObj = JSON.parse(String(msg.headersJson || '{}'));
          } catch {
            headersObj = {};
          }
          const res = await this.engine.executeHttpRequest(
            String(msg.method ?? 'GET'),
            String(msg.url ?? ''),
            headersObj,
            String(msg.body ?? '')
          );
          this.broadcastMessage({ type: 'httpResponse', response: res });
          this.broadcastState();
          break;
        }
        case 'runSqlQuery': {
          const res = await this.engine.executeSqliteQuery(
            String(msg.dbPath ?? '.microcode/workstation.sqlite'),
            String(msg.sql ?? 'SELECT sqlite_version() AS version;')
          );
          this.broadcastMessage({ type: 'sqlResponse', response: res });
          this.broadcastState();
          break;
        }
        case 'execCommand': {
          if (msg.command) {
            await vscode.commands.executeCommand(String(msg.command));
            this.broadcastState();
          }
          break;
        }
      }
    });
  }

  private getHtml(_webview: vscode.Webview, isFullPanel: boolean): string {
    return /* html */ `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <style>
    :root {
      --mc-bg: var(--vscode-sideBar-background, #141416);
      --mc-surface-0: rgba(255, 255, 255, 0.025);
      --mc-surface-1: rgba(255, 255, 255, 0.045);
      --mc-surface-2: rgba(255, 255, 255, 0.075);
      --mc-surface-3: rgba(255, 255, 255, 0.11);
      --mc-border: rgba(255, 255, 255, 0.08);
      --mc-border-strong: rgba(255, 255, 255, 0.15);
      --mc-text: var(--vscode-foreground, #e5e5e7);
      --mc-text-secondary: rgba(235, 235, 245, 0.62);
      --mc-text-muted: rgba(235, 235, 245, 0.38);
      --mc-accent: #0a84ff;
      --mc-accent-soft: rgba(10, 132, 255, 0.14);
      --mc-green: #30d158;
      --mc-green-soft: rgba(48, 209, 88, 0.14);
      --mc-orange: #ff9f0a;
      --mc-orange-soft: rgba(255, 159, 10, 0.14);
      --mc-red: #ff453a;
      --mc-red-soft: rgba(255, 69, 58, 0.14);
      --mc-purple: #bf5af2;
      --mc-purple-soft: rgba(191, 90, 242, 0.14);
      --mc-font-sans: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Inter", system-ui, sans-serif;
      --mc-font-mono: "SF Mono", "JetBrains Mono", Menlo, Monaco, Consolas, monospace;
    }

    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }

    body {
      font-family: var(--mc-font-sans);
      font-size: 12px;
      line-height: 1.45;
      color: var(--mc-text);
      background: var(--mc-bg);
      height: 100vh;
      display: flex;
      flex-direction: column;
      overflow: hidden;
      -webkit-font-smoothing: antialiased;
      user-select: none;
    }

    /* ── Top Bar (36px exact match to MicroCode AIAgentView.swift) ── */
    .mc-topbar {
      min-height: 36px;
      padding: 4px 8px;
      display: flex;
      align-items: center;
      gap: 6px;
      border-bottom: 1px solid var(--mc-border);
      background: rgba(0, 0, 0, 0.16);
      flex-wrap: wrap;
      flex-shrink: 0;
    }

    .mc-icon-btn {
      width: 24px;
      height: 24px;
      border-radius: 5px;
      border: 1px solid transparent;
      background: transparent;
      color: var(--mc-text-secondary);
      display: inline-flex;
      align-items: center;
      justify-content: center;
      cursor: pointer;
      transition: all 0.12s ease;
      flex-shrink: 0;
    }
    .mc-icon-btn:hover {
      background: var(--mc-surface-2);
      color: var(--mc-text);
    }
    .mc-icon-btn.active {
      background: var(--mc-surface-3);
      color: var(--mc-text);
      border-color: var(--mc-border-strong);
    }
    .mc-icon-btn svg {
      width: 13px;
      height: 13px;
      fill: currentColor;
    }

    .mc-vdivider {
      width: 1px;
      height: 14px;
      background: var(--mc-border);
      flex-shrink: 0;
    }

    /* Segmented Mode Tabs */
    .mc-mode-tabs {
      display: inline-flex;
      align-items: center;
      background: rgba(0, 0, 0, 0.25);
      border: 1px solid var(--mc-border);
      border-radius: 5px;
      padding: 1px;
      gap: 1px;
      overflow-x: auto;
      max-width: 100%;
    }
    .mc-mode-tab {
      border: none;
      background: transparent;
      color: var(--mc-text-secondary);
      font-family: var(--mc-font-sans);
      font-size: 10.5px;
      font-weight: 500;
      padding: 3px 7px;
      border-radius: 4px;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      gap: 4px;
      white-space: nowrap;
      transition: all 0.12s ease;
    }
    .mc-mode-tab:hover {
      color: var(--mc-text);
    }
    .mc-mode-tab.active {
      background: var(--mc-surface-3);
      color: var(--mc-text);
      font-weight: 600;
      box-shadow: 0 1px 2px rgba(0,0,0,0.25);
    }
    .mc-mode-tab svg {
      width: 11px;
      height: 11px;
      fill: currentColor;
      opacity: 0.85;
    }

    .mc-dot {
      width: 5px;
      height: 5px;
      border-radius: 50%;
      display: inline-block;
    }
    .mc-dot.green { background: var(--mc-green); }
    .mc-dot.orange { background: var(--mc-orange); }
    .mc-dot.red { background: var(--mc-red); }
    .mc-dot.blue { background: var(--mc-accent); }

    /* Sub-bar for Model, SubAgent, Permission Mode & Status */
    .mc-subbar {
      height: 28px;
      padding: 0 8px;
      display: flex;
      align-items: center;
      gap: 6px;
      border-bottom: 1px solid var(--mc-border);
      background: var(--mc-surface-0);
      flex-shrink: 0;
      overflow-x: auto;
    }

    .mc-pill-select {
      appearance: none;
      background: var(--mc-surface-1);
      color: var(--mc-text);
      border: 1px solid var(--mc-border);
      border-radius: 4px;
      padding: 2px 6px;
      font-family: var(--mc-font-sans);
      font-size: 10px;
      font-weight: 500;
      cursor: pointer;
      outline: none;
    }
    .mc-pill-select:hover {
      border-color: var(--mc-border-strong);
      background: var(--mc-surface-2);
    }

    .mc-status-indicator {
      margin-left: auto;
      display: inline-flex;
      align-items: center;
      gap: 5px;
      font-size: 10px;
      color: var(--mc-text-secondary);
      white-space: nowrap;
    }

    /* ── Main Split Container (History Drawer + Active View) ── */
    .mc-workspace-body {
      flex: 1;
      display: flex;
      min-height: 0;
      overflow: hidden;
    }

    /* History Drawer (170px exact match to AIAgentView.swift historySidebarView) */
    .mc-history-drawer {
      width: 175px;
      border-right: 1px solid var(--mc-border);
      background: rgba(0, 0, 0, 0.18);
      display: none;
      flex-direction: column;
      flex-shrink: 0;
    }
    .mc-history-drawer.open {
      display: flex;
    }
    .mc-history-header {
      padding: 7px 10px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      border-bottom: 1px solid var(--mc-border);
      font-size: 10px;
      font-weight: 700;
      letter-spacing: 0.05em;
      color: var(--mc-text-muted);
    }
    .mc-history-list {
      flex: 1;
      overflow-y: auto;
      padding: 4px;
      display: flex;
      flex-direction: column;
      gap: 2px;
    }
    .mc-history-item {
      padding: 6px 8px;
      border-radius: 5px;
      cursor: pointer;
      display: flex;
      flex-direction: column;
      gap: 3px;
      border: 1px solid transparent;
      position: relative;
    }
    .mc-history-item:hover {
      background: var(--mc-surface-1);
    }
    .mc-history-item.active {
      background: var(--mc-surface-2);
      border-color: var(--mc-border);
    }
    .mc-history-item-title {
      font-size: 11px;
      font-weight: 500;
      color: var(--mc-text);
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      padding-right: 16px;
    }
    .mc-history-item.active .mc-history-item-title {
      font-weight: 600;
    }
    .mc-history-item-meta {
      display: flex;
      align-items: center;
      gap: 4px;
      font-size: 9px;
      color: var(--mc-text-muted);
    }
    .mc-project-badge {
      background: var(--mc-accent-soft);
      color: var(--mc-accent);
      padding: 0 4px;
      border-radius: 3px;
      font-weight: 600;
      max-width: 85px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .mc-history-del {
      position: absolute;
      top: 6px;
      right: 6px;
      background: transparent;
      border: none;
      color: var(--mc-text-muted);
      cursor: pointer;
      opacity: 0;
      font-size: 10px;
    }
    .mc-history-item:hover .mc-history-del {
      opacity: 1;
    }
    .mc-history-del:hover {
      color: var(--mc-red);
    }

    /* ── Primary Content Column ── */
    .mc-main-pane {
      flex: 1;
      display: flex;
      flex-direction: column;
      min-width: 0;
      min-height: 0;
      overflow: hidden;
    }

    .mc-tab-view {
      display: none;
      flex: 1;
      flex-direction: column;
      min-height: 0;
      overflow: hidden;
    }
    .mc-tab-view.active {
      display: flex;
    }

    /* ── CHAT VIEW ── */
    .mc-chat-scroll {
      flex: 1;
      overflow-y: auto;
      padding: 10px 12px;
      display: flex;
      flex-direction: column;
      gap: 10px;
      user-select: text;
    }

    .mc-msg {
      display: flex;
      flex-direction: column;
      gap: 4px;
      padding: 8px 10px;
      border-radius: 6px;
      border: 1px solid var(--mc-border);
      background: var(--mc-surface-0);
    }
    .mc-msg.user {
      background: var(--mc-accent-soft);
      border-color: rgba(10, 132, 255, 0.28);
      align-self: flex-end;
      width: 94%;
    }
    .mc-msg.assistant {
      background: var(--mc-surface-1);
      width: 100%;
    }
    .mc-msg.system {
      background: rgba(255, 159, 10, 0.07);
      border-color: rgba(255, 159, 10, 0.22);
      font-size: 11px;
    }

    .mc-msg-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      font-size: 10px;
      color: var(--mc-text-muted);
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }
    .mc-msg-badges {
      display: inline-flex;
      gap: 4px;
      align-items: center;
    }
    .mc-badge {
      padding: 1px 5px;
      border-radius: 3px;
      font-size: 9px;
      font-weight: 600;
      background: var(--mc-surface-2);
      color: var(--mc-text-secondary);
      font-family: var(--mc-font-mono);
    }

    .mc-msg-body {
      font-size: 12px;
      line-height: 1.5;
      color: var(--mc-text);
      white-space: pre-wrap;
      word-break: break-word;
    }
    .mc-msg-body code {
      font-family: var(--mc-font-mono);
      font-size: 11px;
      background: rgba(0, 0, 0, 0.3);
      padding: 1px 4px;
      border-radius: 3px;
    }
    .mc-msg-body pre {
      font-family: var(--mc-font-mono);
      font-size: 11px;
      background: rgba(0, 0, 0, 0.38);
      border: 1px solid var(--mc-border);
      border-radius: 5px;
      padding: 8px;
      overflow-x: auto;
      margin: 6px 0;
    }

    .mc-tool-pills {
      display: flex;
      flex-wrap: wrap;
      gap: 4px;
      margin-top: 4px;
    }
    .mc-tool-pill {
      display: inline-flex;
      align-items: center;
      gap: 5px;
      padding: 2px 7px;
      border-radius: 4px;
      background: rgba(0, 0, 0, 0.28);
      border: 1px solid var(--mc-border);
      font-family: var(--mc-font-mono);
      font-size: 10px;
      color: var(--mc-text-secondary);
    }

    /* ── ToolApprovalView Card (Exact match to ToolApprovalView.swift) ── */
    .mc-approval-card {
      margin: 0 10px 8px 10px;
      padding: 10px 12px;
      border-radius: 8px;
      background: rgba(25, 25, 28, 0.96);
      border: 1px solid rgba(255, 159, 10, 0.45);
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.35);
      display: none;
      flex-direction: column;
      gap: 8px;
      flex-shrink: 0;
    }
    .mc-approval-card.visible {
      display: flex;
    }
    .mc-approval-top {
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .mc-approval-icon {
      width: 26px;
      height: 26px;
      border-radius: 6px;
      background: var(--mc-orange-soft);
      color: var(--mc-orange);
      display: flex;
      align-items: center;
      justify-content: center;
      flex-shrink: 0;
    }
    .mc-approval-title-group {
      flex: 1;
      min-width: 0;
    }
    .mc-approval-label {
      font-size: 10px;
      font-weight: 600;
      color: var(--mc-text-secondary);
    }
    .mc-approval-toolname {
      font-family: var(--mc-font-mono);
      font-size: 12px;
      font-weight: 700;
      color: var(--mc-text);
    }
    .mc-risk-badge {
      font-size: 9.5px;
      font-weight: 600;
      padding: 2px 6px;
      border-radius: 4px;
      background: var(--mc-orange-soft);
      color: var(--mc-orange);
      text-transform: capitalize;
    }
    .mc-approval-desc {
      font-size: 11px;
      color: var(--mc-text-secondary);
    }
    .mc-approval-args {
      background: rgba(0, 0, 0, 0.35);
      border: 1px solid var(--mc-border);
      border-radius: 5px;
      padding: 6px 8px;
      font-family: var(--mc-font-mono);
      font-size: 10px;
      max-height: 110px;
      overflow-y: auto;
      user-select: text;
    }
    .mc-approval-actions {
      display: flex;
      align-items: center;
      justify-content: flex-end;
      gap: 6px;
    }

    /* ── Composer Footer ── */
    .mc-composer {
      padding: 8px 10px;
      border-top: 1px solid var(--mc-border);
      background: rgba(0, 0, 0, 0.14);
      display: flex;
      flex-direction: column;
      gap: 6px;
      flex-shrink: 0;
    }
    .mc-composer-input {
      width: 100%;
      min-height: 54px;
      max-height: 140px;
      resize: vertical;
      background: rgba(0, 0, 0, 0.28);
      color: var(--mc-text);
      border: 1px solid var(--mc-border-strong);
      border-radius: 6px;
      padding: 7px 9px;
      font-family: var(--mc-font-sans);
      font-size: 12px;
      outline: none;
    }
    .mc-composer-input:focus {
      border-color: var(--mc-accent);
    }
    .mc-composer-bar {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 6px;
    }
    .mc-composer-left {
      display: flex;
      align-items: center;
      gap: 6px;
      font-size: 10.5px;
      color: var(--mc-text-secondary);
    }

    /* Buttons */
    .mc-btn {
      border: 1px solid var(--mc-border-strong);
      background: var(--mc-surface-2);
      color: var(--mc-text);
      font-family: var(--mc-font-sans);
      font-size: 11px;
      font-weight: 500;
      padding: 4px 10px;
      border-radius: 5px;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      gap: 5px;
      transition: all 0.12s ease;
    }
    .mc-btn:hover {
      background: var(--mc-surface-3);
    }
    .mc-btn.primary {
      background: var(--mc-accent);
      border-color: var(--mc-accent);
      color: #ffffff;
      font-weight: 600;
    }
    .mc-btn.primary:hover {
      filter: brightness(1.08);
    }
    .mc-btn.success {
      background: var(--mc-green);
      border-color: var(--mc-green);
      color: #09140c;
      font-weight: 600;
    }
    .mc-btn.danger {
      background: var(--mc-red-soft);
      border-color: rgba(255, 69, 58, 0.35);
      color: var(--mc-red);
    }
    .mc-btn svg {
      width: 11px;
      height: 11px;
      fill: currentColor;
    }

    /* ── PLAN VIEW (Exact match to planStructuredView in AIAgentView.swift) ── */
    .mc-plan-header {
      padding: 7px 12px;
      border-bottom: 1px solid var(--mc-border);
      background: var(--mc-surface-0);
      display: flex;
      align-items: center;
      gap: 8px;
      flex-wrap: wrap;
      flex-shrink: 0;
    }
    .mc-plan-scroll {
      flex: 1;
      overflow-y: auto;
      padding: 12px;
      display: flex;
      flex-direction: column;
      gap: 12px;
      user-select: text;
    }
    .mc-card {
      padding: 10px 12px;
      border-radius: 6px;
      background: var(--mc-surface-1);
      border: 1px solid var(--mc-border);
      display: flex;
      flex-direction: column;
      gap: 8px;
    }
    .mc-card-title {
      font-size: 12px;
      font-weight: 600;
      color: var(--mc-text);
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .mc-step-row {
      display: flex;
      align-items: flex-start;
      gap: 8px;
      padding: 5px 6px;
      border-radius: 5px;
      cursor: pointer;
    }
    .mc-step-row:hover {
      background: var(--mc-surface-1);
    }
    .mc-step-badge {
      font-family: var(--mc-font-mono);
      font-size: 9px;
      font-weight: 700;
      padding: 1px 5px;
      border-radius: 3px;
      flex-shrink: 0;
      margin-top: 1px;
    }
    .mc-step-badge.NEW { background: var(--mc-green-soft); color: var(--mc-green); }
    .mc-step-badge.MODIFY { background: var(--mc-accent-soft); color: var(--mc-accent); }
    .mc-step-badge.DELETE { background: var(--mc-red-soft); color: var(--mc-red); }
    .mc-step-badge.VERIFY { background: var(--mc-purple-soft); color: var(--mc-purple); }

    .mc-file-link {
      font-family: var(--mc-font-mono);
      font-size: 10px;
      color: var(--mc-accent);
      background: var(--mc-accent-soft);
      padding: 1px 6px;
      border-radius: 3px;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      gap: 4px;
      width: fit-content;
      border: none;
    }
    .mc-file-link:hover {
      text-decoration: underline;
    }

    /* ── TASK / SPEC / WALKTHROUGH / AUDIT VIEW ── */
    .mc-subtab-bar {
      padding: 6px 12px;
      border-bottom: 1px solid var(--mc-border);
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 6px;
      background: var(--mc-surface-0);
      flex-shrink: 0;
    }
    .mc-check-row {
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 6px 8px;
      border-radius: 5px;
      border: 1px solid var(--mc-border);
      background: var(--mc-surface-0);
      cursor: pointer;
    }
    .mc-check-row:hover {
      background: var(--mc-surface-1);
    }
    .mc-check-row.done span {
      text-decoration: line-through;
      color: var(--mc-text-muted);
    }

    .mc-editor-area {
      flex: 1;
      width: 100%;
      background: rgba(0, 0, 0, 0.25);
      color: var(--mc-text);
      border: 1px solid var(--mc-border);
      border-radius: 6px;
      padding: 10px;
      font-family: var(--mc-font-mono);
      font-size: 11.5px;
      line-height: 1.5;
      resize: none;
      outline: none;
    }

    /* ── CELLS VIEW ── */
    .mc-cell-card {
      border: 1px solid var(--mc-border);
      border-radius: 6px;
      background: var(--mc-surface-0);
      overflow: hidden;
      display: flex;
      flex-direction: column;
    }
    .mc-cell-header {
      padding: 6px 10px;
      background: var(--mc-surface-1);
      border-bottom: 1px solid var(--mc-border);
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 6px;
    }
    .mc-cell-code {
      width: 100%;
      min-height: 78px;
      background: rgba(0, 0, 0, 0.3);
      color: var(--mc-text);
      border: none;
      padding: 8px 10px;
      font-family: var(--mc-font-mono);
      font-size: 11px;
      line-height: 1.45;
      resize: vertical;
      outline: none;
    }
    .mc-cell-output {
      padding: 7px 10px;
      border-top: 1px solid var(--mc-border);
      background: rgba(0, 0, 0, 0.45);
      font-family: var(--mc-font-mono);
      font-size: 10.5px;
      color: #d1d5db;
      white-space: pre-wrap;
      max-height: 140px;
      overflow-y: auto;
      user-select: text;
    }

    /* ── DEVICES DOCK VIEW ── */
    .mc-device-row {
      padding: 8px 10px;
      border-radius: 6px;
      border: 1px solid var(--mc-border);
      background: var(--mc-surface-1);
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
    }
    .mc-device-screen {
      margin-top: 8px;
      border: 1px solid var(--mc-border-strong);
      border-radius: 10px;
      background: #000;
      padding: 8px;
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 6px;
    }
    .mc-device-screen img {
      max-width: 100%;
      max-height: 340px;
      border-radius: 6px;
      object-fit: contain;
    }

    /* ── INPUTS & TABLES ── */
    .mc-input {
      background: rgba(0, 0, 0, 0.28);
      color: var(--mc-text);
      border: 1px solid var(--mc-border-strong);
      border-radius: 5px;
      padding: 5px 8px;
      font-family: var(--mc-font-sans);
      font-size: 11px;
      outline: none;
    }
    .mc-input.mono {
      font-family: var(--mc-font-mono);
    }
    .mc-input:focus {
      border-color: var(--mc-accent);
    }

    .mc-audit-table {
      width: 100%;
      border-collapse: collapse;
      font-size: 10.5px;
    }
    .mc-audit-table th, .mc-audit-table td {
      text-align: left;
      padding: 5px 6px;
      border-bottom: 1px solid var(--mc-border);
    }
    .mc-audit-table th {
      color: var(--mc-text-muted);
      font-weight: 600;
      text-transform: uppercase;
      font-size: 9.5px;
    }
  </style>
</head>
<body>

  <!-- 1. Official MicroCode 36px Top Bar -->
  <div class="mc-topbar">
    <button class="mc-icon-btn" id="btnToggleHistory" title="Chat History">
      <svg viewBox="0 0 16 16"><path d="M8 1a7 7 0 1 0 7 7h-1.5A5.5 5.5 0 1 1 8 2.5V5l3.2-2.4L8 .2V1zm-.5 3.5v4l3 1.8.75-1.23-2.25-1.32V4.5H7.5z"/></svg>
    </button>
    <button class="mc-icon-btn" id="btnNewChat" title="New Conversation">
      <svg viewBox="0 0 16 16"><path d="M7.25 2v5.25H2v1.5h5.25V14h1.5V8.75H14v-1.5H8.75V2h-1.5z"/></svg>
    </button>

    <div class="mc-vdivider"></div>

    <div class="mc-mode-tabs">
      <button class="mc-mode-tab active" data-tab="chat">
        <svg viewBox="0 0 16 16"><path d="M2.5 2A1.5 1.5 0 0 0 1 3.5v7A1.5 1.5 0 0 0 2.5 12H5l3 3 3-3h2.5A1.5 1.5 0 0 0 15 10.5v-7A1.5 1.5 0 0 0 13.5 2h-11z"/></svg>
        Chat
      </button>
      <button class="mc-mode-tab" data-tab="plan">
        <svg viewBox="0 0 16 16"><path d="M3 2h10a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1zm1.5 3v1.5h7V5h-7zm0 3v1.5h7V8h-7zm0 3v1.5h4V11h-4z"/></svg>
        Plan
        <span id="planPendingDot" class="mc-dot orange" style="display:none;"></span>
      </button>
      <button class="mc-mode-tab" data-tab="task">
        <svg viewBox="0 0 16 16"><path d="M6.5 10.7L3.8 8l-1.1 1.1 3.8 3.8 7-7-1.1-1.1-5.9 5.9z"/></svg>
        Task
      </button>
      <button class="mc-mode-tab" data-tab="cells">
        <svg viewBox="0 0 16 16"><path d="M2 2h12v5H2V2zm1.5 1.5v2h9v-2h-9zM2 9h12v5H2V9zm1.5 1.5v2h9v-2h-9z"/></svg>
        Cells
      </button>
      <button class="mc-mode-tab" data-tab="devices">
        <svg viewBox="0 0 16 16"><path d="M4.5 1A1.5 1.5 0 0 0 3 2.5v11A1.5 1.5 0 0 0 4.5 15h7a1.5 1.5 0 0 0 1.5-1.5v-11A1.5 1.5 0 0 0 11.5 1h-7zM4.5 2.5h7v10h-7v-10zm2.5 11h2v.5H7v-.5z"/></svg>
        Devices
      </button>
      <button class="mc-mode-tab" data-tab="apisql">
        <svg viewBox="0 0 16 16"><path d="M8 1C4.1 1 1 2.3 1 4v8c0 1.7 3.1 3 7 3s7-1.3 7-3V4c0-1.7-3.1-3-7-3zm0 1.5c3.3 0 5.5.9 5.5 1.5S11.3 5.5 8 5.5 2.5 4.6 2.5 4 4.7 2.5 8 2.5zM2.5 5.8C3.8 6.5 5.8 7 8 7s4.2-.5 5.5-1.2V8c0 .6-2.2 1.5-5.5 1.5S2.5 8.6 2.5 8V5.8zm0 4C3.8 10.5 5.8 11 8 11s4.2-.5 5.5-1.2V12c0 .6-2.2 1.5-5.5 1.5S2.5 12.6 2.5 12V9.8z"/></svg>
        API &amp; SQL
      </button>
    </div>

    ${
      !isFullPanel
        ? `<button class="mc-icon-btn" id="btnOpenFull" title="Open Full Workstation in Split Editor" style="margin-left:auto;">
            <svg viewBox="0 0 16 16"><path d="M3 3h4V1.5H1.5V7H3V3zm10 0v4h1.5V1.5H9V3h4zM3 13V9H1.5v5.5H7V13H3zm10 0H9v1.5h5.5V9H13v4z"/></svg>
          </button>`
        : ''
    }
  </div>

  <!-- 2. Sub-bar: Model Selector, Sub-Agent Role, Permission Mode, Runtime Status -->
  <div class="mc-subbar">
    <select id="modelSelect" class="mc-pill-select" title="AI Provider / Sovereign Model">
      <option value="omni-o1x-pro">Omni O1X Pro (3B MoE)</option>
      <option value="omni-o1x-lite">Omni O1X Lite (0.8B)</option>
      <option value="claude-sonnet-4-6">Claude Sonnet 4.6</option>
      <option value="gemini-2.5-pro">Gemini 2.5 Pro</option>
      <option value="gpt-4o">OpenAI GPT-4o</option>
    </select>

    <select id="subAgentSelect" class="mc-pill-select" title="Sub-Agent Persona">
      <option value="coder">Role: Coder</option>
      <option value="architect">Role: Architect</option>
      <option value="reviewer">Role: Reviewer</option>
      <option value="tester">Role: Tester</option>
      <option value="researcher">Role: Researcher</option>
    </select>

    <select id="permSelect" class="mc-pill-select" title="Tool Approval Gate Mode">
      <option value="review">Gate: Review</option>
      <option value="fullAuto">Gate: Full Auto</option>
    </select>

    <div class="mc-status-indicator">
      <span id="statusDot" class="mc-dot green"></span>
      <span id="statusLabel">Ready</span>
    </div>
  </div>

  <!-- 3. Main Body (Collapsible History Drawer + Active Workstation Tab) -->
  <div class="mc-workspace-body">
    <!-- History Sidebar Drawer -->
    <div class="mc-history-drawer" id="historyDrawer">
      <div class="mc-history-header">
        <span>CHATS</span>
        <span id="historyCount">0</span>
      </div>
      <div class="mc-history-list" id="historyList"></div>
    </div>

    <!-- Main Active Pane -->
    <div class="mc-main-pane">

      <!-- ==================== TAB 1: CHAT ==================== -->
      <div class="mc-tab-view active" id="tab-chat">
        <div class="mc-chat-scroll" id="chatScroll"></div>

        <!-- ToolApprovalView Card -->
        <div class="mc-approval-card" id="approvalCard">
          <div class="mc-approval-top">
            <div class="mc-approval-icon">
              <svg viewBox="0 0 16 16" width="14" height="14" fill="currentColor"><path d="M8 1L1 4v4.5c0 4.1 2.9 7.9 7 8.5 4.1-.6 7-4.4 7-8.5V4L8 1zm0 2.1l5 2.1v3.3c0 3.2-2.2 6.2-5 6.8-2.8-.6-5-3.6-5-6.8V5.2l5-2.1zM7.25 5v4h1.5V5h-1.5zm0 5.5v1.5h1.5V10.5h-1.5z"/></svg>
            </div>
            <div class="mc-approval-title-group">
              <div class="mc-approval-label">Tool Execution Request</div>
              <div class="mc-approval-toolname" id="approvalToolName">write_file</div>
            </div>
            <span class="mc-risk-badge" id="approvalRisk">Moderate</span>
          </div>
          <div class="mc-approval-desc" id="approvalDesc"></div>
          <div class="mc-approval-args" id="approvalArgs"></div>
          <div class="mc-approval-actions">
            <button class="mc-btn danger" id="btnRejectTool">Reject</button>
            <button class="mc-btn" id="btnAlwaysAllowTool">Always Allow</button>
            <button class="mc-btn primary" id="btnApproveTool">Approve</button>
          </div>
        </div>

        <!-- Composer -->
        <div class="mc-composer">
          <textarea
            id="chatInput"
            class="mc-composer-input"
            placeholder="Ask MicroCode Agent, or type /plan <goal> to architect a structured implementation plan..."
          ></textarea>
          <div class="mc-composer-bar">
            <label class="mc-composer-left">
              <input type="checkbox" id="chkIncludeEditor" checked />
              <span>Active Editor Context</span>
            </label>
            <div style="display:flex; gap:6px;">
              <button class="mc-btn" id="btnQuickPlan" title="Generate Structured Plan from Prompt">
                Plan
              </button>
              <button class="mc-btn primary" id="btnSendChat">
                Send
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- ==================== TAB 2: PLAN ==================== -->
      <div class="mc-tab-view" id="tab-plan">
        <div class="mc-plan-header">
          <span id="planStateDot" class="mc-dot orange"></span>
          <strong id="planStateText" style="font-size:11px;">Implementation Plan</strong>
          <div style="margin-left:auto; display:flex; gap:6px; align-items:center;">
            <button class="mc-btn" id="btnToggleRawPlan">Raw MD</button>
            <button class="mc-btn danger" id="btnRejectPlan">Reject</button>
            <button class="mc-btn success" id="btnApprovePlan">Approve Plan &amp; Proceed ⌘↵</button>
          </div>
        </div>

        <div class="mc-plan-scroll" id="planStructuredContainer"></div>

        <div class="mc-plan-scroll" id="planRawContainer" style="display:none;">
          <textarea id="planRawEditor" class="mc-editor-area" style="min-height:260px;"></textarea>
          <div style="display:flex; justify-content:flex-end;">
            <button class="mc-btn primary" id="btnSaveRawPlan">Save Plan Markdown</button>
          </div>
        </div>

        <div class="mc-composer">
          <div style="display:flex; gap:6px;">
            <input
              id="planGoalInput"
              class="mc-input"
              style="flex:1;"
              placeholder="Describe feature or architecture goal to generate a structured plan..."
            />
            <button class="mc-btn primary" id="btnGeneratePlanNow">Generate Plan</button>
          </div>
        </div>
      </div>

      <!-- ==================== TAB 3: TASK & GOVERNANCE ==================== -->
      <div class="mc-tab-view" id="tab-task">
        <div class="mc-subtab-bar">
          <div class="mc-mode-tabs">
            <button class="mc-mode-tab active" data-subtab="checklist">Checklist</button>
            <button class="mc-mode-tab" data-subtab="spec">AGENTS.md</button>
            <button class="mc-mode-tab" data-subtab="walkthrough">Walkthrough</button>
            <button class="mc-mode-tab" data-subtab="audit">Flight Audit</button>
          </div>
        </div>

        <!-- Checklist Subview -->
        <div id="subtab-checklist" class="mc-plan-scroll">
          <div id="taskChecklistItems" style="display:flex; flex-direction:column; gap:6px;"></div>
          <div style="display:flex; gap:6px; margin-top:6px;">
            <input id="newTaskInput" class="mc-input" style="flex:1;" placeholder="Add checklist item to .microcode/task.md..." />
            <button class="mc-btn primary" id="btnAddTask">Add</button>
          </div>
        </div>

        <!-- Spec Subview -->
        <div id="subtab-spec" class="mc-plan-scroll" style="display:none;">
          <textarea id="agentsSpecEditor" class="mc-editor-area"></textarea>
          <div style="display:flex; justify-content:flex-end;">
            <button class="mc-btn primary" id="btnSaveAgentsSpec">Save AGENTS.md</button>
          </div>
        </div>

        <!-- Walkthrough Subview -->
        <div id="subtab-walkthrough" class="mc-plan-scroll" style="display:none;">
          <textarea id="walkthroughEditor" class="mc-editor-area"></textarea>
          <div style="display:flex; justify-content:flex-end;">
            <button class="mc-btn primary" id="btnSaveWalkthrough">Save Walkthrough</button>
          </div>
        </div>

        <!-- Flight Audit Subview -->
        <div id="subtab-audit" class="mc-plan-scroll" style="display:none;">
          <table class="mc-audit-table">
            <thead>
              <tr>
                <th>Time</th>
                <th>Actor</th>
                <th>Action</th>
                <th>Target</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody id="auditTableBody"></tbody>
          </table>
        </div>
      </div>

      <!-- ==================== TAB 4: CELLS (.microcode/cells) ==================== -->
      <div class="mc-tab-view" id="tab-cells">
        <div class="mc-subtab-bar">
          <span style="font-size:11px; font-weight:600; color:var(--mc-text-secondary);">Workspace Cells (.microcode/cells)</span>
          <div style="display:flex; gap:6px;">
            <select id="newCellLang" class="mc-pill-select">
              <option value="ardium">Ardium</option>
              <option value="python">Python</option>
              <option value="rust">Rust</option>
              <option value="typescript">TypeScript</option>
              <option value="javascript">JavaScript</option>
              <option value="swift">Swift</option>
              <option value="go">Go</option>
              <option value="c">C</option>
              <option value="cpp">C++</option>
              <option value="sql">SQL</option>
              <option value="sh">Shell</option>
            </select>
            <button class="mc-btn primary" id="btnCreateCell">+ New Cell</button>
          </div>
        </div>
        <div class="mc-plan-scroll" id="cellsListContainer"></div>
      </div>

      <!-- ==================== TAB 5: DEVICES (simctl & adb) ==================== -->
      <div class="mc-tab-view" id="tab-devices">
        <div class="mc-subtab-bar">
          <span style="font-size:11px; font-weight:600; color:var(--mc-text-secondary);">Embedded Runtime Dock (iOS &amp; Android)</span>
          <button class="mc-btn" id="btnRefreshDevices">Refresh Devices</button>
        </div>
        <div class="mc-plan-scroll">
          <div id="devicesListContainer" style="display:flex; flex-direction:column; gap:6px;"></div>
          <div id="deviceViewportContainer" style="display:none;" class="mc-device-screen">
            <div style="width:100%; display:flex; justify-content:space-between; align-items:center;">
              <span id="deviceViewportTitle" style="font-size:10.5px; color:var(--mc-text-secondary);">Live Framebuffer</span>
            </div>
            <img id="deviceScreenshotImg" alt="Device Framebuffer" />
          </div>
        </div>
      </div>

      <!-- ==================== TAB 6: API & SQL STUDIO ==================== -->
      <div class="mc-tab-view" id="tab-apisql">
        <div class="mc-subtab-bar">
          <div class="mc-mode-tabs">
            <button class="mc-mode-tab active" data-apitab="http">HTTP Client</button>
            <button class="mc-mode-tab" data-apitab="sql">SQLite Studio</button>
          </div>
        </div>

        <!-- HTTP Client -->
        <div id="apitab-http" class="mc-plan-scroll">
          <div style="display:flex; gap:6px;">
            <select id="httpMethod" class="mc-pill-select" style="font-weight:700;">
              <option value="GET">GET</option>
              <option value="POST">POST</option>
              <option value="PUT">PUT</option>
              <option value="DELETE">DELETE</option>
            </select>
            <input id="httpUrl" class="mc-input mono" style="flex:1;" value="http://127.0.0.1:3000/api/health" />
            <button class="mc-btn primary" id="btnSendHttp">Send</button>
          </div>
          <div style="font-size:10px; color:var(--mc-text-muted); font-weight:600;">HEADERS (JSON)</div>
          <textarea id="httpHeaders" class="mc-input mono" style="min-height:46px;">{"Content-Type": "application/json"}</textarea>
          <div style="font-size:10px; color:var(--mc-text-muted); font-weight:600;">REQUEST BODY</div>
          <textarea id="httpBody" class="mc-input mono" style="min-height:60px;" placeholder="Optional request payload..."></textarea>
          <div style="display:flex; justify-content:space-between; align-items:center;">
            <span style="font-size:10px; color:var(--mc-text-muted); font-weight:600;">RESPONSE</span>
            <span id="httpMetaBadge" class="mc-badge">Idle</span>
          </div>
          <pre id="httpResponseBox" class="mc-cell-output" style="min-height:130px; border:1px solid var(--mc-border); border-radius:5px;">Ready.</pre>
        </div>

        <!-- SQLite Studio -->
        <div id="apitab-sql" class="mc-plan-scroll" style="display:none;">
          <div style="display:flex; gap:6px; align-items:center;">
            <span style="font-size:10.5px; color:var(--mc-text-secondary);">DB Path:</span>
            <input id="sqlDbPath" class="mc-input mono" style="flex:1;" value=".microcode/workstation.sqlite" />
            <button class="mc-btn primary" id="btnRunSql">Execute SQL</button>
          </div>
          <textarea id="sqlQueryInput" class="mc-input mono" style="min-height:84px;">CREATE TABLE IF NOT EXISTS telemetry (id INTEGER PRIMARY KEY, metric TEXT, value REAL);
INSERT INTO telemetry (metric, value) VALUES ('compile_ms', 14.2);
SELECT * FROM telemetry ORDER BY id DESC LIMIT 10;</textarea>
          <pre id="sqlOutputBox" class="mc-cell-output" style="min-height:150px; border:1px solid var(--mc-border); border-radius:5px;">Run a query to inspect results.</pre>
        </div>
      </div>

    </div>
  </div>

  <script>
    const vscode = acquireVsCodeApi();
    let appState = null;
    let isRawPlanView = false;

    function esc(str) {
      return String(str ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
    }

    function formatMarkdownLite(text) {
      let safe = esc(text);
      safe = safe.replace(/\`\`\`([a-zA-Z0-9_-]*)\\n([\\s\\S]*?)\`\`\`/g, '<pre><code>$2</code></pre>');
      safe = safe.replace(/\`([^\`]+)\`/g, '<code>$1</code>');
      safe = safe.replace(/\\*\\*([^*]+)\\*\\*/g, '<strong>$1</strong>');
      return safe;
    }

    // Mode Tab Switching
    document.querySelectorAll('.mc-mode-tab[data-tab]').forEach(btn => {
      btn.addEventListener('click', () => {
        const target = btn.getAttribute('data-tab');
        document.querySelectorAll('.mc-mode-tab[data-tab]').forEach(b => b.classList.remove('active'));
        document.querySelectorAll('.mc-tab-view').forEach(v => v.classList.remove('active'));
        btn.classList.add('active');
        const view = document.getElementById('tab-' + target);
        if (view) view.classList.add('active');
        if (target === 'devices') {
          vscode.postMessage({ type: 'refreshDevices' });
        }
      });
    });

    // Task Sub-tabs
    document.querySelectorAll('.mc-mode-tab[data-subtab]').forEach(btn => {
      btn.addEventListener('click', () => {
        const target = btn.getAttribute('data-subtab');
        document.querySelectorAll('.mc-mode-tab[data-subtab]').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        ['checklist', 'spec', 'walkthrough', 'audit'].forEach(id => {
          const el = document.getElementById('subtab-' + id);
          if (el) el.style.display = id === target ? 'flex' : 'none';
        });
      });
    });

    // API & SQL Sub-tabs
    document.querySelectorAll('.mc-mode-tab[data-apitab]').forEach(btn => {
      btn.addEventListener('click', () => {
        const target = btn.getAttribute('data-apitab');
        document.querySelectorAll('.mc-mode-tab[data-apitab]').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        document.getElementById('apitab-http').style.display = target === 'http' ? 'flex' : 'none';
        document.getElementById('apitab-sql').style.display = target === 'sql' ? 'flex' : 'none';
      });
    });

    // Topbar Actions
    document.getElementById('btnToggleHistory').addEventListener('click', () => {
      const drawer = document.getElementById('historyDrawer');
      drawer.classList.toggle('open');
      document.getElementById('btnToggleHistory').classList.toggle('active', drawer.classList.contains('open'));
    });

    document.getElementById('btnNewChat').addEventListener('click', () => {
      vscode.postMessage({ type: 'newSession' });
    });

    const btnOpenFull = document.getElementById('btnOpenFull');
    if (btnOpenFull) {
      btnOpenFull.addEventListener('click', () => {
        vscode.postMessage({ type: 'openFullWorkstation' });
      });
    }

    document.getElementById('permSelect').addEventListener('change', (e) => {
      vscode.postMessage({ type: 'setPermissionMode', mode: e.target.value });
    });

    // Chat Actions
    function triggerSendChat() {
      const input = document.getElementById('chatInput');
      const prompt = input.value.trim();
      if (!prompt) return;
      input.value = '';
      vscode.postMessage({
        type: 'sendChat',
        prompt,
        model: document.getElementById('modelSelect').value,
        subAgent: document.getElementById('subAgentSelect').value,
        includeEditor: document.getElementById('chkIncludeEditor').checked
      });
    }

    document.getElementById('btnSendChat').addEventListener('click', triggerSendChat);
    document.getElementById('chatInput').addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        triggerSendChat();
      }
    });

    document.getElementById('btnQuickPlan').addEventListener('click', () => {
      const input = document.getElementById('chatInput');
      const goal = input.value.trim() || 'Architect and verify workspace implementation plan';
      input.value = '';
      document.querySelector('.mc-mode-tab[data-tab="plan"]').click();
      vscode.postMessage({ type: 'generatePlan', goal });
    });

    // Approval Gate Actions
    document.getElementById('btnApproveTool').addEventListener('click', () => {
      vscode.postMessage({ type: 'resolveApproval', decision: 'approve' });
    });
    document.getElementById('btnAlwaysAllowTool').addEventListener('click', () => {
      vscode.postMessage({ type: 'resolveApproval', decision: 'always' });
    });
    document.getElementById('btnRejectTool').addEventListener('click', () => {
      vscode.postMessage({ type: 'resolveApproval', decision: 'reject' });
    });

    // Plan Actions
    document.getElementById('btnToggleRawPlan').addEventListener('click', () => {
      isRawPlanView = !isRawPlanView;
      document.getElementById('planStructuredContainer').style.display = isRawPlanView ? 'none' : 'flex';
      document.getElementById('planRawContainer').style.display = isRawPlanView ? 'flex' : 'none';
    });
    document.getElementById('btnApprovePlan').addEventListener('click', () => {
      vscode.postMessage({ type: 'approvePlan' });
    });
    document.getElementById('btnRejectPlan').addEventListener('click', () => {
      vscode.postMessage({ type: 'rejectPlan' });
    });
    document.getElementById('btnSaveRawPlan').addEventListener('click', () => {
      vscode.postMessage({
        type: 'savePlanMarkdown',
        markdown: document.getElementById('planRawEditor').value
      });
    });
    document.getElementById('btnGeneratePlanNow').addEventListener('click', () => {
      const goal = document.getElementById('planGoalInput').value.trim();
      vscode.postMessage({ type: 'generatePlan', goal });
    });

    // Task & Governance Actions
    document.getElementById('btnAddTask').addEventListener('click', () => {
      const input = document.getElementById('newTaskInput');
      if (!input.value.trim()) return;
      vscode.postMessage({ type: 'addTaskItem', text: input.value.trim() });
      input.value = '';
    });
    document.getElementById('btnSaveAgentsSpec').addEventListener('click', () => {
      vscode.postMessage({
        type: 'saveAgentsSpec',
        markdown: document.getElementById('agentsSpecEditor').value
      });
    });
    document.getElementById('btnSaveWalkthrough').addEventListener('click', () => {
      vscode.postMessage({
        type: 'saveWalkthrough',
        markdown: document.getElementById('walkthroughEditor').value
      });
    });

    // Cells Actions
    document.getElementById('btnCreateCell').addEventListener('click', () => {
      const lang = document.getElementById('newCellLang').value;
      vscode.postMessage({
        type: 'createCell',
        title: lang.toUpperCase() + ' Scratchpad',
        language: lang
      });
    });

    // Devices Actions
    document.getElementById('btnRefreshDevices').addEventListener('click', () => {
      vscode.postMessage({ type: 'refreshDevices' });
    });

    // HTTP & SQL Actions
    document.getElementById('btnSendHttp').addEventListener('click', () => {
      document.getElementById('httpMetaBadge').textContent = 'Running...';
      vscode.postMessage({
        type: 'sendHttpRequest',
        method: document.getElementById('httpMethod').value,
        url: document.getElementById('httpUrl').value,
        headersJson: document.getElementById('httpHeaders').value,
        body: document.getElementById('httpBody').value
      });
    });
    document.getElementById('btnRunSql').addEventListener('click', () => {
      vscode.postMessage({
        type: 'runSqlQuery',
        dbPath: document.getElementById('sqlDbPath').value,
        sql: document.getElementById('sqlQueryInput').value
      });
    });

    // Render Full State
    function renderState(state) {
      appState = state;

      // Permission Mode & Runtime Status
      document.getElementById('permSelect').value = state.permissionMode || 'review';
      const statusDot = document.getElementById('statusDot');
      const statusLabel = document.getElementById('statusLabel');
      if (state.status?.omniOnline) {
        statusDot.className = 'mc-dot green';
        statusLabel.textContent = 'Omni O1X';
      } else if (state.status?.backendOnline) {
        statusDot.className = 'mc-dot green';
        statusLabel.textContent = 'Backend :3000';
      } else if (state.status?.ardiumCompilerPath) {
        statusDot.className = 'mc-dot blue';
        statusLabel.textContent = 'Local Sovereign';
      } else {
        statusDot.className = 'mc-dot orange';
        statusLabel.textContent = 'Direct CLI';
      }

      // History Sidebar
      const sessions = state.sessions || [];
      document.getElementById('historyCount').textContent = String(sessions.length);
      const historyList = document.getElementById('historyList');
      historyList.innerHTML = sessions.map(s => {
        const isActive = s.id === state.activeSession?.id;
        return \`
          <div class="mc-history-item \${isActive ? 'active' : ''}" data-sid="\${esc(s.id)}">
            <div class="mc-history-item-title">\${esc(s.title || 'New Conversation')}</div>
            <div class="mc-history-item-meta">
              <span class="mc-project-badge">\${esc(s.projectName || 'Workspace')}</span>
              <span>\${new Date(s.updatedAt).toLocaleTimeString([], {hour:'2-digit', minute:'2-digit'})}</span>
            </div>
            <button class="mc-history-del" data-del-sid="\${esc(s.id)}" title="Delete">✕</button>
          </div>
        \`;
      }).join('');

      historyList.querySelectorAll('.mc-history-item').forEach(el => {
        el.addEventListener('click', (e) => {
          if (e.target.hasAttribute('data-del-sid')) {
            e.stopPropagation();
            vscode.postMessage({ type: 'deleteSession', sessionId: e.target.getAttribute('data-del-sid') });
            return;
          }
          vscode.postMessage({ type: 'selectSession', sessionId: el.getAttribute('data-sid') });
        });
      });

      // Chat Messages
      const chatScroll = document.getElementById('chatScroll');
      const msgs = state.activeSession?.messages || [];
      chatScroll.innerHTML = msgs.map(m => {
        const toolsHtml = (m.toolCalls || []).map(t => \`
          <span class="mc-tool-pill">
            <span class="mc-dot green"></span>
            <span>\${esc(t.name)}</span>
            <span style="opacity:0.7;">\${esc(t.summary)}</span>
          </span>
        \`).join('');
        return \`
          <div class="mc-msg \${esc(m.role)}">
            <div class="mc-msg-header">
              <span>\${m.role === 'user' ? 'You' : (m.role === 'system' ? 'System Gate' : 'MicroCode Agent')}</span>
              <div class="mc-msg-badges">
                \${m.subAgent ? \`<span class="mc-badge">\${esc(m.subAgent)}</span>\` : ''}
                \${m.model ? \`<span class="mc-badge">\${esc(m.model)}</span>\` : ''}
              </div>
            </div>
            <div class="mc-msg-body">\${formatMarkdownLite(m.content)}</div>
            \${toolsHtml ? \`<div class="mc-tool-pills">\${toolsHtml}</div>\` : ''}
          </div>
        \`;
      }).join('');
      chatScroll.scrollTop = chatScroll.scrollHeight;

      // Pending Tool Approval Banner
      const approvalCard = document.getElementById('approvalCard');
      if (state.pendingApproval) {
        approvalCard.classList.add('visible');
        document.getElementById('approvalToolName').textContent = state.pendingApproval.toolName;
        document.getElementById('approvalRisk').textContent = state.pendingApproval.riskLevel;
        document.getElementById('approvalDesc').textContent = state.pendingApproval.description;
        const argsEntries = Object.entries(state.pendingApproval.arguments || {})
          .map(([k, v]) => \`<div><strong>\${esc(k)}:</strong> \${esc(v)}</div>\`)
          .join('');
        document.getElementById('approvalArgs').innerHTML = argsEntries;
      } else {
        approvalCard.classList.remove('visible');
      }

      // Structured Implementation Plan
      const plan = state.currentPlan;
      const planDot = document.getElementById('planPendingDot');
      const planStateDot = document.getElementById('planStateDot');
      const planStateText = document.getElementById('planStateText');
      if (plan) {
        planDot.style.display = plan.approvalState === 'pending' ? 'inline-block' : 'none';
        planStateDot.className = 'mc-dot ' + (plan.approvalState === 'approved' ? 'green' : (plan.approvalState === 'rejected' ? 'red' : 'orange'));
        planStateText.textContent = plan.approvalState === 'approved' ? 'Plan Approved' : (plan.approvalState === 'rejected' ? 'Plan Rejected' : 'Awaiting Approval');
        document.getElementById('planRawEditor').value = plan.rawMarkdown || '';

        const sectionsHtml = (plan.sections || []).map((sec, idx) => \`
          <div class="mc-card">
            <div class="mc-card-title">
              <span>\${idx + 1}. \${esc(sec.title)}</span>
              <span class="mc-badge">\${sec.steps.filter(s => s.completed).length}/\${sec.steps.length}</span>
            </div>
            <div style="display:flex; flex-direction:column; gap:4px;">
              \${sec.steps.map(st => \`
                <div class="mc-step-row" data-stepid="\${esc(st.id)}">
                  <input type="checkbox" \${st.completed ? 'checked' : ''} style="margin-top:2px;" />
                  <span class="mc-step-badge \${esc(st.action)}">\${esc(st.action)}</span>
                  <div style="flex:1; display:flex; flex-direction:column; gap:3px;">
                    <span style="font-size:11.5px; \${st.completed ? 'text-decoration:line-through; color:var(--mc-text-muted);' : ''}">\${esc(st.description)}</span>
                    \${st.fileLink ? \`<button class="mc-file-link" data-openfile="\${esc(st.fileLink)}">\${esc(st.fileLink)}</button>\` : ''}
                  </div>
                </div>
              \`).join('')}
            </div>
          </div>
        \`).join('');

        document.getElementById('planStructuredContainer').innerHTML = \`
          <div class="mc-card">
            <div class="mc-card-title"><span>\${esc(plan.title)}</span></div>
            <div style="font-size:11.5px; color:var(--mc-text-secondary);">\${esc(plan.summary)}</div>
          </div>
          \${sectionsHtml}
        \`;

        document.querySelectorAll('.mc-step-row').forEach(row => {
          row.addEventListener('click', (e) => {
            if (e.target.hasAttribute('data-openfile')) {
              e.stopPropagation();
              vscode.postMessage({ type: 'openFileLink', filePath: e.target.getAttribute('data-openfile') });
              return;
            }
            vscode.postMessage({ type: 'togglePlanStep', stepId: row.getAttribute('data-stepid') });
          });
        });
      }

      // Task Checklist
      const taskLines = (state.taskMarkdown || '').split('\\n');
      const checklistEl = document.getElementById('taskChecklistItems');
      checklistEl.innerHTML = taskLines.map((line, idx) => {
        const m = line.match(/^\\s*-\\s*\\[([ xX/])\\]\\s*(.+)$/);
        if (!m) return '';
        const done = m[1].toLowerCase() === 'x';
        return \`
          <div class="mc-check-row \${done ? 'done' : ''}" data-lineidx="\${idx}">
            <input type="checkbox" \${done ? 'checked' : ''} />
            <span>\${esc(m[2])}</span>
          </div>
        \`;
      }).join('');
      checklistEl.querySelectorAll('.mc-check-row').forEach(row => {
        row.addEventListener('click', () => {
          vscode.postMessage({ type: 'toggleTaskLine', lineIndex: Number(row.getAttribute('data-lineidx')) });
        });
      });

      // AGENTS.md & Walkthrough
      const specEd = document.getElementById('agentsSpecEditor');
      if (document.activeElement !== specEd) {
        specEd.value = state.agentsSpec || '';
      }
      const walkEd = document.getElementById('walkthroughEditor');
      if (document.activeElement !== walkEd) {
        walkEd.value = state.walkthroughMarkdown || '';
      }

      // Flight Audit Table
      const auditBody = document.getElementById('auditTableBody');
      auditBody.innerHTML = (state.auditLog || []).map(a => \`
        <tr>
          <td style="font-family:var(--mc-font-mono);">\${new Date(a.timestamp).toLocaleTimeString([], {hour:'2-digit', minute:'2-digit', second:'2-digit'})}</td>
          <td>\${esc(a.actor)}</td>
          <td><code>\${esc(a.action)}</code></td>
          <td style="font-family:var(--mc-font-mono);">\${esc(a.target)}</td>
          <td><span class="mc-badge">\${esc(a.status)}</span></td>
        </tr>
      \`).join('');

      // Cells List
      const cellsContainer = document.getElementById('cellsListContainer');
      const cells = state.cells || [];
      cellsContainer.innerHTML = cells.map(c => \`
        <div class="mc-cell-card" data-cid="\${esc(c.id)}">
          <div class="mc-cell-header">
            <div style="display:flex; align-items:center; gap:6px;">
              <span class="mc-dot \${c.status === 'success' ? 'green' : (c.status === 'error' ? 'red' : 'blue')}"></span>
              <strong style="font-size:11px;">\${esc(c.title)}</strong>
              <span class="mc-badge">\${esc(c.language)}</span>
            </div>
            <div style="display:flex; gap:4px;">
              <button class="mc-btn" data-playground-cid="\${esc(c.id)}" title="Open in Playground">Playground</button>
              <button class="mc-btn primary" data-run-cid="\${esc(c.id)}">Run</button>
              <button class="mc-btn danger" data-del-cid="\${esc(c.id)}">✕</button>
            </div>
          </div>
          <textarea class="mc-cell-code" id="cell-code-\${esc(c.id)}">\${esc(c.code)}</textarea>
          \${c.output ? \`<div class="mc-cell-output">\${esc(c.output)}</div>\` : ''}
        </div>
      \`).join('');

      cellsContainer.querySelectorAll('[data-run-cid]').forEach(btn => {
        btn.addEventListener('click', () => {
          const cid = btn.getAttribute('data-run-cid');
          const codeEl = document.getElementById('cell-code-' + cid);
          btn.textContent = 'Running...';
          vscode.postMessage({ type: 'runCell', cellId: cid, code: codeEl ? codeEl.value : undefined });
        });
      });
      cellsContainer.querySelectorAll('[data-playground-cid]').forEach(btn => {
        btn.addEventListener('click', () => {
          const cid = btn.getAttribute('data-playground-cid');
          const cell = (appState.cells || []).find(x => x.id === cid);
          const codeEl = document.getElementById('cell-code-' + cid);
          if (cell) {
            vscode.postMessage({
              type: 'openInPlayground',
              code: codeEl ? codeEl.value : cell.code,
              language: cell.language
            });
          }
        });
      });
      cellsContainer.querySelectorAll('[data-del-cid]').forEach(btn => {
        btn.addEventListener('click', () => {
          vscode.postMessage({ type: 'deleteCell', cellId: btn.getAttribute('data-del-cid') });
        });
      });
    }

    // Message Receiver
    window.addEventListener('message', (event) => {
      const msg = event.data;
      if (msg.type === 'stateSync') {
        renderState(msg.state);
      } else if (msg.type === 'chatBusy') {
        const btn = document.getElementById('btnSendChat');
        btn.textContent = msg.busy ? 'Thinking...' : 'Send';
        btn.disabled = Boolean(msg.busy);
      } else if (msg.type === 'devicesList') {
        const list = msg.devices || [];
        const container = document.getElementById('devicesListContainer');
        if (list.length === 0) {
          container.innerHTML = '<div class="mc-card">No iOS Simulators or Android ADB devices found.</div>';
          return;
        }
        container.innerHTML = list.map(d => \`
          <div class="mc-device-row">
            <div style="display:flex; flex-direction:column; gap:2px;">
              <div style="display:flex; align-items:center; gap:6px;">
                <span class="mc-dot \${d.state.toLowerCase().includes('booted') || d.state.toLowerCase() === 'device' ? 'green' : 'orange'}"></span>
                <strong style="font-size:11.5px;">\${esc(d.name)}</strong>
                <span class="mc-badge">\${esc(d.platform.toUpperCase())}</span>
              </div>
              <span style="font-size:10px; color:var(--mc-text-muted); font-family:var(--mc-font-mono);">\${esc(d.runtime)} • \${esc(d.state)}</span>
            </div>
            <div style="display:flex; gap:5px;">
              \${!(d.state.toLowerCase().includes('booted') || d.state.toLowerCase() === 'device')
                ? \`<button class="mc-btn" data-boot-id="\${esc(d.id)}" data-plat="\${esc(d.platform)}">Boot</button>\`
                : ''}
              <button class="mc-btn primary" data-shot-id="\${esc(d.id)}" data-plat="\${esc(d.platform)}">Capture Screen</button>
            </div>
          </div>
        \`).join('');

        container.querySelectorAll('[data-boot-id]').forEach(b => {
          b.addEventListener('click', () => {
            b.textContent = 'Booting...';
            vscode.postMessage({
              type: 'bootDevice',
              deviceId: b.getAttribute('data-boot-id'),
              platform: b.getAttribute('data-plat')
            });
          });
        });
        container.querySelectorAll('[data-shot-id]').forEach(b => {
          b.addEventListener('click', () => {
            b.textContent = 'Capturing...';
            vscode.postMessage({
              type: 'captureDeviceScreen',
              deviceId: b.getAttribute('data-shot-id'),
              platform: b.getAttribute('data-plat')
            });
          });
        });
      } else if (msg.type === 'deviceScreenshot') {
        const vp = document.getElementById('deviceViewportContainer');
        const img = document.getElementById('deviceScreenshotImg');
        const title = document.getElementById('deviceViewportTitle');
        vp.style.display = 'flex';
        if (msg.base64Png) {
          title.textContent = 'Live Framebuffer (' + msg.deviceId + ')';
          img.src = 'data:image/png;base64,' + msg.base64Png;
          img.style.display = 'block';
        } else {
          title.textContent = msg.error || 'Failed to capture screen';
          img.style.display = 'none';
        }
        vscode.postMessage({ type: 'refreshDevices' });
      } else if (msg.type === 'httpResponse') {
        const r = msg.response;
        document.getElementById('httpMetaBadge').textContent = \`HTTP \${r.status} • \${r.durationMs}ms\`;
        document.getElementById('httpResponseBox').textContent = r.body || '(empty response)';
      } else if (msg.type === 'sqlResponse') {
        const r = msg.response;
        document.getElementById('sqlOutputBox').textContent = r.error ? ('Error: ' + r.error) : (r.output || '(0 rows)');
      }
    });

    vscode.postMessage({ type: 'init' });
  </script>
</body>
</html>`;
  }
}
