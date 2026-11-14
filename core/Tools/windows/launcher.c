// The starters: the programs a DJ sees at the top of the Deckie folder. One source, built twice by
// core/Tools/windows/package.sh:
//
//   "Deckie Desk.exe"       (built with -DDECKIE_DESK) starts app\deckie-desk.exe, Deckie Desk's window. It is a
//                           program of the "windows" kind: no console window opens behind it, and what it has to
//                           say it says in a message box.
//   "Make Crate File.exe"   starts app\deckie-make.exe, the program a music folder is dropped on. It is a console
//                           program: it says things in the console window and keeps it open.
//
// Each passes on whatever was dropped on it or typed after its name, waits, and ends with the real program's code.
//
// Why a starter at all. The real programs need some twenty library files next to them, which would bury the one
// thing to click. And three things can go wrong before a real program can say a word, each of which Windows reports
// with a box nobody understands, or with a window that vanishes. The starter says them in plain words:
//   1. started from inside the zip, without unzipping (Windows then copies out this one file and nothing else);
//   2. Microsoft's Visual C++ runtime is missing (four files the zip carries in "app"; DEPENDENCIES.md, section 3);
//   3. the real program stopped in a way it did not expect.
//
// A PC without Microsoft's WebView2 Runtime (the part of Windows that shows Desk's window) is not this file's to
// find: deckie-desk.exe asks the same loader that would start it, and says what to do (desk-shell, Notice.swift).
//
// It uses nothing but Windows' own kernel32.dll, and user32.dll for the message box: no C runtime, so it starts on
// any 64-bit Windows 10 or 11. Built with the clang that comes with Swift.
//
// DECKIE_NO_BOXES (any value) in the environment is for a check with no one at the keyboard, which must not wait
// for a click: "Deckie Desk.exe" then writes its message to standard error and shows no box, asks Windows to show
// none of its own either when the real program cannot start (the real program then just ends with Windows' code),
// and writes the real program's code when it is not 0.

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

// The compiler may ask for these two even with no C runtime.
void *memset(void *dest, int value, size_t count) {
    unsigned char *d = (unsigned char *)dest;
    while (count--) *d++ = (unsigned char)value;
    return dest;
}
void *memcpy(void *dest, const void *src, size_t count) {
    unsigned char *d = (unsigned char *)dest;
    const unsigned char *s = (const unsigned char *)src;
    while (count--) *d++ = *s++;
    return dest;
}

#ifdef DECKIE_DESK
#define REAL_PROGRAM L"\\deckie-desk.exe"
#define STARTER_NAME L"Deckie Desk"
// The real program's own endings are 0 to 9 (desk-shell, main.swift), each already said in its own words.
#define LAST_OWN_CODE 9u
#else
#define REAL_PROGRAM L"\\deckie-make.exe"
#define STARTER_NAME L"Make Crate File"
// 0 to 3 are the real program's own endings, each already said in its own words (and it waited for Enter).
#define LAST_OWN_CODE 3u
#endif

static WCHAR here[4096];
static WCHAR child[4200];
static WCHAR appDir[4200];
static WCHAR commandLine[32768];
static WCHAR typed[256];
static WCHAR message[4096];
static char bytes[4096];

static size_t length(const WCHAR *s) { size_t n = 0; while (s[n]) n++; return n; }
static void append(WCHAR *to, size_t capacity, const WCHAR *s) {
    size_t n = length(to);
    while (*s && n + 1 < capacity) to[n++] = *s++;
    to[n] = 0;
}

// Plain bytes to a handle that is not a console (output sent to a file): every message here is ASCII.
static void writeBytes(HANDLE to, const WCHAR *text) {
    DWORD written = 0;
    size_t n = 0;
    while (text[n] && n < sizeof(bytes)) { bytes[n] = (char)text[n]; n++; }
    if (to != NULL && to != INVALID_HANDLE_VALUE) WriteFile(to, bytes, (DWORD)n, &written, NULL);
}

#ifdef DECKIE_DESK
static int quiet(void) { return GetEnvironmentVariableW(L"DECKIE_NO_BOXES", typed, 255) > 0; }
#endif

// Says one whole message and waits until it has been read: a message box for "Deckie Desk", the console window and
// "Press Enter" for "Make Crate File".
static void tell(const WCHAR *text) {
#ifdef DECKIE_DESK
    if (quiet()) {
        writeBytes(GetStdHandle(STD_ERROR_HANDLE), text);
        writeBytes(GetStdHandle(STD_ERROR_HANDLE), L"\r\n");
        return;
    }
    MessageBoxW(NULL, text, STARTER_NAME, MB_OK | MB_ICONINFORMATION | MB_SETFOREGROUND);
#else
    HANDLE out = GetStdHandle(STD_OUTPUT_HANDLE);
    HANDLE in = GetStdHandle(STD_INPUT_HANDLE);
    DWORD written = 0, mode = 0, count = 0;
    if (!WriteConsoleW(out, text, (DWORD)length(text), &written, NULL)) writeBytes(out, text);
    static const WCHAR enter[] = L"\r\n\r\nPress Enter to close this window.\r\n";
    if (!WriteConsoleW(out, enter, (DWORD)length(enter), &written, NULL)) writeBytes(out, enter);
    if (GetConsoleMode(in, &mode)) ReadConsoleW(in, typed, 255, &count, NULL);
#endif
}

void entry(void) {
#ifdef DECKIE_DESK
    // A check: no box of Windows' own when a library is missing or the program stops (the real program inherits
    // this), so that the code comes back instead of a box nobody can click.
    if (quiet()) SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX);
