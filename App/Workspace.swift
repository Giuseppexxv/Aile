import Foundation
import UIKit
import PDFKit
import Vision

struct ToolCall {
    let name: String
    let args: [String: Any]

    private var path: String { (args["path"] as? String) ?? "" }

    /// Descrizione semplice, pensata per chi non è tecnico.
    var summary: String {
        switch name {
        case "write_file": return "Scrivo «\(path)»"
        case "append_file": return "Aggiungo testo a «\(path)»"
        case "replace_in_file": return "Modifico «\(path)»"
        case "read_file": return "Leggo «\(path)»"
        case "list_files": return "Guardo i file del progetto"
        case "make_dir": return "Creo la cartella «\(path)»"
        case "delete_file": return "Elimino «\(path)»"
        case "fetch_url": return "Leggo una pagina web"
        case "copy_to_clipboard": return "Copio negli appunti"
        default: return name
        }
    }

    var icon: String {
        switch name {
        case "write_file", "append_file": return "doc.badge.plus"
        case "replace_in_file": return "pencil"
        case "read_file": return "doc.text.magnifyingglass"
        case "list_files", "make_dir": return "folder"
        case "delete_file": return "trash"
        case "fetch_url": return "globe"
        case "copy_to_clipboard": return "doc.on.clipboard"
        default: return "gearshape"
        }
    }
}

/// Cartella del progetto attivo, dove l'agente può lavorare.
/// È visibile anche nell'app File (Su iPhone > Agente Locale > Progetti).
enum Workspace {
    static var root: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    struct WSError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func resolve(_ path: String) throws -> URL {
        let cleaned = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let rel = cleaned.hasPrefix("/") ? String(cleaned.dropFirst()) : cleaned
        let url = (rel.isEmpty || rel == ".") ? root : root.appendingPathComponent(rel)
        let std = url.standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        guard std.path == rootPath || std.path.hasPrefix(rootPath + "/") else {
            throw WSError(message: "Percorso fuori dal progetto: \(path)")
        }
        return std
    }

    static func relativePath(_ url: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let p = url.standardizedFileURL.path
        guard p.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(p.dropFirst(rootPath.count + 1))
    }

    static func allFiles() -> [URL] {
        guard let en = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var result: [URL] = []
        for case let url as URL in en {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !isDir { result.append(url) }
        }
        return result.sorted { $0.path < $1.path }
    }

