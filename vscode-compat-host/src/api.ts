
export type HostEvent = (method: string, params: Record<string, unknown>) => void;

export function createMicroCodeShim(emit: HostEvent) {
    const registeredCommands = new Map<string, (...args: any[]) => any>();
    return {
    commands: {
        registerCommand: (command: string, callback: (...args: any[]) => any) => {
            registeredCommands.set(command, callback);
            emit('command/register', { command });
            return { dispose: () => registeredCommands.delete(command) };
        },
        executeCommand: (command: string, ...rest: any[]) => {
            const callback = registeredCommands.get(command);
            return Promise.resolve(callback?.(...rest));
        }
    },
    window: {
        showInformationMessage: (message: string) => {
            emit('window/info', { message });
            return Promise.resolve();
        },
        createOutputChannel: (name: string) => {
            return {
                appendLine: (val: string) => emit('window/output', { name, value: val }),
                show: () => { },
                dispose: () => { }
            };
        }
    },
    workspace: {
        getConfiguration: (section: string) => {
            return {
                get: (key: string, defaultValue?: any) => defaultValue
            };
        }
    }
};
}
