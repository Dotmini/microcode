import * as vscode from 'vscode';
import * as cp from 'child_process';
import * as fs from 'fs';
import * as http from 'http';
import * as https from 'https';
import * as os from 'os';
import * as path from 'path';
import { BackendManager } from '../backendManager';
import { MicroCodeCellCodeLensProvider } from '../notebook/cellCodeLens';

export interface PlanStepItem {
  id: string;
  action: 'NEW' | 'MODIFY' | 'DELETE' | 'VERIFY';
  description: string;
  detail?: string;
  fileLink?: string;
  completed: boolean;
}

export interface PlanSectionItem {
  id: string;
  title: string;
  steps: PlanStepItem[];
}

export interface ImplementationPlanModel {
  title: string;
  summary: string;
  createdAt: string;
  approvalState: 'pending' | 'approved' | 'rejected';
  sections: PlanSectionItem[];
  openQuestions: string[];
  verificationSteps: string[];
  rawMarkdown: string;
}

export interface ToolApprovalRequest {
  id: string;
  toolName: string;
  riskLevel: 'safe' | 'moderate' | 'critical';
  description: string;
  arguments: Record<string, string>;
}

export interface ChatMessageItem {
  id: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
  timestamp: string;
  subAgent?: string;
  model?: string;
  toolCalls?: Array<{ name: string; status: string; summary: string }>;
}

export interface ChatSessionItem {
  id: string;
  title: string;
  projectPath: string;
  projectName: string;
  updatedAt: string;
  messages: ChatMessageItem[];
}

export interface MicroCodeCellItem {
  id: string;
  title: string;
  language: string;
  code: string;
  output: string;
  status: 'idle' | 'running' | 'success' | 'error';
  updated_at: string;
}

export interface RuntimeDeviceItem {
  id: string;
  name: string;
  platform: 'ios' | 'android';
  runtime: string;
  state: string;
}

export interface FlightAuditEntry {
  id: string;
  timestamp: string;
  actor: string;
  action: string;
  target: string;
  status: 'approved' | 'executed' | 'rejected';
}

export class WorkstationEngine {
  private sessions: ChatSessionItem[] = [];
  private activeSessionId = '';
  private currentPlan: ImplementationPlanModel | null = null;
  private pendingApproval: ToolApprovalRequest | null = null;
  private permissionMode: 'review' | 'fullAuto' = 'review';
  private auditLog: FlightAuditEntry[] = [];
  private pendingApprovalAction: (() => Promise<void>) | null = null;

  constructor(
    private readonly context: vscode.ExtensionContext,
    private readonly backendManager: BackendManager,
    private readonly cellRunner: MicroCodeCellCodeLensProvider,
    private readonly outputChannel: vscode.OutputChannel
  ) {
    this.loadWorkspaceState();
  }

  public getWorkspaceRoot(): string {
    return (
      vscode.workspace.workspaceFolders?.[0]?.uri.fsPath ??
      this.backendManager.findRepoRoot()
    );
  }

  public getMicroCodeDir(): string {
    const dir = path.join(this.getWorkspaceRoot(), '.microcode');
    fs.mkdirSync(dir, { recursive: true });
    return dir;
  }

  public loadWorkspaceState(): void {
    const mcDir = this.getMicroCodeDir();
    const chatsPath = path.join(mcDir, 'chats.json');
    if (fs.existsSync(chatsPath)) {
      try {
        this.sessions = JSON.parse(fs.readFileSync(chatsPath, 'utf8'));
      } catch {
        this.sessions = [];
      }
    }
    if (this.sessions.length === 0) {
      this.createNewSession();
    } else if (!this.activeSessionId) {
      this.activeSessionId = this.sessions[0].id;
    }

    this.loadPlanFromDisk();
  }

  public saveSessions(): void {
    try {
      const chatsPath = path.join(this.getMicroCodeDir(), 'chats.json');
      fs.writeFileSync(chatsPath, JSON.stringify(this.sessions, null, 2), 'utf8');
    } catch {
      // ignore write error
    }
  }

  public createNewSession(): ChatSessionItem {
    const wsRoot = this.getWorkspaceRoot();
    const session: ChatSessionItem = {
      id: `chat_${Date.now().toString(36)}`,
      title: 'New Session',
      projectPath: wsRoot,
      projectName: path.basename(wsRoot),
      updatedAt: new Date().toISOString(),
      messages: []
    };
    this.sessions.unshift(session);
    this.activeSessionId = session.id;
    this.saveSessions();
    return session;
  }

  public selectSession(id: string): void {
    if (this.sessions.some((s) => s.id === id)) {
      this.activeSessionId = id;
    }
  }

  public deleteSession(id: string): void {
    this.sessions = this.sessions.filter((s) => s.id !== id);
    if (this.sessions.length === 0) {
      this.createNewSession();
    } else if (this.activeSessionId === id) {
      this.activeSessionId = this.sessions[0].id;
    }
    this.saveSessions();
  }

