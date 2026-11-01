//
//  AgentExecutionContext.swift
//  MicroCode
//
//  Task-local execution isolation context for multi-workspace, multi-window,
//  and background chat agent runs. Guarantees that every tool invocation,
//  sandbox check, shell working directory, and transcript persistence remains
//  pinned to the exact workspace and conversation that initiated the run,
//  even if the user switches chats, projects, or windows mid-generation.
//

import Foundation

enum AgentExecutionContext {
    @TaskLocal static var workspaceRoot: String?
    @TaskLocal static var chatId: String?
    @TaskLocal static var scopeRawValue: String?
}
