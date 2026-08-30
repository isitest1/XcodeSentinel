import XCTest
@testable import SentinelCore

final class AccessibilitySnapshotTests: XCTestCase {
    func testDecodeToleratesMissingOptionalFields() throws {
        let json = #"{ "root": { "role": "AXGroup", "children": [ { "role": "AXStaticText", "value": "hi" } ] } }"#
        let snapshot = try AXSnapshot.decode(from: Data(json.utf8))
        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertNil(snapshot.targetName)
        XCTAssertEqual(snapshot.root.children.first?.isEnabled, true)
        XCTAssertEqual(snapshot.root.children.first?.isFocused, false)
    }

    func testRoundTrip() throws {
        let original = AXSnapshot(
            targetName: "SampleApp",
            capturedAt: makeDate(2026, 8, 30, 12, 0),
            xcodeVersion: "16.0",
            root: AXNode(role: "AXGroup", children: [
                AXNode(role: "AXStaticText", value: "Generating…"),
                AXNode(role: "AXButton", title: "Send", isEnabled: false)
            ])
        )
        let restored = try AXSnapshot.decode(from: original.encoded())
        XCTAssertEqual(restored, original)
    }

    func testFlattenedIsDepthFirst() {
        let tree = AXNode(role: "root", value: "0", children: [
            AXNode(role: "a", value: "1", children: [AXNode(role: "a1", value: "2")]),
            AXNode(role: "b", value: "3")
        ])
        XCTAssertEqual(tree.flattened().compactMap(\.value), ["0", "1", "2", "3"])
    }

    func testTextsSkipsBlankValues() {
        let node = AXNode(role: "x", title: "  ", value: "real", descriptionText: "")
        XCTAssertEqual(node.texts, ["real"])
    }

    func testAllTextsCollectsEverything() {
        let snapshot = AXSnapshot(root: AXNode(role: "g", children: [
            AXNode(role: "AXStaticText", value: "one"),
            AXNode(role: "AXStaticText", value: "two", descriptionText: "three")
        ]))
        XCTAssertEqual(Set(snapshot.allTexts), ["one", "two", "three"])
    }
}
