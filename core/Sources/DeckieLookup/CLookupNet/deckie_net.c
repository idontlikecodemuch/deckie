// deckie_net.c: see deckie_net.h. Two implementations, one for Windows (WinHTTP) and one for Linux (libsoup 3), and
// a third that says "not on this computer" everywhere else (the Mac uses Foundation's URL loading in Swift).

#include "deckie_net.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DECKIE_NET_MAX_BODY ((size_t)16 * 1024 * 1024)

static int fail(int code, char *message, size_t size, const char *what, long detail) {
    if (message && size) snprintf(message, size, "%s (%ld)", what, detail);
    return code;
}

void deckie_net_free(deckie_net_response *r) {
    if (!r) return;
    free(r->headers);
    free(r->body);
    memset(r, 0, sizeof(*r));
}

#if defined(_WIN32)

// ---- Windows: WinHTTP, opened at run time (winhttp.dll is in every Windows this program runs on; opening it late
// keeps the list of libraries the program needs to start as it was).

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winhttp.h>

typedef HINTERNET (WINAPI *open_fn)(LPCWSTR, DWORD, LPCWSTR, LPCWSTR, DWORD);
typedef BOOL (WINAPI *close_fn)(HINTERNET);
typedef BOOL (WINAPI *timeouts_fn)(HINTERNET, int, int, int, int);
typedef BOOL (WINAPI *crack_fn)(LPCWSTR, DWORD, DWORD, LPURL_COMPONENTS);
typedef HINTERNET (WINAPI *connect_fn)(HINTERNET, LPCWSTR, INTERNET_PORT, DWORD);
typedef HINTERNET (WINAPI *open_request_fn)(HINTERNET, LPCWSTR, LPCWSTR, LPCWSTR, LPCWSTR, LPCWSTR *, DWORD);
typedef BOOL (WINAPI *set_option_fn)(HINTERNET, DWORD, LPVOID, DWORD);
typedef BOOL (WINAPI *add_headers_fn)(HINTERNET, LPCWSTR, DWORD, DWORD);
typedef BOOL (WINAPI *send_fn)(HINTERNET, LPCWSTR, DWORD, LPVOID, DWORD, DWORD, DWORD_PTR);
typedef BOOL (WINAPI *receive_fn)(HINTERNET, LPVOID);
typedef BOOL (WINAPI *query_headers_fn)(HINTERNET, DWORD, LPCWSTR, LPVOID, LPDWORD, LPDWORD);
typedef BOOL (WINAPI *query_data_fn)(HINTERNET, LPDWORD);
typedef BOOL (WINAPI *read_fn)(HINTERNET, LPVOID, DWORD, LPDWORD);

static INIT_ONCE once = INIT_ONCE_STATIC_INIT;
static int available;
static open_fn h_open;
static close_fn h_close;
static timeouts_fn h_timeouts;
static crack_fn h_crack;
static connect_fn h_connect;
static open_request_fn h_open_request;
static set_option_fn h_set_option;
static add_headers_fn h_add_headers;
static send_fn h_send;
static receive_fn h_receive;
static query_headers_fn h_query_headers;
static query_data_fn h_query_data;
static read_fn h_read;

static BOOL CALLBACK load(PINIT_ONCE o, PVOID p, PVOID *c) {
    (void)o; (void)p; (void)c;
    // From the system's own folder only, never from beside the program.
    HMODULE lib = LoadLibraryExW(L"winhttp.dll", NULL, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!lib) return TRUE;
#define SYM(var, type, name) var = (type)(void *)GetProcAddress(lib, name); if (!var) return TRUE
    SYM(h_open, open_fn, "WinHttpOpen");
    SYM(h_close, close_fn, "WinHttpCloseHandle");
    SYM(h_timeouts, timeouts_fn, "WinHttpSetTimeouts");
    SYM(h_crack, crack_fn, "WinHttpCrackUrl");
    SYM(h_connect, connect_fn, "WinHttpConnect");
    SYM(h_open_request, open_request_fn, "WinHttpOpenRequest");
    SYM(h_set_option, set_option_fn, "WinHttpSetOption");
    SYM(h_add_headers, add_headers_fn, "WinHttpAddRequestHeaders");
    SYM(h_send, send_fn, "WinHttpSendRequest");
    SYM(h_receive, receive_fn, "WinHttpReceiveResponse");
    SYM(h_query_headers, query_headers_fn, "WinHttpQueryHeaders");
    SYM(h_query_data, query_data_fn, "WinHttpQueryDataAvailable");
    SYM(h_read, read_fn, "WinHttpReadData");
#undef SYM
    available = 1;
    return TRUE;
}

