import * as vscode from 'vscode';
import * as cp from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import * as http from 'http';

export interface BackendHealthStatus {
  backendOnline: boolean;
  backendUrl: string;
  omniOnline: boolean;
  omniUrl: string;
  ardiumBinary: string | null;
}

export class BackendManager implements vscode.Disposable {
  private sidecarProcess: cp.ChildProcess | null = null;
  private statusBarItem: vscode.StatusBarItem;
  private outputChannel: vscode.OutputChannel;
  private pollTimer: NodeJS.Timeout | null = null;
  private lastStatus: BackendHealthStatus = {
    backendOnline: false,
    backendUrl: 'http://127.0.0.1:3000',
    omniOnline: false,
    omniUrl: 'http://127.0.0.1:1234/v1',
    ardiumBinary: null
  };

  private readonly statusListeners: Array<(status: BackendHealthStatus) => void> = [];

  constructor(private readonly context: vscode.ExtensionContext, outputChannel: vscode.OutputChannel) {
    this.outputChannel = outputChannel;
    this.statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
    this.statusBarItem.command = 'microcode.openWorkstation';
    this.statusBarItem.text = '$(terminal) MicroCode';
    this.statusBarItem.tooltip = 'Open MicroCode Sovereign Workstation (Split View)';
    this.statusBarItem.show();
  }

  public onDidChangeStatus(listener: (status: BackendHealthStatus) => void): vscode.Disposable {
    this.statusListeners.push(listener);
    listener(this.lastStatus);
    return {
      dispose: () => {
        const idx = this.statusListeners.indexOf(listener);
        if (idx >= 0) {
          this.statusListeners.splice(idx, 1);
        }
      }
    };
  }

  public getStatus(): BackendHealthStatus {
    return this.lastStatus;
  }

  public async initialize(): Promise<void> {
    await this.refreshHealth();

    const config = vscode.workspace.getConfiguration('microcode');
    const autoStart = config.get<boolean>('autoStartBackend', true);
    if (!this.lastStatus.backendOnline && autoStart) {
      await this.trySpawnSidecar(true);
    }

    this.pollTimer = setInterval(() => {
      void this.refreshHealth();
    }, 10000);
  }

  public async refreshHealth(): Promise<BackendHealthStatus> {
    const config = vscode.workspace.getConfiguration('microcode');
    const backendUrl = config.get<string>('backendUrl', 'http://127.0.0.1:3000');
    const omniUrl = config.get<string>('omniAiUrl', 'http://127.0.0.1:1234/v1');

    const [backendOnline, omniOnline] = await Promise.all([
      this.checkHttpEndpoint(`${backendUrl.replace(/\/$/, '')}/health`),
      this.checkHttpEndpoint(`${omniUrl.replace(/\/$/, '')}/models`)
    ]);

    const ardiumBinary = this.findArdiumBinary();

    this.lastStatus = {
      backendOnline,
      backendUrl,
      omniOnline,
      omniUrl,
      ardiumBinary
    };

    this.updateStatusBar();
    for (const listener of this.statusListeners) {
      listener(this.lastStatus);
    }
    return this.lastStatus;
  }

  public async trySpawnSidecar(silent = false): Promise<boolean> {
    const current = await this.refreshHealth();
    if (current.backendOnline) {
      if (!silent) {
        void vscode.window.showInformationMessage(`MicroCode Rust Backend is online at ${current.backendUrl}`);
      }
      return true;
    }

    const binaryPath = this.findBackendBinary();
    if (!binaryPath) {
      if (!silent) {
        void vscode.window.showWarningMessage(
          'MicroCode Rust Backend binary not found. Run `./build.sh --backend-only` or start the server on port 3000.'
        );
      }
      return false;
    }

    this.outputChannel.appendLine(`🚀 Starting MicroCode Rust Backend sidecar: ${binaryPath}`);
    this.sidecarProcess = cp.spawn(binaryPath, [], {
      cwd: path.dirname(binaryPath),
      env: { ...process.env, RUST_LOG: 'info' },
      stdio: ['ignore', 'pipe', 'pipe']
    });

    this.sidecarProcess.stdout?.on('data', (chunk: Buffer) => {
      this.outputChannel.append(chunk.toString());
    });
    this.sidecarProcess.stderr?.on('data', (chunk: Buffer) => {
      this.outputChannel.append(chunk.toString());
    });
    this.sidecarProcess.on('exit', (code) => {
      this.outputChannel.appendLine(`[MicroCode Backend exited with code ${code ?? 'null'}]`);
      this.sidecarProcess = null;
      void this.refreshHealth();
    });

    await new Promise((resolve) => setTimeout(resolve, 1500));
    const after = await this.refreshHealth();
    if (after.backendOnline && !silent) {
      void vscode.window.showInformationMessage('MicroCode Rust Backend started and connected.');
    }
    return after.backendOnline;
  }

