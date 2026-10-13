import Foundation

struct ChatItem: Identifiable, Codable {
    enum Role: String, Codable { case user, assistant, tool }
    var id = UUID()
    var role: Role
    var text: String
    var toolName: String? = nil
    var ok: Bool = true
    var previewPath: String? = nil
    var attachments: [String] = []
}

struct Project: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var folder: String
}

struct ChatThread: Identifiable, Codable {
    var id = UUID()
    var title: String
    var projectID: UUID
    var items: [ChatItem]
    var date: Date = Date()
}

struct PendingQuestion: Identifiable {
    let id = UUID()
    let question: String
    let options: [String]
}

/// Stima del peso di un modello a partire dal nome (es. "Qwen3-4B-4bit").
enum ModelInfo {
    enum Weight { case ok, heavy, tooHeavy, unknown }

    static var deviceRAMGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    }

    static func estimatedGB(_ id: String) -> Double? {
        let name = id.split(separator: "/").last.map(String.init) ?? id
        let ns = name as NSString

        // numero di parametri: 4B, 1.5B, 270M ...
        guard let paramRe = try? NSRegularExpression(
            pattern: #"(?<![A-Za-z0-9])(\d+(?:\.\d+)?)([BbMm])(?![A-Za-z])"#),
              let m = paramRe.firstMatch(in: name, range: NSRange(location: 0, length: ns.length)),
              let number = Double(ns.substring(with: m.range(at: 1)))
        else { return nil }
        let unit = ns.substring(with: m.range(at: 2)).lowercased()
        let billions = unit == "b" ? number : number / 1000

        // bit per peso
        var bits = 16.0
        let lower = name.lowercased()
        if let bitRe = try? NSRegularExpression(pattern: #"(\d+)[-_ ]?bit"#),
           let bm = bitRe.firstMatch(in: lower, range: NSRange(location: 0, length: (lower as NSString).length)),
           let b = Double((lower as NSString).substring(with: bm.range(at: 1))) {
            bits = b
        } else if lower.contains("fp4") {
            bits = 4
        } else if lower.contains("fp8") {
            bits = 8
        }
        return billions * bits / 8 * 1.12
    }

    static func weight(_ id: String) -> Weight {
        guard let gb = estimatedGB(id) else { return .unknown }
        let ram = deviceRAMGB
        if gb > ram * 0.42 { return .tooHeavy }
        if gb > ram * 0.28 { return .heavy }
        return .ok
    }

    static func sizeLabel(_ id: String) -> String {
        guard let gb = estimatedGB(id) else { return "" }
        return String(format: "≈ %.1f GB", gb)
    }

    static func warning(_ id: String) -> String {
        let size = sizeLabel(id)
        let ram = String(format: "%.0f", deviceRAMGB)
        switch weight(id) {
        case .tooHeavy:
            return "Questo modello (\(size)) è troppo grande per un iPhone con \(ram) GB di memoria: molto probabilmente l'app si chiuderà da sola. Puoi provare lo stesso, ma è meglio scegliere un modello più piccolo."
        case .heavy:
            return "Questo modello (\(size)) è pesante per un iPhone con \(ram) GB di memoria: potrebbe essere lento o chiudere l'app. Vuoi provarlo?"
        default:
            return ""
        }
    }
}
