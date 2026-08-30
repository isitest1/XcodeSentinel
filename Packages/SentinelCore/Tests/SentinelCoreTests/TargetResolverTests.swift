import XCTest
@testable import SentinelCore

final class TargetResolverTests: XCTestCase {
    private let identity = TargetIdentity(
        workspacePath: "/Users/dev/code/SampleApp/SampleApp.xcodeproj",
        displayName: "SampleApp - main"
    )

    func testExactAXDocumentPathIsHighConfidence() {
        let windows = [
            WindowDescriptor(pid: 10, axDocumentPath: "/Users/dev/code/Other/Other.xcodeproj", axTitle: "Other"),
            WindowDescriptor(pid: 11, axDocumentPath: "/Users/dev/code/SampleApp/SampleApp.xcodeproj", axTitle: "SampleApp — ContentView.swift")
        ]
        guard case let .matched(win, confidence) = TargetResolver.resolve(identity, among: windows) else {
            return XCTFail("expected a match")
        }
        XCTAssertEqual(win.pid, 11)
        XCTAssertEqual(confidence, .high)
    }

    func testAXDocumentPathMatchesThroughFileURLAndPercentEncoding() {
        let windows = [
            WindowDescriptor(axDocumentPath: "file:///Users/dev/code/Sample%20App//SampleApp.xcodeproj/")
        ]
        let id = TargetIdentity(
            workspacePath: "/Users/dev/code/Sample App/SampleApp.xcodeproj",
            displayName: "x"
        )
        guard case let .matched(_, confidence) = TargetResolver.resolve(id, among: windows) else {
            return XCTFail("expected a match")
        }
        XCTAssertEqual(confidence, .high)
    }

    func testFallsBackToWorkspaceNameInTitle() {
        let windows = [
            WindowDescriptor(pid: 1, axTitle: "SampleApp — AppDelegate.swift — Edited")
        ]
        guard case let .matched(_, confidence) = TargetResolver.resolve(identity, among: windows) else {
            return XCTFail("expected a match")
        }
        XCTAssertEqual(confidence, .medium)
    }

    func testFallsBackToDisplayNameInTitle() {
        // Title carries only the display name, not the workspace file name.
        let id = TargetIdentity(workspacePath: "/x/Foo.xcodeproj", displayName: "my nightly build")
        let windows = [WindowDescriptor(pid: 2, axTitle: "my nightly build — file.swift")]
        guard case let .matched(_, confidence) = TargetResolver.resolve(id, among: windows) else {
            return XCTFail("expected a match")
        }
        XCTAssertEqual(confidence, .low)
    }

    func testNoMatchIsNotFound() {
        let windows = [WindowDescriptor(pid: 1, axTitle: "CompletelyDifferent — main.swift")]
        XCTAssertEqual(TargetResolver.resolve(identity, among: windows), .notFound)
    }

    func testEmptyWindowListIsNotFound() {
        XCTAssertEqual(TargetResolver.resolve(identity, among: []), .notFound)
    }

    func testTwoEqualBestMatchesAreAmbiguous() {
        let windows = [
            WindowDescriptor(pid: 1, axTitle: "SampleApp — a.swift"),
            WindowDescriptor(pid: 2, axTitle: "SampleApp — b.swift")
        ]
        guard case let .ambiguous(matches) = TargetResolver.resolve(identity, among: windows) else {
            return XCTFail("expected ambiguous")
        }
        XCTAssertEqual(matches.count, 2)
    }

    func testExactPathWinsOverTitleMatchOnAnotherWindow() {
        let windows = [
            WindowDescriptor(pid: 1, axTitle: "SampleApp — a.swift"),
            WindowDescriptor(pid: 2, axDocumentPath: identity.workspacePath, axTitle: "unrelated")
        ]
        guard case let .matched(win, confidence) = TargetResolver.resolve(identity, among: windows) else {
            return XCTFail("expected a match")
        }
        XCTAssertEqual(win.pid, 2)
        XCTAssertEqual(confidence, .high)
    }
}

final class WorkspacePathTests: XCTestCase {
    func testNameStripsExtension() {
        XCTAssertEqual(WorkspacePath.name(from: "/a/b/SampleApp.xcodeproj"), "SampleApp")
        XCTAssertEqual(WorkspacePath.name(from: "/a/b/My.App.xcworkspace"), "My.App")
        XCTAssertEqual(WorkspacePath.name(from: "/a/b/SampleApp.xcworkspace/"), "SampleApp")
    }

    func testNameOfExtensionlessFolder() {
        XCTAssertEqual(WorkspacePath.name(from: "/a/b/MyPackage"), "MyPackage")
        XCTAssertEqual(WorkspacePath.name(from: "MyPackage"), "MyPackage")
    }

    func testNameOfEmpty() {
        XCTAssertEqual(WorkspacePath.name(from: ""), "")
    }

    func testNormalizeStripsSchemeAndDecodesAndCollapses() {
        XCTAssertEqual(
            WorkspacePath.normalize("file:///Users/dev/Sample%20App//Foo.xcodeproj/"),
            "/Users/dev/Sample App/Foo.xcodeproj"
        )
    }

    func testNormalizeKeepsBareRootSlash() {
        XCTAssertEqual(WorkspacePath.normalize("/"), "/")
    }
}
