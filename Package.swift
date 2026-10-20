// swift-tools-version:6.0
import PackageDescription

// MuPDF is built out of tree by `make deps` (see Makefile) into build/deps/mupdf.
// SwiftPM cannot drive MuPDF's own make-based build, so we link the prebuilt
// static archives and point both clang and the Swift importer at its headers.
let root = Context.packageDirectory
let mupdfInclude = "\(root)/Vendor/mupdf/include"
let mupdfLib = "\(root)/build/deps/mupdf"

let package = Package(
    name: "SiliconReader",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SiliconReader", targets: ["SiliconReader"])
    ],
    targets: [
        .target(
            name: "CMuPDF",
            cSettings: [.unsafeFlags(["-I", mupdfInclude])],
            linkerSettings: [
                .unsafeFlags(["-L", mupdfLib]),
                .linkedLibrary("mupdf"),
                .linkedLibrary("mupdf-third"),
            ]
        ),
        .target(
            name: "CDjVu",
            path: "Vendor/djvudec",
            exclude: ["LICENSE.md"],
            sources: ["djvu.c"],
            publicHeadersPath: ".",
            cSettings: [.unsafeFlags(["-O2", "-w"])]
        ),
        .target(
            name: "ReaderCore",
            dependencies: ["CMuPDF", "CDjVu"]
        ),
        .executableTarget(
            name: "SiliconReader",
            dependencies: ["ReaderCore"]
        ),
        .testTarget(
            name: "ReaderCoreTests",
            dependencies: ["ReaderCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
