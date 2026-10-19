// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AutohandVoice",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "AutohandVoiceCore", targets: ["AutohandVoiceCore"]),
        .library(
            name: "AutohandVoiceQwenASR",
            targets: ["AutohandVoiceQwenASR"]
        ),
        .executable(name: "autohand-voice", targets: ["AutohandVoice"]),
        .executable(name: "autohand-voice-stt", targets: ["AutohandVoiceSTT"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            exact: "0.15.8"
        ),
        // Optional local Qwen3-ASR engine (Apple Silicon only). 0.31.4 is
        // the newest release that resolves with tools 5.9 / Swift 6.0.
        .package(
            url: "https://github.com/ml-explore/mlx-swift",
            exact: "0.31.4"
        ),
    ],
    targets: [
        // llama.cpp b11721 (MIT): a universal macOS framework with Metal
        // shaders built in. Runs the optional on-device Talk model.
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11721/llama-b11721-xcframework.zip",
            checksum: "9efc8f94a7fb54abb4931bac484a025417cee5bbf8e15ba49b4d9ddef997460f"
        ),
        .target(
            name: "AutohandVoiceLLM",
            dependencies: ["AutohandVoiceCore", "llama"]
        ),
        .target(
            name: "AutohandVoiceCore",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .target(
            name: "AutohandVoiceQwenASR",
            dependencies: [
                "AutohandVoiceCore",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
            ],
            exclude: [
                "Vendor/SpeechSwift/LICENSE",
                "Vendor/SpeechSwift/NOTICE.md",
            ]
        ),
        .executableTarget(
            name: "AutohandVoice",
            dependencies: ["AutohandVoiceCore", "AutohandVoiceLLM", "AutohandVoiceQwenASR"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
        ),
        .executableTarget(
            name: "AutohandVoiceSTT",
            dependencies: ["AutohandVoiceCore", "AutohandVoiceQwenASR"]
        ),
        .testTarget(
            name: "AutohandVoiceCoreTests",
            dependencies: ["AutohandVoiceCore"]
        ),
        .testTarget(
            name: "AutohandVoiceQwenASRTests",
            dependencies: ["AutohandVoiceQwenASR", "AutohandVoiceCore"]
        ),
    ]
)
