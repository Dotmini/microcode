//
//  RemoteTerminalView.swift
//  MicroCode
//
//  Created by Tirawat Nantamas
//  Copyright © 2025-2026 Dotmini Company Limited. All rights reserved.
//

import SwiftUI
import SwiftTerm
import AppKit

struct RemoteTerminalView: View {
    let server: RemoteConnectionConfig

    private var sshArgs: [String] {
        var args: [String] = ["-p", "\(server.port)"]
        if server.authType == .key, !server.keyPath.isEmpty {
            let expanded = (server.keyPath as NSString).expandingTildeInPath
            args.append(contentsOf: ["-i", expanded])
        }
        let target = server.username.isEmpty ? server.host : "\(server.username)@\(server.host)"
        args.append(target)
        return args
    }

    var body: some View {
        NativeSSHPTYView(executable: "/usr/bin/ssh", args: sshArgs)
            .id("\(server.host):\(server.port):\(server.username)")
    }
}

private struct NativeSSHPTYView: NSViewRepresentable {
    let executable: String
    let args: [String]

    func makeNSView(context: Context) -> MicroCodePTYTerminalView {
        let tv = MicroCodePTYTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        tv.configureNativeLook(fontName: "SF Mono", fontSize: 12.5, textColor: .white, backgroundColor: .black)
        let env = TerminalTabSession.buildTerminalEnvironment(workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path)
        tv.startProcess(executable: executable, args: args, environment: env)
        return tv
    }

    func updateNSView(_ nsView: MicroCodePTYTerminalView, context: Context) {}

    static func dismantleNSView(_ nsView: MicroCodePTYTerminalView, coordinator: ()) {
        nsView.send(data: [0x03, 0x04][...])
    }
}
