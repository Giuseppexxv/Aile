import SwiftUI

struct SideMenu: View {
    @ObservedObject var store: Store
    var onNewChat: () -> Void
    var onOpen: (ChatThread) -> Void
    var onDelete: (UUID) -> Void
    var onSheet: (ActiveSheet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.title2)
                Text("Agente Locale").font(.title3.bold())
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 12)

            menuRow("Nuova chat", icon: "square.and.pencil", action: onNewChat)
            menuRow("Progetti", icon: "square.stack.3d.up", detail: store.currentProject.name) {
                onSheet(.projects)
            }
            menuRow("File del progetto", icon: "folder") { onSheet(.files) }
            menuRow("Add-on", icon: "puzzlepiece.extension") { onSheet(.addons) }
            menuRow("Impostazioni", icon: "gearshape") { onSheet(.settings) }

            Divider().padding(.vertical, 10).padding(.horizontal, 12)

            Text("Le tue chat")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.bottom, 4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if store.threads.isEmpty {
                        Text("Nessuna chat ancora")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 6)
                    }
                    ForEach(store.threads) { thread in
                        chatRow(thread)
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func menuRow(_ title: String, icon: String, detail: String? = nil,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chatRow(_ thread: ChatThread) -> some View {
        let projectName = store.projects.first(where: { $0.id == thread.projectID })?.name ?? ""
        let isCurrent = thread.id == store.currentThreadID
        return Button { onOpen(thread) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(thread.title).lineLimit(1)
                Text(projectName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(isCurrent ? Color.white.opacity(0.10) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { onDelete(thread.id) } label: {
                Label("Elimina chat", systemImage: "trash")
            }
        }
    }
}

// MARK: Progetti

struct ProjectsView: View {
    @ObservedObject var agent: AgentViewModel
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var showNew = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.projects) { project in
                        Button {
                            agent.selectProject(project)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                Text(project.name)
                                Spacer()
                                if project.id == store.currentProjectID {
                                    Image(systemName: "checkmark").foregroundStyle(.green)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in
                        for i in offsets { agent.deleteProject(store.projects[i]) }
                    }
                } footer: {
                    Text("Ogni progetto è una cartella con i suoi file. L'agente lavora solo dentro il progetto attivo. Scorri a sinistra per eliminare un progetto.")
                }
            }
            .navigationTitle("Progetti")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
            .alert("Nuovo progetto", isPresented: $showNew) {
                TextField("Nome del progetto", text: $newName)
                Button("Crea") {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    newName = ""
                    if !name.isEmpty {
                        agent.createProject(name)
                        dismiss()
                    }
                }
                Button("Annulla", role: .cancel) { newName = "" }
            }
        }
    }
}

// MARK: Add-on

struct AddonsView: View {
    @ObservedObject var agent: AgentViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("addon.web") private var web = false
    @AppStorage("addon.clipboard") private var clipboard = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $web) {
                        addonLabel("Navigazione web", icon: "globe",
                                   text: "L'agente può leggere una pagina internet che gli indichi.")
                    }
                    Toggle(isOn: $clipboard) {
                        addonLabel("Appunti", icon: "doc.on.clipboard",
                                   text: "L'agente può copiare un testo negli appunti, pronto da incollare altrove.")
                    }
                } footer: {
                    Text("Gli add-on danno nuove capacità all'agente. Sono spenti finché non li accendi.")
                }
            }
            .navigationTitle("Add-on")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
            .onChange(of: web) { _, _ in agent.addonsChanged() }
            .onChange(of: clipboard) { _, _ in agent.addonsChanged() }
        }
    }

    private func addonLabel(_ title: String, icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 28).foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: Impostazioni

struct SettingsView: View {
    @ObservedObject var agent: AgentViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("maxSteps") private var maxSteps = 12
    @AppStorage("confirmDelete") private var confirmDelete = true
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Passaggi per ogni ordine: \(maxSteps)", value: $maxSteps, in: 4...30)
                } header: {
                    Text("Lavoro dell'agente")
                } footer: {
                    Text("Più passaggi permettono lavori più grandi, come un sito intero, ma richiedono più tempo.")
                }

                Section {
                    Toggle("Chiedi prima di eliminare file", isOn: $confirmDelete)
                }

                Section("Il tuo iPhone") {
                    LabeledContent("Memoria (RAM)", value: String(format: "%.0f GB", ModelInfo.deviceRAMGB))
                    Text("Per stare tranquilli scegli modelli che pesano meno di circa \(String(format: "%.1f", ModelInfo.deviceRAMGB * 0.28)) GB. Oltre \(String(format: "%.1f", ModelInfo.deviceRAMGB * 0.42)) GB l'app rischia di chiudersi.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Elimina tutte le chat", role: .destructive) { confirmClear = true }
                }

                Section("Informazioni") {
                    Text("Tutto gira sul telefono: i tuoi file e le tue chat non escono dal dispositivo. I file dei progetti li trovi anche nell'app File, sotto «Su iPhone» > «Agente Locale» > «Progetti».")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
            .confirmationDialog("Eliminare tutte le chat?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Elimina", role: .destructive) { agent.clearAllChats() }
            }
        }
    }
}
