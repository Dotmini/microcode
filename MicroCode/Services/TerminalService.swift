//
//  TerminalService.swift
//  MicroCode
//
//  Created by SPU AI CLUB
//  Copyright © 2024 AIPRENEUR. All rights reserved.
//

import Foundation
import Combine

class TerminalService: ObservableObject {
    @Published var output: String = ""
    @Published var isRunning: Bool = false
    @Published var currentDirectory: String = FileManager.default.currentDirectoryPath
    
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    
    init() {
        startShell()
    }
    
    func startShell(directory: String? = nil) {
        // Stop existing process if any
        stop()
        
        // Find shell path
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-l"] // Login shell
        
        if let dir = directory, !dir.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
            self.currentDirectory = dir
        } else {
            // Default to home or fixed path if no workspace
            self.currentDirectory = FileManager.default.homeDirectoryForCurrentUser.path
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        }
        
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Handle Output
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                DispatchQueue.main.async {
                    self?.appendOutput(str)
                }
            }
        }
        
        // Handle Error
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                DispatchQueue.main.async {
                    self?.appendOutput(str)
                }
            }
        }
        
        do {
            try process.run()
            self.process = process
            self.inputPipe = inputPipe
            self.outputPipe = outputPipe
            self.errorPipe = errorPipe
            self.isRunning = true
            
            // Clean output for new shell
            self.output = "Terminal started in \(self.currentDirectory)\n"
        } catch {
            DispatchQueue.main.async {
                self.output += "Error starting terminal: \(error.localizedDescription)\n"
            }
        }
    }
    
    private func appendOutput(_ str: String) {
        self.output += str
        
        // Limit output size to prevent rendering lag (e.g., last 50,000 chars)
        let maxSize = 50_000
        if self.output.count > maxSize {
            self.output = String(self.output.suffix(maxSize))
        }
    }
    
    func setWorkingDirectory(_ directory: String) {
        guard directory != currentDirectory else { return }
        startShell(directory: directory)
    }
    
    func sendCommand(_ command: String) {
        guard isRunning, let inputPipe = inputPipe else { return }
        
        let cmdWithNewline = command + "\n"
        if let data = cmdWithNewline.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(data)
        }
    }
    
    func stop() {
        process?.terminate()
        process = nil
        isRunning = false
    }
    
    func clear() {
        output = ""
    }
}
