// deckie_ort.c: opens ONNX Runtime's shared library at run time (see deckie_ort.h). Nothing here reaches the
// network; it only opens a file the caller names.
#include "deckie_ort.h"

#include <stdio.h>
#include <string.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#else
#include <dlfcn.h>
#endif

typedef const OrtApiBase *(ORT_API_CALL *DeckieGetApiBase)(void);

static void put_message(char *message, size_t capacity, const char *text) {
    if (message == NULL || capacity == 0) return;
    snprintf(message, capacity, "%s", text);
}

uint32_t deckie_ort_header_api_version(void) { return ORT_API_VERSION; }

#ifdef _WIN32
/// UTF-8 to a newly allocated wide string (free() it), or NULL.
static wchar_t *widen(const char *utf8) {
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, -1, NULL, 0);
    if (n <= 0) return NULL;
    wchar_t *w = (wchar_t *)malloc((size_t)n * sizeof(wchar_t));
    if (w == NULL) return NULL;
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, -1, w, n) != n) {
        free(w);
        return NULL;
    }
    return w;
}

static void put_windows_error(char *message, size_t capacity, const char *what, DWORD code) {
    char text[384];
    DWORD len = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, NULL, code, 0, text,
                               (DWORD)sizeof(text), NULL);
    while (len > 0 && (text[len - 1] == '\n' || text[len - 1] == '\r' || text[len - 1] == ' ')) text[--len] = 0;
    if (message != NULL && capacity > 0) {
        if (len > 0) snprintf(message, capacity, "%s (Windows error %lu: %s)", what, (unsigned long)code, text);
        else snprintf(message, capacity, "%s (Windows error %lu)", what, (unsigned long)code);
    }
}
#endif

const OrtApi *deckie_ort_load(const char *utf8_path, DeckieOrtLoadError *error, const char **library_version,
                              char *message, size_t message_capacity) {
    DeckieOrtLoadError ignored;
    if (error == NULL) error = &ignored;
    if (library_version != NULL) *library_version = NULL;
    put_message(message, message_capacity, "");
    DeckieGetApiBase get_api_base = NULL;

#ifdef _WIN32
    wchar_t *wide = widen(utf8_path);
    if (wide == NULL) {
        *error = DECKIE_ORT_CANNOT_OPEN;
        put_message(message, message_capacity, "the library path is not valid UTF-8");
        return NULL;
    }
    // LOAD_WITH_ALTERED_SEARCH_PATH: DLLs the library itself needs are looked for next to it first.
    HMODULE handle = LoadLibraryExW(wide, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
    free(wide);
    if (handle == NULL) {
        *error = DECKIE_ORT_CANNOT_OPEN;
        put_windows_error(message, message_capacity, "LoadLibraryExW failed", GetLastError());
        return NULL;
    }
    FARPROC symbol = GetProcAddress(handle, "OrtGetApiBase");
    if (symbol == NULL) {
        *error = DECKIE_ORT_NO_ENTRY_POINT;
        put_windows_error(message, message_capacity, "no OrtGetApiBase in the library", GetLastError());
        return NULL;
    }
    memcpy(&get_api_base, &symbol, sizeof(get_api_base));
#else
    void *handle = dlopen(utf8_path, RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        *error = DECKIE_ORT_CANNOT_OPEN;
        const char *why = dlerror();
        put_message(message, message_capacity, why != NULL ? why : "dlopen failed");
        return NULL;
    }
    dlerror();
    void *symbol = dlsym(handle, "OrtGetApiBase");
    if (symbol == NULL) {
        *error = DECKIE_ORT_NO_ENTRY_POINT;
        const char *why = dlerror();
        put_message(message, message_capacity, why != NULL ? why : "no OrtGetApiBase in the library");
        return NULL;
    }
    memcpy(&get_api_base, &symbol, sizeof(get_api_base));
#endif

    const OrtApiBase *base = get_api_base();
    if (base == NULL || base->GetApi == NULL) {
        *error = DECKIE_ORT_NO_ENTRY_POINT;
        put_message(message, message_capacity, "OrtGetApiBase returned no table");
        return NULL;
    }
    const char *version = base->GetVersionString != NULL ? base->GetVersionString() : NULL;
    if (library_version != NULL) *library_version = version;
    const OrtApi *api = base->GetApi(ORT_API_VERSION);
    if (api == NULL) {
        *error = DECKIE_ORT_API_UNSUPPORTED;
        if (message != NULL && message_capacity > 0)
            snprintf(message, message_capacity,
                     "ONNX Runtime %s does not offer API version %u, which the vendored header (1.31.1) needs",
                     version != NULL ? version : "(unknown version)", (unsigned)ORT_API_VERSION);
        return NULL;
    }
    *error = DECKIE_ORT_LOADED;
    return api;
}

OrtStatus *deckie_ort_create_session(const OrtApi *api, const OrtEnv *env, const char *utf8_model_path,
                                     const OrtSessionOptions *options, OrtSession **out) {
#ifdef _WIN32
    wchar_t *wide = widen(utf8_model_path);
    if (wide == NULL) return api->CreateStatus(ORT_INVALID_ARGUMENT, "the model path is not valid UTF-8");
    OrtStatus *status = api->CreateSession(env, wide, options, out);
    free(wide);
    return status;
#else
    return api->CreateSession(env, utf8_model_path, options, out);
#endif
}
