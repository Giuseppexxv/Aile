import SwiftUI
import UIKit
import MLXLLM
import MLXLMCommon

@MainActor
final class AgentViewModel: ObservableObject {
    @Published var items: [ChatItem] = []
    @Published var currentModelID: String?
    @Published var loadError: String?
    @Published var downloadProgress = 0.0
    @Published var isLoading = false
    @Published var isReady = false
    @Published var isGenerating = false
    @Published var activity: String?
    @Published var pending: PendingQuestion?
    @Published var attachments: [String] = []

    let store = Store()

    private var container: ModelContainer?
    private var session: ChatSession?
    private var task: Task<Void, Never>?
    private var continuation: CheckedContinuation<String, Never>?
    private var threadID = UUID()
    private var needsRecap = false
    private var runToken = UUID()
    private var lastHTML: String?

    init() {
        Workspace.root = store.currentFolder
    }

    // MARK: Impostazioni lette al volo

    private var maxSteps: Int {
        let v = UserDefaults.standard.integer(forKey: "maxSteps")
        return v == 0 ? 12 : v
    }
    private var confirmDelete: Bool {
        UserDefaults.standard.object(forKey: "confirmDelete") as? Bool ?? true
    }
    private var webOn: Bool { UserDefaults.standard.bool(forKey: "addon.web") }
    private var clipboardOn: Bool { UserDefaults.standard.bool(forKey: "addon.clipboard") }

    var shortModelName: String {
        currentModelID?.split(separator: "/").last.map(String.init) ?? "Scegli un modello"
    }

    // MARK: Modello

    private func makeSession() {
        guard let container else { session = nil; return }
        session = ChatSession(
            container,
            instructions: ToolParser.systemPrompt(web: webOn, clipboard: clipboardOn))
    }

    func addonsChanged() {
        makeSession()
        needsRecap = !items.isEmpty
    }

    func loadModel(_ id: String) async {
        guard !isLoading else { return }
        stop()
        isLoading = true
        isReady = false
        loadError = nil
        downloadProgress = 0
        session = nil
        container = nil
        currentModelID = id

        do {
            let configuration = ModelConfiguration(id: id)
            let loaded = try await LLMModelFactory.shared.loadContainer(
                configuration: configuration
            ) { progress in
                Task { @MainActor in
                    self.downloadProgress = progress.fractionCompleted
                }
            }
            container = loaded
            makeSession()
            needsRecap = !items.isEmpty
            isReady = true
            UserDefaults.standard.set(id, forKey: "lastModel")
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    func loadLastModelIfNeeded() async {
        guard currentModelID == nil,
              let id = UserDefaults.standard.string(forKey: "lastModel") else { return }
        await loadModel(id)
    }

    // MARK: Chat e progetti

    private func saveCurrent() {
        guard !items.isEmpty else { return }
        let first = items.first(where: { $0.role == .user })?.text ?? "Nuova chat"
        let title = String(first.prefix(40))
        store.save(ChatThread(id: threadID, title: title, projectID: store.currentProjectID, items: items))
        store.currentThreadID = threadID
    }

    private func resetChat() {
        threadID = UUID()
        items = []
        needsRecap = false
        lastHTML = nil
        attachments = []
        makeSession()
    }

    func newChat() {
        stop()
        resetChat()
    }

    func open(_ thread: ChatThread) {
        stop()
        if let p = store.projects.first(where: { $0.id == thread.projectID }) {
            store.selectProject(p)
            Workspace.root = store.currentFolder
        }
        threadID = thread.id
        items = thread.items
        needsRecap = !items.isEmpty
        attachments = []
        makeSession()
    }

    func selectProject(_ p: Project) {
        stop()
        store.selectProject(p)
        Workspace.root = store.currentFolder
        resetChat()
    }

    func createProject(_ name: String) {
        let p = store.createProject(name: name)
        selectProject(p)
    }

    func deleteProject(_ p: Project) {
        guard store.projects.count > 1 else { return }
        let wasCurrent = p.id == store.currentProjectID
        if wasCurrent { stop() }
        store.deleteProject(p)
        if wasCurrent {
            Workspace.root = store.currentFolder
            resetChat()
        }
    }

    func deleteChat(_ id: UUID) {
        if id == threadID { stop() }
        store.deleteThread(id)
        if id == threadID { resetChat() }
    }

    func clearAllChats() {
        stop()
        store.deleteAllThreads()
        resetChat()
    }

    // MARK: Allegati

    private func uniqueName(_ base: String) -> String {
        let fm = FileManager.default
        let ext = (base as NSString).pathExtension
        let stem = (base as NSString).deletingPathExtension
        var name = base
        var n = 2
        while fm.fileExists(atPath: Workspace.root.appendingPathComponent(name).path) {
            name = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            n += 1
        }
        return name
    }

    func attachFiles(_ urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let name = uniqueName(url.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: url, to: Workspace.root.appendingPathComponent(name))
                attachments.append(name)
            } catch {
                loadError = "Non riesco ad allegare «\(url.lastPathComponent)»: \(error.localizedDescription)"
            }
        }
    }

