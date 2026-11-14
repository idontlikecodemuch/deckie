// The window Deckie Desk opens on Windows and Linux (D32), as a small C interface the Swift shell calls: a window
// holding the system's web view (WebView2 on Windows, WebKitGTK on Linux, WKWebView on the Mac, through the vendored
// `webview` library), one channel each way between the page and Swift, and the few things a page cannot do itself
// (choose a folder and be told its path, open a folder in the file manager).
//
// Threads: everything here runs on the window's thread (the one that called deskshell_create and runs
// deskshell_run), except deskshell_post and deskshell_dispatch, which may be called from any thread.
#ifndef DESKSHELL_H
#define DESKSHELL_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct deskshell *deskshell_t;

/// Called on the window's thread with each message the page sends (`window.deckieShell.send(text)`), as UTF-8.
typedef void (*deskshell_message_fn)(const char *text, void *context);
/// Work to run on the window's thread.
typedef void (*deskshell_work_fn)(void *context);

/// Opens a window of the given size in points, titled `title`. NULL when the system's web view is missing (WebView2
/// not installed, WebKitGTK not found) or the window could not be made. `debug` non-zero lets the web inspector open.
deskshell_t deskshell_create(int debug, const char *title, int width, int height);

/// Where the page's messages go. Set before deskshell_load.
void deskshell_on_message(deskshell_t s, deskshell_message_fn fn, void *context);

/// Shows the page at `url` (a file:// URL to the pages beside the program).
void deskshell_load(deskshell_t s, const char *url);

/// Shows `html` as the page (the self-test uses it).
void deskshell_set_html(deskshell_t s, const char *html);

/// Hands `text` (UTF-8, one message) to the page's `window.deckieShell.receive`. Any thread.
void deskshell_post(deskshell_t s, const char *text);

/// Runs `js` in the page. Window's thread. The shell's tour and check use it; the pages' messages use deskshell_post.
void deskshell_eval(deskshell_t s, const char *js);

/// Runs `fn(context)` on the window's thread. Any thread.
void deskshell_dispatch(deskshell_t s, deskshell_work_fn fn, void *context);

/// Runs the window until it is closed or deskshell_terminate is called. Returns 0 when it ends normally.
int deskshell_run(deskshell_t s);

/// Ends deskshell_run. Window's thread (use deskshell_dispatch from another).
void deskshell_terminate(deskshell_t s);

void deskshell_destroy(deskshell_t s);

/// The system's own folder chooser over the window; the folder's path as UTF-8 (free it with deskshell_free), or
/// NULL when the DJ cancelled. `title` is the chooser's message. Not on the Mac: the Swift shell uses NSOpenPanel.
char *deskshell_choose_folder(deskshell_t s, const char *title);

/// The system's own file chooser, for one file. As deskshell_choose_folder.
char *deskshell_choose_file(deskshell_t s, const char *title);

/// Opens a folder in the system's file manager (Explorer, the Linux desktop's own). Not on the Mac.
void deskshell_open_folder(const char *path);

void deskshell_free(char *text);

/// The web view itself (a WKWebView on the Mac, a WebKitWebView on Linux, an ICoreWebView2Controller on Windows), for
/// the shell's own uses (the Mac's snapshots of the window for its screenshots).
void *deskshell_native_view(deskshell_t s);

/// Which web view this is: "WebView2", "WebKitGTK" or "WKWebView".
const char *deskshell_engine_name(void);

// The rest is for Windows, where Desk is a program of the "windows" kind (no console window) started by a double
// click. Each does nothing, or answers no, on the other systems.

/// Call first, before anything is written. A program of the "windows" kind started by a double click has no standard
/// input, output or error at all; this gives it Windows' "NUL" (which swallows what is written) for each one that is
/// missing, so that a line written for a developer cannot stop the program.
void deskshell_prepare_process(void);

/// The version of Microsoft's WebView2 Runtime (the "Evergreen" one, shared by all programs) installed on this PC,
/// read from the registry values Microsoft documents for this question (`pv` under `EdgeUpdate\Clients\{F3017226-
/// FE2A-4295-8BDF-00C3A9A7E4C5}`, for the whole PC and for this account); NULL when there is none. Free it with
/// deskshell_free. The window itself is the proof (deskshell_create); this says why when it could not be made.
char *deskshell_webview2_version(void);

/// Shows `text` in a message box titled `title`, over no window. `ask` zero: one button, OK. Non-zero: Yes and No.
/// Returns 1 for Yes (or OK), 0 otherwise, and 0 at once where there are no message boxes (Linux, the Mac).
int deskshell_notice(const char *title, const char *text, int ask);

/// Opens a web address in the DJ's own browser. Windows only; only ever called after the DJ said yes.
void deskshell_open_address(const char *address);

/// 1 when the window carries an icon of its own (the program's icon resource number 1, set on the title bar and the
/// taskbar when the window was made), 0 when the program was built without one or on the other systems.
int deskshell_window_has_icon(deskshell_t s);

#ifdef __cplusplus
}
#endif

#endif
