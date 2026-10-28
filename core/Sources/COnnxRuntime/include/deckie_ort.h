// deckie_ort.h: ONNX Runtime opened at run time, not linked at build time.
//
// The package builds on every platform with nothing installed: only ONNX Runtime's C API header is vendored here
// (onnxruntime_c_api.h and the two headers it includes, unmodified from the 1.31.1 release; DEPENDENCIES.md). At run
// time deckie_ort_load opens the shared library (dlopen on Linux and macOS, LoadLibraryExW on Windows), finds its one
// exported entry point, OrtGetApiBase, and asks it for the function table (OrtApi) of the API version this header
// describes (ORT_API_VERSION). Everything else is called through that table.
#ifndef DECKIE_ORT_H
#define DECKIE_ORT_H

#include <stddef.h>
#include <stdint.h>

#include "onnxruntime_c_api.h"

#ifdef __cplusplus
extern "C" {
#endif

/// Why deckie_ort_load returned no table.
typedef enum DeckieOrtLoadError {
    DECKIE_ORT_LOADED = 0,
    /// The library file could not be opened (missing, wrong architecture, a dependency missing).
    DECKIE_ORT_CANNOT_OPEN = 1,
    /// The file opened but has no OrtGetApiBase: not ONNX Runtime.
    DECKIE_ORT_NO_ENTRY_POINT = 2,
    /// ONNX Runtime refused ORT_API_VERSION: the library is older than the vendored header.
    DECKIE_ORT_API_UNSUPPORTED = 3,
} DeckieOrtLoadError;

/// The API version of the vendored header (ORT_API_VERSION).
uint32_t deckie_ort_header_api_version(void);

/// Opens the ONNX Runtime library at `utf8_path` and returns its function table for ORT_API_VERSION, or NULL.
/// On return `*error` says which step failed; `message` (if not NULL) gets a NUL-terminated explanation of at most
/// `message_capacity` bytes; `*library_version` (if not NULL) points to ONNX Runtime's version string (owned by the
/// library) when the file was ONNX Runtime, else NULL. The library stays loaded for the life of the process.
const OrtApi *deckie_ort_load(const char *utf8_path, DeckieOrtLoadError *error, const char **library_version,
                              char *message, size_t message_capacity);

/// api->CreateSession with the model path given as UTF-8 on every platform (ONNX Runtime wants wide characters on
/// Windows; this converts).
OrtStatus *deckie_ort_create_session(const OrtApi *api, const OrtEnv *env, const char *utf8_model_path,
                                     const OrtSessionOptions *options, OrtSession **out);

#ifdef __cplusplus
}
#endif

#endif
