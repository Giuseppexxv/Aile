import Foundation

/// Progetti (cartelle di file) e chat salvate.
@MainActor
final class Store: ObservableObject {
    @Published var projects: [Project] = []
    @Published var threads: [ChatThread] = []
    @Published var currentProjectID = UUID()
    @Published var currentThreadID: UUID?

    private let dir: URL
    private let projectsRoot: URL

    init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = support.appendingPathComponent("AgenteLocale", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        projectsRoot = docs.appendingPathComponent("Progetti", isDirectory: true)
        try? fm.createDirectory(at: projectsRoot, withIntermediateDirectories: true)

        var loaded = Store.load([Project].self, from: dir.appendingPathComponent("projects.json")) ?? []
        if loaded.isEmpty {
            loaded = [Project(name: "Il mio progetto", folder: "Il mio progetto")]
        }
        projects = loaded
        threads = Store.load([ChatThread].self, from: dir.appendingPathComponent("chats.json")) ?? []

        let savedID = UserDefaults.standard.string(forKey: "currentProject").flatMap(UUID.init(uuidString:))
        currentProjectID = loaded.first(where: { $0.id == savedID })?.id ?? loaded[0].id
        for p in projects { ensureFolder(p) }
        persist()
    }

    var currentProject: Project {
        projects.first(where: { $0.id == currentProjectID }) ?? projects[0]
    }

    func folderURL(_ p: Project) -> URL {
        projectsRoot.appendingPathComponent(p.folder, isDirectory: true)
    }

    var currentFolder: URL { folderURL(currentProject) }

    private func ensureFolder(_ p: Project) {
        try? FileManager.default.createDirectory(at: folderURL(p), withIntermediateDirectories: true)
    }

    // MARK: Progetti

    @discardableResult
    func createProject(name: String) -> Project {
        var clean = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { clean = "Progetto" }
        var folder = clean
        var n = 2
        while projects.contains(where: { $0.folder == folder }) {
            folder = "\(clean) \(n)"
            n += 1
        }
        let p = Project(name: clean, folder: folder)
        projects.append(p)
        ensureFolder(p)
        persist()
        return p
    }

    func selectProject(_ p: Project) {
        currentProjectID = p.id
        UserDefaults.standard.set(p.id.uuidString, forKey: "currentProject")
    }

    func deleteProject(_ p: Project) {
        guard projects.count > 1 else { return }
        try? FileManager.default.removeItem(at: folderURL(p))
        projects.removeAll { $0.id == p.id }
        threads.removeAll { $0.projectID == p.id }
        if currentProjectID == p.id { selectProject(projects[0]) }
        persist()
    }

    // MARK: Chat

    func save(_ thread: ChatThread) {
        var t = thread
        t.date = Date()
        threads.removeAll { $0.id == t.id }
        threads.insert(t, at: 0)
        persist()
    }

    func deleteThread(_ id: UUID) {
        threads.removeAll { $0.id == id }
        persist()
    }

    func deleteAllThreads() {
        threads = []
        persist()
    }

    // MARK: Salvataggio

    private func persist() {
        if let d = try? JSONEncoder().encode(projects) {
            try? d.write(to: dir.appendingPathComponent("projects.json"), options: .atomic)
        }
        if let d = try? JSONEncoder().encode(threads) {
            try? d.write(to: dir.appendingPathComponent("chats.json"), options: .atomic)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
