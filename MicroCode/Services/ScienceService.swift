import Foundation
import SceneKit

struct ProteinAtom: Sendable {
    let x: Float
    let y: Float
    let z: Float
    let element: String
    let atomName: String
    let residueName: String
    let residueID: String
    let chainID: String
    let confidence: Float?
}

struct ProteinStructureDocument: Sendable {
    let name: String
    let format: String
    let atoms: [ProteinAtom]
    let sourceAtomCount: Int
    let wasDownsampled: Bool

    var chains: [String] {
        var values = Set<String>()
        for atom in atoms { values.insert(atom.chainID) }
        return values.sorted()
    }
    var residueCount: Int {
        var values = Set<String>()
        for atom in atoms { values.insert(atom.chainID + ":" + atom.residueID) }
        return values.count
    }
    var ligandCount: Int {
        let standard = Set(["ALA", "ARG", "ASN", "ASP", "CYS", "GLN", "GLU", "GLY", "HIS", "ILE", "LEU", "LYS", "MET", "PHE", "PRO", "SER", "THR", "TRP", "TYR", "VAL", "A", "C", "G", "U", "DA", "DC", "DG", "DT"])
        var ligands = Set<String>()
        for atom in atoms where !standard.contains(atom.residueName) && atom.residueName != "HOH" {
            ligands.insert(atom.chainID + ":" + atom.residueID + ":" + atom.residueName)
        }
        return ligands.count
    }
    var meanConfidence: Float? {
        var total: Float = 0
        var count = 0
        for atom in atoms {
            if let confidence = atom.confidence { total += confidence; count += 1 }
        }
        return count == 0 ? nil : total / Float(count)
    }
}

struct ScienceProjectContext: Sendable {
    let workspaceName: String
    let fileCount: Int
    let structures: [String]
    let sequences: [String]
    let results: [String]
    let papers: [String]
    let datasets: [String]
    let workflows: [String]

    var compactDescription: String {
        func row(_ name: String, _ values: [String]) -> String {
            values.isEmpty ? "\(name): none" : "\(name) (\(values.count)): \(values.prefix(18).joined(separator: ", "))"
        }
        return [
            "Scientific workspace: \(workspaceName) (\(fileCount) indexed files)",
            row("Structures", structures), row("Sequences/MSA", sequences),
            row("Results and figures", results), row("Papers/LaTeX", papers),
            row("Datasets", datasets), row("Analysis workflows", workflows)
        ].joined(separator: "\n")
    }
}

enum ScienceServiceError: LocalizedError {
    case unsupportedFormat(String)
    case fileTooLarge(Int)
    case noAtoms
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext): return "Unsupported scientific structure format: \(ext)"
        case .fileTooLarge(let bytes): return "Structure file is too large (\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)))."
        case .noAtoms: return "No atomic coordinates were found in this file."
        case .malformed(let reason): return reason
        }
    }
}

enum ScienceService {
    static let maximumFileBytes = 64 * 1024 * 1024
    static let maximumRenderedAtoms = 100_000

