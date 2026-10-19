import * as readline from 'readline';
import * as path from 'path';
import Module from 'module';
import { createMicroCodeShim, Uri } from './api';

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
  terminal: false
});

const emit = (method: string, params: Record<string, unknown>) => {
  console.log(JSON.stringify({ jsonrpc: '2.0', method, params }));
};

const vscode = createMicroCodeShim(emit);
const originalLoad = (Module as any)._load;
(Module as any)._load = function (request: string, parent: unknown, isMain: boolean) {
  if (request === 'vscode') return vscode;
  return originalLoad.call(this, request, parent, isMain);
};
(global as any).vscode = vscode;

console.error('MicroCode Compat Host Started');

rl.on('line', (line: string) => {
  if (!line.trim()) return;
  try {
    const msg = JSON.parse(line);
    void handleMessage(msg);
  } catch (e) {
    console.error('Failed to parse message:', e);
  }
});

async function handleMessage(msg: any): Promise<void> {
  if (msg.method === 'ext/load') {
    const { path: extMainPath, id, root } = msg.params;
    try {
      console.error(`Loading extension at: ${extMainPath}`);
      const extension = require(extMainPath);
      if (extension.activate) {
        const extRoot = root || path.dirname(extMainPath);
        const context = {
          subscriptions: [],
          extensionPath: extRoot,
          extensionUri: Uri.file(extRoot),
          globalStorageUri: Uri.file(path.join(extRoot, '.storage'))
        };
        await Promise.resolve(extension.activate(context));
        sendResponse(msg.id, { status: 'activated', id });
      } else {
        sendError(msg.id, -32000, 'No activate function found');
      }
    } catch (e: any) {
      sendError(msg.id, -32000, `Failed to load: ${e.message}`);
    }
  } else if (msg.method === 'command/execute') {
    const { command, args = [] } = msg.params ?? {};
    try {
      const result = await vscode.commands.executeCommand(command, ...(Array.isArray(args) ? args : []));
      sendResponse(msg.id, { status: 'executed', command, result: result ?? null });
    } catch (e: any) {
      sendError(msg.id, -32000, `Command execution failed: ${e.message}`);
    }
  }
}

function sendResponse(id: number, result: any) {
  console.log(
    JSON.stringify({
      jsonrpc: '2.0',
      id,
      result
    })
  );
}

function sendError(id: number, code: number, message: string) {
  console.log(
    JSON.stringify({
      jsonrpc: '2.0',
      id,
      error: { code, message }
    })
  );
}
