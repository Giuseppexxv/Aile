import Foundation

struct HFModel: Identifiable, Decodable, Hashable {
    let id: String
    let downloads: Int?
    let likes: Int?
}

/// Elenco dei modelli scelti dall'utente + ricerca su Hugging Face.
@MainActor
final class ModelLibrary: ObservableObject {
    static let defaults = [
        "mlx-community/Qwen2.5-Coder-3B-Instruct-4bit",
        "mlx-community/Qwen2.5-3B-Instruct-4bit",
        "mlx-community/Qwen3-4B-4bit",
        "mlx-community/Llama-3.2-3B-Instruct-4bit",
        "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
    ]
    private let key = "savedModels"

    @Published var saved: [String]
    @Published var results: [HFModel] = []
    @Published var isSearching = false
    @Published var searchError: String?

    init() {
        saved = UserDefaults.standard.stringArray(forKey: key) ?? ModelLibrary.defaults
    }

    func add(_ id: String) {
        let clean = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.contains("/"), !saved.contains(clean) else { return }
        saved.append(clean)
        persist()
    }

    func remove(at offsets: IndexSet) {
        saved.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(saved, forKey: key)
    }

    func search(_ query: String) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = []; return }
        guard var comps = URLComponents(string: "https://huggingface.co/api/models") else { return }
        comps.queryItems = [
            URLQueryItem(name: "search", value: q),
            URLQueryItem(name: "filter", value: "mlx"),
            URLQueryItem(name: "pipeline_tag", value: "text-generation"),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: "25")
        ]
        guard let url = comps.url else { return }
        isSearching = true
        searchError = nil
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            results = try JSONDecoder().decode([HFModel].self, from: data)
        } catch {
            searchError = "Ricerca non riuscita: \(error.localizedDescription)"
        }
        isSearching = false
    }
}
