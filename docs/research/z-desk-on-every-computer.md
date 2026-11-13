# Research Z: Deckie Desk on every computer

Dated Nov 13, 2026. A survey with options and a recommendation, no decisions and no code. It follows D29 (a PC
version is wanted) and the owner's words: "I think we will start with web then move to native app but I want to know
the options." It builds on letter M (the core language, and its note that a Windows window in Swift is hard), letter
L (what carries off Apple), `docs/product/desk.md` (what Desk does), D14, D21 and D25 to D29, and the dependency
policy in `DEPENDENCIES.md`. Web research and reading only: nothing was built or measured except where a line says
"in this repository".

Tags on claims: **[opened]** = I opened and read the source today; **[search]** = I have it only from a search
result's summary today and did not open the page; **[mem]** = from general knowledge, not re-read today, so it may
be out of date; **[inf]** = my inference, with the reasoning; **[unverified]** = I looked and could not confirm.
Effort is in agent-assisted weeks of the owner's attention, as in letter M, and every effort figure is [inf]. This
field moves quickly: every dated fact is as of the date given. Nothing here is legal advice.

## In plain words

Deckie Desk has two halves. The **engine** is everything under the window: it reads the music, works out tempo,
key and bars, and writes the crate file. It is written in Swift and already builds on Mac, Windows and Linux. The
**interface** is the window a DJ sees and clicks. Today the only interface is the Mac's, built with Apple's own
window tools, which exist only on Apple computers. So a PC needs a new interface, and the question is what to build
it with.

There are four families of answer.

1. **A web-style interface.** The window's contents are a web page (HTML for structure, CSS for looks, JavaScript
   for behaviour), but the page lives on the DJ's own computer and talks only to the engine there. Nothing goes to
   the internet. The page can be shown in the DJ's ordinary browser, or inside a **web view**: a browser with no
   address bar that an app embeds in its own window. Windows, Linux and the Mac each ship a web view (WebView2,
   WebKitGTK and WKWebView). A small program that opens a window and puts a web view in it is called a **shell**.
   Tauri and Electron are ready-made shells; Electron brings its own copy of the Chrome browser, Tauri uses the
   one the computer already has.