  public findRepoRoot(): string {
    const wsFolder = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
    if (wsFolder && fs.existsSync(path.join(wsFolder, 'mcp-server.py'))) {
      return wsFolder;
    }
    const extParent = path.resolve(this.context.extensionPath, '..');
    if (fs.existsSync(path.join(extParent, 'mcp-server.py'))) {
      return extParent;
    }
    return wsFolder ?? this.context.extensionPath;
  }

  public findBackendBinary(): string | null {
    const repoRoot = this.findRepoRoot();
    const candidates = [
      '/Volumes/MAC/CodeTunerBuild/cargo-target/release/microcode-backend',
      '/Volumes/MAC/CodeTunerBuild/cargo-target/debug/microcode-backend',
      path.join(repoRoot, 'backend', 'target', 'release', 'microcode-backend'),
      path.join(repoRoot, 'backend', 'target', 'debug', 'microcode-backend'),
      path.join(repoRoot, 'backend', 'target', 'release', 'backend'),
      path.join(repoRoot, 'backend', 'target', 'debug', 'backend'),
      '/Applications/MicroCode.app/Contents/MacOS/microcode-backend',
      path.join(process.env.HOME ?? '', 'Applications/MicroCode.app/Contents/MacOS/microcode-backend')
    ];

    for (const candidate of candidates) {
      if (fs.existsSync(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  public findArdiumBinary(): string | null {
    const config = vscode.workspace.getConfiguration('microcode');
    const customPath = config.get<string>('ardiumBinaryPath', '').trim();
    if (customPath && fs.existsSync(customPath)) {
      return customPath;
    }

    if (process.env.ARDIUM_BIN && fs.existsSync(process.env.ARDIUM_BIN)) {
      return process.env.ARDIUM_BIN;
    }

    const home = process.env.HOME ?? '';
    const candidates = [
      path.join(home, '.cargo', 'bin', 'arc'),
      '/opt/homebrew/bin/arc',
      '/usr/local/bin/arc',
      '/usr/local/ardium/bin/arc',
      '/usr/local/bin/ardium',
      '/usr/local/ardium/ardium',
      '/opt/homebrew/bin/ardium'
    ];

    for (const candidate of candidates) {
      if (fs.existsSync(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  public async requestJson<T = any>(endpointPath: string, method: 'GET' | 'POST', body?: unknown): Promise<T> {
    const status = this.getStatus();
    const baseUrl = status.backendUrl.replace(/\/$/, '');
    const targetUrl = new URL(`${baseUrl}${endpointPath}`);

    return new Promise<T>((resolve, reject) => {
      const payload = body !== undefined ? JSON.stringify(body) : undefined;
      const req = http.request(
        {
          hostname: targetUrl.hostname,
          port: targetUrl.port || 80,
          path: targetUrl.pathname + targetUrl.search,
          method,
          headers: {
            'Content-Type': 'application/json',
            ...(payload ? { 'Content-Length': Buffer.byteLength(payload) } : {})
          },
          timeout: 15000
        },
        (res) => {
          const chunks: Buffer[] = [];
          res.on('data', (d: Buffer) => chunks.push(d));
          res.on('end', () => {
            const raw = Buffer.concat(chunks).toString('utf8');
            if ((res.statusCode ?? 500) >= 200 && (res.statusCode ?? 500) < 300) {
              try {
                resolve(raw ? (JSON.parse(raw) as T) : ({} as T));
              } catch {
                resolve(raw as unknown as T);
              }
            } else {
              reject(new Error(`HTTP ${res.statusCode}: ${raw}`));
            }
          });
        }
      );

      req.on('error', reject);
      req.on('timeout', () => {
        req.destroy(new Error('Request timed out'));
      });
      if (payload) {
        req.write(payload);
      }
      req.end();
    });
  }

  private checkHttpEndpoint(urlStr: string): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      try {
        const parsed = new URL(urlStr);
        const req = http.request(
          {
            hostname: parsed.hostname,
            port: parsed.port || 80,
            path: parsed.pathname + parsed.search,
            method: 'GET',
            timeout: 1500
          },
          (res) => {
            res.resume();
            resolve((res.statusCode ?? 500) < 500);
          }
        );
        req.on('error', () => resolve(false));
        req.on('timeout', () => {
          req.destroy();
          resolve(false);
        });
        req.end();
      } catch {
        resolve(false);
      }
    });
  }

  private updateStatusBar(): void {
    const parts: string[] = [];
    parts.push(this.lastStatus.backendOnline ? 'Rust:On' : 'Rust:Standby');
    if (this.lastStatus.omniOnline) {
      parts.push('Omni:O1X');
    }
    if (this.lastStatus.ardiumBinary) {
      parts.push('Ardium:v2.3');
    }
    this.statusBarItem.text = `$(sparkle) MicroCode (${parts.join(' · ')})`;
  }

  public dispose(): void {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
    if (this.sidecarProcess) {
      this.sidecarProcess.kill();
      this.sidecarProcess = null;
    }
    this.statusBarItem.dispose();
  }
}
