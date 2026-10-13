import SwiftUI

struct FilesView: View {
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var files: [URL] = []

    var body: some View {
        NavigationStack {
            Group {
                if files.isEmpty {
                    ContentUnavailableView(
                        "Il progetto è vuoto",
                        systemImage: "folder",
                        description: Text("I file creati dall'agente compaiono qui e nell'app File, sotto Su iPhone > Agente Locale > Progetti.")
                    )
                } else {
                    List {
                        ForEach(files, id: \.self) { url in
                            NavigationLink(Workspace.relativePath(url)) {
                                FileViewer(url: url)
                            }
                        }
                        .onDelete { offsets in
                            for i in offsets { try? FileManager.default.removeItem(at: files[i]) }
                            files = Workspace.allFiles()
                        }
                    }
                }
            }
            .navigationTitle(store.currentProject.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }
                }
            }
            .onAppear { files = Workspace.allFiles() }
        }
    }
}

struct FileViewer: View {
    let url: URL
    @State private var text = ""
    @State private var preview: PreviewTarget?

    private var isHTML: Bool {
        ["html", "htm"].contains(url.pathExtension.lowercased())
    }

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(url.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isHTML {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        preview = PreviewTarget(url: url, root: Workspace.root)
                    } label: {
                        Image(systemName: "safari")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: url)
            }
        }
        .sheet(item: $preview) { target in
            PreviewSheet(target: target)
        }
        .onAppear {
            text = (try? Workspace.readText(url)) ?? "(file non leggibile come testo)"
        }
    }
}