2. **Native per platform.** Each computer's own window tools: Microsoft's on Windows (WinUI 3 or WPF, normally
   written in the C# language), GTK or Qt on Linux, Apple's SwiftUI on the Mac. Three interfaces, each at home.
3. **Swift all the way.** Use Swift for the Windows and Linux windows too, through young community projects that
   connect Swift to Microsoft's and Linux's window tools.
4. **One cross-platform toolkit.** A single framework that draws the same interface on every desktop (Qt,
   Flutter, Avalonia and others). Each brings its own programming language.

However the interface is built, it has to **talk to the engine**. A **protocol** is the agreed list of messages
between the two ("add this folder", "song 12 of 240 done", "stop"). If the protocol is clean and all the thinking
stays in the engine, the interface is thin and can be replaced later without touching the engine. That is what
makes "web now, native later" cheap or expensive.

Getting a program onto a stranger's Windows PC has its own hurdle. Windows shows a blue warning, "Windows protected
your PC", for programs it does not know. **Code signing** is a digital signature that says who made a program; it
needs a certificate bought from an authority, or Microsoft's own signing service. A signature alone no longer
removes the warning: Windows also wants **reputation**, meaning many people have run the file without trouble.
Programs installed from the Microsoft Store never show the warning.

Last, the Mac flow ends with AirDrop, Apple's way to send a file to a nearby iPad. Windows has no AirDrop, so
"Send to iPad" needs another road on a PC.

**What this letter finds, in short.**

- The engine being Swift does not force the interface to be Swift. A separate engine program that the interface
  starts and talks to in plain text messages is the cheapest, safest join, and it is how many well-known tools work.
- A web-style interface inside the computer's own web view, with a small shell, is the quickest route to a real
  Windows and Linux app, and it can reuse the site's look. Showing it in the DJ's ordinary browser is quicker
  still to start but has real gaps: a browser will not tell the engine where a folder is, and the app has no window
  of its own.
- Swift for the Windows window is not ready to bet a product on. The best-known bindings were archived in Oct 2025
  and the one large app built that way is being retired.
- "Web now, native later" is honest only in a narrow sense. Teams rarely move from web to native; the public
  examples mostly went the other way. What does carry is the engine, the protocol, the words and the design. Plan
  for the web interface to last, and keep it thin so the choice stays open.
- For the first tester, the Microsoft Store is the one route with no warning screen, and registration is now free.
  Outside the Store, Microsoft's signing service costs $9.99 a month, and early downloads still see a warning.
- A crate file is a folder of many small files, 22 MB and 141 MB for the two real crates on this Mac. On Windows
  the realistic ways to an iPad are a USB stick, iCloud Drive, or a cable. Email is out.

## Where things stand in this repository

- `core/Sources/DeckieDesk` holds the app logic that is not about windows (the crates Desk keeps, the one run,
  name corrections, undo data): 1,062 lines of Swift across 8 files.
- `desk-app/Desk/Sources` is the Mac window: 2,222 lines of Swift. It uses Apple's file chooser (`NSOpenPanel`) in
  six places and Apple's share sheet (`NSSharingServicePicker`) for "Send to iPad". Those are the Mac-only parts a
  PC interface must replace.
- The PC and Linux status log says Windows "builds and passes everything that needs no model". A full run with the
  models on a real Windows PC is not yet recorded there. **That has to pass before any interface matters.**
- D29 also needs the core to recognise songs and read key without Apple. That work is separate from this letter
  and is not solved by any interface choice.
- A crate file is a package folder (`crate-format.md`): the Mac shows it as one file, Windows shows a folder.
  The two crates under `~/Music/Deckie` on this Mac are 22 MB and 141 MB, each made of one small file or more per
  song. This matters in section 7.
- The booth app already declares file sharing and opening documents in place (`deck-app/Deck/Info.plist`), which
  two of the transfer routes in section 7 depend on.

## 1. The options, side by side

### 1.1 What each is, what it asks of the team, and whether its licence fits

The allowlist (`DEPENDENCIES.md`, letter M 3.4): MIT, BSD, Apache 2.0, ISC, zlib, public domain and CC0 ship; LGPL
ships only as a separately loaded library; MPL 2.0 ships unmodified; GPL and AGPL never ship. "Use the platform
first" covers parts that come with the operating system, such as a web view.

| Option | What it is | What the team must know | Licence, and fit | Maturity, and who ships with it |
|---|---|---|---|---|
| **Engine serves pages to the default browser** | The engine runs a small web server that only this computer can reach; the DJ's browser shows the pages | HTML, CSS, JavaScript; a small web server inside the Swift engine | Nothing new to license. But SwiftNIO, the usual Swift server library (Apache 2.0), says it is "developed and tested on macOS and Linux" and does not list Windows [opened], so the server would be hand-written or need a Windows check | Old and proven as a pattern: Syncthing (file sync) serves its interface at 127.0.0.1:8384 [opened]; Jupyter does the same [mem] |
| **Own small shell around the system web view** | A tiny program opens a window holding WebView2 (Windows), WebKitGTK (Linux) or WKWebView (Mac) and starts the engine | The same web skills, plus a little window code per platform. The `webview` library (MIT, 14.3k stars) wraps all three behind one C interface, which Swift can call directly [opened] | MIT fits. WebView2 comes with Windows 11 and is on "the vast majority" of Windows 10 PCs [opened]; WebKitGTK is LGPL and comes from the Linux system, separately loaded, so it fits | The pattern is what Tauri, Wails and Neutralino do underneath. The `webview` library itself has no file chooser, no installer and no update system; those are ours to add [opened, inf] |
| **Tauri 2** | A ready-made shell on the system web view, written in Rust, with an installer builder, updater, tray icon, file dialogs and a way to bundle and start another program (a "sidecar") | Web skills, and a few hundred lines of Rust for the shell; the Rust toolchain on the build machines | MIT or Apache 2.0 [opened]: fits. It pulls in a large tree of Rust packages, which the dependency policy would have to admit and gate (letter M: `cargo-deny` does this well) | Active: releases through mid 2026 [search]. Windows 10 and up, Linux with webkit2gtk 4.1 (Ubuntu 22.04 and up) [opened]. Security audit for major and minor releases [opened] |
| **Electron** | A shell that carries its own copy of Chrome and of Node.js (a JavaScript runtime) | Web skills and Node.js | MIT [mem]: fits | The most used desktop web shell. Lexicon and DJ.Studio ship with it (letter M); 1Password 8 pairs it with a Rust core [opened] |
| **Wails** | Like Tauri, with Go in place of Rust | Web skills and Go | MIT [mem]: fits | Version 2 is the stable line; version 3 reached beta on Aug 2, 2026 [search] |
| **Neutralino** | A very small shell on the system web view with a built-in local server | Web skills | MIT [mem]: fits | Version 6.8.0, June 2026 [search]. Small community; fewer ready-made parts |
| **WinUI 3 in C#** (Windows) | Microsoft's current native toolkit | C#, XAML (Microsoft's layout language), Visual Studio | MIT; Microsoft finished open-sourcing it in Aug 2026 [search]: fits | Windows App SDK 2.0 shipped Apr 29, 2026, with later 2.x releases [search]. Microsoft said in 2026 it is building new "100% native" Windows apps on it [search] |
| **WPF in C#** (Windows) | Microsoft's older native toolkit, since 2006 | C#, XAML | MIT [mem]: fits | Very mature; Mixed In Key began as a C# .NET Windows app (letter M) |
| **GTK 4** (Linux) | The GNOME desktop's toolkit, a C library | C interface, callable from Swift | LGPL [mem], supplied by the system: fits | Mature on Linux; poor fit on Windows [mem] |
| **Qt 6** (all desktops) | A C++ toolkit, with its own layout language QML | C++ and QML, CMake | LGPL version 3, GPL, or commercial. LGPL fits only as separately loaded libraries, with LGPL 3's duties [mem]. Commercial: Qt for Small Business, under 1 million euros a year revenue, 546 euros a year per developer for desktop apps [search] | The DJ industry's toolkit: Mixxx; Serato's legal notices list Qt under LGPL 3.0 [opened]; Engine DJ scanned as a Qt app [search] |
| **Swift with WinUI** (swift-winrt) | Generated Swift bindings to Microsoft's WinUI | Swift, plus WinUI's ideas, plus the binding generator | BSD-3 [opened]: fits | See 1.3. The reference bindings, `swift-winui`, were archived Oct 16, 2025 and call themselves "an outdated snapshot"; x64 only [opened] |
| **SwiftCrossUI** | A SwiftUI-like toolkit in Swift with backends for WinUI, GTK and AppKit | Swift | MIT [opened]: fits | 1.8k stars, no numbered releases listed, "still a work-in-progress"; the WinUI and GTK backends support "most" features, AppKit "all" [opened] |
| **Flutter** | Google's toolkit; draws everything itself; Dart language | Dart | BSD-3 [mem]: fits | Mature on phones, sound on desktop [mem]. LocalSend ships with it [mem] |
| **Avalonia** | A WPF-like toolkit for Windows, Linux and Mac in C# | C#, XAML | MIT [mem]: fits | Avalonia 12 (2026) [search]. Widely used in .NET shops [mem] |
| **.NET MAUI** | Microsoft's cross-platform toolkit | C# | MIT [mem]: fits | No Linux support [mem]: fails the brief |
| **Compose Multiplatform** | JetBrains' toolkit; Kotlin language; carries a Java runtime on desktop | Kotlin | Apache 2.0 [mem]: fits | Stable on desktop [mem]; JetBrains' own tools use it |
| **Slint** | A small toolkit with its own layout language; logic in Rust, C++ or (beta) JavaScript and Python | Its language plus Rust or C++ | Three choices: a "Royalty-free License", GPLv3, or paid [opened]. The royalty-free licence is Slint's own text, not on the allowlist: the owner would have to read and admit it | Aimed first at embedded screens [mem]. Desktop use is real but small |
| **React Native for Windows and macOS** | Microsoft's ports of React Native | JavaScript, React, plus native glue | MIT [mem]: fits | No Linux [mem]: fails the brief |
| **Dear ImGui and similar** | Toolkits that redraw the whole window every frame, made for tools inside games | C++ | MIT [mem]: fits | Not meant for end-user apps; no screen-reader support [mem] |

### 1.2 Size, speed, feel, access, files and packaging

How to read it. "Size" is what the interface adds to the download, on top of the engine. The engine's own weight is
the same in every row: the Swift runtime files (about 20 MB by letter M's older figure), ONNX Runtime and the two
models [not measured for Windows]. Memory matters less than it looks here, because one engine job already peaks at
about 1.1 GB (status log, entry 15), far more than any interface.

| Option | Size and memory | Start-up | Look and feel on Windows | Screen readers and keyboard | Folders dropped in, file chooser, drives | Packaging and updates |
|---|---|---|---|---|---|---|
| **Default browser** | Adds almost nothing; the browser's memory is already in use | As fast as opening a tab | A web page in a browser tab: address bar, other tabs, no icon of its own in the taskbar | Good if the pages are written properly: browsers expose HTML to Narrator and NVDA [mem] | **Weak.** A web page is never told where a folder is: the directory picker "returns a handle" and "web pages never receive a filesystem path" [opened], and it does not exist in Firefox or Safari [search]. So the engine must show the chooser itself or draw its own list of drives and folders in the page. Dropping a folder on the page cannot work | No installer needed for the pages; the engine still needs one. No update system of its own |
| **Own shell, system web view** | About 2 MB for the WebView2 installer stub if the PC lacks it [opened]; otherwise a few hundred KB. Memory like one browser tab | Fast | Our own window, icon and title; inside, our design. Not Windows' own controls | As above | The shell can ask Windows for its real folder chooser and pass the path to the engine. Dropped folders need native code in the shell [inf: to be spiked] | Ours to choose: section 6 |
| **Tauri 2** | "A minimal Tauri app can be less than 600KB" [opened]. One Windows 11 test found idle memory near Electron's (142 MB against 149 MB), others found a third of it [search]: on Windows the system web view is Chromium too | Fast | As the own shell | As above | Dialog and drag-and-drop support that hand real paths to the shell [mem] | Builds `.msi` and NSIS `.exe` installers, `.deb`, `.rpm`, `.AppImage`, `.dmg`; built-in updater [opened] |
| **Electron** | Installers of roughly 80 to 150 MB and 150 to 300 MB idle, by 2026 blog comparisons [search] | Slower: it starts a whole browser | As the own shell | As above | Real paths available to the app [mem] | Mature installers and updaters [mem] |
| **WinUI 3 or WPF** | A few MB, or tens of MB if the .NET runtime is bundled [mem] | Fast | **Best**: Windows' own controls, menus, dialogs | **Best** on Windows: built on Windows' accessibility system [mem] | All native | MSIX and the Store are the home route; section 6 |
| **Qt 6** | Tens of MB of Qt libraries [mem] | Fast | Good, near native | Good [mem] | All native | Own installers; no built-in updater [mem] |
| **Swift with WinUI, SwiftCrossUI** | Swift runtime plus Windows App SDK | Unknown | Native controls in principle | SwiftCrossUI's page does not mention accessibility, drag and drop or file dialogs [opened] | Unknown; likely ours to write | Ours to work out. Letter M: the Windows workgroup is still settling "best practices for shipping Swift libraries with Windows apps" |
| **Flutter** | Tens of MB [mem] | Fast | Its own drawing; can imitate Windows | Supported; its docs name Narrator and NVDA [search] | Through plugins [mem] | MSIX through a plugin [mem] |
| **Avalonia** | Tens of MB with .NET [mem] | Fast | Its own drawing in a Windows style | Windows UI Automation "full support"; version 12 added a Linux accessibility backend [search] | Native dialogs [mem] | Standard .NET packaging [mem] |
| **Compose Multiplatform** | Large: bundles a Java runtime [mem] | Slower [mem] | Its own drawing | Weaker on Windows [unverified] | Through Java's dialogs [mem] | jpackage installers [mem] |
| **Slint** | A few MB [mem] | Fast | Its own drawing | Not confirmed today: a 2022 issue proposed adding it [search] | Limited [unverified] | Ours to choose |
| **Dear ImGui** | Tiny | Instant | Looks like a game tool | None [mem] | By hand | Ours to choose |

Three points the tables compress:

- **Removable drives and CDs are the engine's job in every web route.** A web page cannot list drives. The engine
  can, and the core already reads folders, drives and CDs of files. So "Add music" offering "a drive or CD that is
  plugged in" (desk.md, step 1) works the same in any interface: the interface asks the engine for the list.
  Whether the core's drive listing already works on Windows is not recorded [unverified].
- **The site's look carries only to the web routes.** `site/site.css` already holds Deckie Booth's Simple view as
  named colours, radii and fonts (`--bg`, `--surface`, `--acc`, `--r-card`, Inter and Pacifico), with focus
  outlines for keyboard use. A web-style Desk can start from that file. A native or toolkit interface would
  re-create the look by hand.
- **Web-view memory is a real complaint in 2026, for big apps.** WhatsApp's Windows app went from native to a web
  view in 2025 and reports put its memory at over 1 GB against about 190 MB before [search]. Desk is one window
  with a table and a progress bar, not a chat app with years of history, so this is a caution, not a verdict [inf].

### 1.3 Swift all the way: the state of Swift for Windows interfaces

- **The official picture.** Swift installs on Windows and a Windows workgroup has existed since January 2026
  (letter M). Its remit is the language and its libraries, not a window toolkit. There is no official Swift
  interface toolkit for Windows.
- **swift-winrt and swift-winui** (The Browser Company). swift-winrt generates Swift bindings to Microsoft's
  modern Windows interfaces; BSD-3, 863 stars, no releases listed [opened]. Its sample output, swift-winui, was
  **archived on Oct 16, 2025**; its page says it "contains an outdated snapshot of a subset of WinRT projections",
  that only x64 is supported and that "not all APIs can be generated" [opened]. A separate community generator
  (tristanlabelle/swift-winrt) warns it is "not ready for external usage" [search, undated].
- **Who ships this way.** The Browser Company built Arc for Windows on it; Arc for Windows retires on Dec 22,
  2026 (letter M). Its newer browser, Dia, reached Windows in Oct 2026, more than a year after the Mac (letter M),
  and its job listings for the Windows team ask for C++, Swift, WinUI, WPF and XAML together [search]. I found no
  engineering write-up from them newer than 2023, and no other company shipping a Swift interface on Windows
  [unverified].
- **SwiftCrossUI.** MIT, 1.8k stars, active in 2026, with a WinUI backend (recommended on Windows) and GTK backends
  that support "most" features; "still a work-in-progress" [opened]. Promising for a hobby tool; no evidence of a
  shipped commercial app [unverified].
- **SwiftOpenUI.** Announced March 2026 with Win32 and GTK backends; its author said "Still not ready for
  production", and a September 2026 reply says the project is suspended [opened].
- **swift-win32.** An older wrapper over the classic Windows controls [mem]; not checked today [unverified].
- **A third way that is Swift but not a native toolkit:** a shell written in Swift that calls the `webview` C
  library (section 1.1). The window's contents are web pages, the shell and the engine are both Swift. This keeps
  D14's one language without depending on WinUI bindings [inf]. It is untried here and would need a short spike.

Reading [inf]: a company with dedicated toolchain engineers took this road and found it slow; the public bindings
are no longer kept current. For a team of one owner and agents, a Swift-native Windows window means being first to
meet the bugs, which letter M already named as the regret to avoid.

## 2. Talking to the Swift engine

Four ways an interface in another technology can drive the Swift core.

| Way | How it works | Effort | Progress and stopping during a long run | What breaks | Security |
|---|---|---|---|---|---|
| **A. Separate engine program, messages over standard input and output** | The shell starts `deckie-desk-engine` as a child program and they exchange one JSON message per line through the pipes every program has | **Lowest.** Swift's standard library can do it; no network code. 1 to 2 weeks for the protocol and a test client | The engine writes an event per song ("12 of 240", minutes left). "Stop" is a message; closing the pipe or ending the program also stops it. The build is already resumable (status log, entry 13), so a hard stop loses at most the song in hand [inf] | Anything else printed to standard output corrupts the stream, so logs must go to standard error. Windows may alter line endings unless the pipe is set to binary. File names must travel as UTF-8 text inside JSON, never as command-line arguments, or accented and non-Latin song names break on Windows [inf]. The engine must exit when its input closes, or a crashed shell leaves it running | **Best.** No port is opened. Only the program that started the engine can talk to it |
| **B. Local socket or named pipe** | Same messages over a private channel that either side can open | A little more: socket code differs per platform | As A | As A, plus picking the channel's name and cleaning it up | Good if the pipe is restricted to the same user |
| **C. Local HTTP server** | The engine listens on the computer's own address (127.0.0.1) and the interface sends web requests; a WebSocket or event stream carries progress | Medium: a web server in Swift that works on Windows (see 1.1), 2 to 3 weeks | Progress as a stream of events; stop as a request. The run lives in the engine, so closing the tab does not stop it, which is good and also means the engine needs its own way to quit | The port may be taken; antivirus and firewalls look harder at a program that listens; the browser tab can be closed or duplicated | **Needs care**, below |
| **D. A library with a C interface, loaded by the shell** | The core is built as a library; the shell calls its functions directly. Swift 6.3 added the `@c` attribute for exposing functions to C [search] | Medium to high: every type that crosses must be flattened to C; callbacks for progress run on the engine's threads | Progress through a callback; stop through a flag the engine checks | A crash in the engine kills the window too. Memory ownership mistakes at the seam. The Swift runtime files must sit beside the shell | Fine: all in one program |
| **E. Generated bindings** | A tool writes the glue from Swift to the shell's language | High for this pair: I found no maintained generator from a Swift core to C#, Rust or JavaScript; the known ones run the other way (letter M: UniFFI is Rust to Swift) [inf] | As D | The generator becomes a dependency with its own risks | As D |

**Keeping other programs and web pages away from a local HTTP server (way C).** The known practice [opened where
marked]:

- Listen on 127.0.0.1 only, never on every network address. Syncthing: "The default listening address is
  127.0.0.1:8384, so you can only access the GUI from the same machine" [opened].
- Check the `Host` header on every request. Syncthing added this in version 0.14.6 because it "protects against
  most forms of DNS rebinding attack" [opened]. DNS rebinding is a trick where a web page on the internet makes
  the browser treat a local address as its own.
- Require a secret made fresh at each start, passed in the address the engine opens and then sent with every
  request, as Jupyter does [mem]. Refuse requests whose `Origin` is not the engine's own page, and send no
  cross-origin permission headers.
- Browsers now help, but do not rely on it. Chrome has asked permission before a public website may reach a local
  address since version 142 (Oct 2025) and for WebSockets since 147 (April 2026) [search]. Firefox and Safari
  differ.
- What none of this stops: another program already running as the same user on the same PC. That program could
  read the DJ's files anyway.

**What others do.** Tauri's sidecar feature is way A ready-made: the shell bundles another program, starts it,
reads its output as events and writes to its input [opened]. Code editors talk to language tools the same way
(the Language Server Protocol) [mem]. 1Password 8 is closer to way D: a Rust core inside an Electron app [opened].
Syncthing and Jupyter are way C [opened, mem].

Reading [inf]: way A fits Deckie best. `core/` already builds command-line programs (`deckie-build`), the run is
already resumable, there is no seam inside the Mac app (it keeps calling `DeckieDesk` directly), and the same
engine program can be driven by a test script on all three CI machines with no window at all. Way C is needed only
if the interface is the DJ's ordinary browser.

## 3. What comparable apps do

Most DJ companies do not publish their stacks; the evidence is licence pages, job ads and scans of installed apps.

| App | Interface built with | Evidence | Note |
|---|---|---|---|
| **Mixxx** | C++ with Qt; a new interface "100% based on Qt Quick / QML" is planned for 3.0 | Mixxx news, Aug 2025 [search]; letter M | One codebase on three desktops for two decades |
| **Serato DJ** | C++ with Qt | Serato's legal notices list Qt under LGPL 3.0, and also ONNX Runtime under MIT [opened]; C++ job ads (letter M) | The same model runtime Deckie's core uses |
| **Engine DJ** (desktop) | Qt | Desktop Insights' scan of the Mac build [search] | |
| **rekordbox** | Not established | Pioneer's open-source page lists only an MP3 library for the Mac and Windows app [opened]; a forum post says JUCE (letter M) | [unverified] |
| **Traktor** | Not established today | | [unverified] |
| **VirtualDJ** | Native, own interface; Mac build reports a Cocoa runtime | Desktop Insights [search]; plugin kit in C++ (letter M) | |
| **Mixed In Key** | Two native apps: began as C# .NET on Windows; the Mac app is written in Swift | Letter M; Desktop Insights' developer page [search] | The "two interfaces" route, from a small company |
| **Lexicon** | Electron | Letter M | Grew from a web app |
| **DJ.Studio** | Electron | Letter M | |
| **MusicBee** | Windows only | [mem], not checked today | [unverified] |
| **Swinsian** | Mac only | [mem], not checked today | [unverified] |

The pattern [inf]: the performance apps, which draw moving waveforms sixty times a second, are C++ with Qt. The
library tools, which are tables, forms and progress bars, are web shells. Deckie Desk is a library tool. Deckie
Booth, the part that performs, is already native on the iPad.

**Heavy engine, thin interface, outside DJ software:**

- **1Password 8** (2021): a shared Rust core with an Electron interface on Windows, Mac and Linux. They had planned
  a SwiftUI Mac app beside a web one and stopped it. Their account of the earlier years, with a separate stack per
  platform: changes needed four teams and "We were paralyzed"; even with shared SwiftUI code they kept "building
  separate implementations of certain components and sometimes whole features" [opened]. Users objected loudly to
  the non-native Mac feel [search].
- **WhatsApp for Windows**: Electron, then a native app, then in 2025 back to a web view, with reports of much
  higher memory and a slower app [search].
- **Microsoft Teams**: moved from Electron to WebView2 and said memory and disk use fell [search].
- **Microsoft itself, 2026**: a new team to build "100% native" Windows apps in place of web ones, with no list of
  apps or dates yet [search].
- **Syncthing**: a Go engine with its interface in the browser for over a decade [opened]. Community-made native
  wrappers exist around it [mem].
- **Arc and Dia**: section 1.3.

## 4. Starting on the web and moving to native later

**Is it a real path?** In the sense of "the web interface is a draft we will throw away for a native one": I found
no small team that wrote up doing that, and the well-documented moves run the other way or sideways [unverified
that none exists]. 1Password dropped native interfaces for a web one. WhatsApp did the same on Windows. Teams kept
its web interface and changed the shell under it. The reason is the one 1Password gave: every native interface is
a second and third copy of each screen.

**In the sense of "start in a browser, then give it its own window, then decide":** yes, and it is cheap, because
each step keeps everything from the step before.

| Step | What is new | What carries over |
|---|---|---|
| 1. Pages in a browser against the engine | The protocol, the engine program, the pages | |
| 2. The same pages in a shell with a web view | A window, an icon, a real folder chooser, an installer | Everything from step 1 |
| 3. If ever wanted, a native Windows window | The Windows interface only | The engine, the protocol and its tests, the words, the colours and layout as a design, everything learned from testers |

What is thrown away at step 3 is the HTML, CSS and JavaScript: by the Mac window's size, roughly 2,000 lines [inf].
What makes step 3 expensive is not the rewrite but owning two interfaces afterwards, if Linux stays on the web one.

**What to decide now so that any later move is cheap:**

1. **One written protocol, with a version number**, and a test client that drives the engine with no window.
   Messages are requests ("add music from this folder to this crate"), events ("song read", "run finished") and
   state ("the crates, the showing crate, its songs").
2. **No logic in the interface.** The interface shows state and sends requests. D28's rules (which crate is
   showing, undo, what has already been read) live in `DeckieDesk`, where they already are.
3. **The run lives in the engine.** An interface can close and reopen and find the run still going.
4. **One list of words per app** (D28), kept as data, not scattered through pages. The engine sends reasons as
   codes ("damaged file"), and the interface looks up the words. Then the word audit changes one file per app.
5. **One file of design tokens** (the named colours, radii and fonts), starting from `site/site.css`.
6. **Paths and names as UTF-8 text everywhere.**

## 5. One interface for every desktop, or keep the Mac's SwiftUI window

| | Keep SwiftUI on the Mac, new interface for Windows and Linux | One interface everywhere, replacing the Mac window |
|---|---|---|
| Cost now | Nothing on the Mac | Redo 2,222 lines that work, and re-test the Mac flow |
| Cost of every later change | Each new screen is built twice (the Sources panel, the crate menu, undo are all still moving) | Once |
| Mac feel | Native: menus, Command-Z, the share sheet with AirDrop, the file chooser | A web view or toolkit window. A Swift shell on the Mac can still call the real share sheet and file chooser [inf], so AirDrop need not be lost |
| Drift | The two can differ in words and behaviour. The shared `DeckieDesk` logic and one word list each limit this | None |
| Risk | Twice the interface review for the owner | Trading a working app for an unproven one while the product is still changing |

Reading [inf]: do not replace the Mac window now. It works, it is where the product is being designed this month,
and its Mac-only parts are exactly the ones a DJ notices. But make the choice cheap to revisit: the Mac window
should use `DeckieDesk` for everything it can, so the two interfaces differ only in drawing. Once the Windows
interface has caught up and been used by testers, the owner can compare them side by side and choose to keep both,
or to put the web interface in a Mac shell and retire the SwiftUI one. 1Password's history says the pressure will
be toward one.

## 6. Getting it onto a DJ's Windows PC

### 6.1 The warning, signing and reputation

Microsoft's own page, dated May 4, 2026 [opened]:

- Windows judges a download by two things: who signed it, and whether this exact file has been run by many people
  without trouble.
- An unsigned program shows "Windows protected your PC"; the user "must choose 'Run anyway'".
- A signed program from a new publisher still shows a warning "until reputation accumulates"; the publisher's
  verified name is shown. "There is no exact threshold, but it can take several weeks and hundreds of clean
  installs from a wide audience."
- "EV certificates no longer bypass SmartScreen." (EV, extended validation, is the dearer kind of certificate.)
  "Paying a premium for EV solely to avoid SmartScreen warnings is no longer justified."
- "The simplest way to avoid SmartScreen warnings is to publish through the Microsoft Store." Store apps "are
  never subject to SmartScreen download warnings."
- Reputation follows the signer: a later version signed by the same identity can inherit it; unsigned files start
  from zero every time.
- On Windows 11 PCs with Smart App Control switched on, unsigned files are blocked outright unless already known.
  A Feb 2026 forum thread reports some signed apps blocked too [search].

| Route | Cost (date of source) | Warning on first download | Notes |
|---|---|---|---|
| **Microsoft Store, packaged as MSIX** (Windows' modern package format) | Registration free for individuals since Sept 2025 and for companies since May 2026 [search: Microsoft's developer blog]. "Free Microsoft code signing and CDN hosting" [opened] | **None** | Updates are automatic. The app must pass Store review. Whether a Swift engine with its runtime files packs cleanly into MSIX is untested [unverified] |
| **Microsoft Store, with our own installer** | Free listing; the installer must be signed with a certificate from a recognised authority, install silently and be hosted by us [opened] | None when installed through the Store [inf] | Still needs a certificate |
| **Azure Artifact Signing** (Microsoft's signing service, formerly Trusted Signing) | "Starts at $9.99/month" [opened, May 2026]; the Basic plan covers 5,000 signatures a month [search]. Needs a paid Azure subscription; billing is not pro-rated [opened] | Yes, until reputation builds | No hardware token; signs from the build machines. Identity checks take "1 to 20 business days". Eligibility below |
| **OV certificate from an authority** (OV, organisation validation: the standard kind) | Roughly $220 to $440 a year by reseller lists in 2026 [search] | Yes, until reputation builds | The key must live on a hardware token or cloud service; certificates last at most 460 days from Mar 1, 2026 [search] |
| **EV certificate** | Roughly $290 to $685 a year [search] | Yes: no longer any shortcut [opened] | Not worth the extra |
| **Unsigned** | $0 | "Windows protected your PC" on every version, forever | Blocked on PCs with Smart App Control. Not acceptable for a non-technical tester |

**Eligibility for Artifact Signing, for a small US company.** The quickstart, updated Oct 8, 2026: "Public Trust
certificates are available to organizations in the United States, Canada, the European Union, the United Kingdom"
and others; "Individual developers must be located in the United States or Canada" [opened]. In April 2025
Microsoft limited new sign-ups to organisations "with at least three years of verifiable history" [search]. The
current quickstart does not state that rule, and I could not confirm whether it still applies [unverified]. If it
does and the company is younger, the individual route is open to a US resident; the publisher name Windows shows
would then be that person's legal name, not the company's. The service does not issue EV certificates and will
not customise the name [opened].

**Antivirus false alarms.** New programs from unknown publishers are sometimes flagged by antivirus heuristics,
most often unsigned ones [mem]. Signing every file and keeping one signing identity is Microsoft's advice
[opened]. A wrongly flagged file can be submitted to Microsoft Security Intelligence [opened]; other vendors have
their own forms [mem]. A program that listens on a network port draws more attention than one that does not
[inf], another point for way A in section 2.

### 6.2 Installer, portable folder, updates

| Form | What the DJ does | Updates | Notes |
|---|---|---|---|
| **Store (MSIX)** | Clicks "Get" in the Microsoft Store | Automatic | No warning, clean uninstall |
| **Installer** (`.msi`, or an `.exe` made with NSIS, Inno Setup or WiX) | Downloads, runs, clicks through | Needs an updater: Tauri's built in [opened], or Velopack (MIT; installer, delta updates, self-updating portable build; Windows, Mac, Linux) [opened], or WinSparkle [mem] | The warning rules of 6.1 apply. If the PC lacks WebView2 the installer runs Microsoft's 2 MB stub [opened] |
| **Portable folder** (a zip) | Unzips, double-clicks | None, unless Velopack's portable build | Simplest to make. Files from a downloaded zip still carry the "from the internet" mark, so the warning still appears [mem]. Easy to lose or run from inside the zip |
| **MSIX outside the Store** | Double-clicks a `.msix` | Through an App Installer file [mem] | Must be signed by us; same reputation rules |

### 6.3 Linux, in brief

- **AppImage**: one file the DJ marks as runnable; no install, no store. Some distributions need an extra library
  to run it [mem].
- **Flatpak**, usually through Flathub: sandboxed, updates itself, works across distributions. File choosers go
  through the desktop's portal; reading removable drives needs a declared permission [mem].
- **A `.deb`**: native to Debian and Ubuntu only.
- Tauri builds `.deb`, `.rpm` and `.AppImage` [opened]. There is no signing warning and no cost. The main Linux
  risk for a web-style interface is that the system's WebKitGTK differs between distributions; Tauri 2 needs
  webkit2gtk 4.1, so Ubuntu 22.04 or newer [opened].

## 7. What Windows lacks that the Mac flow uses

**The share sheet.** Windows has a share dialog of its own, but what it offers is Windows' Nearby Sharing (to other
Windows PCs and Android phones), email and installed apps. Nothing in it reaches an iPad directly [mem]. I found no
source saying Microsoft's Phone Link sends files to an iPad [unverified].

**The crate file's shape matters first.** It is a folder of many small files, 22 MB and 141 MB for the two crates
on this Mac. A USB stick, iCloud Drive and a cable can carry a folder. A web download, email or a chat app cannot:
they need one file. So some routes need Desk to pack the folder into a single file and the booth to unpack it.
Whether the booth should accept a packed crate file is a small format question for the owner; D27 shows the format
can take additions.

| Way | What the DJ does | Needs | Works with no internet | Risks |
|---|---|---|---|---|
| **A USB stick or SD card** | Desk writes the crate file to a drive that is plugged in; the DJ plugs it into the iPad and opens it from the Files app | An iPad that takes the drive (USB-C, or an adapter). The Files app reads exFAT, FAT32, APFS and HFS+ drives [search] | Yes | DJs already carry sticks, and the crate file can ride with the music. The booth already declares opening documents in place, so it may be able to read the crate file straight from the stick [inf: to be tested]. On Windows the crate file looks like a folder a DJ could open and disturb |
| **iCloud Drive** | Installs Apple's iCloud for Windows, signs in; Desk saves the crate file into the iCloud Drive folder; it appears in Files on the iPad | iCloud for Windows puts an iCloud Drive entry in File Explorer [search: Apple's guide]. An Apple Account on the PC; room in iCloud | No | Thousands of small files may sync slowly [inf]. One more install and sign-in for a non-technical DJ. Closest to the Mac's second route |
| **A cable and Apple's "Apple Devices" app** | Connects the iPad by cable, opens Apple Devices, selects the iPad, then Files, and drags the crate file onto Deckie Booth | "A list of the apps on your device that support file sharing appears"; "The files are immediately transferred" [opened]. The booth already enables file sharing | Yes | Several steps in someone else's app. Whether a folder drags across as one item was not confirmed [unverified]. Wi-Fi works too after setup [opened] |
| **The home network, Desk offers the file** | Desk shows a QR code; the iPad's camera opens it in Safari and downloads; the DJ opens the download in Deckie Booth | Both on the same network; a single packed file; Desk listening on the network, not just on the PC itself | Yes, with a router | Windows Firewall asks the user to allow it the first time, and blocks it on networks marked public [mem]. Some routers stop devices seeing each other. A listening program on the network needs the care of section 2 and more |
| **The home network, the booth receives** | In Deckie Booth the DJ taps "Receive from Desk"; Desk on the PC finds the iPad and sends | Booth work: advertise itself on the network and accept one file. The PC only connects outward, so Windows Firewall does not ask [mem]; the iPad asks once for local-network permission [mem] | Yes, with a router | The nearest thing to AirDrop, and the same on Linux. LocalSend, an open-source app, works this way with its app on both devices [mem]. New code on both sides |
| **Email, chat apps, other clouds** | Sends or uploads one file | A packed file; an account | No | Email limits are commonly about 25 MB [mem]: too small. OneDrive, Google Drive or Dropbox work if the DJ already uses them |

