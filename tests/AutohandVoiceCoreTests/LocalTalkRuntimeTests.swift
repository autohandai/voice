import XCTest
@testable import AutohandVoiceCore

final class LocalTalkRuntimeTests: XCTestCase {
    func testParsesCommandLineNames() {
        XCTAssertEqual(LocalTalkRuntime(argument: "mlx"), .mlx)
        XCTAssertEqual(LocalTalkRuntime(argument: "MLX"), .mlx)
        XCTAssertEqual(LocalTalkRuntime(argument: "llama"), .llamaCpp)
        XCTAssertEqual(LocalTalkRuntime(argument: "llama.cpp"), .llamaCpp)
        XCTAssertEqual(LocalTalkRuntime(argument: "gguf"), .llamaCpp)
        XCTAssertNil(LocalTalkRuntime(argument: "remote"))
    }

    func testAutomaticChoicePrefersMLXOnlyWhenItCanRunAndIsInstalled() {
        XCTAssertEqual(
            LocalTalkRuntime.resolve(requested: nil, mlxSupported: true, mlxInstalled: true),
            .mlx
        )
        XCTAssertEqual(
            LocalTalkRuntime.resolve(requested: nil, mlxSupported: true, mlxInstalled: false),
            .llamaCpp
        )
        // Intel and Rosetta: always llama.cpp, even with MLX files on disk.
        XCTAssertEqual(
            LocalTalkRuntime.resolve(requested: nil, mlxSupported: false, mlxInstalled: true),
            .llamaCpp
        )
    }

    func testExplicitChoiceIsNeverSwappedSilently() {
        // An explicit MLX request on an Intel Mac stays MLX, so the engine
        // reports itself unavailable instead of quietly using llama.cpp.
        XCTAssertEqual(
            LocalTalkRuntime.resolve(requested: .mlx, mlxSupported: false, mlxInstalled: false),
            .mlx
        )
        XCTAssertEqual(
            LocalTalkRuntime.resolve(requested: .llamaCpp, mlxSupported: true, mlxInstalled: true),
            .llamaCpp
        )
    }
}