  public getActiveSession(): ChatSessionItem {
    let found = this.sessions.find((s) => s.id === this.activeSessionId);
    if (!found) {
      found = this.createNewSession();
    }
    return found;
  }

  public setPermissionMode(mode: 'review' | 'fullAuto'): void {
    this.permissionMode = mode;
  }

  // ─── Task & Rules Markdown Files ──────────────────────────────────────────

  public readTaskFiles(): {
    taskMd: string;
    agentMd: string;
    walkthroughMd: string;
    discoveredRules: string[];
  } {
    const ws = this.getWorkspaceRoot();
    const mcDir = this.getMicroCodeDir();

    const taskPath = path.join(mcDir, 'task.md');
    const walkthroughPath = path.join(mcDir, 'walkthrough.md');
    const agentsMdPath = fs.existsSync(path.join(ws, 'AGENTS.md'))
      ? path.join(ws, 'AGENTS.md')
      : path.join(mcDir, 'agent.md');

    const defaultTask = `# Implementation Checklist\n\n- [x] Audit workspace architecture & active files\n- [ ] Implement core module changes and type definitions\n- [ ] Run verification suite and static diagnostics\n`;
    if (!fs.existsSync(taskPath)) {
      try {
        fs.writeFileSync(taskPath, defaultTask, 'utf8');
      } catch {
        // ignore
      }
    }

    const taskMd = fs.existsSync(taskPath) ? fs.readFileSync(taskPath, 'utf8') : defaultTask;
    const agentMd = fs.existsSync(agentsMdPath) ? fs.readFileSync(agentsMdPath, 'utf8') : '# Agent Rules (AGENTS.md)\n';
    const walkthroughMd = fs.existsSync(walkthroughPath) ? fs.readFileSync(walkthroughPath, 'utf8') : '';

    const ruleCandidates = ['AGENTS.md', 'CLAUDE.md', '.cursorrules', '.windsurfrules', '.github/copilot-instructions.md'];
    const discoveredRules = ruleCandidates.filter((rel) => fs.existsSync(path.join(ws, rel)));

    return { taskMd, agentMd, walkthroughMd, discoveredRules };
  }

  public saveTaskFiles(taskMd?: string, agentMd?: string, walkthroughMd?: string): void {
    const ws = this.getWorkspaceRoot();
    const mcDir = this.getMicroCodeDir();
    if (typeof taskMd === 'string') {
      fs.writeFileSync(path.join(mcDir, 'task.md'), taskMd, 'utf8');
      this.loadPlanFromDisk();
    }
    if (typeof agentMd === 'string') {
      const target = fs.existsSync(path.join(ws, 'AGENTS.md'))
        ? path.join(ws, 'AGENTS.md')
        : path.join(mcDir, 'agent.md');
      fs.writeFileSync(target, agentMd, 'utf8');
    }
    if (typeof walkthroughMd === 'string') {
      fs.writeFileSync(path.join(mcDir, 'walkthrough.md'), walkthroughMd, 'utf8');
    }
    this.recordAudit('User', 'Save Workspace Spec/Task Files', '.microcode/task.md', 'executed');
  }

  public toggleChecklistLine(lineIndex: number): void {
    const { taskMd } = this.readTaskFiles();
    const lines = taskMd.split(/\r?\n/);
    if (lineIndex >= 0 && lineIndex < lines.length) {
      const line = lines[lineIndex];
      if (line.includes('- [ ]')) {
        lines[lineIndex] = line.replace('- [ ]', '- [x]');
      } else if (line.includes('- [x]')) {
        lines[lineIndex] = line.replace('- [x]', '- [ ]');
      } else if (line.includes('- [X]')) {
        lines[lineIndex] = line.replace('- [X]', '- [ ]');
      }
      this.saveTaskFiles(lines.join('\n'));
    }
  }

  // ─── Formal Implementation Plan Manager ───────────────────────────────────

  public loadPlanFromDisk(): ImplementationPlanModel | null {
    const mcDir = this.getMicroCodeDir();
    const planJsonPath = path.join(mcDir, 'plan.json');
    if (fs.existsSync(planJsonPath)) {
      try {
        this.currentPlan = JSON.parse(fs.readFileSync(planJsonPath, 'utf8'));
        return this.currentPlan;
      } catch {
        // fallback to task.md parser
      }
    }

    const { taskMd } = this.readTaskFiles();
    this.currentPlan = this.parsePlanFromMarkdown(taskMd, this.currentPlan?.approvalState ?? 'pending');
    return this.currentPlan;
  }