**How other DJ software does it** [mem]: the DJ habit is the USB stick; rekordbox exports to one for the club's
players, and cloud library sync is a paid extra. So "save it to your stick" will read as normal to a DJ in a way it
would not to anyone else.

Reading [inf]: on Windows, "Send to iPad" should open a small panel in Desk's own window with the roads that are
actually available on that PC, in this order: a plugged-in drive, iCloud Drive if it is installed, then "with a
cable" as written steps. The network road is the best experience but is new work in the booth; it can follow.

## Options for the owner

Four whole routes. Each assumes the same first step, which is the same under all of them and useful by itself: the
protocol and the engine program of section 2 (way A), 1 to 2 weeks, tested on all three CI machines.

### Route 1. Pages in the DJ's browser now, a window later

*What it is.* The engine serves the pages on the computer's own address and opens the default browser.

- **Costs.** 3 to 4 weeks after the protocol. A small web server in the Swift engine that works on Windows, and
  the security work of section 2.
- **Gains.** No shell, no second toolchain. Quickest to a first look. The pages are the ones Route 2 uses.
- **Risks.** No folder dropped in, and no folder chooser unless the engine shows one or draws its own list. It
  looks like a website: an address bar, a tab that can be closed while Desk runs, no icon in the taskbar. A
  listening program invites firewall and antivirus questions. For a non-technical tester, "open Deckie Desk" would
  mean "a browser tab opens", which is not the Mac flow.
