//
//  DotnetService.swift
//  MicroCode
//
//  Created by SPU AI CLUB
//  Copyright © 2025 Dotmini Software. All rights reserved.
//

import Foundation

struct DotnetResult {
    let success: Bool
    let stdout: String
    let stderr: String
    let exitCode: Int
}

class DotnetService {
    static let shared = DotnetService()
    private let baseURL = "http://localhost:3000/api/dotnet"
    
    func createProject(template: String, name: String, outputDir: String) async throws -> DotnetResult {
        let url = URL(string: "\(baseURL)/new")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60 // 60 seconds timeout
        
        let body = [
            "template": template,
            "name": name,
            "output_dir": outputDir
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check HTTP response
            if let httpResponse = response as? HTTPURLResponse {
                guard httpResponse.statusCode == 200 else {
                    let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw NSError(
                        domain: "DotnetService",
                        code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(errorText)"]
                    )
                }
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            
            return DotnetResult(
                success: json["success"] as? Bool ?? false,
                stdout: json["stdout"] as? String ?? "No output",
                stderr: json["stderr"] as? String ?? "",
                exitCode: 0
            )
        } catch let error as NSError {
            // Better error messages
            if error.domain == NSURLErrorDomain && error.code == NSURLErrorCannotConnectToHost {
                throw NSError(
                    domain: "DotnetService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Cannot connect to backend server. Make sure MicroCode backend is running on port 3000."]
                )
            }
            throw error
        }
    }
    
    func buildProject(projectPath: String, configuration: String) async throws -> DotnetResult {
        let url = URL(string: "\(baseURL)/build")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "project_path": projectPath,
            "configuration": configuration
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        return DotnetResult(
            success: json["success"] as? Bool ?? false,
            stdout: json["stdout"] as? String ?? "",
            stderr: json["stderr"] as? String ?? "",
            exitCode: json["exit_code"] as? Int ?? -1
        )
    }
    
    func runProject(projectPath: String, args: [String]) async throws -> DotnetResult {
        let url = URL(string: "\(baseURL)/run")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "project_path": projectPath,
            "args": args
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        return DotnetResult(
            success: true,
            stdout: json["stdout"] as? String ?? "",
            stderr: json["stderr"] as? String ?? "",
            exitCode: json["exit_code"] as? Int ?? -1
        )
    }
    
    func cleanProject(projectPath: String) async throws -> DotnetResult {
        let url = URL(string: "\(baseURL)/clean")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["project_path": projectPath]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        return DotnetResult(
            success: json["success"] as? Bool ?? false,
            stdout: json["stdout"] as? String ?? "",
            stderr: json["stderr"] as? String ?? "",
            exitCode: 0
        )
    }
}