    /// Legge testo da file di testo, PDF e foto (riconoscimento del testo nelle immagini).
    static func readText(_ url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let doc = PDFDocument(url: url) else { throw WSError(message: "PDF non leggibile") }
            let t = doc.string ?? ""
            return t.isEmpty ? "(il PDF non contiene testo leggibile)" : t
        case "png", "jpg", "jpeg", "heic", "heif":
            guard let cg = UIImage(contentsOfFile: url.path)?.cgImage else {
                throw WSError(message: "immagine non leggibile")
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            try handler.perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.isEmpty ? "(nessun testo riconosciuto nell'immagine)" : lines.joined(separator: "\n")
        default:
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    static func run(_ call: ToolCall) -> (ok: Bool, output: String) {
        func str(_ key: String) -> String? {
            if let s = call.args[key] as? String { return s }
            if let n = call.args[key] as? NSNumber { return n.stringValue }
            return nil
        }
        let fm = FileManager.default
        do {
            switch call.name {
            case "list_files":
                let url = try resolve(str("path") ?? ".")
                let items = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                if items.isEmpty { return (true, "(cartella vuota)") }
                let lines = items.map { item -> String in
                    let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    return item.lastPathComponent + (isDir ? "/" : "")
                }
                return (true, lines.joined(separator: "\n"))

            case "read_file":
                guard let path = str("path") else { throw WSError(message: "manca 'path'") }
                let url = try resolve(path)
                guard fm.fileExists(atPath: url.path) else { throw WSError(message: "file non trovato: \(path)") }
                let text = try readText(url)
                if text.count > 8000 {
                    return (true, String(text.prefix(8000)) + "\n…[troncato, \(text.count) caratteri totali]")
                }
                return (true, text.isEmpty ? "(file vuoto)" : text)

            case "write_file":
                guard let path = str("path") else { throw WSError(message: "manca 'path'") }
                let content = str("content") ?? ""
                let url = try resolve(path)
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: url, atomically: true, encoding: .utf8)
                return (true, "scritto \(path) (\(content.count) caratteri)")

            case "append_file":
                guard let path = str("path") else { throw WSError(message: "manca 'path'") }
                let content = str("content") ?? ""
                let url = try resolve(path)
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                try (existing + content).write(to: url, atomically: true, encoding: .utf8)
                return (true, "aggiunto testo a \(path)")

            case "replace_in_file":
                guard let path = str("path"), let old = str("old") else {
                    throw WSError(message: "servono 'path' e 'old'")
                }
                let new = str("new") ?? ""
                let url = try resolve(path)
                guard fm.fileExists(atPath: url.path) else { throw WSError(message: "file non trovato: \(path)") }
                var text = try String(contentsOf: url, encoding: .utf8)
                guard let range = text.range(of: old) else {
                    throw WSError(message: "testo da sostituire non trovato in \(path)")
                }
                text.replaceSubrange(range, with: new)
                try text.write(to: url, atomically: true, encoding: .utf8)
                return (true, "modificato \(path)")

            case "make_dir":
                guard let path = str("path") else { throw WSError(message: "manca 'path'") }
                try fm.createDirectory(at: try resolve(path), withIntermediateDirectories: true)
                return (true, "cartella creata: \(path)")

            case "delete_file":
                guard let path = str("path") else { throw WSError(message: "manca 'path'") }
                let url = try resolve(path)
                guard url.path != root.standardizedFileURL.path else {
                    throw WSError(message: "non puoi cancellare la cartella del progetto")
                }
                guard fm.fileExists(atPath: url.path) else { throw WSError(message: "non trovato: \(path)") }
                try fm.removeItem(at: url)
                return (true, "eliminato \(path)")

            default:
                return (false, "tool sconosciuto: \(call.name)")
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

/// Prompt di sistema e lettura dei comandi generati dal modello.
enum ToolParser {
    static func systemPrompt(web: Bool, clipboard: Bool) -> String {
        var extraTools = ""
        if web { extraTools += "\n- fetch_url {\"url\": \"https://...\"} : read the text of a web page" }
        if clipboard { extraTools += "\n- copy_to_clipboard {\"text\": \"...\"} : copy text to the user's clipboard" }

        return #"""
        You are "Agente Locale", a friendly assistant that runs entirely on the user's iPhone. The user is NOT technical: speak simply, never use jargon, never show code in your replies. You work like a careful developer: when the user asks for something (a website, a text, a file...), you do the whole job yourself by creating and editing files in the user's project folder, and only at the end you reply with a short, simple summary (1-3 sentences) in the user's language.

        HOW TO USE TOOLS
        Use one tool per turn, then stop and wait for the result.

        1) To create or overwrite a file, write exactly:
        <write_file path="index.html">
        ...the full content of the file...
        </write_file>
        To add text at the end of a file, use <append_file path="notes.txt">...</append_file> in the same way.

        2) For every other tool, write exactly:
        <tool_call>{"name": "TOOL_NAME", "arguments": {...}}</tool_call>

        Tools:
        - list_files {"path": "."} : list a folder
        - read_file {"path": "notes.txt"} : read a file (works for text, PDF and photos that contain text)
        - replace_in_file {"path": "index.html", "old": "exact old text", "new": "new text"} : replace the first occurrence
        - make_dir {"path": "images"} : create a folder
        - delete_file {"path": "old.txt"} : delete a file or folder
        - ask_user {"question": "Short question?", "options": ["Round", "Square"]} : ask the user and wait for the answer. Use it ONLY when you really need a choice that you cannot reasonably decide yourself (for example a name or a style). Ask one simple question at a time. "options" is optional.
        """# + extraTools + #"""


        RULES
        - Paths are relative to the project folder.
        - Websites: build a complete, beautiful, modern, mobile-friendly site as ONE self-contained index.html (CSS inside <style>, JavaScript inside <script>, no external libraries, no images from the internet: use emojis, gradients and CSS shapes). Never stop halfway: write the whole file.
        - Read a file before you edit it. Never invent the content of files you have not read.
        - Decide the small things yourself. Do not ask permission for every step.
        - Never put a tool and a final answer in the same turn. After the last tool result, give the final short answer with no tool.
        - Files attached by the user are already in the project folder: use read_file to look at them.
        """#
    }

    private static let markers = ["<tool_call>", "<write_file", "<append_file"]

    static func hasCompleteCall(_ s: String) -> Bool {
        s.contains("</tool_call>") || s.contains("</write_file>") || s.contains("</append_file>")
    }

    static func hasUnclosedBlock(_ s: String) -> Bool {
        for tag in ["write_file", "append_file"] {
            let opens = s.components(separatedBy: "<\(tag)").count - 1
            let closes = s.components(separatedBy: "</\(tag)>").count - 1
            if opens > closes { return true }
        }
        return false
    }

    /// Testo da mostrare all'utente (senza comandi e senza ragionamenti interni).
    static func visibleText(_ s: String) -> String {
        var text = s
        if let re = try? NSRegularExpression(pattern: #"<think>[\s\S]*?</think>"#) {
            text = re.stringByReplacingMatches(
                in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "")
        }
        if let r = text.range(of: "<think>") { text = String(text[..<r.lowerBound]) }
        var cut: String.Index? = nil
        for marker in markers {
            if let r = text.range(of: marker), cut == nil || r.lowerBound < cut! { cut = r.lowerBound }
        }
        if let cut { text = String(text[..<cut]) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cosa sta facendo l'agente in questo momento (per l'indicatore di attività).
    static func activity(_ s: String) -> String? {
        for (tag, verb) in [("write_file", "Scrivo"), ("append_file", "Aggiungo testo a")] {
            if let r = s.range(of: "<\(tag)") {
                let tail = String(s[r.upperBound...])
                var name = "un file"
                if let re = try? NSRegularExpression(pattern: #"path=["']([^"'>]+)["']"#),
                   let m = re.firstMatch(in: tail, range: NSRange(location: 0, length: (tail as NSString).length)) {
                    name = "«" + (tail as NSString).substring(with: m.range(at: 1)) + "»"
                }
                let count = tail.count
                return "\(verb) \(name)… (\(count) caratteri)"
            }
        }
        if s.contains("<tool_call>") { return "Preparo un'azione…" }
        if s.contains("<think>") && !s.contains("</think>") { return "Sto pensando…" }
        if visibleText(s).isEmpty { return "Sto pensando…" }
        return nil
    }

    static func parse(_ text: String) -> [ToolCall] {
        var found: [(Int, ToolCall)] = []
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        // Blocchi <write_file path="..."> ... </write_file>
        for tag in ["write_file", "append_file"] {
            let pattern = #"<\#(tag)\s+path=["']([^"'>]+)["']\s*>([\s\S]*?)</\#(tag)>"#
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            for m in re.matches(in: text, range: full) {
                let path = ns.substring(with: m.range(at: 1))
                let content = cleanContent(ns.substring(with: m.range(at: 2)))
                found.append((m.range.location, ToolCall(name: tag, args: ["path": path, "content": content])))
            }
        }

        // Chiamate JSON <tool_call>{...}</tool_call>
        var jsons: [(Int, String)] = []
        if let re = try? NSRegularExpression(pattern: #"<tool_call>\s*(\{[\s\S]*?\})\s*</tool_call>"#) {
            for m in re.matches(in: text, range: full) {
                jsons.append((m.range.location, ns.substring(with: m.range(at: 1))))
            }
        }
        if jsons.isEmpty, let r = text.range(of: "<tool_call>") {
            let tail = String(text[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if tail.hasPrefix("{"), let end = tail.lastIndex(of: "}") {
                jsons.append((text.distance(from: text.startIndex, to: r.lowerBound), String(tail[...end])))
            }
        }
        for (loc, json) in jsons {
            if let call = decode(json) { found.append((loc, call)) }
        }

        return found.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    private static func cleanContent(_ raw: String) -> String {
        var c = raw
        if c.hasPrefix("\n") { c.removeFirst() }
        if c.hasSuffix("\n") { c.removeLast() }
        let trimmed = c.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            var lines = trimmed.components(separatedBy: "\n")
            lines.removeFirst()
            if let last = lines.last, last.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
            c = lines.joined(separator: "\n")
        }
        return c
    }

    private static func decode(_ json: String) -> ToolCall? {
        for candidate in [json, sanitize(json)] {
            guard let data = candidate.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = obj["name"] as? String else { continue }
            let args = (obj["arguments"] as? [String: Any]) ?? (obj["parameters"] as? [String: Any]) ?? [:]
            return ToolCall(name: name, args: args)
        }
        return nil
    }

    /// Corregge a-capo e tab "veri" dentro le stringhe JSON, errore frequente nei modelli piccoli.
    private static func sanitize(_ json: String) -> String {
        var out = ""
        var inString = false
        var escaped = false
        for ch in json {
            if inString {
                if escaped { out.append(ch); escaped = false; continue }
                switch ch {
                case "\\": out.append(ch); escaped = true
                case "\"": out.append(ch); inString = false
                case "\n": out += "\\n"
                case "\r": break
                case "\t": out += "\\t"
                default: out.append(ch)
                }
            } else {
                if ch == "\"" { inString = true }
                out.append(ch)
            }
        }
        return out
    }
}