    func attachPhoto(data: Data) {
        let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.9) ?? data
        let name = uniqueName("foto.jpg")
        do {
            try jpeg.write(to: Workspace.root.appendingPathComponent(name))
            attachments.append(name)
        } catch {
            loadError = "Non riesco ad allegare la foto: \(error.localizedDescription)"
        }
    }

    func removeAttachment(_ name: String) {
        attachments.removeAll { $0 == name }
    }

    // MARK: Domande all'utente

    private func ask(_ q: PendingQuestion) async -> String {
        await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            continuation = cont
            pending = q
        }
    }

    func answer(_ text: String) {
        guard let cont = continuation else { return }
        continuation = nil
        pending = nil
        items.append(ChatItem(role: .user, text: text))
        cont.resume(returning: text)
    }

    // MARK: Invio e ciclo dell'agente

    private func recap() -> String {
        let lines = items.suffix(12).compactMap { item -> String? in
            switch item.role {
            case .user: return "User: " + String(item.text.prefix(400))
            case .assistant: return "Assistant: " + String(item.text.prefix(400))
            case .tool: return "Action done: " + item.text
            }
        }
        return "[Earlier conversation, for context only]\n" + lines.joined(separator: "\n")
            + "\n[End of earlier conversation]\n\n"
    }

    func send(_ text: String) {
        if pending != nil { answer(text); return }
        guard isReady, !isGenerating, let session else { return }

        let files = attachments
        attachments = []
        let recapText = needsRecap ? recap() : ""
        needsRecap = false

        items.append(ChatItem(role: .user, text: text, attachments: files))
        saveCurrent()

        var prompt = recapText + text
        if !files.isEmpty {
            prompt += "\n\n[The user attached these files, now in the project folder: "
                + files.joined(separator: ", ") + ". Use read_file to look at them.]"
        }

        lastHTML = nil
        runToken = UUID()
        let token = runToken
        isGenerating = true
        task = Task {
            await runAgent(session: session, firstPrompt: prompt)
            if token == runToken {
                activity = nil
                isGenerating = false
                saveCurrent()
            }
        }
    }

    private func runAgent(session: ChatSession, firstPrompt: String) async {
        var prompt = firstPrompt
        let limit = maxSteps
        for _ in 0..<limit {
            if Task.isCancelled { return }
            items.append(ChatItem(role: .assistant, text: ""))
            let index = items.count - 1
            var full = ""
            activity = "Sto pensando…"
            do {
                for try await chunk in session.streamResponse(to: prompt) {
                    if Task.isCancelled { break }
                    full += chunk
                    items[index].text = ToolParser.visibleText(full)
                    activity = ToolParser.activity(full)
                    // appena il modello chiude un comando ci fermiamo: il risultato lo diamo noi
                    if ToolParser.hasCompleteCall(full) { break }
                }
            } catch {
                if !Task.isCancelled {
                    items[index].text += "\n[Errore: \(error.localizedDescription)]"
                }
                return
            }
            if Task.isCancelled { return }
            activity = nil

            let calls = ToolParser.parse(full)
            let shown = items[index].text
            if shown.isEmpty { items.remove(at: index) }

            if calls.isEmpty {
                if ToolParser.hasUnclosedBlock(full) {
                    items.append(ChatItem(role: .tool, text: "Il file era incompleto, riprovo", toolName: "retry", ok: false))
                    prompt = "<tool_response>\n[error] Your file block was not closed with its closing tag, so nothing was saved. Write the complete file again, from the opening tag to the closing tag.\n</tool_response>"
                    continue
                }
                if shown.isEmpty && lastHTML == nil {
                    items.append(ChatItem(role: .assistant, text: "Non ho ricevuto nessuna risposta dal modello. Riprova, o prova un modello diverso."))
                }
                if let html = lastHTML {
                    items.append(ChatItem(role: .tool, text: "Il tuo sito è pronto", toolName: "preview", previewPath: html))
                }
                return
            }

            var results: [String] = []
            for call in calls {
                activity = call.summary + "…"
                let (ok, output) = await execute(call)
                if Task.isCancelled { return }
                if call.name != "ask_user" {
                    items.append(ChatItem(role: .tool, text: call.summary, toolName: call.name, ok: ok))
                }
                if ok, call.name == "write_file", let path = call.args["path"] as? String,
                   path.lowercased().hasSuffix(".html") {
                    lastHTML = path
                }
                results.append("[\(call.name)] \(ok ? "ok" : "error"): \(output)")
            }
            activity = nil
            prompt = "<tool_response>\n" + results.joined(separator: "\n\n") + "\n</tool_response>"
        }
        items.append(ChatItem(role: .assistant, text: "Mi fermo qui: ho raggiunto il limite di passaggi per un singolo ordine. Puoi aumentarlo da Impostazioni, oppure scrivimi «continua»."))
        if let html = lastHTML {
            items.append(ChatItem(role: .tool, text: "Anteprima del sito", toolName: "preview", previewPath: html))
        }
    }

    private func execute(_ call: ToolCall) async -> (Bool, String) {
        switch call.name {
        case "ask_user":
            let q = (call.args["question"] as? String) ?? "Come vuoi procedere?"
            let options = (call.args["options"] as? [Any])?.compactMap { $0 as? String } ?? []
            items.append(ChatItem(role: .assistant, text: q))
            let a = await ask(PendingQuestion(question: q, options: options))
            return (true, "The user answered: \(a)")

        case "delete_file":
            if confirmDelete {
                let path = (call.args["path"] as? String) ?? "questo file"
                let q = "Posso eliminare «\(path)»?"
                items.append(ChatItem(role: .assistant, text: q))
                let a = await ask(PendingQuestion(question: q, options: ["Sì, elimina", "No"]))
                if !a.lowercased().hasPrefix("s") {
                    return (false, "The user said no. Do not delete it.")
                }
            }
            return Workspace.run(call)

        case "fetch_url":
            guard webOn else { return (false, "This tool is not available.") }
            return await fetchURL((call.args["url"] as? String) ?? "")

        case "copy_to_clipboard":
            guard clipboardOn else { return (false, "This tool is not available.") }
            UIPasteboard.general.string = (call.args["text"] as? String) ?? ""
            return (true, "copied to the clipboard")

        default:
            return Workspace.run(call)
        }
    }

    private func fetchURL(_ s: String) async -> (Bool, String) {
        guard let url = URL(string: s), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return (false, "invalid URL")
        }
        do {
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: req)
            var text = String(decoding: data, as: UTF8.self)
            for pattern in [#"<script[\s\S]*?</script>"#, #"<style[\s\S]*?</style>"#, #"<[^>]+>"#] {
                if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    text = re.stringByReplacingMatches(
                        in: text, range: NSRange(location: 0, length: (text as NSString).length),
                        withTemplate: " ")
                }
            }
            if let re = try? NSRegularExpression(pattern: #"\s+"#) {
                text = re.stringByReplacingMatches(
                    in: text, range: NSRange(location: 0, length: (text as NSString).length),
                    withTemplate: " ")
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return (true, String(trimmed.prefix(6000)))
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func stop() {
        runToken = UUID()
        task?.cancel()
        task = nil
        if let cont = continuation {
            continuation = nil
            cont.resume(returning: "(annullato)")
        }
        pending = nil
        activity = nil
        isGenerating = false
        saveCurrent()
    }
}