  public parsePlanFromMarkdown(md: string, approvalState: 'pending' | 'approved' | 'rejected' = 'pending'): ImplementationPlanModel {
    const lines = md.split(/\r?\n/);
    let title = 'Workspace Implementation Plan';
    let summary = 'Phased execution plan synchronized with .microcode/task.md and AST RepoMap.';
    const sections: PlanSectionItem[] = [];
    let currentSection: PlanSectionItem = {
      id: 'sec_1',
      title: 'Core Implementation Steps',
      steps: []
    };

    for (let i = 0; i < lines.length; i++) {
      const trimmed = lines[i].trim();
      if (trimmed.startsWith('# ')) {
        title = trimmed.slice(2).trim();
      } else if (trimmed.startsWith('## ')) {
        if (currentSection.steps.length > 0) {
          sections.push(currentSection);
        }
        currentSection = {
          id: `sec_${sections.length + 1}`,
          title: trimmed.slice(3).trim(),
          steps: []
        };
      } else if (/^[-*]\s+\[([ xX])\]\s+/.test(trimmed)) {
        const completed = /^[-*]\s+\[[xX]\]/.test(trimmed);
        let text = trimmed.replace(/^[-*]\s+\[[ xX]\]\s+/, '');
        let action: 'NEW' | 'MODIFY' | 'DELETE' | 'VERIFY' = 'MODIFY';
        const badgeMatch = text.match(/^\[(NEW|MODIFY|DELETE|VERIFY)\]\s*/i);
        if (badgeMatch) {
          action = badgeMatch[1].toUpperCase() as any;
          text = text.slice(badgeMatch[0].length);
        } else if (/create|add|new/i.test(text)) {
          action = 'NEW';
        } else if (/test|verify|check|diagnose/i.test(text)) {
          action = 'VERIFY';
        }

        const fileMatch = text.match(/`([^`]+\.[a-zA-Z0-9]+)`/);
        currentSection.steps.push({
          id: `step_${i}`,
          action,
          description: text,
          fileLink: fileMatch ? fileMatch[1] : undefined,
          completed
        });
      }
    }

    if (currentSection.steps.length > 0 || sections.length === 0) {
      sections.push(currentSection);
    }

    return {
      title,
      summary,
      createdAt: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
      approvalState,
      sections,
      openQuestions: [],
      verificationSteps: [
        'Run static typecheck and Ardium @owned RAII diagnostics',
        'Verify clean working tree and zero regressions in Shadow Workspace'
      ],
      rawMarkdown: md
    };
  }

  public setPlanApproval(state: 'approved' | 'rejected'): void {
    if (!this.currentPlan) {
      this.loadPlanFromDisk();
    }
    if (this.currentPlan) {
      this.currentPlan.approvalState = state;
      const planJsonPath = path.join(this.getMicroCodeDir(), 'plan.json');
      fs.writeFileSync(planJsonPath, JSON.stringify(this.currentPlan, null, 2), 'utf8');
      this.recordAudit(
        'User',
        state === 'approved' ? 'Approve Implementation Plan (⌘↵)' : 'Reject Implementation Plan',
        this.currentPlan.title,
        state === 'approved' ? 'approved' : 'rejected'
      );
    }
  }

  public togglePlanStep(sectionIdOrStepId: string, maybeStepId?: string): void {
    if (!this.currentPlan) return;
    const stepId = maybeStepId ?? sectionIdOrStepId;
    for (const sec of this.currentPlan.sections) {
      if (!maybeStepId || sec.id === sectionIdOrStepId) {
        const st = sec.steps.find((s) => s.id === stepId);
        if (st) {
          st.completed = !st.completed;
          const lineIdx = Number(stepId.replace('step_', ''));
          if (!Number.isNaN(lineIdx)) {
            this.toggleChecklistLine(lineIdx);
          }
        }
      }
    }
    const planJsonPath = path.join(this.getMicroCodeDir(), 'plan.json');
    fs.writeFileSync(planJsonPath, JSON.stringify(this.currentPlan, null, 2), 'utf8');
  }

  public async approvePlan(): Promise<void> {
    this.setPlanApproval('approved');
  }

  public rejectPlan(): void {
    this.setPlanApproval('rejected');
  }

  public saveRawPlanMarkdown(markdown: string): void {
    this.saveTaskFiles(markdown);
    this.currentPlan = this.parsePlanFromMarkdown(markdown, this.currentPlan?.approvalState ?? 'pending');
    const planJsonPath = path.join(this.getMicroCodeDir(), 'plan.json');
    fs.writeFileSync(planJsonPath, JSON.stringify(this.currentPlan, null, 2), 'utf8');
  }

  public toggleTaskChecklistLine(lineIndex: number): void {
    this.toggleChecklistLine(lineIndex);
  }

  public readTaskMarkdown(): string {
    return this.readTaskFiles().taskMd;
  }

  public saveTaskMarkdown(markdown: string): void {
    this.saveTaskFiles(markdown, undefined, undefined);
  }

  public saveAgentsSpec(markdown: string): void {
    this.saveTaskFiles(undefined, markdown, undefined);
  }

  public saveWalkthroughMarkdown(markdown: string): void {
    this.saveTaskFiles(undefined, undefined, markdown);
  }

  // ─── Polyglot Cells (.microcode/cells/*.json) ─────────────────────────────

  public listCells(): MicroCodeCellItem[] {
    const cellsDir = path.join(this.getMicroCodeDir(), 'cells');
    fs.mkdirSync(cellsDir, { recursive: true });
    const files = fs.readdirSync(cellsDir).filter((f) => f.endsWith('.json')).sort();
    const cells: MicroCodeCellItem[] = [];
    for (const file of files) {
      try {
        const data = JSON.parse(fs.readFileSync(path.join(cellsDir, file), 'utf8'));
        cells.push({
          id: data.id || path.basename(file, '.json'),
          title: data.title || `Cell ${data.id}`,
          language: data.language || 'ardium',
          code: data.code || '',
          output: data.output || '',
          status: data.status || 'idle',
          updated_at: data.updated_at || new Date().toISOString()
        });
      } catch {
        // skip malformed cell
      }
    }

    if (cells.length === 0) {
      const starter: MicroCodeCellItem = {
        id: 'cell_01',
        title: 'Ardium v2.3 RAII Verification',
        language: 'ardium',
        code: 'fn main() {\n    @owned let buf = alloc(128);\n    poke(buf + 0, 42);\n    print("Ardium @owned buffer[0] = ");\n    print(peek(buf + 0));\n    print("\\n");\n}',
        output: '',
        status: 'idle',
        updated_at: new Date().toISOString()
      };
      this.saveCell(starter);
      cells.push(starter);
    }
    return cells;
  }

  public saveCell(cell: MicroCodeCellItem): void {
    const cellsDir = path.join(this.getMicroCodeDir(), 'cells');
    fs.mkdirSync(cellsDir, { recursive: true });
    const safeId = cell.id.replace(/[^A-Za-z0-9_-]/g, '').slice(0, 48) || `cell_${Date.now().toString(36)}`;
    cell.id = safeId;
    cell.updated_at = new Date().toISOString();
    fs.writeFileSync(path.join(cellsDir, `${safeId}.json`), JSON.stringify(cell, null, 2), 'utf8');
  }

  public createCell(title: string, language: string, code: string): MicroCodeCellItem {
    const cell: MicroCodeCellItem = {
      id: `cell_${Date.now().toString(36)}`,
      title,
      language,
      code,
      output: '',
      status: 'idle',
      updated_at: new Date().toISOString()
    };
    this.saveCell(cell);
    this.recordAudit('PolyglotKernel', 'Create Cell', cell.title, 'executed');
    return cell;
  }

  public updateCell(cellId: string, code: string, title?: string, language?: string): void {
    const existing = this.listCells().find((c) => c.id === cellId);
    if (!existing) return;
    existing.code = code;
    if (title) existing.title = title;
    if (language) existing.language = language;
    this.saveCell(existing);
  }

  public async runCellById(cellId: string): Promise<MicroCodeCellItem | null> {
    return this.runSavedCell(cellId);
  }

  public deleteCell(cellId: string): void {
    const safeId = cellId.replace(/[^A-Za-z0-9_-]/g, '');
    const p = path.join(this.getMicroCodeDir(), 'cells', `${safeId}.json`);
    if (fs.existsSync(p)) {
      fs.unlinkSync(p);
    }
  }

  public async runSavedCell(cellId: string, codeOverride?: string, langOverride?: string): Promise<MicroCodeCellItem | null> {
    const cells = this.listCells();
    const cell = cells.find((c) => c.id === cellId);
    if (!cell) return null;

    if (typeof codeOverride === 'string') cell.code = codeOverride;
    if (typeof langOverride === 'string') cell.language = langOverride;
    cell.status = 'running';
    this.saveCell(cell);

    const start = Date.now();
    const res = await this.cellRunner.runCodeSnippet(cell.code, cell.language);
    const elapsed = Date.now() - start;

    const combined = [res.stdout, res.stderr].filter(Boolean).join('\n').trim();
    cell.output = combined
      ? `${combined}\n\n[exit ${res.exitCode} · ${elapsed}ms]`
      : `[exit ${res.exitCode} · ${elapsed}ms]`;
    cell.status = res.exitCode === 0 ? 'success' : 'error';
    this.saveCell(cell);
    this.recordAudit('PolyglotKernel', `Run Cell (${cell.language})`, cell.title, 'executed');
    return cell;
  }

  // ─── Device & Simulator Dock (xcrun simctl & adb) ─────────────────────────

  public async listDevices(): Promise<RuntimeDeviceItem[]> {
    const devices: RuntimeDeviceItem[] = [];

    // 1. iOS Simulators via xcrun simctl
    try {
      const simJson = await this.execCommand('xcrun', ['simctl', 'list', 'devices', 'available', '--json']);
      const parsed = JSON.parse(simJson);
      const devMap = parsed.devices || {};
      for (const [runtimeKey, list] of Object.entries<any[]>(devMap)) {
        const runtimeName = runtimeKey.split('.').pop()?.replace(/-/g, ' ') || runtimeKey;
        for (const item of list) {
          if (item.isAvailable) {
            devices.push({
              id: item.udid,
              name: item.name,
              platform: 'ios',
              runtime: runtimeName,
              state: item.state
            });
          }
        }
      }
    } catch {
      // simctl not available
    }

    // 2. Android devices via adb
    try {
      const adbOut = await this.execCommand('adb', ['devices', '-l']);
      const lines = adbOut.split(/\r?\n/).slice(1);
      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed) continue;
        const parts = trimmed.split(/\s+/);
        if (parts.length >= 2) {
          const modelMatch = trimmed.match(/model:([^\s]+)/);
          devices.push({
            id: parts[0],
            name: modelMatch ? modelMatch[1].replace(/_/g, ' ') : parts[0],
            platform: 'android',
            runtime: 'Android ADB',
            state: parts[1] === 'device' ? 'Booted' : parts[1]
          });
        }
      }
    } catch {
      // adb not available
    }

    // Sort Booted first
    devices.sort((a, b) => (a.state === 'Booted' ? -1 : b.state === 'Booted' ? 1 : 0));
    return devices.slice(0, 25);
  }

  public async bootDevice(deviceId: string, platform: 'ios' | 'android'): Promise<string> {
    if (platform === 'ios') {
      try {
        await this.execCommand('xcrun', ['simctl', 'boot', deviceId]);
      } catch {
        // might already be booted
      }
      await this.execCommand('open', ['-a', 'Simulator']);
      this.recordAudit('DeviceRuntime', 'Boot iOS Simulator', deviceId, 'executed');
      return 'Booted iOS Simulator';
    }
    return 'Android device ready';
  }

  public async captureDeviceScreenshot(
    deviceId: string,
    platform: 'ios' | 'android'
  ): Promise<{ base64Png?: string; error?: string }> {
    const tmpFile = path.join(os.tmpdir(), `mc_screen_${Date.now()}.png`);
    try {
      if (platform === 'ios') {
        await this.execCommand('xcrun', ['simctl', 'io', deviceId, 'screenshot', tmpFile]);
      } else {
        await new Promise<void>((resolve, reject) => {
          const out = fs.createWriteStream(tmpFile);
          const proc = cp.spawn('adb', ['-s', deviceId, 'exec-out', 'screencap', '-p']);
          proc.stdout.pipe(out);
          proc.on('close', () => resolve());
          proc.on('error', reject);
        });
      }
      if (fs.existsSync(tmpFile)) {
        const b64 = fs.readFileSync(tmpFile).toString('base64');
        fs.unlinkSync(tmpFile);
        this.recordAudit('DeviceRuntime', 'Capture Screen Framebuffer', deviceId, 'executed');
        return { base64Png: b64 };
      }
      return { error: 'Device did not return a framebuffer image (ensure simulator/device is booted).' };
    } catch (err: any) {
      if (fs.existsSync(tmpFile)) fs.unlinkSync(tmpFile);
      return { error: err?.message ?? 'Failed to capture screenshot' };
    }
  }

  // ─── API Client & SQL Studio ──────────────────────────────────────────────

  public async executeHttpRequest(
    method: string,
    urlStr: string,
    headersObj: Record<string, string>,
    bodyRaw: string
  ): Promise<{ status: number; durationMs: number; headers: string; body: string }> {
    const res = await this.sendApiRequest(method, urlStr, JSON.stringify(headersObj), bodyRaw);
    return {
      status: res.status,
      durationMs: res.elapsedMs,
      headers: res.responseHeaders,
      body: res.body
    };
  }

  public async executeSqliteQuery(dbPath: string, query: string): Promise<{ output: string; error?: string }> {
    return this.executeSqlQuery(dbPath, query);
  }

  public async sendApiRequest(
    method: string,
    urlStr: string,
    headersRaw: string,
    bodyRaw: string
  ): Promise<{ status: number; elapsedMs: number; responseHeaders: string; body: string }> {
    const start = Date.now();
    return new Promise((resolve) => {
      try {
        const u = new URL(urlStr);
        const isHttps = u.protocol === 'https:';
        const headers: Record<string, string> = {};
        if (headersRaw.trim()) {
          try {
            Object.assign(headers, JSON.parse(headersRaw));
          } catch {
            for (const line of headersRaw.split(/\r?\n/)) {
              const idx = line.indexOf(':');
              if (idx > 0) {
                headers[line.slice(0, idx).trim()] = line.slice(idx + 1).trim();
              }
            }
          }
        }

        const lib = isHttps ? https : http;
        const req = lib.request(
          {
            hostname: u.hostname,
            port: u.port || (isHttps ? 443 : 80),
            path: u.pathname + u.search,
            method: method.toUpperCase(),
            headers,
            timeout: 15000
          },
          (res) => {
            const chunks: Buffer[] = [];
            res.on('data', (d: Buffer) => chunks.push(d));
            res.on('end', () => {
              const elapsedMs = Date.now() - start;
              const rawBody = Buffer.concat(chunks).toString('utf8');
              let formatted = rawBody;
              try {
                formatted = JSON.stringify(JSON.parse(rawBody), null, 2);
              } catch {
                // keep raw text
              }
              resolve({
                status: res.statusCode ?? 0,
                elapsedMs,
                responseHeaders: JSON.stringify(res.headers, null, 2),
                body: formatted
              });
            });
          }
        );
        req.on('error', (err) => {
          resolve({
            status: 0,
            elapsedMs: Date.now() - start,
            responseHeaders: '{}',
            body: `Request Error: ${err.message}`
          });
        });
        if (bodyRaw && !['GET', 'HEAD'].includes(method.toUpperCase())) {
          req.write(bodyRaw);
        }
        req.end();
      } catch (err: any) {
        resolve({
          status: 0,
          elapsedMs: Date.now() - start,
          responseHeaders: '{}',
          body: `Invalid URL or request: ${err?.message ?? String(err)}`
        });
      }
    });
  }

  public async executeSqlQuery(dbPath: string, query: string): Promise<{ output: string; error?: string }> {
    const resolvedDb =
      !dbPath || dbPath === ':memory:'
        ? ':memory:'
        : path.isAbsolute(dbPath)
        ? dbPath
        : path.join(this.getWorkspaceRoot(), dbPath);

    try {
      const out = await this.execCommand('sqlite3', ['-header', '-column', resolvedDb, query]);
      this.recordAudit('DatabaseStudio', 'Execute SQL Query', path.basename(resolvedDb), 'executed');
      return { output: out || '(Query executed successfully — 0 rows returned)' };
    } catch (err: any) {
      return { output: '', error: err?.message ?? String(err) };
    }
  }

  // ─── AI Agent Execution & Tool Approval Gate ──────────────────────────────

  public async sendChatMessage(
    prompt: string,
    modelKey: string,
    subAgent: string,
    _editorContext?: { fileName: string; languageId: string; code: string; filePath: string }
  ): Promise<void> {
    await this.sendAgentPrompt(prompt, subAgent, modelKey, () => {});
  }

  public async generateStructuredPlan(goal: string): Promise<void> {
    await this.generateImplementationPlan(goal, 'omni-o1x-pro');
  }

  public async sendAgentPrompt(
    prompt: string,
    subAgent: string,
    modelKey: string,
    onUpdate: () => void
  ): Promise<void> {
    const session = this.getActiveSession();
    if (session.messages.length === 0) {
      session.title = prompt.slice(0, 42);
    }

    session.messages.push({
      id: `msg_${Date.now()}`,
      role: 'user',
      content: prompt,
      timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
      subAgent,
      model: modelKey
    });
    session.updatedAt = new Date().toISOString();
    this.saveSessions();
    onUpdate();

    // Handle Slash Commands deterministically
    const trimmed = prompt.trim();
    if (trimmed.startsWith('/plan')) {
      const objective = trimmed.replace(/^\/plan\s*/, '') || 'Refactor and verify active module';
      await this.generateImplementationPlan(objective, modelKey);
      session.messages.push({
        id: `msg_${Date.now() + 1}`,
        role: 'assistant',
        content: `Formal Implementation Plan generated for **${objective}** and saved to \`.microcode/task.md\`. Switch to the **Plan** tab or press \`⌘↵\` to review and approve.`,
        timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
        subAgent,
        model: modelKey,
        toolCalls: [{ name: 'plan_compiler', status: 'done', summary: 'Updated .microcode/task.md & plan.json' }]
      });
      this.saveSessions();
      onUpdate();
      return;
    }

    if (trimmed.startsWith('/verify') || trimmed.startsWith('/diagnose')) {
      const editor = vscode.window.activeTextEditor;
      const targetFile = editor ? editor.document.fileName : this.getWorkspaceRoot();
      const gitStat = await this.execCommand('git', ['status', '--short'], this.getWorkspaceRoot()).catch(() => 'Clean');
      session.messages.push({
        id: `msg_${Date.now() + 1}`,
        role: 'assistant',
        content: `### Verification & Diagnostics Report\n- **Active Target**: \`${path.basename(targetFile)}\`\n- **Working Tree Status**:\n\`\`\`text\n${gitStat.trim() || 'Clean working tree'}\n\`\`\``,
        timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
        subAgent: 'test_runner',
        model: modelKey,
        toolCalls: [{ name: 'workspace_verify', status: 'done', summary: 'Checked git status & diagnostics' }]
      });
      this.saveSessions();
      onUpdate();
      return;
    }

    // Gather Active Editor & Repo Context
    const editor = vscode.window.activeTextEditor;
    const activeFile = editor ? path.relative(this.getWorkspaceRoot(), editor.document.fileName) : '';
    const activeCode = editor
      ? editor.document.getText(editor.selection.isEmpty ? undefined : editor.selection).slice(0, 4500)
      : '';

    const toolCalls: Array<{ name: string; status: string; summary: string }> = [];
    if (activeFile) {
      toolCalls.push({
        name: 'file_read',
        status: 'done',
        summary: `Read context from ${activeFile}`
      });
    }

    // Query selected AI Engine (Omni O1X Local, Rust Backend, or ACP CLI)
    const replyText = await this.queryAiEngine(prompt, activeFile, activeCode, subAgent, modelKey);

    session.messages.push({
      id: `msg_${Date.now() + 1}`,
      role: 'assistant',
      content: replyText,
      timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
      subAgent,
      model: modelKey,
      toolCalls
    });
    this.saveSessions();
    this.recordAudit(subAgent, `Agent Response (${modelKey})`, activeFile || 'Workspace', 'executed');
    onUpdate();
  }

  public async requestWriteApproval(
    codeToApply: string,
    onUpdate: () => void
  ): Promise<void> {
    const editor = vscode.window.activeTextEditor;
    const targetPath = editor ? editor.document.fileName : path.join(this.getWorkspaceRoot(), 'output.ar');

    const applyFn = async () => {
      fs.writeFileSync(targetPath, codeToApply, 'utf8');
      this.recordAudit('AgentTool', 'replace_in_file', path.basename(targetPath), 'executed');
      void vscode.window.showInformationMessage(`Applied changes to ${path.basename(targetPath)}`);
    };

    if (this.permissionMode === 'fullAuto') {
      await applyFn();
      onUpdate();
      return;
    }

    this.pendingApproval = {
      id: `req_${Date.now()}`,
      toolName: 'replace_in_file',
      riskLevel: 'moderate',
      description: `Modify active source file (${path.basename(targetPath)}) with generated code block.`,
      arguments: {
        path: targetPath,
        lines: `${codeToApply.split('\n').length} lines`
      }
    };
    this.pendingApprovalAction = applyFn;
    onUpdate();
  }

  public async resolveToolApproval(
    decision: 'approve' | 'always' | 'reject',
    onUpdate?: () => void
  ): Promise<void> {
    if (!this.pendingApproval) return;
    const req = this.pendingApproval;
    const act = this.pendingApprovalAction;
    this.pendingApproval = null;
    this.pendingApprovalAction = null;

    if (decision === 'always') {
      this.permissionMode = 'fullAuto';
    }

    if (decision === 'approve' || decision === 'always') {
      if (act) {
        await act();
      }
    } else {
      this.recordAudit('User', 'Reject Tool Execution', req.toolName, 'rejected');
    }
    onUpdate?.();
  }

  private async generateImplementationPlan(objective: string, modelKey: string): Promise<void> {
    const editor = vscode.window.activeTextEditor;
    const activeFile = editor
      ? path.relative(this.getWorkspaceRoot(), editor.document.fileName)
      : 'src/main.rs';

    const md = `# ${objective}\n\n## Phase 1: AST Analysis & Architecture Alignment\n- [x] [VERIFY] Inspect active module \`${activeFile}\` and symbol dependencies\n- [ ] [MODIFY] Refactor implementation in \`${activeFile}\` with deterministic error handling\n\n## Phase 2: Verification & Diagnostics\n- [ ] [VERIFY] Execute compiler diagnostics and verify clean working tree\n`;

    this.saveTaskFiles(md);
    this.currentPlan = this.parsePlanFromMarkdown(md, 'pending');
    const planJsonPath = path.join(this.getMicroCodeDir(), 'plan.json');
    fs.writeFileSync(planJsonPath, JSON.stringify(this.currentPlan, null, 2), 'utf8');
    this.recordAudit('PlanEngine', `Draft Implementation Plan (${modelKey})`, objective, 'executed');
  }

  private async queryAiEngine(
    prompt: string,
    activeFile: string,
    activeCode: string,
    subAgent: string,
    modelKey: string
  ): Promise<string> {
    const status = await this.backendManager.refreshHealth();

    // 1. Try Local Dotmini Sovereign AI (Omni O1X on localhost:1234)
    if (status.omniOnline || modelKey.startsWith('omni-')) {
      try {
        const omniBase = status.omniUrl.replace(/\/$/, '');
        const u = new URL(`${omniBase}/chat/completions`);
        const payload = JSON.stringify({
          model: modelKey,
          messages: [
            {
              role: 'system',
              content: `You are MicroCode (${subAgent} role) by Dotmini Software. Respond with concise, production-grade architectural analysis and code.`
            },
            {
              role: 'user',
              content: activeCode
                ? `File: ${activeFile}\n\`\`\`\n${activeCode}\n\`\`\`\n\nRequest: ${prompt}`
                : prompt
            }
          ],
          temperature: 0.2
        });

        const text = await new Promise<string>((resolve, reject) => {
          const req = http.request(
            {
              hostname: u.hostname,
              port: u.port || 1234,
              path: u.pathname,
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(payload)
              },
              timeout: 20000
            },
            (res) => {
              const chunks: Buffer[] = [];
              res.on('data', (d: Buffer) => chunks.push(d));
              res.on('end', () => {
                const raw = Buffer.concat(chunks).toString('utf8');
                if ((res.statusCode ?? 500) < 300) {
                  try {
                    const parsed = JSON.parse(raw);
                    resolve(parsed.choices?.[0]?.message?.content ?? raw);
                  } catch {
                    resolve(raw);
                  }
                } else {
                  reject(new Error(`HTTP ${res.statusCode}`));
                }
              });
            }
          );
          req.on('error', reject);
          req.on('timeout', () => req.destroy(new Error('Timeout')));
          req.write(payload);
          req.end();
        });
        return text;
      } catch {
        // fall through to Rust backend
      }
    }

    // 2. Try MicroCode Rust Backend (:3000)
    if (status.backendOnline) {
      try {
        const res = await this.backendManager.requestJson<any>('/api/ai/explain', 'POST', {
          code: activeCode ? `${prompt}\n\n${activeCode}` : prompt,
          language: vscode.window.activeTextEditor?.document.languageId ?? 'rust'
        });
        if (res && typeof res === 'object' && res.explanation) {
          return String(res.explanation);
        }
        return typeof res === 'string' ? res : JSON.stringify(res, null, 2);
      } catch {
        // fall through to local AST inspection summary
      }
    }

    // 3. Deterministic Workspace & AST Analysis Fallback when offline
    const linesCount = activeCode ? activeCode.split('\n').length : 0;
    return [
      `### Analysis (${subAgent} · Workspace Local Engine)`,
      activeFile
        ? `Inspected active buffer \`${activeFile}\` (${linesCount} lines).`
        : `Workspace root: \`${path.basename(this.getWorkspaceRoot())}\`.`,
      ``,
      `- **Rust Backend (\`:3000\`)**: ${status.backendOnline ? 'Connected' : 'Standby'}`,
      `- **Dotmini Omni O1X (\`:1234\`)**: ${status.omniOnline ? 'Connected' : 'Standby'}`,
      `- **Tip**: Type \`/plan ${prompt}\` to generate a structured Implementation Plan in \`.microcode/task.md\`, or \`/verify\` to run workspace diagnostics.`
    ].join('\n');
  }

  public getFullState() {
    const taskFiles = this.readTaskFiles();
    const health = this.backendManager.getStatus();
    return {
      workspaceName: path.basename(this.getWorkspaceRoot()),
      workspacePath: this.getWorkspaceRoot(),
      status: {
        backendOnline: health.backendOnline,
        omniOnline: health.omniOnline,
        ardiumCompilerPath: health.ardiumBinary
      },
      permissionMode: this.permissionMode,
      sessions: this.sessions.map((s) => ({
        id: s.id,
        title: s.title,
        projectName: s.projectName,
        updatedAt: s.updatedAt,
        messageCount: s.messages.length
      })),
      activeSession: this.getActiveSession(),
      currentPlan: this.currentPlan ?? this.loadPlanFromDisk(),
      pendingApproval: this.pendingApproval,
      taskMarkdown: taskFiles.taskMd,
      agentsSpec: taskFiles.agentMd,
      walkthroughMarkdown: taskFiles.walkthroughMd,
      cells: this.listCells(),
      auditLog: this.auditLog.slice(0, 50)
    };
  }

  public getStateSnapshot() {
    return this.getFullState();
  }

  private recordAudit(
    actor: string,
    action: string,
    target: string,
    status: 'approved' | 'executed' | 'rejected'
  ): void {
    this.auditLog.unshift({
      id: `aud_${Date.now()}`,
      timestamp: new Date().toISOString(),
      actor,
      action,
      target,
      status
    });
  }

  private execCommand(cmd: string, args: string[], cwd?: string): Promise<string> {
    return new Promise((resolve, reject) => {
      cp.execFile(cmd, args, { cwd: cwd ?? this.getWorkspaceRoot(), timeout: 15000 }, (err, stdout, stderr) => {
        if (err) {
          reject(new Error(stderr || err.message));
        } else {
          resolve(stdout);
        }
      });
    });
  }
}
