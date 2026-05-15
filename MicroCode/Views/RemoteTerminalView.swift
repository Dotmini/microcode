//
//  RemoteTerminalView.swift
//  MicroCode
//
//  Created by SPU AI CLUB
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
//

import SwiftUI

import SwiftUI

struct RemoteTerminalView: View {
    let server: RemoteConnectionConfig
    // Note: The websocket URL in TerminalWebView is currently hardcoded to localhost:3000/ws/terminal
    // In a real remote scenario, we would proxy or SSH tunnel this.
    // Since the requirement is "Realtime like macOS Native" for local or remote, 
    // and we built the backend PTY to map to local shell or potentially remote SSH,
    // we use the backend's websocket for now.
    
    var body: some View {
        TerminalWebView(url: URL(string: "http://localhost:3000")!)
    }
}