int deckie_net_available(void) {
    InitOnceExecuteOnce(&once, load, NULL, NULL);
    return available;
}

static wchar_t *wide(const char *utf8) {
    int n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
    if (n <= 0) return NULL;
    wchar_t *w = (wchar_t *)malloc((size_t)n * sizeof(wchar_t));
    if (w) MultiByteToWideChar(CP_UTF8, 0, utf8, -1, w, n);
    return w;
}

static char *narrow(const wchar_t *w) {
    int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    if (n <= 0) return NULL;
    char *s = (char *)malloc((size_t)n);
    if (s) WideCharToMultiByte(CP_UTF8, 0, w, -1, s, n, NULL, NULL);
    return s;
}

/// Whether a WinHTTP error means "no answer could be had" rather than a fault of ours.
static int no_answer(DWORD e) {
    switch (e) {
    case ERROR_WINHTTP_CANNOT_CONNECT: case ERROR_WINHTTP_CONNECTION_ERROR: case ERROR_WINHTTP_NAME_NOT_RESOLVED:
    case ERROR_WINHTTP_TIMEOUT: case ERROR_WINHTTP_SECURE_FAILURE: case ERROR_WINHTTP_OPERATION_CANCELLED:
    case ERROR_WINHTTP_AUTODETECTION_FAILED: case ERROR_WINHTTP_UNABLE_TO_DOWNLOAD_SCRIPT:
    case ERROR_WINHTTP_SECURE_CHANNEL_ERROR: case ERROR_WINHTTP_CLIENT_AUTH_CERT_NEEDED:
    case ERROR_WINHTTP_SECURE_CERT_DATE_INVALID: case ERROR_WINHTTP_SECURE_CERT_CN_INVALID:
    case ERROR_WINHTTP_SECURE_INVALID_CA: case ERROR_WINHTTP_SECURE_CERT_REV_FAILED:
    case ERROR_WINHTTP_SECURE_INVALID_CERT: case ERROR_WINHTTP_SECURE_CERT_REVOKED:
    case ERROR_WINHTTP_SECURE_CERT_WRONG_USAGE: case ERROR_WINHTTP_INVALID_SERVER_RESPONSE:
    case ERROR_WINHTTP_REDIRECT_FAILED: case ERROR_WINHTTP_RESEND_REQUEST:
    case ERROR_NOT_ENOUGH_MEMORY: case ERROR_ACCESS_DENIED:
    case WSAEACCES: case WSAENETDOWN: case WSAENETUNREACH: case WSAEHOSTUNREACH: case WSAECONNREFUSED: case WSAETIMEDOUT:
        return 1;
    default:
        return 0;
    }
}

