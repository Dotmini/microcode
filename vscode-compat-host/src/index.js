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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const readline = __importStar(require("readline"));
const path = __importStar(require("path"));
const module_1 = __importDefault(require("module"));
const api_1 = require("./api");
const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: false
});
const emit = (method, params) => {
    console.log(JSON.stringify({ jsonrpc: '2.0', method, params }));
};
const vscode = (0, api_1.createMicroCodeShim)(emit);
const originalLoad = module_1.default._load;
module_1.default._load = function (request, parent, isMain) {
    if (request === 'vscode')
        return vscode;
    return originalLoad.call(this, request, parent, isMain);
};
global.vscode = vscode;
console.error('MicroCode Compat Host Started');
rl.on('line', (line) => {
    if (!line.trim())
        return;
    try {
        const msg = JSON.parse(line);
        void handleMessage(msg);
    }
    catch (e) {
        console.error('Failed to parse message:', e);
    }
});
async function handleMessage(msg) {
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
                    extensionUri: api_1.Uri.file(extRoot),
                    globalStorageUri: api_1.Uri.file(path.join(extRoot, '.storage'))
                };
                await Promise.resolve(extension.activate(context));
                sendResponse(msg.id, { status: 'activated', id });
            }
            else {
                sendError(msg.id, -32000, 'No activate function found');
            }
        }
        catch (e) {
            sendError(msg.id, -32000, `Failed to load: ${e.message}`);
        }
    }
    else if (msg.method === 'command/execute') {
        const { command, args = [] } = msg.params ?? {};
        try {
            const result = await vscode.commands.executeCommand(command, ...(Array.isArray(args) ? args : []));
            sendResponse(msg.id, { status: 'executed', command, result: result ?? null });
        }
        catch (e) {
            sendError(msg.id, -32000, `Command execution failed: ${e.message}`);
        }
    }
}
function sendResponse(id, result) {
    console.log(JSON.stringify({
        jsonrpc: '2.0',
        id,
        result
    }));
}
function sendError(id, code, message) {
    console.log(JSON.stringify({
        jsonrpc: '2.0',
        id,
        error: { code, message }
    }));
}
