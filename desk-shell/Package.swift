// swift-tools-version: 6.0
// Deckie Desk's window on Windows and Linux (D32): a small Swift program, `deckie-desk`, that opens a window holding
// the system's web view, shows the pages in `desk-web/` and passes messages between them and the engine program
// (`deckie-desk-engine` in `core/`, docs/architecture/desk-protocol.md). It builds on the Mac too, with WKWebView, so
// the pages can be looked at here; the Mac's own Desk stays the SwiftUI app in `desk-app/`.
//
// CDeskShell: the vendored `webview` library (0.12.0, MIT) compiled as C++, with a C interface for Swift
// (deskshell.h) and the system's folder and file choosers on Windows and Linux. On Windows it includes Microsoft's
// WebView2.h (SDK 1.0.4191.47, BSD-3-Clause) and loads WebView2 at run time with the library's own loader, so no
// WebView2Loader.dll travels with it. Both are pinned by hash in DEPENDENCIES.md; nothing is fetched at build time.
// CWebKitGTK: Linux only; WebKitGTK's and GTK's flags from pkg-config (libwebkit2gtk-4.1-dev), supplied by the system.
import PackageDescription

let package = Package(
    name: "DeckieDeskShell",
    products: [
        .executable(name: "deckie-desk", targets: ["deckie-desk"]),
    ],
    targets: [
        .systemLibrary(name: "CWebKitGTK", pkgConfig: "webkit2gtk-4.1",
                       providers: [.apt(["libwebkit2gtk-4.1-dev"])]),
        .target(
            name: "CDeskShell",
            dependencies: [.target(name: "CWebKitGTK", condition: .when(platforms: [.linux]))],
            exclude: ["vendor/webview/LICENSE", "vendor/WebView2/LICENSE.txt"],
            cxxSettings: [
                .headerSearchPath("vendor/WebView2", .when(platforms: [.windows])),
                .define("WEBVIEW_GTK", .when(platforms: [.linux])),
                .define("WEBVIEW_EDGE", .when(platforms: [.windows])),
                .define("WEBVIEW_COCOA", .when(platforms: [.macOS])),
                .define("UNICODE", .when(platforms: [.windows])),
                .define("_UNICODE", .when(platforms: [.windows])),
                .define("NOMINMAX", .when(platforms: [.windows])),
            ],
            linkerSettings: [
                .linkedFramework("WebKit", .when(platforms: [.macOS])),
                .linkedFramework("Cocoa", .when(platforms: [.macOS])),
                .linkedLibrary("advapi32", .when(platforms: [.windows])),
                .linkedLibrary("ole32", .when(platforms: [.windows])),
                .linkedLibrary("shell32", .when(platforms: [.windows])),
                .linkedLibrary("shlwapi", .when(platforms: [.windows])),
                .linkedLibrary("user32", .when(platforms: [.windows])),
                .linkedLibrary("version", .when(platforms: [.windows])),
            ]),
        .executableTarget(name: "deckie-desk", dependencies: ["CDeskShell"]),
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
