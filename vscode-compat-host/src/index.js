"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const readline = require("readline");
const api_1 = require("./api");
const Module = require("module");

// Hook Node.js require('vscode')
const originalRequire = Module.prototype.require;
Module.prototype.require = function(request) {
    if (request === 'vscode') {
        return api_1.microcodeShim;
    }
    return originalRequire.apply(this, arguments);
};

// Also polyfill global vscode
global.vscode = api_1.microcodeShim;

const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: false
});

console.error("MicroCode Compat Host Started");

rl.on('line', (line) => {
    if (!line.trim()) return;
    try {
        const msg = JSON.parse(line);
        handleMessage(msg);
    } catch (e) {
        console.error("Failed to parse message:", e);
    }
});

async function handleMessage(msg) {
    if (msg.method === 'ext/load') {
        const { id, path, root } = msg.params;
        try {
            console.error(`Loading extension [${id}] at: ${path}`);
            let extension;
            try {
                extension = require(path);
            } catch (loadErr) {
                if (path && path.endsWith('.json')) {
                    sendResponse(msg.id, { status: 'activated', type: 'theme', file: path });
                    return;
                }
                try {
                    extension = await import(path);
                } catch (importErr) {
                    throw loadErr;
                }
            }

            if (extension && typeof extension.activate === 'function') {
                const fs = require('fs');
                const nodePath = require('path');
                let pkgJson = {};
                try {
                    const p = nodePath.join(root || '', 'package.json');
                    if (fs.existsSync(p)) pkgJson = JSON.parse(fs.readFileSync(p, 'utf8'));
                } catch (e) {}

                const context = {
                    subscriptions: [],
                    workspaceState: { get: () => undefined, update: () => Promise.resolve() },
                    globalState: { get: () => undefined, update: () => Promise.resolve(), setKeysForSync: () => {} },
                    extensionUri: api_1.microcodeShim.Uri.file(root || ''),
                    extensionPath: root || '',
                    extensionMode: 1,
                    extension: {
                        id,
                        extensionUri: api_1.microcodeShim.Uri.file(root || ''),
                        extensionPath: root || '',
                        isActive: true,
                        packageJSON: pkgJson,
                        exports: {}
                    },
                    asAbsolutePath: (relPath) => (root ? root + '/' + relPath : relPath)
                };
                try {
                    const result = extension.activate(context);
                    if (result && typeof result.then === 'function') {
                        result.then(
                            () => sendResponse(msg.id, { status: 'activated', async: true }),
                            (err) => sendResponse(msg.id, { status: 'activated', warning: err && err.message })
                        );
                    } else {
                        sendResponse(msg.id, { status: 'activated' });
                    }
                } catch (actErr) {
                    console.error(`Activation notice for ${id}:`, actErr.message);
                    sendResponse(msg.id, { status: 'activated', warning: actErr.message });
                }
            } else {
                sendResponse(msg.id, { status: 'activated', declarative: true });
            }
        } catch (e) {
            console.error(`Error loading ${id}:`, e.message);
            sendError(msg.id, -32000, `Failed to load: ${e.message}`);
        }
    } else if (msg.method === 'command/execute') {
        const { command, args } = msg.params || {};
        api_1.microcodeShim.commands.executeCommand(command, ...(args || []))
            .then(
                (res) => sendResponse(msg.id, { status: 'success', command, result: res }),
                (err) => sendError(msg.id, -32001, err ? err.message : 'Command execution failed')
            );
    }
}

function sendResponse(id, result) {
    console.log(JSON.stringify({
        jsonrpc: "2.0",
        id,
        result
    }));
}

function sendError(id, code, message) {
    console.log(JSON.stringify({
        jsonrpc: "2.0",
        id,
        error: { code, message }
    }));
}
