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

It finds the engine and the pages beside itself, then in this checkout (`--engine`, `--pages` say otherwise). The
engine in turn finds ONNX Runtime and the two models beside itself, then in the checkout. On Linux it needs
`libwebkit2gtk-4.1-dev` to build; on Windows, the WebView2 runtime to run.

## Checks

- `deckie-desk --self-test`: the window alone; one message each way with a small page, then exits.
- `deckie-desk --check`: the window, the engine and the pages; the page draws the engine's first screen and a
  request goes through it and back. It says how long after the program started the page showed the engine's words.
- `deckie-desk --check --music <folder> --export-to <folder>`: the same, then as a DJ would, through the page's own
  buttons: Add music with that folder, the run to its end, Export crate file. `--check-log <file>` writes what a
  check says to a file as well (a Windows program with no console has no standard error to read).
- `deckie-desk --tour <out> --music <folder> --export-to <folder>` (Mac only): steps through every screen with the
  music given and writes a picture of each (from the web view itself, so no screen-recording permission is needed).
  `DECKIE_DESK_DRIVES=<folder>` lists that folder's folders as the drives plugged in.

CI: `.github/workflows/desk-window.yml` builds and runs all of this on Linux (under Xvfb) and Windows.

## On Windows, in the zip

`core/Tools/windows/package.sh` puts the release build in the zip a DJ downloads, started by `Deckie Desk.exe`
(`.github/workflows/pc-package.yml` builds it and tries it from the unzipped folder):

- **No console window.** The copies of `deckie-desk.exe` and `deckie-desk-engine.exe` in the zip are marked as
  programs of the "windows" kind (`core/Tools/windows/pe_kind.py`). Such a program started by a double click has no
  standard output or error, so the shell gives itself harmless ones first (`deskshell_prepare_process`).
- **The icon** is the program's resource number 1 (`core/Tools/windows/icon.sh` makes it from the iPad app's
  picture; linked in with `-Xlinker <folder>/desk.res`). The shell sets it on the window (`set_icon` in
  `deskshell.cc`); a build without it keeps the plain icon.
- **A PC without Microsoft's WebView2 Runtime** gets no window. The shell then says so in a message box, names
  Microsoft's page, offers to open it and points to `Make Crate File`, and ends with code 4 (`Notice.swift`,
  `main.swift`). `DECKIE_NO_BOXES` says it on standard error instead, for checks; `DECKIE_DESK_NO_WEBVIEW2` makes
  the shell behave as on such a PC.
- The shell's own words to a DJ are the few in `Notice.swift`, since they must be said before there is a window.