- **First working version.** Double-click Deckie Desk; the browser opens on Desk's page in the site's look; "Add
  music" shows a list of drives and folders drawn by the page; a progress bar; "Send to iPad" offers a drive or
  iCloud Drive.

### Route 2. The same pages inside Desk's own window, from the first release

*What it is.* A web-style interface in the system web view, a small shell, the engine as a separate program. Two
ways to make the shell: **Tauri 2**, or **our own shell in Swift** on the `webview` C library.

- **Costs.** 4 to 6 weeks after the protocol with Tauri: the pages, a few hundred lines of Rust, installers. Tauri
  means a Rust toolchain and a large tree of Rust packages to admit under the dependency policy. The Swift shell
  avoids both but we would write the folder chooser, drop handling and installer hookup ourselves: 1 to 3 weeks
  more, with unknowns.
- **Gains.** A real app: its own window and icon, the real Windows folder chooser, folders dropped in, an
  installer and updater (Tauri's, or Velopack). No port open, so the simplest security story. Windows and Linux
  from one interface. The site's look reused. During development the same pages can still be opened in a browser.
- **Risks.** Not Windows' own controls; a careful DJ will see it is a web-style app. WebKitGTK differences on
  Linux. With Tauri, a second language in the repository, though it holds no Deckie logic; D14 says Deckie's own
  code is Swift, so the owner should say whether a shell counts. With the Swift shell, being early again.
- **First working version.** Install Deckie Desk from the Store or an installer; a window opens in the Deckie
  look; "Add music" opens Windows' folder chooser or lists plugged-in drives; one progress bar with minutes left;
  the finished screen; "Send to iPad" with a drive, iCloud Drive or cable steps.

### Route 3. Native on each platform

*What it is.* WinUI 3 (or WPF) in C# on Windows, GTK on Linux, SwiftUI on the Mac, all driving the same engine.

- **Costs.** 6 to 10 weeks for Windows after the protocol, 4 to 6 more for Linux. C# as a second language, with
  real interface code in it. Every later screen built three times. A variant halves this: Avalonia, one C#
  interface for Windows and Linux.
- **Gains.** The best Windows feel, the best screen-reader and keyboard support, the smallest memory. MSIX and the
  Store are this route's home ground. In step with Microsoft's 2026 direction.
- **Risks.** Three interfaces for one owner to review while the product's flow is still changing (D25 to D30 are
  all from today). Linux likely waits.
