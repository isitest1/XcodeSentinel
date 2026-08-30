// macOS only. Build on the host with Xcode (see App/README.md).
#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import SentinelCore
import UniformTypeIdentifiers

/// The AX Inspector (CLAUDE.md section 10). Dumps a selected window's AX tree
/// with role/title/value/identifier, highlights the pattern currently matching,
/// supports text search, and exports the tree as `AXSnapshot` JSON for bug
/// reports and Linux test fixtures.
///
/// Skeleton: tree rendering and live matching are built on the host.
struct AXInspectorView: View {
    let model: AppModel
    @State private var snapshot: AXSnapshot?
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Button("Capture Selected Window") {
                    // TODO(host): AXTreeReader().snapshot(ofWindow:...)
                }
                TextField("Search text", text: $search)
                Button("Export JSON…") { export() }
                    .disabled(snapshot == nil)
            }
            if let snapshot {
                Text("\(snapshot.root.flattened().count) nodes")
                    .font(.caption).foregroundStyle(.secondary)
                // TODO(host): OutlineGroup over AXNode.children with highlight.
            } else {
                Text("No capture yet.").foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
    }

    private func export() {
        guard let snapshot, let data = try? snapshot.encoded() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ax-snapshot.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }
}
#endif
