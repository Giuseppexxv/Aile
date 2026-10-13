import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

enum ActiveSheet: Identifiable {
    case models, files, projects, addons, settings
    case preview(PreviewTarget)

    var id: String {
        switch self {
        case .models: return "models"
        case .files: return "files"
        case .projects: return "projects"
        case .addons: return "addons"
        case .settings: return "settings"
        case .preview(let t): return "preview-" + t.id
        }
    }
}

struct ContentView: View {
    @StateObject private var agent = AgentViewModel()
    @StateObject private var library = ModelLibrary()

    @State private var input = ""
    @State private var showMenu = false
    @State private var sheet: ActiveSheet?
    @State private var heavyModel: String?
    @State private var showHeavyAlert = false
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?

    private let examples = [
        "Fai un sito per la mia pizzeria",
        "Scrivi una lista della spesa per la settimana",
        "Leggi il PDF che ti allego e riassumilo"
    ]

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        let hasContent = !trimmedInput.isEmpty || !agent.attachments.isEmpty
        if agent.pending != nil { return !trimmedInput.isEmpty }
        return hasContent && agent.isReady && !agent.isGenerating
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Backdrop()
                chat
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showMenu = true } label: { Image(systemName: "line.3.horizontal") }
                }
                ToolbarItem(placement: .principal) { modelMenu }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
        }
        .overlay { drawer }
        .sheet(item: $sheet) { s in
            switch s {
            case .models: ModelsView(library: library, agent: agent, onChoose: choose)
            case .files: FilesView(store: agent.store)
            case .projects: ProjectsView(agent: agent, store: agent.store)
            case .addons: AddonsView(agent: agent)
            case .settings: SettingsView(agent: agent)
            case .preview(let target): PreviewSheet(target: target)
            }
        }
        .alert("Modello pesante", isPresented: $showHeavyAlert, presenting: heavyModel) { id in
            Button("Prova lo stesso") { Task { await agent.loadModel(id) } }
            Button("Annulla", role: .cancel) {}
        } message: { id in
            Text(ModelInfo.warning(id))
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { agent.attachFiles(urls) }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    agent.attachPhoto(data: data)
                }
                photoItem = nil
            }
        }
        .task { await agent.loadLastModelIfNeeded() }
    }

    // MARK: Scelta del modello

    private func choose(_ id: String) {
        guard !agent.isLoading else { return }
        if id == agent.currentModelID && agent.isReady { return }
        let present = {
            switch ModelInfo.weight(id) {
            case .heavy, .tooHeavy:
                heavyModel = id
                showHeavyAlert = true
            default:
                Task { await agent.loadModel(id) }
            }
        }
        if sheet != nil {
            sheet = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { present() }
        } else {
            present()
        }
    }

    private func menuTitle(_ id: String) -> String {
        let name = id.split(separator: "/").last.map(String.init) ?? id
        var title = name
        let size = ModelInfo.sizeLabel(id)
        if !size.isEmpty { title += " · " + size }
        switch ModelInfo.weight(id) {
        case .heavy, .tooHeavy: title += " ⚠︎"
        default: break
        }
        return title
    }

    private var titleText: String {
        if agent.isLoading { return "Scarico… \(Int(agent.downloadProgress * 100))%" }
        return agent.shortModelName
    }

    private var modelMenu: some View {
        Menu {
            Section("I tuoi modelli") {
                ForEach(library.saved, id: \.self) { id in
                    Button { choose(id) } label: {
                        if id == agent.currentModelID {
                            Label(menuTitle(id), systemImage: "checkmark")
                        } else {
                            Text(menuTitle(id))
                        }
                    }
                }
            }
            Divider()
            Button { sheet = .models } label: {
                Label("Scarica altri modelli…", systemImage: "arrow.down.circle")
            }
        } label: {
            HStack(spacing: 4) {
                Text(titleText).font(.headline).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
            }
        }
    }

    // MARK: Menu laterale

    private var drawer: some View {
        ZStack(alignment: .leading) {
            if showMenu {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { showMenu = false }
                    .transition(.opacity)
                SideMenu(
                    store: agent.store,
                    onNewChat: { agent.newChat(); showMenu = false },
                    onOpen: { thread in agent.open(thread); showMenu = false },
                    onDelete: { id in agent.deleteChat(id) },
                    onSheet: { target in
                        showMenu = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { sheet = target }
                    }
                )
                .frame(width: 310)
                .frame(maxHeight: .infinity)
                .glass(cornerRadius: 30)
                .padding(8)
                .transition(.move(edge: .leading))
                .gesture(
                    DragGesture().onEnded { value in
                        if value.translation.width < -60 { showMenu = false }
                    }
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showMenu)
    }

    // MARK: Chat

    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    if agent.isLoading { loadingChip }
                    if let err = agent.loadError { errorChip(err) }
                    if agent.items.isEmpty {
                        emptyState
                    } else {
                        ForEach(agent.items) { item in
                            row(item).id(item.id)
                        }
                    }
                    if let q = agent.pending, !q.options.isEmpty { optionsView(q) }
                    if let activity = agent.activity { activityChip(activity) }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: agent.items.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: agent.items.last?.text) { _, _ in scrollToBottom(proxy) }
            .onChange(of: agent.activity) { _, _ in scrollToBottom(proxy) }
            .onChange(of: agent.pending?.id) { _, _ in scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        proxy.scrollTo("bottom", anchor: .bottom)
    }

    private var loadingChip: some View {
        VStack(spacing: 6) {
            Text("Preparo \(agent.shortModelName)…").font(.subheadline.weight(.semibold))
            ProgressView(value: agent.downloadProgress)
            Text("La prima volta il modello va scaricato: serve il Wi-Fi.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(14)
        .glass(cornerRadius: 18)
    }

    private func errorChip(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.footnote)
            Spacer(minLength: 0)
        }
        .padding(12)
        .glass(cornerRadius: 16, tint: .orange)
    }

    private func activityChip(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(text).font(.footnote).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glass(cornerRadius: 18)
    }

    private func optionsView(_ q: PendingQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(q.options, id: \.self) { option in
                Button { agent.answer(option) } label: {
                    Text(option).frame(maxWidth: .infinity)
                }
                .modifier(GlassButton())
            }
            Text("…oppure scrivi la tua risposta qui sotto.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.9))
            Text("Cosa vuoi creare oggi?")
                .font(.title3.weight(.semibold))
            if agent.isReady {
                Text("Dimmi cosa ti serve: faccio tutto io e ti chiedo qualcosa solo se serve davvero.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                VStack(spacing: 8) {
                    ForEach(examples, id: \.self) { example in
                        Button { input = example } label: {
                            Text(example).font(.subheadline).frame(maxWidth: .infinity)
                        }
                        .modifier(GlassButton())
                    }
                }
            } else if !agent.isLoading {
                Text("Per cominciare scegli un modello dal menu in alto: tocca il nome al centro.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button { sheet = .models } label: {
                    Label("Scegli o scarica un modello", systemImage: "arrow.down.circle")
                        .padding(.horizontal, 8)
                }
                .modifier(GlassButton(prominent: true))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
    }

    @ViewBuilder
    private func row(_ item: ChatItem) -> some View {
        switch item.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(item.attachments, id: \.self) { name in
                        Label(name, systemImage: "paperclip").font(.caption)
                    }
                    Text(item.text).textSelection(.enabled)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .glass(cornerRadius: 20, tint: .blue)
            }
        case .assistant:
            HStack {
                Text(markdown(item.text.isEmpty ? "…" : item.text))
                    .textSelection(.enabled)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .glass(cornerRadius: 20)
                Spacer(minLength: 48)
            }
        case .tool:
            toolRow(item)
        }
    }

    @ViewBuilder
    private func toolRow(_ item: ChatItem) -> some View {
        if let path = item.previewPath {
            Button { openPreview(path) } label: {
                Label("Apri il sito  ·  \(path)", systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .modifier(GlassButton(prominent: true))
        } else {
            HStack(spacing: 8) {
                Image(systemName: item.ok ? icon(for: item.toolName) : "exclamationmark.triangle.fill")
                    .foregroundStyle(item.ok ? Color.teal : Color.orange)
                Text(item.text).font(.footnote).lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .glass(cornerRadius: 14, tint: item.ok ? .teal : .orange)
        }
    }

    private func icon(for tool: String?) -> String {
        ToolCall(name: tool ?? "", args: [:]).icon
    }

    private func openPreview(_ path: String) {
        let url = Workspace.root.appendingPathComponent(path)
        sheet = .preview(PreviewTarget(url: url, root: Workspace.root))
    }

    private func markdown(_ s: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: s, options: options)) ?? AttributedString(s)
    }

    // MARK: Barra di scrittura

    private var inputBar: some View {
        VStack(spacing: 8) {
            if !agent.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(agent.attachments, id: \.self) { name in
                            HStack(spacing: 6) {
                                Image(systemName: "paperclip")
                                Text(name).lineLimit(1)
                                Button { agent.removeAttachment(name) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                            .font(.footnote)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .glass(cornerRadius: 14)
                        }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                Menu {
                    Button { showFileImporter = true } label: { Label("File", systemImage: "doc") }
                    Button { showPhotoPicker = true } label: { Label("Foto", systemImage: "photo") }
                } label: {
                    Image(systemName: "plus").frame(width: 28, height: 28)
                }
                .modifier(GlassButton())
                .buttonBorderShape(.circle)

                TextField(placeholder, text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .glass(cornerRadius: 24, interactive: true)

                if agent.isGenerating && agent.pending == nil {
                    Button { agent.stop() } label: {
                        Image(systemName: "stop.fill").frame(width: 28, height: 28)
                    }
                    .modifier(GlassButton(prominent: true))
                    .buttonBorderShape(.circle)
                } else {
                    Button { sendTapped() } label: {
                        Image(systemName: "arrow.up").frame(width: 28, height: 28)
                    }
                    .modifier(GlassButton(prominent: true))
                    .buttonBorderShape(.circle)
                    .disabled(!canSend)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var placeholder: String {
        if agent.pending != nil { return "Scrivi la tua risposta…" }
        return agent.isReady ? "Dimmi cosa vuoi fare…" : "Prima scegli un modello…"
    }

    private func sendTapped() {
        let text = trimmedInput.isEmpty ? "Guarda i file che ti ho allegato." : trimmedInput
        input = ""
        agent.send(text)
    }
}
