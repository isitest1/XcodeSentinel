import SwiftUI
import SentinelCore
import UniformTypeIdentifiers

// MARK: - Tree node wrapper (Identifiable for OutlineGroup)

private final class AXNodeItem: Identifiable, @unchecked Sendable {
    let id = UUID()
    let node: AXNode
    /// nil means "leaf" for OutlineGroup's children: key path.
    let childItems: [AXNodeItem]?

    init(_ node: AXNode) {
        self.node = node
        self.childItems = node.children.isEmpty ? nil : node.children.map { AXNodeItem($0) }
    }
}

// MARK: - Inspector view

/// AX Inspector (CLAUDE.md §10). Captures a selected Xcode window's AX tree,
/// displays it with role/title/value/identifier, supports text search, and
/// exports the snapshot as JSON for bug reports and Linux test fixtures.
struct AXInspectorView: View {
    let model: AppModel

    @State private var availableWindows: [WindowDescriptor] = []
    @State private var selectedWindowIndex: Int = 0
    @State private var snapshot: AXSnapshot?
    @State private var rootItems: [AXNodeItem] = []
    @State private var search = ""
    @State private var isCapturing = false
    @State private var statusMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if rootItems.isEmpty {
                emptyState
            } else {
                treeContent
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .task { await refreshWindows() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("Window:", selection: $selectedWindowIndex) {
                if availableWindows.isEmpty {
                    Text("No Xcode windows found").tag(0)
                } else {
                    ForEach(availableWindows.indices, id: \.self) { i in
                        Text(availableWindows[i].displayLabel).tag(i)
                    }
                }
            }
            .frame(maxWidth: 300)

            Button("Refresh") { Task { await refreshWindows() } }

            Button(isCapturing ? "Capturing…" : "Capture") {
                Task { await captureSelected() }
            }
            .disabled(availableWindows.isEmpty || isCapturing)
            .keyboardShortcut("r", modifiers: .command)

            Spacer()

            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

            Button("Export JSON…") { exportJSON() }
                .disabled(snapshot == nil)
        }
        .padding(10)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "eye.slash")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            if statusMessage.isEmpty {
                Text("Select a window and press Capture.")
                    .foregroundStyle(.secondary)
            } else {
                Text(statusMessage).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Tree

    private var treeContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let snapshot {
                let total = snapshot.root.flattened().count
                let matches = search.isEmpty ? 0 : countMatches(in: snapshot.root)
                Text("\(total) nodes\(search.isEmpty ? "" : " · \(matches) match\(matches == 1 ? "" : "es") — showing all below")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                Divider()
            }

            if search.isEmpty {
                List(rootItems, children: \.childItems) { item in
                    NodeRowView(item: item, search: search)
                }
                .listStyle(.sidebar)
            } else {
                flatSearchResultsView
            }
        }
    }

    // Flat list of every matching node with breadcrumb path, shown while searching.
    private var flatSearchResultsView: some View {
        let matches = flatMatches()
        return Group {
            if matches.isEmpty {
                VStack {
                    Spacer()
                    Text("No matches for \"\(search)\"")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(Array(matches.enumerated()), id: \.offset) { _, match in
                    FlatMatchRow(node: match.node, breadcrumb: match.breadcrumb)
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func refreshWindows() async {
        availableWindows = await model.xcodeWindows()
        if selectedWindowIndex >= availableWindows.count {
            selectedWindowIndex = 0
        }
    }

    private func captureSelected() async {
        guard !availableWindows.isEmpty else { return }
        isCapturing = true
        statusMessage = ""
        defer { isCapturing = false }

        let descriptor = availableWindows[selectedWindowIndex]
        let captured: AXSnapshot? = await AccessibilityActor.run {
            guard let element = XcodeWindowEnumerator().liveElement(for: descriptor) else {
                return nil
            }
            return AXTreeReader().snapshot(
                ofWindow: element,
                targetName: descriptor.displayLabel
            )
        }

        if let captured {
            snapshot = captured
            rootItems = [AXNodeItem(captured.root)]
            statusMessage = ""
        } else {
            statusMessage = "Could not read window. Is Accessibility permission granted?"
        }
    }

    private func exportJSON() {
        guard let snapshot, let data = try? snapshot.encoded() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ax-snapshot.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func countMatches(in node: AXNode) -> Int {
        flatMatches().count
    }

    // MARK: - Flat search helpers

    private struct FlatMatch {
        let node: AXNode
        let breadcrumb: String  // parent path, e.g. "AXWindow › AXSplitGroup › AXGroup"
    }

    private func flatMatches() -> [FlatMatch] {
        guard let snapshot, !search.isEmpty else { return [] }
        return collectMatches(in: snapshot.root, path: [], query: search.lowercased())
    }

    private func collectMatches(in node: AXNode, path: [String], query: String) -> [FlatMatch] {
        let label: String = {
            var parts = [node.role]
            if let t = node.title { parts.append("\"\(t)\"") }
            return parts.joined(separator: " ")
        }()
        let childPath = path + [label]
        var results: [FlatMatch] = []
        if node.texts.contains(where: { $0.localizedCaseInsensitiveContains(query) }) {
            results.append(FlatMatch(node: node, breadcrumb: path.joined(separator: " › ")))
        }
        for child in node.children {
            results += collectMatches(in: child, path: childPath, query: query)
        }
        return results
    }
}

// MARK: - Node row

private struct NodeRowView: View {
    let item: AXNodeItem
    let search: String

    private var node: AXNode { item.node }

    private var isMatch: Bool {
        guard !search.isEmpty else { return false }
        return node.texts.contains { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(node.role)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(isMatch ? Color.orange : Color.primary)
                .bold(isMatch)

            VStack(alignment: .leading, spacing: 2) {
                if let title = node.title {
                    attribute(label: "title", value: title, color: .secondary)
                }
                if let value = node.value {
                    attribute(label: "val", value: value, color: .blue)
                }
                if let desc = node.descriptionText {
                    attribute(label: "desc", value: desc, color: .secondary)
                }
                if let id = node.identifier {
                    attribute(label: "id", value: id, color: .purple)
                }
            }

            Spacer()

            if !node.isEnabled {
                Text("disabled").font(.caption2).foregroundStyle(.red)
            }
            if node.isFocused {
                Image(systemName: "scope").font(.caption).foregroundStyle(.green)
            }
        }
        .padding(.vertical, 1)
        .listRowBackground(isMatch ? Color.orange.opacity(0.12) : Color.clear)
    }

    private func attribute(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(label + "=")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(color)
                .lineLimit(3)
        }
    }
}

// MARK: - Flat search result row

private struct FlatMatchRow: View {
    let node: AXNode
    let breadcrumb: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !breadcrumb.isEmpty {
                Text(breadcrumb)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            HStack(alignment: .top, spacing: 6) {
                Text(node.role)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.orange)
                    .bold()
                VStack(alignment: .leading, spacing: 2) {
                    if let title = node.title {
                        labeledValue("title", value: title, color: .secondary)
                    }
                    if let value = node.value {
                        labeledValue("val", value: value, color: .blue)
                    }
                    if let desc = node.descriptionText {
                        labeledValue("desc", value: desc, color: .secondary)
                    }
                    if let id = node.identifier {
                        labeledValue("id", value: id, color: .purple)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func labeledValue(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(label + "=").font(.caption).foregroundStyle(.secondary)
            Text(value).font(.caption).foregroundStyle(color).lineLimit(2)
        }
    }
}