int deckie_net_get(const char *url, const char *const *headers, size_t header_count, int timeout_seconds,
                   deckie_net_response *out, char *message, size_t message_size) {
    memset(out, 0, sizeof(*out));
    if (!deckie_net_available()) return fail(1, message, message_size, "WinHTTP could not be opened", (long)GetLastError());
    int result = 3;
    const char *what = "the address could not be read";
    DWORD error = 0;
    HINTERNET session = NULL, connection = NULL, request = NULL;
    wchar_t *wurl = wide(url), *host = NULL, *path = NULL, *raw = NULL;
    uint8_t *body = NULL;
    size_t size = 0, room = 0;
    if (!wurl) goto done;

    URL_COMPONENTS parts;
    memset(&parts, 0, sizeof(parts));
    parts.dwStructSize = sizeof(parts);
    parts.dwHostNameLength = (DWORD)-1;
    parts.dwUrlPathLength = (DWORD)-1;
    parts.dwExtraInfoLength = (DWORD)-1;
    if (!h_crack(wurl, 0, 0, &parts)) { error = GetLastError(); goto done; }
    if (parts.nScheme != INTERNET_SCHEME_HTTP && parts.nScheme != INTERNET_SCHEME_HTTPS) goto done;
    host = (wchar_t *)calloc((size_t)parts.dwHostNameLength + 1, sizeof(wchar_t));
    size_t path_length = (size_t)parts.dwUrlPathLength + (size_t)parts.dwExtraInfoLength;
    path = (wchar_t *)calloc(path_length + 2, sizeof(wchar_t));
    if (!host || !path) goto done;
    memcpy(host, parts.lpszHostName, (size_t)parts.dwHostNameLength * sizeof(wchar_t));
    memcpy(path, parts.lpszUrlPath, (size_t)parts.dwUrlPathLength * sizeof(wchar_t));
    memcpy(path + parts.dwUrlPathLength, parts.lpszExtraInfo, (size_t)parts.dwExtraInfoLength * sizeof(wchar_t));
    if (path_length == 0) path[0] = L'/';

    // The PC's own proxy settings (Windows 8.1 and later); no agent name here, the caller's header gives it.
    what = "WinHTTP did not start";
    session = h_open(NULL, WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (!session) { error = GetLastError(); goto done; }
    int ms = timeout_seconds * 1000;
    h_timeouts(session, ms, ms, ms, ms);
    connection = h_connect(session, host, parts.nPort, 0);
    if (!connection) { error = GetLastError(); goto done; }
    request = h_open_request(connection, L"GET", path, NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES,
                             parts.nScheme == INTERNET_SCHEME_HTTPS ? WINHTTP_FLAG_SECURE : 0);
    if (!request) { error = GetLastError(); goto done; }
    // No cookies kept or sent, no credentials offered. (WinHTTP has no cache.)
    DWORD off = WINHTTP_DISABLE_COOKIES | WINHTTP_DISABLE_AUTHENTICATION;
    h_set_option(request, WINHTTP_OPTION_DISABLE_FEATURE, &off, sizeof(off));
    for (size_t i = 0; i < header_count; i++) {
        wchar_t *line = wide(headers[i]);
        if (!line) goto done;
        BOOL ok = h_add_headers(request, line, (DWORD)-1, WINHTTP_ADDREQ_FLAG_ADD | WINHTTP_ADDREQ_FLAG_REPLACE);
        free(line);
        if (!ok) { what = "a header was refused"; error = GetLastError(); goto done; }
    }

    what = "no answer";
    if (!h_send(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, 0)
        || !h_receive(request, NULL)) {
        error = GetLastError();
        result = no_answer(error) ? 2 : 3;
        goto done;
    }
    DWORD status = 0, length = sizeof(status);
    if (!h_query_headers(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, WINHTTP_HEADER_NAME_BY_INDEX,
                         &status, &length, WINHTTP_NO_HEADER_INDEX)) { error = GetLastError(); goto done; }
    length = 0;
    h_query_headers(request, WINHTTP_QUERY_RAW_HEADERS_CRLF, WINHTTP_HEADER_NAME_BY_INDEX, NULL, &length, WINHTTP_NO_HEADER_INDEX);
    if (length) {
        raw = (wchar_t *)calloc((size_t)length / sizeof(wchar_t) + 1, sizeof(wchar_t));
        if (!raw) goto done;
        if (!h_query_headers(request, WINHTTP_QUERY_RAW_HEADERS_CRLF, WINHTTP_HEADER_NAME_BY_INDEX, raw, &length,
                             WINHTTP_NO_HEADER_INDEX)) raw[0] = 0;
    }
    for (;;) {
        DWORD waiting = 0, got = 0;
        if (!h_query_data(request, &waiting)) { error = GetLastError(); result = no_answer(error) ? 2 : 3; goto done; }
        if (waiting == 0) break;
        if (size + waiting > DECKIE_NET_MAX_BODY) { what = "the answer is too large"; goto done; }
        if (size + waiting > room) {
            room = (size + waiting) * 2;
            uint8_t *more = (uint8_t *)realloc(body, room);
            if (!more) goto done;
            body = more;
        }
        if (!h_read(request, body + size, waiting, &got)) { error = GetLastError(); result = no_answer(error) ? 2 : 3; goto done; }
        if (got == 0) break;
        size += got;
    }
    out->status = (int)status;
    out->headers = raw ? narrow(raw) : NULL;
    // The status line comes first ("HTTP/1.1 200 OK"); the lines after it are the headers. "\r\n" becomes "\n".
    if (out->headers) {
        char *from = strstr(out->headers, "\r\n"), *to = out->headers;
        from = from ? from + 2 : out->headers + strlen(out->headers);
        for (; *from; from++) if (*from != '\r') *to++ = *from;
        *to = 0;
    }
    out->body = body;
    out->body_size = size;
    body = NULL;
    result = 0;

done:
    if (result != 0) fail(result, message, message_size, what, (long)error);
    free(body); free(raw); free(host); free(path); free(wurl);
    if (request) h_close(request);
    if (connection) h_close(connection);
    if (session) h_close(session);
    return result;
}

#elif defined(__linux__)

// ---- Linux: libsoup 3, opened at run time. No libsoup header is needed to build: the few functions used are
// declared here as libsoup and GLib document them, and found by name. Where the window's web view is installed
// (WebKitGTK 4.1), libsoup 3 and GLib's networking are too.

#include <dlfcn.h>
#include <pthread.h>

typedef struct { uint32_t domain; int code; char *message; } g_error;   // GLib's GError
typedef void (*header_fn)(const char *name, const char *value, void *user);

static pthread_once_t once = PTHREAD_ONCE_INIT;
static int available;
static void *(*s_session_new)(void);
static void (*s_session_set_timeout)(void *, unsigned);
static void (*s_session_set_idle_timeout)(void *, unsigned);
static void *(*s_message_new)(const char *, const char *);
static void *(*s_message_get_request_headers)(void *);
static void *(*s_message_get_response_headers)(void *);
static void (*s_headers_replace)(void *, const char *, const char *);
static void (*s_headers_foreach)(void *, header_fn, void *);
static void *(*s_send_and_read)(void *, void *, void *, g_error **);
static unsigned (*s_message_get_status)(void *);
static const void *(*g_bytes_data)(void *, size_t *);
static void (*g_bytes_free)(void *);
static void (*g_error_release)(g_error *);
static void (*g_object_release)(void *);

static void load(void) {
    void *soup = dlopen("libsoup-3.0.so.0", RTLD_NOW | RTLD_LOCAL);
    if (!soup) return;
    // GLib comes with libsoup (it needs it); its functions are found through libsoup's own list of libraries.
#define SYM(var, name) *(void **)(&var) = dlsym(soup, name); if (!var) return
    SYM(s_session_new, "soup_session_new");
    SYM(s_session_set_timeout, "soup_session_set_timeout");
    SYM(s_session_set_idle_timeout, "soup_session_set_idle_timeout");
    SYM(s_message_new, "soup_message_new");
    SYM(s_message_get_request_headers, "soup_message_get_request_headers");
    SYM(s_message_get_response_headers, "soup_message_get_response_headers");
    SYM(s_headers_replace, "soup_message_headers_replace");
    SYM(s_headers_foreach, "soup_message_headers_foreach");
    SYM(s_send_and_read, "soup_session_send_and_read");
    SYM(s_message_get_status, "soup_message_get_status");
    SYM(g_bytes_data, "g_bytes_get_data");
    SYM(g_bytes_free, "g_bytes_unref");
    SYM(g_error_release, "g_error_free");
    SYM(g_object_release, "g_object_unref");
#undef SYM
    available = 1;
}

int deckie_net_available(void) {
    pthread_once(&once, load);
    return available;
}

typedef struct { char *text; size_t size, room; int failed; } header_lines;

static void add_header(const char *name, const char *value, void *user) {
    header_lines *h = (header_lines *)user;
    size_t need = strlen(name) + strlen(value) + 4;
    if (h->size + need > h->room) {
        size_t room = (h->size + need) * 2;
        char *more = (char *)realloc(h->text, room);
        if (!more) { h->failed = 1; return; }
        h->text = more; h->room = room;
    }
    h->size += (size_t)snprintf(h->text + h->size, h->room - h->size, "%s: %s\n", name, value);
}

int deckie_net_get(const char *url, const char *const *headers, size_t header_count, int timeout_seconds,
                   deckie_net_response *out, char *message, size_t message_size) {
    memset(out, 0, sizeof(*out));
    if (!deckie_net_available()) return fail(1, message, message_size, "libsoup 3 could not be opened", 0);
    if (strncmp(url, "http://", 7) != 0 && strncmp(url, "https://", 8) != 0)
        return fail(3, message, message_size, "the address could not be read", 0);
    void *message_object = s_message_new("GET", url);
    if (!message_object) return fail(3, message, message_size, "the address could not be read", 0);
    // A session of its own for each request: nothing is kept between them. A new session has no cookie store and no
    // cache (libsoup adds those only when asked), follows the system's proxy settings and checks HTTPS against the
    // system's certificates.
    void *session = s_session_new();
    s_session_set_timeout(session, (unsigned)timeout_seconds);
    s_session_set_idle_timeout(session, (unsigned)timeout_seconds);
    void *request_headers = s_message_get_request_headers(message_object);
    for (size_t i = 0; i < header_count; i++) {
        const char *colon = strchr(headers[i], ':');
        if (!colon) continue;
        size_t n = (size_t)(colon - headers[i]);
        char name[128];
        if (n == 0 || n >= sizeof(name)) continue;
        memcpy(name, headers[i], n);
        name[n] = 0;
        const char *value = colon + 1;
        while (*value == ' ') value++;
        s_headers_replace(request_headers, name, value);
    }
    int result = 0;
    g_error *error = NULL;
    void *bytes = s_send_and_read(session, message_object, NULL, &error);
    if (!bytes || error) {
        if (message && message_size) snprintf(message, message_size, "no answer: %.200s", error && error->message ? error->message : "?");
        result = 2;
    } else {
        size_t size = 0;
        const void *data = g_bytes_data(bytes, &size);
        header_lines lines = { NULL, 0, 0, 0 };
        s_headers_foreach(s_message_get_response_headers(message_object), add_header, &lines);
        if (size > DECKIE_NET_MAX_BODY || lines.failed) {
            free(lines.text);
            result = fail(3, message, message_size, "the answer is too large", (long)size);
        } else {
            out->status = (int)s_message_get_status(message_object);
            out->headers = lines.text;
            out->body = (uint8_t *)malloc(size ? size : 1);
            if (!out->body) { deckie_net_free(out); result = fail(3, message, message_size, "out of memory", 0); }
            else { if (size) memcpy(out->body, data, size); out->body_size = size; }
        }
    }
    if (error) g_error_release(error);
    if (bytes) g_bytes_free(bytes);
    g_object_release(message_object);
    g_object_release(session);
    return result;
}

#else

int deckie_net_available(void) { return 0; }

int deckie_net_get(const char *url, const char *const *headers, size_t header_count, int timeout_seconds,
                   deckie_net_response *out, char *message, size_t message_size) {
    (void)url; (void)headers; (void)header_count; (void)timeout_seconds;
    memset(out, 0, sizeof(*out));
    return fail(1, message, message_size, "not built for this system", 0);
}

#endif
