import * as vscode from 'vscode';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { BackendManager } from './backendManager';

export class McpRegistrationService {
  constructor(
    private readonly backendManager: BackendManager,
    private readonly outputChannel: vscode.OutputChannel
  ) {}

  public registerNativeMcpProvider(context: vscode.ExtensionContext): void {
    const lmNamespace = (vscode as any).lm;
    if (lmNamespace && typeof lmNamespace.registerMcpServerDefinitionProvider === 'function') {
      try {
        const disposable = lmNamespace.registerMcpServerDefinitionProvider('microcode.mcpProvider', {
          provideMcpServerDefinitions: async () => {
            const mcpScript = this.resolveMcpScriptPath();
            const workspaceRoot = this.backendManager.findRepoRoot();
            return [
              {
                label: 'MicroCode Workspace & Polyglot Tools (35+ Tools)',
                command: 'python3',
                args: [mcpScript],
                env: {
                  MICROCODE_WORKSPACE: workspaceRoot
                }
              }
            ];
          }
        });
        context.subscriptions.push(disposable);
        this.outputChannel.appendLine('🔌 Registered MicroCode MCP Server Provider with IDE Language Model API.');
      } catch (err: any) {
        this.outputChannel.appendLine(`ℹ️ MCP native provider registration skipped: ${err?.message ?? String(err)}`);
      }
    }
  }

  public resolveMcpScriptPath(): string {
    const repoRoot = this.backendManager.findRepoRoot();
    const candidates = [
      path.join(repoRoot, 'mcp-server.py'),
      '/Applications/MicroCode.app/Contents/Resources/mcp-server.py',
      path.join(os.homedir(), 'Applications/MicroCode.app/Contents/Resources/mcp-server.py')
    ];
    for (const candidate of candidates) {
      if (fs.existsSync(candidate)) {
        return candidate;
      }
    }
    return path.join(repoRoot, 'mcp-server.py');
  }

  public async installMcpEverywhere(): Promise<void> {
    const mcpScript = this.resolveMcpScriptPath();
    const workspaceRoot =
      vscode.workspace.workspaceFolders?.[0]?.uri.fsPath ?? this.backendManager.findRepoRoot();

    const serverEntry = {
      command: 'python3',
      args: [mcpScript],
      env: {
        MICROCODE_WORKSPACE: workspaceRoot
      }
    };

    const updatedTargets: string[] = [];

    // 1. Workspace .vscode/mcp.json (VS Code 1.99+ / GitHub Copilot MCP)
    if (vscode.workspace.workspaceFolders?.[0]) {
      const vscodeMcpPath = path.join(workspaceRoot, '.vscode', 'mcp.json');
      this.mergeJsonFile(vscodeMcpPath, 'servers', 'microcode', {
        type: 'stdio',
        ...serverEntry
      });
      updatedTargets.push('.vscode/mcp.json');

      // 2. Workspace .cursor/mcp.json (Cursor IDE)
      const cursorMcpPath = path.join(workspaceRoot, '.cursor', 'mcp.json');
      this.mergeJsonFile(cursorMcpPath, 'mcpServers', 'microcode', serverEntry);
      updatedTargets.push('.cursor/mcp.json');
    }

    // 3. Windsurf global MCP config (~/.codeium/windsurf/mcp_config.json)
    const windsurfDir = path.join(os.homedir(), '.codeium', 'windsurf');
    if (fs.existsSync(path.join(os.homedir(), '.codeium'))) {
      const windsurfMcpPath = path.join(windsurfDir, 'mcp_config.json');
      this.mergeJsonFile(windsurfMcpPath, 'mcpServers', 'microcode', serverEntry);
      updatedTargets.push('~/.codeium/windsurf/mcp_config.json');
    }

    this.outputChannel.show(true);
    this.outputChannel.appendLine(`✅ Configured MicroCode MCP Server (${mcpScript}) in: ${updatedTargets.join(', ')}`);
    void vscode.window.showInformationMessage(
      `MicroCode MCP (35+ tools) configured for: ${updatedTargets.join(', ')}`
    );
  }

  private mergeJsonFile(filePath: string, rootKey: string, serverKey: string, value: unknown): void {
    try {
      const dir = path.dirname(filePath);
      fs.mkdirSync(dir, { recursive: true });
      let current: Record<string, any> = {};
      if (fs.existsSync(filePath)) {
        try {
          current = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        } catch {
          current = {};
        }
      }
      if (!current[rootKey] || typeof current[rootKey] !== 'object') {
        current[rootKey] = {};
      }
      current[rootKey][serverKey] = value;
      fs.writeFileSync(filePath, JSON.stringify(current, null, 2) + '\n', 'utf8');
    } catch (err: any) {
      this.outputChannel.appendLine(`⚠️ Failed to update ${filePath}: ${err?.message ?? String(err)}`);
    }
  }
}