    @inline(never)
    static func indexWorkspace(at root: URL) -> ScienceProjectContext {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isHiddenKey]
        let skipped = Set([".git", ".build", "build", "DerivedData", "node_modules", "__pycache__", ".venv", "venv"])
        var structures: [String] = [], sequences: [String] = [], results: [String] = []
        var papers: [String] = [], datasets: [String] = [], workflows: [String] = []
        var count = 0
        guard let iterator = manager.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }) else {
            return ScienceProjectContext(workspaceName: root.lastPathComponent, fileCount: 0, structures: [], sequences: [], results: [], papers: [], datasets: [], workflows: [])
        }
        for case let url as URL in iterator {
            if skipped.contains(url.lastPathComponent) { iterator.skipDescendants(); continue }
            guard count < 4_000 else { break }
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else { continue }
            count += 1
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            let ext = url.pathExtension.lowercased()
            if ["pdb", "ent", "cif", "mmcif"].contains(ext) { structures.append(relative) }
            else if ["fa", "faa", "fna", "fasta", "a3m"].contains(ext) { sequences.append(relative) }
            else if ["png", "jpg", "jpeg", "svg", "html", "htm"].contains(ext) { results.append(relative) }
            else if ["tex", "bib", "pdf", "md"].contains(ext) { papers.append(relative) }
            else if ["csv", "tsv", "parquet", "h5", "h5ad", "json", "npy", "npz"].contains(ext) { datasets.append(relative) }
            else if ["py", "r", "jl", "ipynb", "sh"].contains(ext) { workflows.append(relative) }
        }
        return ScienceProjectContext(workspaceName: root.lastPathComponent, fileCount: count, structures: structures.sorted(), sequences: sequences.sorted(), results: results.sorted(), papers: papers.sorted(), datasets: datasets.sorted(), workflows: workflows.sorted())
    }

    @inline(never)
    static func loadStructure(at url: URL) throws -> ProteinStructureDocument {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile != false else { throw ScienceServiceError.malformed("Not a regular file.") }
        let byteCount = values.fileSize ?? 0
        guard byteCount <= maximumFileBytes else { throw ScienceServiceError.fileTooLarge(byteCount) }
        let text = try String(contentsOf: url, encoding: .utf8)
        let ext = url.pathExtension.lowercased()
        let parsed: [ProteinAtom]
        switch ext {
        case "pdb", "ent": parsed = parsePDB(text)
        case "cif", "mmcif": parsed = parseMMCIF(text)
        default: throw ScienceServiceError.unsupportedFormat(ext)
        }
        guard !parsed.isEmpty else { throw ScienceServiceError.noAtoms }
        let sampled = downsample(parsed, limit: maximumRenderedAtoms)
        return ProteinStructureDocument(
            name: url.lastPathComponent,
            format: ext == "pdb" || ext == "ent" ? "PDB" : "PDBx/mmCIF",
            atoms: sampled,
            sourceAtomCount: parsed.count,
            wasDownsampled: sampled.count != parsed.count
        )
    }

    @inline(never)
    static func inspectFile(at url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        if ["pdb", "ent", "cif", "mmcif"].contains(ext) {
            let structure = try loadStructure(at: url)
            let confidence = structure.meanConfidence.map { String(format: "%.1f", $0) } ?? "not present"
            return """
            Scientific structure: \(structure.name)
            Format: \(structure.format)
            Atoms: \(structure.sourceAtomCount)
            Residues: \(structure.residueCount)
            Chains: \(structure.chains.joined(separator: ", "))
            Non-standard residues/ligands: \(structure.ligandCount)
            Mean B-factor/confidence: \(confidence)
            Viewer downsampled: \(structure.wasDownsampled ? "yes" : "no")
            """
        }
        if ["fa", "faa", "fna", "fasta", "a3m"].contains(ext) {
            let text = try String(contentsOf: url, encoding: .utf8)
            let records = parseFASTA(text)
            let total = records.reduce(0) { $0 + $1.sequence.count }
            let alphabet = Set(records.flatMap { $0.sequence.uppercased() })
            return "FASTA/A3M: \(records.count) sequence(s), \(total) total symbols, alphabet: \(String(alphabet.sorted()))"
        }
        if ext == "json" {
            return try validateAlphaFoldInput(at: url)
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return "Scientific artifact: \(url.lastPathComponent), \(values.fileSize ?? 0) bytes. No specialized parser is available."
    }

    @inline(never)
    static func validateAlphaFoldInput(at url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            throw ScienceServiceError.malformed("AlphaFold 3 code input must be one JSON object per file.")
        }
        var issues: [String] = []
        let name = root["name"] as? String ?? ""
        if name.isEmpty { issues.append("missing non-empty 'name'") }
        if root["dialect"] as? String != "alphafold3" { issues.append("'dialect' must be 'alphafold3'") }
        let version = root["version"] as? Int ?? 0
        if !(1...4).contains(version) { issues.append("'version' must be 1...4") }
        let seeds = root["modelSeeds"] as? [Any] ?? []
        if seeds.isEmpty { issues.append("at least one model seed is required") }
        let sequences = root["sequences"] as? [[String: Any]] ?? []
        if sequences.isEmpty { issues.append("at least one sequence entity is required") }
        var ids = Set<String>()
        for (index, entity) in sequences.enumerated() {
            let supported = ["protein", "rna", "dna", "ligand"].filter { entity[$0] != nil }
            if supported.count != 1 { issues.append("sequence \(index + 1) must contain exactly one supported entity") }
            if let body = supported.first.flatMap({ entity[$0] as? [String: Any] }) {
                let entityIDs: [String]
                if let id = body["id"] as? String { entityIDs = [id] }
                else { entityIDs = body["id"] as? [String] ?? [] }
                if entityIDs.isEmpty { issues.append("sequence \(index + 1) has no id") }
                for id in entityIDs {
                    if !ids.insert(id).inserted { issues.append("duplicate entity id '\(id)'") }
                }
            }
        }
        if issues.isEmpty {
            return "Valid AlphaFold 3 input: '\(name)', version \(version), \(sequences.count) entities, \(seeds.count) seed(s)."
        }
        return "AlphaFold 3 input has \(issues.count) issue(s):\n- " + issues.joined(separator: "\n- ")
    }

    @inline(never)
    static func makeScene(for structure: ProteinStructureDocument, showBackbone: Bool = true) -> SCNScene {
        let scene = SCNScene()
        let root = SCNNode()
        scene.rootNode.addChildNode(root)
        guard !structure.atoms.isEmpty else { return scene }

        var center = SIMD3<Float>(repeating: 0)
        for atom in structure.atoms { center += SIMD3<Float>(atom.x, atom.y, atom.z) }
        center /= Float(structure.atoms.count)
        var vertices: [SCNVector3] = []
        var colors: [SIMD4<Float>] = []
        vertices.reserveCapacity(structure.atoms.count)
        colors.reserveCapacity(structure.atoms.count)
        for atom in structure.atoms {
            vertices.append(SCNVector3(atom.x - center.x, atom.y - center.y, atom.z - center.z))
            colors.append(color(for: atom.element))
        }
        let vertexData = vertices.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let vertexSource = SCNGeometrySource(data: vertexData, semantic: .vertex, vectorCount: vertices.count, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<SCNVector3>.stride)
        let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: colors.count, usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<SIMD4<Float>>.stride)
        var indices: [Int32] = []
        indices.reserveCapacity(vertices.count)
        for index in 0..<vertices.count { indices.append(Int32(index)) }
        let indexData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let points = SCNGeometryElement(data: indexData, primitiveType: .point, primitiveCount: vertices.count, bytesPerIndex: MemoryLayout<Int32>.size)
        points.pointSize = showBackbone ? 1.5 : 5
        points.minimumPointScreenSpaceRadius = 1
        points.maximumPointScreenSpaceRadius = 8
        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [points])
        geometry.firstMaterial?.lightingModel = .constant
        if !showBackbone { root.addChildNode(SCNNode(geometry: geometry)) }

        if showBackbone {
            let backbone = structure.atoms.filter {
                let name = $0.atomName.uppercased()
                return name == "CA" || name == "P"
            }
            let palette: [NSColor] = [
                NSColor(calibratedRed: 0.36, green: 0.64, blue: 0.86, alpha: 1),
                NSColor(calibratedRed: 0.45, green: 0.72, blue: 0.57, alpha: 1),
                NSColor(calibratedRed: 0.78, green: 0.59, blue: 0.39, alpha: 1),
                NSColor(calibratedRed: 0.67, green: 0.52, blue: 0.76, alpha: 1)
            ]
            let grouped = Dictionary(grouping: backbone, by: \.chainID)
            for (chainIndex, chainID) in grouped.keys.sorted().enumerated() {
                let atoms = grouped[chainID] ?? []
                let material = SCNMaterial()
                material.diffuse.contents = palette[chainIndex % palette.count]
                material.roughness.contents = 0.48
                material.metalness.contents = 0.04
                for atom in atoms {
                    let sphere = SCNSphere(radius: 0.23)
                    sphere.segmentCount = 8
                    sphere.firstMaterial = material
                    let node = SCNNode(geometry: sphere)
                    node.position = SCNVector3(atom.x - center.x, atom.y - center.y, atom.z - center.z)
                    root.addChildNode(node)
                }
                if atoms.count > 1 {
                    for index in 1..<atoms.count {
                        let a = SIMD3<Float>(atoms[index - 1].x, atoms[index - 1].y, atoms[index - 1].z) - center
                        let b = SIMD3<Float>(atoms[index].x, atoms[index].y, atoms[index].z) - center
                        let distance = simd_distance(a, b)
                        guard distance > 0.01, distance < 8 else { continue }
                        let cylinder = SCNCylinder(radius: 0.13, height: CGFloat(distance))
                        cylinder.radialSegmentCount = 8
                        cylinder.firstMaterial = material
                        let node = SCNNode(geometry: cylinder)
                        node.position = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
                        node.look(at: SCNVector3(b.x, b.y, b.z), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
                        root.addChildNode(node)
                    }
                }
            }
            if backbone.isEmpty { root.addChildNode(SCNNode(geometry: geometry)) }
        }

        let camera = SCNCamera()
        camera.zFar = 100_000
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        var extent = Float(10)
        for vertex in vertices {
            extent = Swift.max(extent, Float(abs(vertex.x)), Float(abs(vertex.y)), Float(abs(vertex.z)))
        }
        cameraNode.position = SCNVector3(0, 0, Swift.max(Float(30), extent * 2.8))
        scene.rootNode.addChildNode(cameraNode)
        scene.background.contents = NSColor.black
        return scene
    }

    @inline(never)
    private static func parsePDB(_ text: String) -> [ProteinAtom] {
        var atoms: [ProteinAtom] = []
        atoms.reserveCapacity(min(text.count / 80, maximumRenderedAtoms))
        var enteredModel = false
        for line in text.split(whereSeparator: \ .isNewline) {
            if line.hasPrefix("MODEL") {
                if enteredModel { break }
                enteredModel = true
                continue
            }
            if line.hasPrefix("ENDMDL") && enteredModel { break }
            guard line.hasPrefix("ATOM") || line.hasPrefix("HETATM") else { continue }
            let value = String(line)
            func field(_ range: Range<Int>) -> String {
                guard value.count >= range.lowerBound else { return "" }
                let start = value.index(value.startIndex, offsetBy: min(range.lowerBound, value.count))
                let end = value.index(value.startIndex, offsetBy: min(range.upperBound, value.count))
                return String(value[start..<end]).trimmingCharacters(in: .whitespaces)
            }
            guard let x = Float(field(30..<38)), let y = Float(field(38..<46)), let z = Float(field(46..<54)) else { continue }
            let alternate = field(16..<17)
            guard alternate.isEmpty || alternate == "A" else { continue }
            let atomName = field(12..<16)
            let inferredElement = atomName.filter(\.isLetter).prefix(1).uppercased()
            atoms.append(ProteinAtom(x: x, y: y, z: z, element: field(76..<78).uppercased().isEmpty ? inferredElement : field(76..<78).uppercased(), atomName: atomName, residueName: field(17..<20).uppercased(), residueID: field(22..<27), chainID: field(21..<22).isEmpty ? "_" : field(21..<22), confidence: Float(field(60..<66))))
        }
        return atoms
    }

    @inline(never)
    private static func parseMMCIF(_ text: String) -> [ProteinAtom] {
        let lines = text.split(whereSeparator: \ .isNewline).map(String.init)
        var i = 0
        while i < lines.count {
            guard lines[i].trimmingCharacters(in: .whitespaces) == "loop_" else { i += 1; continue }
            i += 1
            var headers: [String] = []
            while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("_atom_site.") {
                headers.append(lines[i].trimmingCharacters(in: .whitespaces))
                i += 1
            }
            guard !headers.isEmpty else { continue }
            var tokens: [String] = []
            while i < lines.count {
                let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
                if trimmed == "#" || trimmed == "loop_" || trimmed.hasPrefix("_") { break }
                tokens.append(contentsOf: tokenizeCIFLine(trimmed))
                i += 1
            }
            func column(_ names: [String]) -> Int? { names.compactMap { headers.firstIndex(of: $0) }.first }
            guard let xIndex = column(["_atom_site.Cartn_x"]), let yIndex = column(["_atom_site.Cartn_y"]), let zIndex = column(["_atom_site.Cartn_z"]) else { continue }
            let elementIndex = column(["_atom_site.type_symbol"])
            let atomIndex = column(["_atom_site.auth_atom_id", "_atom_site.label_atom_id"])
            let residueIndex = column(["_atom_site.auth_comp_id", "_atom_site.label_comp_id"])
            let residueIDIndex = column(["_atom_site.auth_seq_id", "_atom_site.label_seq_id"])
            let chainIndex = column(["_atom_site.auth_asym_id", "_atom_site.label_asym_id"])
            let confidenceIndex = column(["_atom_site.B_iso_or_equiv"])
            let modelIndex = column(["_atom_site.pdbx_PDB_model_num"])
            let alternateIndex = column(["_atom_site.label_alt_id"])
            var atoms: [ProteinAtom] = []
            for start in stride(from: 0, to: tokens.count - headers.count + 1, by: headers.count) {
                let row = Array(tokens[start..<start + headers.count])
                guard let x = Float(row[xIndex]), let y = Float(row[yIndex]), let z = Float(row[zIndex]) else { continue }
                func value(_ index: Int?, fallback: String = "") -> String {
                    guard let index, index < row.count, row[index] != ".", row[index] != "?" else { return fallback }
                    return row[index]
                }
                guard value(modelIndex, fallback: "1") == "1" else { continue }
                let alternate = value(alternateIndex)
                guard alternate.isEmpty || alternate == "A" else { continue }
                atoms.append(ProteinAtom(x: x, y: y, z: z, element: value(elementIndex, fallback: "C").uppercased(), atomName: value(atomIndex), residueName: value(residueIndex).uppercased(), residueID: value(residueIDIndex), chainID: value(chainIndex, fallback: "_"), confidence: Float(value(confidenceIndex))))
            }
            if !atoms.isEmpty { return atoms }
        }
        return []
    }

    @inline(never)
    private static func tokenizeCIFLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        for character in line {
            if let activeQuote = quote {
                if character == activeQuote { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty { result.append(current); current = "" }
            } else { current.append(character) }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    @inline(never)
    private static func parseFASTA(_ text: String) -> [(name: String, sequence: String)] {
        var records: [(String, String)] = []
        var name = "sequence_1"
        var sequence = ""
        for rawLine in text.split(whereSeparator: \ .isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(">") {
                if !sequence.isEmpty { records.append((name, sequence)) }
                name = String(line.dropFirst())
                sequence = ""
            } else { sequence += line.filter { !$0.isWhitespace } }
        }
        if !sequence.isEmpty { records.append((name, sequence)) }
        return records
    }

    @inline(never)
    private static func downsample(_ atoms: [ProteinAtom], limit: Int) -> [ProteinAtom] {
        guard atoms.count > limit else { return atoms }
        let strideValue = max(1, atoms.count / limit)
        var sampled: [ProteinAtom] = []
        sampled.reserveCapacity(limit)
        var index = 0
        while index < atoms.count && sampled.count < limit {
            sampled.append(atoms[index])
            index += strideValue
        }
        return sampled
    }

    private static func color(for element: String) -> SIMD4<Float> {
        switch element.uppercased() {
        case "H": return SIMD4(0.85, 0.85, 0.85, 1)
        case "C": return SIMD4(0.45, 0.55, 0.65, 1)
        case "N": return SIMD4(0.25, 0.45, 0.95, 1)
        case "O": return SIMD4(0.95, 0.25, 0.25, 1)
        case "S": return SIMD4(0.95, 0.75, 0.15, 1)
        case "P": return SIMD4(1.0, 0.5, 0.1, 1)
        default: return SIMD4(0.3, 0.8, 0.65, 1)
        }
    }
}

struct ScienceInspectTool: AgentTool {
    let name = "science_inspect"
    let description = "Inspect a local scientific artifact (PDB, mmCIF, FASTA/A3M, or AlphaFold JSON) and return compact metadata."
    let parameters = [ToolParameter(name: "path", type: "string", description: "Workspace-relative artifact path", required: true)]
    func execute(params: [String: Any]) async throws -> String {
        guard let path = params["path"] as? String else { throw ToolBoxError.invalidParams("path is required") }
        return try await Task.detached(priority: .userInitiated) { try ScienceService.inspectFile(at: URL(fileURLWithPath: path)) }.value
    }
}

struct AlphaFoldInputValidateTool: AgentTool {
    let name = "alphafold_input_validate"
    let description = "Validate an AlphaFold 3 input JSON locally without running inference or uploading data."
    let parameters = [ToolParameter(name: "path", type: "string", description: "Workspace-relative AlphaFold 3 JSON path", required: true)]
    func execute(params: [String: Any]) async throws -> String {
        guard let path = params["path"] as? String else { throw ToolBoxError.invalidParams("path is required") }
        return try await Task.detached(priority: .userInitiated) { try ScienceService.validateAlphaFoldInput(at: URL(fileURLWithPath: path)) }.value
    }
}