- **First working version.** A Windows app that looks like a Windows app, the same three steps. Linux later.

### Route 4. Swift all the way

*What it is.* SwiftCrossUI, or swift-winrt with WinUI directly, for Windows; GTK from Swift for Linux.

- **Costs.** Unknown; a guess of 8 to 14 weeks with wide error bars, and standing upkeep of bindings nobody else
  keeps current.
- **Gains.** One language, as D14 intends. SwiftCrossUI could in principle draw the Mac window too.
- **Risks.** The highest of the four. The reference WinUI bindings are archived; the one large app built this way
  is being retired; no accessibility story found. Letter M's named regret: "we may be first to hit it".
- **First working version.** A two-week spike that shows a window, a folder chooser, a table and a progress bar on
  Windows. If the spike fails, the weeks are lost.

## Recommendation

**Route 2, with the browser as the workbench on the way there.** In order:

1. **Write the protocol and the engine program first** (section 2, way A; section 4's six rules). It is needed by
   every route, it is all Swift, and it can be tested with no window. In the same step, prove one full run with the
   models on a real Windows PC, which the status log does not yet show.
2. **Build the pages against it**, starting from `site/site.css`, with every word in one list. Open them in a
   browser while developing. This is the owner's "start with web", kept as a tool for building rather than as what
   the first tester receives.
3. **Put them in a shell before the first tester sees anything.** My choice is Tauri 2, because the installer,
   updater, folder chooser and drop handling come ready and are used by many apps, and because the shell holds no
   Deckie logic. This needs the owner's yes on two things: a little Rust in the repository beside D14, and Tauri's
   package tree under the dependency policy. If either is a no, spend two days on the Swift shell with the
   `webview` library first; if a window, the folder chooser and a message round trip work on Windows, take that.
4. **Give it to the first tester through the Microsoft Store**, which is free and is the only route with no
   warning screen. Start Azure Artifact Signing in parallel ($9.99 a month), because identity checks can take up
   to 20 business days and a download outside the Store will be wanted later.
5. **"Send to iPad" on Windows starts as a drive, iCloud Drive and cable steps.** Put the network road, with the
   booth receiving, on the list for after.
6. **Keep the Mac's SwiftUI window for now**, moved fully onto `DeckieDesk`. Compare the two interfaces once
   Windows has caught up, and decide then whether to keep both.
7. **Treat "native later" as an open door, not a plan.** The evidence is that teams keep the web interface once it
   exists. If testers on Windows say it feels wrong, Route 3 for Windows alone is then a contained job, because the
   engine, protocol, words and design all carry.

Why not the others. Route 1 gives a non-technical tester a browser tab and no way to drop or choose a folder
properly, to save perhaps two weeks. Route 3 is the best Windows app and the most work to keep, at the moment the
flow is changing fastest. Route 4 bets the PC version on bindings their own authors have set aside.

**What would change this recommendation.** A full Windows run that shows the engine needs so much memory that a
web view's share matters on an 8 GB PC. The Store refusing or mangling a Swift engine in an MSIX package.
Accessibility becoming a stated requirement at a level only native controls meet. Or a maintained, released Swift
toolkit for Windows appearing with shipped apps behind it.

## What I could not open or verify

- Whether Azure Artifact Signing still requires three years of company history. The April 2025 rule is from a
  search summary; the current quickstart, which I opened, does not state it.
- The Microsoft Store's free registration for companies: from search summaries of Microsoft's blog of May 7, 2026;
  the Partner Center page itself was not opened.
- Whether a Swift program with its runtime files and ONNX Runtime packs and runs correctly inside MSIX.
- What rekordbox and Traktor are built with. Desktop Insights pages for them were not found (two guessed addresses
  returned "not found").
- MusicBee's and Swinsian's stacks, the swift-win32 project's current state, and Compose Multiplatform's and
  Slint's screen-reader support on Windows: not checked today.
- Licences marked [mem] in section 1.1 (Electron, Wails, Neutralino, WPF, GTK, Flutter, Avalonia, .NET MAUI,
  Compose Multiplatform, React Native for Windows, Dear ImGui): from memory. Each must be quoted from its licence
  file before adoption, as the policy requires.
- Tauri's and Electron's handling of dropped folders and real file paths: from memory, not opened.
- Windows Firewall's behaviour for a program that listens only on the PC's own address against one that listens on
  the network, and iPadOS's local-network prompt: from memory.
- Apple's pages for iCloud Drive on Windows and for external drives on iPad returned only their menus; the facts
  cited are from search summaries of those pages.
- Whether Apple Devices carries a folder to an app as one item.
- The 2026 comparison figures for Electron and Tauri size and memory, and the WhatsApp memory figures, come from
  blogs and news reports with mixed quality, through search summaries.
- Whether the core's listing of drives and CDs already works on Windows.
- No retrospective was found from a small team that moved a desktop app from a web interface to a native one.

## Sources

Opened today unless marked.

**Swift on Windows and Swift toolkits.** swift-winui (archived Oct 16, 2025)
https://github.com/thebrowsercompany/swift-winui ; swift-winrt https://github.com/thebrowsercompany/swift-winrt ;
SwiftCrossUI https://github.com/moreSwift/swift-cross-ui ; SwiftOpenUI thread (March to Sept 2026)
https://forums.swift.org/t/swiftui-for-linux-windows-and-web-still-experimental/85463 ; SwiftNIO's platforms
https://github.com/apple/swift-nio ; [search] "Swift, meet WinRT" https://speakinginswift.substack.com/p/swift-meet-winrt ;
[search] tristanlabelle/swift-winrt https://github.com/tristanlabelle/swift-winrt ; [search] Dia Windows job listing
https://www.builtinla.com/job/staff-software-engineer-windows-product/4683737 ; [search] SE-0495, the `@c` attribute
https://forums.swift.org/t/accepted-se-0495-c-compatible-functions-and-enums/82833 .

**Web shells and web views.** Tauri https://github.com/tauri-apps/tauri , https://v2.tauri.app/start/ and sidecars
https://v2.tauri.app/develop/sidecar/ ; the `webview` library https://github.com/webview/webview ; WebView2
distribution (updated Oct 2, 2026) https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution ;
the directory picker https://developer.mozilla.org/en-US/docs/Web/API/Window/showDirectoryPicker ; [search] its
browser support https://caniuse.com/mdn-api_window_showdirectorypicker ; [search] Tauri release list
https://tauri.app/release/tauri/all-versions/ ; [search] Wails 3 status https://docs-preview.wails.io/status/ ;
[search] Neutralino release notes https://neutralino.js.org/docs/release-notes/framework ; [search] Electron and
Tauri comparisons https://www.pkgpulse.com/guides/electron-vs-tauri-2026 and
https://tech-insider.org/tauri-vs-electron-2026/ .

**Native and cross-platform toolkits.** Slint https://github.com/slint-ui/slint ; [search] Windows App SDK 2.0
notes https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-notes/windows-app-sdk-2-0 ; [search]
Qt for Small Business https://www.qt.io/pricing/qt-for-small-business ; Qt pricing page (no figures shown)
https://www.qt.io/pricing ; [search] Avalonia 12 https://avaloniaui.net/blog/avalonia-12 and accessibility
https://docs.avaloniaui.net/docs/app-development/accessibility ; [search] Flutter accessibility
https://docs.flutter.dev/ui/accessibility/assistive-technologies ; [search] Slint accessibility issue (2022)
https://github.com/slint-ui/slint/issues/32 ; [search] Microsoft's "100% native" apps
https://windowslatest.com/2026/03/28/microsoft-plans-to-build-100-native-apps-for-windows-11-as-web-apps-ruin-the-os-experience/
and https://www.pcgamer.com/software/operating-systems/microsoft-is-building-new-100-percent-native-windows-programs-to-replace-memory-hogging-web-apps
(opened; only the headline came through).

**Talking to the engine, and local servers.** Syncthing FAQ (listen address, host check)
https://docs.syncthing.net/users/faq.html and security page https://docs.syncthing.net/users/security.html ;
[search] Chrome's Local Network Access https://developer.chrome.com/blog/local-network-access and
https://developer.chrome.com/docs/modern-web-guidance/guides/security/local-network-access .

**Comparable apps.** Serato legal notices (first 100,000 characters read)
https://serato.com/legal/software-legal-notices ; Pioneer DJ open-source page
https://www.pioneerdj.com/en/support/open-source-code-distribution/gpl-lgpl-source-code/ ; 1Password 8, "the story
so far" (Aug 12, 2021) https://1password.com/blog/1password-8-the-story-so-far ; [search] Engine DJ scan
https://desktopinsights.com/apps/engine-dj ; [search] VirtualDJ scan https://desktopinsights.com/apps/virtualdj ;
[search] Mixed In Key developer page https://desktopinsights.com/developers/mixed-in-key-llc ; [search] Mixxx's QML
plan https://mixxx.org/news/2025-08-06-qml-project/ ; [search] WhatsApp's move to WebView2
https://www.neowin.net/amp/whatsapp-for-windows-is-ditching-uwp-for-a-web-app/ and
https://www.notebookcheck.net/WhatsApp-ditches-native-Windows-11-app-in-favor-of-Microsoft-WebView2.1063682.0.html ;
[search] Teams' new architecture
https://techcommunity.microsoft.com/t5/microsoft-teams-blog/microsoft-teams-advantages-of-the-new-architecture/ba-p/3775704 ;
[search] reaction to 1Password 8
https://sixcolors.com/post/2021/08/not-important-enough-1password-abandons-its-native-mac-app/ . Letter M's
sources for Lexicon, DJ.Studio, Mixed In Key's origin, Arc and Dia.

**Windows distribution.** SmartScreen reputation (May 4, 2026)
https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation ; Artifact Signing FAQ
(updated Oct 27, 2026) https://learn.microsoft.com/en-us/azure/artifact-signing/faq and quickstart (updated Oct 8,
2026) https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart ; Store requirements for MSI and EXE
(updated Aug 24, 2026)
https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msi/app-package-requirements ; Velopack
https://github.com/velopack/velopack ; [search] Artifact Signing pricing
https://azure.microsoft.com/pricing/details/artifact-signing/ ; [search] general availability, Jan 2026
https://www.devclass.com/security/2026/01/14/code-signing-windows-apps-may-be-easier-and-more-secure-with-new-azure-artifact-service/4079554 ;
[search] the April 2025 three-year rule https://techcommunity.microsoft.com/blog/microsoft-security-blog/-/4399713 ;
[search] Store registration free for companies (May 7, 2026)
https://blogs.windows.com/windowsdeveloper/2026/05/07/publish-to-microsoft-store-as-a-company-now-with-free-registration-and-faster-onboarding/
and for individuals (Sept 10, 2025)
https://blogs.windows.com/windowsdeveloper/2025/09/10/free-developer-registration-for-individual-developers-on-microsoft-store/ ;
[search] certificate prices and the 460-day limit https://www.ssldragon.com/ssl-certificates/code-signing/ ,
https://sslinsights.com/digicert-vs-sectigo-code-signing/ and
https://www.ssl2buy.com/wiki/code-signing-certificate-validity-reduced-to-460-days ; [search] Smart App Control
reports https://learn.microsoft.com/en-us/answers/questions/5791210/application-signed-and-blocked-by-smart-app-contro .

**PC to iPad.** Apple Devices file transfer
https://support.apple.com/guide/devices-windows/transfer-files-between-your-pc-and-devices-mchl4bd77d3a/windows ;
[search] iCloud Drive in iCloud for Windows https://support.apple.com/guide/icloud-windows/icwddbc813bd ; [search]
external storage on iPad https://support.apple.com/guide/ipad/connect-external-storage-devices-ipad2f0e4ce1/ipados
(opened; only the menu came through) and
https://www.seagate.com/gb/en/support/kb/lacie/external-storage-with-ipad-usb-c-and-iphone-usb-c/ .

**In this repository.** `docs/product/desk.md`; `docs/product/00-decisions.md` (D14, D21, D25 to D30);
`docs/research/m-core-language-and-dependencies.md` (sections 1, 3.4, 4, 6); `docs/research/l-non-apple.md`;
`DEPENDENCIES.md`; `docs/product/voice.md`; `site/site.css`, `site/README.md`; `docs/architecture/crate-format.md`;
`docs/architecture/pc-linux-status.md` (entries 13 and 15, and "Where things stand"); `core/Sources/DeckieDesk`;
`desk-app/Desk/Sources`; `deck-app/Deck/Info.plist`.
