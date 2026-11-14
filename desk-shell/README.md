# Deckie Desk's window on Windows and Linux

D32: Desk on Windows and Linux is web pages (`../desk-web/`) in a window of its own. This folder is that window: a
small Swift program, `deckie-desk`, over the system's own web view (WebView2 on Windows, WebKitGTK on Linux, WKWebView
on the Mac) through the vendored `webview` library (`DEPENDENCIES.md`, sections 9 and 10). It starts the engine
program, `deckie-desk-engine` (`../core`), and passes messages between it and the pages
(`../docs/architecture/desk-protocol.md`). It holds no Deckie logic: folder choosers, opening a folder, folders
dropped on the window, and the passing of messages.

The Mac keeps its own Desk (`../desk-app/`); this builds on the Mac too, so the pages can be seen there.

## Build and run

    cd core && swift build --product deckie-desk-engine        # the engine
    cd desk-shell && swift build                               # the window
    DECKIE_DESK_HOME=/tmp/desk DECKIE_DJ_HOME=/tmp/dj .build/debug/deckie-desk

It finds the engine and the pages beside itself, then in this checkout (`--engine`, `--pages` say otherwise). On
Linux it needs `libwebkit2gtk-4.1-dev` to build; on Windows, the WebView2 runtime to run.

## Checks

- `deckie-desk --self-test`: the window alone; one message each way with a small page, then exits.
- `deckie-desk --check`: the window, the engine and the pages; the page draws the engine's first screen and a
  request goes through it and back.
- `deckie-desk --tour <out> --music <folder> --export-to <folder>` (Mac only): steps through every screen with the
  music given and writes a picture of each (from the web view itself, so no screen-recording permission is needed).
  `DECKIE_DESK_DRIVES=<folder>` lists that folder's folders as the drives plugged in.

CI: `.github/workflows/desk-window.yml` builds and runs all of this on Linux (under Xvfb) and Windows.
