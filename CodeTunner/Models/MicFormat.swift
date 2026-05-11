//
//  MicFormat.swift
//  CodeTunner
//
//  Proprietary highly-compressed Notebook format for MicroCode (.mic)
//  Copyright © 2026 Dotmini Software. All rights reserved.
//

import Foundation

// MARK: - .mic File Structure

/// The root struct representing a .mic notebook file.
struct MicNotebook: Codable {
    var version: Int = 1
    var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var cells: [MicCell]
    
    // Convert from UI Model
    init(from model: NotebookModel) {
        self.id = model.id
        self.name = model.name
        self.createdAt = model.createdAt
        self.modifiedAt = model.modifiedAt
        self.cells = model.cells.map { MicCell(from: $0) }
    }
    
    // Convert to UI Model
    func toModel() -> NotebookModel {
        let model = NotebookModel(name: self.name)
        model.createdAt = self.createdAt
        model.modifiedAt = self.modifiedAt
        model.cells = self.cells.map { $0.toModel() }
        return model
    }
}

/// Represents an individual cell within the .mic format.
struct MicCell: Codable {
    var id: UUID
    var type: String
    var language: String
    var content: String
    var output: String
    var executionCount: Int?
    var colorTheme: String
    var isCollapsed: Bool
    var procedureMetadata: [String: String]? // Stored as JSON strings to bypass AnyCodable complexity
    var generatedCode: String
    
    // Convert from UI Model
    init(from model: NotebookCellModel) {
        self.id = model.id
        self.type = model.type.rawValue
        self.language = model.language.rawValue
        self.content = model.content
        self.output = model.output
        self.executionCount = model.executionCount
        self.colorTheme = model.colorTheme.rawValue
        self.isCollapsed = model.isCollapsed
        self.generatedCode = model.generatedCode
        
        if !model.procedureMetadata.isEmpty {
            var stringMap: [String: String] = [:]
            for (key, value) in model.procedureMetadata {
                if let data = try? JSONEncoder().encode(value), let str = String(data: data, encoding: .utf8) {
                    stringMap[key] = str
                }
            }
            self.procedureMetadata = stringMap
        }
    }
    
    // Convert to UI Model
    func toModel() -> NotebookCellModel {
        let cellType = NotebookCellModel.CellType(rawValue: self.type) ?? .code
        let cellLanguage = CellLanguage(rawValue: self.language) ?? .python
        let model = NotebookCellModel(type: cellType, language: cellLanguage, content: self.content)
        
        // We cannot override `id` directly if it's a `let` in ObservableObject,
        // but typically in UI we just let it generate a new UUID or use the old one if supported.
        // Let's assume NotebookCellModel.id is immutable, so we just copy properties.
        model.output = self.output
        model.executionCount = self.executionCount
        model.colorTheme = CellColorTheme(rawValue: self.colorTheme) ?? .none
        model.isCollapsed = self.isCollapsed
        model.generatedCode = self.generatedCode
        
        if let metadata = self.procedureMetadata {
            for (key, str) in metadata {
                if let data = str.data(using: .utf8), let anyVal = try? JSONDecoder().decode(AnyCodable.self, from: data) {
                    model.procedureMetadata[key] = anyVal
                }
            }
        }
        
        return model
    }
}
