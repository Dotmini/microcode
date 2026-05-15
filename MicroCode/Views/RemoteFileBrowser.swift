//
//  RemoteFileBrowser.swift
//  MicroCode
//
//  Created by SPU AI CLUB
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
//

import SwiftUI

struct RemoteFileBrowser: View {
    let server: RemoteConnectionConfig
    @State private var remoteFiles: [FileInfo] = []
    @State private var currentPath: String = "/"

    var body: some View {
        VStack(spacing: 0) {
            // Path bar
            HStack {
                Text("Path:")
                    .foregroundColor(.secondary)
                TextField("", text: $currentPath)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { refreshFiles() }
                Button("Go") {
                    refreshFiles()
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            List {
                if currentPath != "/" {
                     Button("..") {
                         let components = currentPath.split(separator: "/")
                         if components.count > 0 {
                             currentPath = "/" + components.dropLast().joined(separator: "/")
                             if currentPath.isEmpty { currentPath = "/" }
                             refreshFiles()
                         }
                     }
                }
                
                ForEach(remoteFiles, id: \.name) { file in
                    Button(action: {
                        if file.isDirectory {
                            currentPath = (currentPath == "/" ? "" : currentPath) + "/" + file.name
                            refreshFiles()
                        }
                    }) {
                        HStack {
                            Image(systemName: file.isDirectory ? "folder.fill" : "doc")
                                .foregroundColor(file.isDirectory ? .blue : .secondary)
                            Text(file.name)
                            Spacer()
                            Text(file.isDirectory ? "Folder" : ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            refreshFiles()
        }
    }
    
    func refreshFiles() {
        Task {
            do {
                let files = try await BackendService.shared.listRemoteFiles(id: server.id.uuidString, path: currentPath)
                await MainActor.run {
                    self.remoteFiles = files.sorted { $0.isDirectory && !$1.isDirectory }
                }
            } catch {
                print("Failed to list files: \(error)")
            }
        }
    }
}
