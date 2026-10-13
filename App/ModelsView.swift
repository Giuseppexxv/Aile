import SwiftUI

/// Dove si scaricano e si scelgono i modelli.
struct ModelsView: View {
    @ObservedObject var library: ModelLibrary
    @ObservedObject var agent: AgentViewModel
    var onChoose: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var manualID = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(library.saved, id: \.self) { id in
                        Button { onChoose(id) } label: { row(id, selected: id == agent.currentModelID && agent.isReady) }
                            .foregroundStyle(.primary)
                    }
                    .onDelete(perform: library.remove)
                } header: {
                    Text("I tuoi modelli")
                } footer: {
                    Text("Tocca un modello per usarlo: la prima volta viene scaricato. Scorri a sinistra per toglierlo dalla lista.")
                }

                Section {
                    TextField("es. mlx-community/Qwen3-4B-4bit", text: $manualID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Aggiungi e usa") {
                        let id = manualID.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard id.contains("/") else { return }
                        library.add(id)
                        manualID = ""
                        onChoose(id)
                    }
                    .disabled(!manualID.contains("/"))
                    if let url = URL(string: "https://huggingface.co/mlx-community") {
                        Link(destination: url) {
                            Label("Sfoglia i modelli su Hugging Face", systemImage: "safari")
                        }
                    }
                } header: {
                    Text("Dove scaricarli")
                } footer: {
                    Text("I modelli si scaricano da Hugging Face. Copia il nome del modello (es. mlx-community/Qwen3-4B-4bit) e incollalo qui sopra. Servono modelli in formato MLX. Puoi usare qualsiasi modello: se è troppo grande per il tuo iPhone ti avviso prima.")
                }

                if library.isSearching {
                    Section { ProgressView() }
                }
                if let err = library.searchError {
                    Section { Text(err).foregroundStyle(.orange) }
                }
                if !library.results.isEmpty {
                    Section("Risultati della ricerca") {
                        ForEach(library.results) { model in
                            Button {
                                library.add(model.id)
                                onChoose(model.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(model.id).font(.subheadline)
                                        weightIcon(model.id)
                                    }
                                    Text("\(ModelInfo.sizeLabel(model.id))   ↓ \(model.downloads ?? 0)   ♥ \(model.likes ?? 0)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Modelli")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Cerca su Hugging Face")
            .onSubmit(of: .search) {
                Task { await library.search(query) }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
        }
    }

    private func row(_ id: String, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(id.split(separator: "/").last.map(String.init) ?? id)
                    weightIcon(id)
                }
                Text("\(ModelInfo.sizeLabel(id))  \(id)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private func weightIcon(_ id: String) -> some View {
        switch ModelInfo.weight(id) {
        case .heavy:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        case .tooHeavy:
            Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red)
        default:
            EmptyView()
        }
    }
}
