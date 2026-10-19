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
            dependencies: ["AutohandVoiceCore", "AutohandVoiceQwenASR"]
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