#endif
    // Where this program is, and the real one beside it in "app".
    DWORD n = GetModuleFileNameW(NULL, here, 4095);
    while (n > 0 && here[n - 1] != L'\\' && here[n - 1] != L'/') n--;
    here[n] = 0;
    appDir[0] = 0; append(appDir, 4200, here); append(appDir, 4200, L"app");
    child[0] = 0; append(child, 4200, appDir); append(child, 4200, REAL_PROGRAM);

    if (GetFileAttributesW(child) == INVALID_FILE_ATTRIBUTES) {
        tell(L"Deckie cannot start from here: the rest of its files are missing.\r\n\r\n"
             L"This happens when it is started from inside the zip. Unzip first:\r\n"
             L"right-click the Deckie zip, choose \"Extract All\", then open the new folder\r\n"
             L"and start \"" STARTER_NAME L"\" from there.");
        ExitProcess(3);
    }

    // Microsoft's Visual C++ runtime: looked for the way the real program will find it (its own folder first).
    SetDllDirectoryW(appDir);
    static const WCHAR *runtime[] = { L"VCRUNTIME140.dll", L"VCRUNTIME140_1.dll", L"MSVCP140.dll", L"MSVCP140_1.dll" };
    for (int i = 0; i < 4; i++) {
        HMODULE lib = LoadLibraryW(runtime[i]);
        if (lib == NULL) {
            message[0] = 0;
            append(message, 4096, L"Deckie needs a free part from Microsoft that this PC does not have yet:\r\n"
                                  L"the \"Visual C++ Redistributable\" (missing file: ");
            append(message, 4096, runtime[i]);
            append(message, 4096, L").\r\n\r\n"
                                  L"Get it from Microsoft, install it, then start Deckie again:\r\n"
                                  L"  https://aka.ms/vs/17/release/vc_redist.x64.exe\r\n\r\n"
                                  L"It is the same part many programs and games install. It is safe and small.");
            tell(message);
            ExitProcess(4);
        }
        FreeLibrary(lib);
    }

    // The real program's command line: its own path, then everything after this program's name on ours.
    const WCHAR *rest = GetCommandLineW();
    if (*rest == L'"') { rest++; while (*rest && *rest != L'"') rest++; if (*rest) rest++; }
    else { while (*rest && *rest != L' ' && *rest != L'\t') rest++; }
    commandLine[0] = 0;
    append(commandLine, 32768, L"\"");
    append(commandLine, 32768, child);
    append(commandLine, 32768, L"\"");
    append(commandLine, 32768, rest);

    STARTUPINFOW start;
    PROCESS_INFORMATION process;
    memset(&start, 0, sizeof(start));
    memset(&process, 0, sizeof(process));
    start.cb = sizeof(start);
#ifdef DECKIE_DESK
    // A program of the "windows" kind is not handed its starter's output unless told to. When this one was given
    // somewhere to write (a check that keeps what the program says), the real program writes there too; after a
    // double click there is nowhere, and nothing is passed.
    HANDLE err = GetStdHandle(STD_ERROR_HANDLE);
    if (err != NULL && err != INVALID_HANDLE_VALUE) {
        start.dwFlags |= STARTF_USESTDHANDLES;
        start.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
        start.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
        start.hStdError = err;
    }
#endif
    if (!CreateProcessW(child, commandLine, NULL, NULL, TRUE, 0, NULL, NULL, &start, &process)) {
        tell(L"Deckie could not be started. Windows may have blocked it.\r\n"
             L"See \"READ ME FIRST.txt\" in this folder for what to do.");
        ExitProcess(5);
    }
    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(process.hProcess, &code);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
#ifdef DECKIE_DESK
    if (code != 0 && quiet()) {
        // For a check: the code itself, as Windows writes such codes (0xC0000135 is "a library file was not found").
        static const WCHAR digits[] = L"0123456789ABCDEF";
        message[0] = 0;
        append(message, 4096, L"Deckie Desk (starter): app\\deckie-desk.exe ended with code 0x");
        size_t at = length(message);
        for (int shift = 28; shift >= 0; shift -= 4) message[at++] = digits[(code >> shift) & 15];
        message[at] = 0;
        append(message, 4096, L"\r\n");
        writeBytes(GetStdHandle(STD_ERROR_HANDLE), message);
    }
#endif
    // Windows' own codes for "a library file was not found" and "a library file is too old to have what the program
    // needs": Microsoft's runtime is there but older than the one Swift was built with.
    if (code == 0xC0000135u || code == 0xC0000139u) {
        tell(L"\r\nDeckie could not start: a free part from Microsoft on this PC is missing or too old\r\n"
             L"(the \"Visual C++ Redistributable\").\r\n\r\n"
             L"Get the current one from Microsoft, install it, then start Deckie again:\r\n"
             L"  https://aka.ms/vs/17/release/vc_redist.x64.exe");
    } else if (code > LAST_OWN_CODE) {
#ifdef DECKIE_DESK
        tell(L"Deckie Desk stopped unexpectedly, and that is our fault, not yours.\r\n\r\n"
             L"Please tell the person who gave you Deckie what you were doing when it stopped.\r\n"
             L"Your crates are kept: start Deckie Desk again and they are there.\r\n\r\n"
             L"\"Make Crate File\" in this folder also makes a crate file, without the window.");
#else
        tell(L"\r\nDeckie stopped unexpectedly, and that is our fault, not yours.\r\n"
             L"Please tell the person who gave you Deckie, and send the log file if there is one\r\n"
             L"next to your music folder (its name ends with \"Deckie log.txt\").");
#endif
    }
    ExitProcess(code);
}
