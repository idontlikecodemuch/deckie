// "Make Crate File.exe": the one program a DJ sees in the Deckie folder. It starts app\deckie-make.exe (the real
// program, with the libraries it needs beside it) and passes on whatever was dropped on it.
//
// Why a starter at all. The real program needs some twenty library files next to it, which would bury the one thing
// to click. And three things can go wrong before the real program can say a word, each of which Windows reports with
// a box nobody understands, or with a window that vanishes. The starter says them in plain words and keeps the
// window open:
//   1. started from inside the zip, without unzipping (Windows then copies out this one file and nothing else);
//   2. Microsoft's Visual C++ runtime is not on this PC (four files Windows itself does not always have, which
//      Deckie may not ship: DEPENDENCIES.md);
//   3. the real program stopped in a way it did not expect.
//
// It uses nothing but Windows' own kernel32.dll: no C runtime, so it starts on any 64-bit Windows 10 or 11. Built by
// core/Tools/windows/package.sh with the clang that comes with Swift.

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

static WCHAR here[4096];
static WCHAR child[4200];
static WCHAR appDir[4200];
static WCHAR commandLine[32768];
static WCHAR typed[256];

static size_t length(const WCHAR *s) { size_t n = 0; while (s[n]) n++; return n; }
static void append(WCHAR *to, size_t capacity, const WCHAR *s) {
    size_t n = length(to);
    while (*s && n + 1 < capacity) to[n++] = *s++;
    to[n] = 0;
}

static void say(const WCHAR *text) {
    HANDLE out = GetStdHandle(STD_OUTPUT_HANDLE);
    DWORD written = 0;
    if (!WriteConsoleW(out, text, (DWORD)length(text), &written, NULL)) {
        // Not a console (output sent to a file): plain bytes; every message here is ASCII.
        char bytes[2048];
        size_t n = 0;
        while (text[n] && n < sizeof(bytes)) { bytes[n] = (char)text[n]; n++; }
        WriteFile(out, bytes, (DWORD)n, &written, NULL);
    }
}

static void waitForEnter(void) {
    HANDLE in = GetStdHandle(STD_INPUT_HANDLE);
    DWORD mode = 0, count = 0;
    say(L"\r\nPress Enter to close this window.\r\n");
    if (GetConsoleMode(in, &mode)) ReadConsoleW(in, typed, 255, &count, NULL);
}

void entry(void) {
    // Where this program is, and the real one beside it in "app".
    DWORD n = GetModuleFileNameW(NULL, here, 4095);
    while (n > 0 && here[n - 1] != L'\\' && here[n - 1] != L'/') n--;
    here[n] = 0;
    appDir[0] = 0; append(appDir, 4200, here); append(appDir, 4200, L"app");
    child[0] = 0; append(child, 4200, appDir); append(child, 4200, L"\\deckie-make.exe");

    if (GetFileAttributesW(child) == INVALID_FILE_ATTRIBUTES) {
        say(L"Deckie cannot start from here: the rest of its files are missing.\r\n\r\n"
            L"This happens when it is started from inside the zip. Unzip first:\r\n"
            L"right-click the Deckie zip, choose \"Extract All\", then open the new folder\r\n"
            L"and start \"Make Crate File\" from there.\r\n");
        waitForEnter();
        ExitProcess(3);
    }

    // Microsoft's Visual C++ runtime: looked for the way the real program will find it (its own folder first).
    SetDllDirectoryW(appDir);
    static const WCHAR *runtime[] = { L"VCRUNTIME140.dll", L"VCRUNTIME140_1.dll", L"MSVCP140.dll", L"MSVCP140_1.dll" };
    for (int i = 0; i < 4; i++) {
        HMODULE lib = LoadLibraryW(runtime[i]);
        if (lib == NULL) {
            say(L"Deckie needs a free part from Microsoft that this PC does not have yet:\r\n"
                L"the \"Visual C++ Redistributable\" (missing file: ");
            say(runtime[i]);
            say(L").\r\n\r\n"
                L"Get it from Microsoft, install it, then start Deckie again:\r\n"
                L"  https://aka.ms/vs/17/release/vc_redist.x64.exe\r\n\r\n"
                L"It is the same part many programs and games install. It is safe and small.\r\n");
            waitForEnter();
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
    if (!CreateProcessW(child, commandLine, NULL, NULL, TRUE, 0, NULL, NULL, &start, &process)) {
        say(L"Deckie could not be started. Windows may have blocked it.\r\n"
            L"See \"READ ME FIRST.txt\" in this folder for what to do.\r\n");
        waitForEnter();
        ExitProcess(5);
    }
    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(process.hProcess, &code);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    // 0 to 3 are the real program's own endings, each already said in its own words (and it waited for Enter).
    if (code > 3) {
        say(L"\r\nDeckie stopped unexpectedly, and that is our fault, not yours.\r\n"
            L"Please tell the person who gave you Deckie, and send the log file if there is one\r\n"
            L"next to your music folder (its name ends with \"Deckie log.txt\").\r\n");
        waitForEnter();
    }
    ExitProcess(code);
}
