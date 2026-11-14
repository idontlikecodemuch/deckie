// deckie_net.h: one HTTP GET by the system's own networking, for DeckieLookup on Windows and Linux (D36; the owner's
// yes of Nov 14, 2026). On Windows it is WinHTTP, which is part of Windows; on Linux it is libsoup 3, which the
// window's web view already needs. Neither is linked: each is opened at run time, and when it cannot be opened the
// lookup says it is not on this computer. Nothing here is shipped with Deckie (DEPENDENCIES.md, section 12).
//
// What a request is: the address and the headers given, nothing else of ours. No cookies are kept or sent, nothing
// is cached, no credentials are offered. HTTPS is checked against the system's own certificates, and the PC's proxy
// settings are followed.
#ifndef DECKIE_NET_H
#define DECKIE_NET_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// An answer. `headers` is the answer's header lines, "Name: value" each ended by "\n", NUL-terminated; `body` is
/// `body_size` bytes. Free both with `deckie_net_free`.
typedef struct {
    int status;
    char *headers;
    uint8_t *body;
    size_t body_size;
} deckie_net_response;

/// 1 when this computer's networking library could be opened, else 0.
int deckie_net_available(void);

/// Sends one GET to `url` (UTF-8, http or https) with `header_count` header lines ("Name: value", UTF-8) and waits
/// at most `timeout_seconds` for each step (finding the host, connecting, sending, the answer).
/// Returns 0 with `out` filled when an answer came, whatever its status. Otherwise: 1 when the networking library
/// is not on this computer; 2 when there was no answer (no connection, the host not found, a firewall or proxy in
/// the way, a certificate that does not check out, the time limit); 3 when the address or the answer could not be
/// handled (also an answer over 16 MB). `message` (if not NULL) then holds a short ASCII reason for the log.
int deckie_net_get(const char *url, const char *const *headers, size_t header_count, int timeout_seconds,
                   deckie_net_response *out, char *message, size_t message_size);

void deckie_net_free(deckie_net_response *response);

#ifdef __cplusplus
}
#endif

#endif
