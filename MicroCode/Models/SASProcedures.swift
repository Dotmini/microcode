import SwiftUI

enum SASModuleType: String, CaseIterable, Identifiable {
    case dataStep = "DATA Step"
    case procSql = "PROC SQL"
    case procMeans = "PROC MEANS"
    case procReg = "PROC REG"
    case procFreq = "PROC FREQ"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .dataStep: return "tablecells.fill"
        case .procSql: return "cylinder.fill"
        case .procMeans: return "sum"
        case .procReg: return "chart.xyaxis.line"
        case .procFreq: return "chart.bar.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .dataStep: return .blue
        case .procSql: return .purple
        case .procMeans: return .green
        case .procReg: return .orange
        case .procFreq: return .pink
        }
    }
}

struct SASProcedureParams: Codable {
    var moduleType: String
    var inputTable: String = ""
    var outputTable: String = ""
    var selectedVariables: [String] = []
    var targetVariable: String = ""
    var groupBy: [String] = []
    var whereClause: String = ""
    var customCode: String = ""
    
    // Statistics for PROC MEANS
    var stats: [String] = ["MEAN", "STD", "N", "MIN", "MAX"]
    
    // Logic for DATA Step
    var dataStepLogic: [DataStepOperation] = []
}

struct DataStepOperation: Identifiable, Codable {
    let id = UUID()
    var type: OperationType
    var field: String = ""
    var formula: String = ""
    
    enum OperationType: String, Codable, CaseIterable {
        case addColumn = "Add Column"
        case dropColumn = "Drop Column"
        case filter = "Filter Row"
        case rename = "Rename"
    }
}
