import * as vscode from 'vscode';
import { ArdiumService } from './ardium/ardiumService';
import { BackendManager } from './backendManager';
import { McpRegistrationService } from './mcpRegistration';
import { MicroCodeCellCodeLensProvider, ParsedCodeCell } from './notebook/cellCodeLens';
import {
  MicroCodeNotebookSerializer,
  MicroCodePolyglotController
} from './notebook/polyglotController';
import { MicroCodeAgentSidebarProvider } from './views/agentSidebar';
import { MicroCodePlaygroundPanel } from './views/playgroundPanel';
import { WorkstationEngine } from './views/workstationEngine';

export async function activate(context: vscode.ExtensionContext): Promise<void> {
  const outputChannel = vscode.window.createOutputChannel('MicroCode Workstation');
  context.subscriptions.push(outputChannel);
  outputChannel.appendLine('MicroCode Workstation Extension v2.5.27 activating...');

  // 1. Backend & Toolchain Manager
  const backendManager = new BackendManager(context, outputChannel);
  context.subscriptions.push(backendManager);

  // 2. Ardium v2.3 Compiler, RAII Analyzer & LSP Service
  const ardiumService = new ArdiumService(backendManager, outputChannel);
  context.subscriptions.push(ardiumService);
  ardiumService.startLspIfAvailable();

  // 3. Inline Cell Mode (# %% / // %%) CodeLens & Executor
  const cellProvider = new MicroCodeCellCodeLensProvider(backendManager, outputChannel);
  if (vscode.languages && typeof vscode.languages.registerCodeLensProvider === 'function') {
    context.subscriptions.push(
      vscode.languages.registerCodeLensProvider({ scheme: 'file' }, cellProvider)
    );
  }

  // 4. Polyglot Notebook (.mcn) Serializer & Controller
  let polyglotController: MicroCodePolyglotController | undefined;
  if (
    vscode.workspace &&
    typeof vscode.workspace.registerNotebookSerializer === 'function' &&
    vscode.notebooks &&
    typeof vscode.notebooks.createNotebookController === 'function'
  ) {
    context.subscriptions.push(
      vscode.workspace.registerNotebookSerializer(
        'microcode-polyglot-notebook',
        new MicroCodeNotebookSerializer()
      )
    );
    polyglotController = new MicroCodePolyglotController(backendManager, cellProvider);
    context.subscriptions.push(polyglotController);
  }

  // 5. MCP Auto-Registration Service (35+ MicroCode Tools)
  const mcpService = new McpRegistrationService(backendManager, outputChannel);
  mcpService.registerNativeMcpProvider(context);

  // 6. Sovereign Workstation Engine & Agent Sidebar / Split Panel
  const workstationEngine = new WorkstationEngine(
    context,
    backendManager,
    cellProvider,
    outputChannel
  );
  const sidebarProvider = new MicroCodeAgentSidebarProvider(
    context,
    backendManager,
    workstationEngine
  );

  if (vscode.window && typeof vscode.window.registerWebviewViewProvider === 'function') {
    context.subscriptions.push(
      vscode.window.registerWebviewViewProvider(
        MicroCodeAgentSidebarProvider.viewType,
        sidebarProvider
      )
    );
  }

  // 7. Register Commands
  context.subscriptions.push(
    vscode.commands.registerCommand('microcode.openWorkstation', () => {
      sidebarProvider.openFullWorkstationPanel();
    }),
    vscode.commands.registerCommand('microcode.runArdium', () => ardiumService.runCurrentFile()),
    vscode.commands.registerCommand('microcode.compileArdium', () =>
      ardiumService.compileCurrentFile()
    ),
    vscode.commands.registerCommand('microcode.diagnoseArdium', () =>
      ardiumService.diagnoseDocument(undefined, false)
    ),
    vscode.commands.registerCommand('microcode.runCell', (cell?: ParsedCodeCell) =>
      cellProvider.executeCell(cell)
    ),
    vscode.commands.registerCommand(
      'microcode.openPlayground',
      (initialCode?: string, initialLanguage?: string) => {
        MicroCodePlaygroundPanel.show(cellProvider, initialCode, initialLanguage, workstationEngine);
      }
    ),
    vscode.commands.registerCommand('microcode.startBackend', () =>
      backendManager.trySpawnSidecar(false)
    ),
    vscode.commands.registerCommand('microcode.installMcpEverywhere', () =>
      mcpService.installMcpEverywhere()
    ),
    vscode.commands.registerCommand('microcode.createPolyglotNotebook', async () => {
      if (polyglotController) {
        await polyglotController.createSampleNotebook();
      } else {
        void vscode.window.showInformationMessage('Notebook API is not supported in this host.');
      }
    })
  );

  // 8. Start background health check & optional Rust sidecar
  void backendManager.initialize();
  outputChannel.appendLine('MicroCode Workstation Extension ready.');
}

export function deactivate(): void {
  // Disposables registered in context.subscriptions are automatically cleaned up.
}
