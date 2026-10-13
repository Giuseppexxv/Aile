import SwiftUI
import WebKit

struct PreviewTarget: Identifiable {
    let url: URL
    let root: URL
    var id: String { url.path }
}

struct WebView: UIViewRepresentable {
    let url: URL
    let readAccess: URL

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.loadFileURL(url, allowingReadAccessTo: readAccess)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct PreviewSheet: View {
    let target: PreviewTarget
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebView(url: target.url, readAccess: target.root)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(target.url.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fine") { dismiss() }
                    }
                }
        }
    }
}
