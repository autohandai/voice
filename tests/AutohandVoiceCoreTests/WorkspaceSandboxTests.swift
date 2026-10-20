import XCTest
@testable import AutohandVoiceCore

final class WorkspaceSandboxTests: XCTestCase {
    private var root: URL!
    private var sandbox: WorkspaceSandbox!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        sandbox = WorkspaceSandbox(root: root)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    func testFilesAreWrittenAndReadInsideTheWorkspace() throws {
        try sandbox.write("notes/plan.md", contents: "# Plan\n")
        XCTAssertEqual(try sandbox.read("notes/plan.md"), "# Plan\n")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("notes/plan.md").path
        ))
    }

    func testListingShowsFoldersAndFilesSorted() throws {
        try sandbox.write("b.txt", contents: "b")
        try sandbox.write("a/inner.txt", contents: "a")
        let entries = try sandbox.list("")
        XCTAssertEqual(entries.map(\.name), ["a", "b.txt"])
        XCTAssertEqual(entries.map(\.isDirectory), [true, false])
    }

    func testPathsCannotEscapeTheWorkspace() {
        for path in ["../outside.txt", "/etc/hosts", "a/../../outside.txt", "~/x"] {
            XCTAssertThrowsError(try sandbox.read(path), path) { error in
                XCTAssertEqual(error as? WorkspaceSandbox.Failure, .outsideWorkspace, path)
            }
        }
    }

    func testASymlinkPointingOutsideIsRefused() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try "secret".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link.txt"),
            withDestinationURL: outside
        )
        XCTAssertThrowsError(try sandbox.read("link.txt")) { error in
            XCTAssertEqual(error as? WorkspaceSandbox.Failure, .outsideWorkspace)
        }
    }

    func testLargeFilesAreRefusedRatherThanTruncatedSilently() throws {
        let big = String(repeating: "x", count: WorkspaceSandbox.maximumReadBytes + 1)
        try big.write(to: root.appendingPathComponent("big.txt"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try sandbox.read("big.txt")) { error in
            XCTAssertEqual(error as? WorkspaceSandbox.Failure, .tooLarge)
        }
        XCTAssertThrowsError(
            try sandbox.write("huge.txt", contents: String(repeating: "y", count: WorkspaceSandbox.maximumWriteBytes + 1))
        ) { error in
            XCTAssertEqual(error as? WorkspaceSandbox.Failure, .tooLarge)
        }
    }

    func testMissingFilesSaySo() {
        XCTAssertThrowsError(try sandbox.read("nope.txt")) { error in
            XCTAssertEqual(error as? WorkspaceSandbox.Failure, .notFound)
        }
    }

    func testDefaultWorkspaceIsTheDesktop() {
        XCTAssertEqual(
            WorkspaceSandbox.defaultRoot.lastPathComponent,
            "Desktop"
        )
    }
}
