// deckie_capture.h: sound in from a microphone or another input, for the booth inside Desk (research booth-in-desk,
// step 1). A small C face on miniaudio (vendor/miniaudio.h, vendored unmodified; DEPENDENCIES.md section 15), so Swift
// sees a handful of functions and not miniaudio's thousands. The same code on every system: WASAPI on Windows, Core
// Audio on the Mac, PulseAudio (which PipeWire also answers) or ALSA on Linux, the last two opened at run time.
#ifndef DECKIE_CAPTURE_H
#define DECKIE_CAPTURE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Bytes that name an input to the system (miniaudio's `ma_device_id`, copied as it is); checked in deckie_capture.c.
#define DECKIE_CAPTURE_ID_BYTES 512
#define DECKIE_CAPTURE_NAME_BYTES 256

typedef struct {
    char name[DECKIE_CAPTURE_NAME_BYTES];   // UTF-8, as the system names it
    int is_default;                         // the input the system's sound settings choose
    unsigned char id[DECKIE_CAPTURE_ID_BYTES];
} deckie_capture_input;

/// Lists the inputs sound can be taken from, at most `max` into `out`. Returns how many there are (which may be more
/// than `max`), or -1 when the system's sound could not be reached; `backend` (if not NULL) then or otherwise holds
/// the name of the system's sound interface used ("WASAPI", "Core Audio", "PulseAudio", "ALSA"), and `message` a
/// short ASCII reason on failure. Asks no permission: listing names opens no input.
int deckie_capture_list(deckie_capture_input *out, int max, char *backend, size_t backend_size, char *message, size_t message_size);

/// Sound as it arrives: `frames` frames of `channels` interleaved 32-bit floats. Called on the system's sound thread:
/// copy and return.
typedef void (*deckie_capture_sound)(void *user, const float *samples, uint32_t frames, uint32_t channels);
/// Something happened to the input: DECKIE_CAPTURE_GONE (it stopped without being asked: unplugged, taken away, or
/// the system's sound restarted), DECKIE_CAPTURE_REROUTED (the system moved the stream to another input, as Windows
/// does when the default input changes).
typedef void (*deckie_capture_event)(void *user, int event);
#define DECKIE_CAPTURE_GONE 1
#define DECKIE_CAPTURE_REROUTED 2

typedef struct deckie_capture deckie_capture;

/// Error codes from opening and starting.
#define DECKIE_CAPTURE_OK 0
#define DECKIE_CAPTURE_NO_SYSTEM 1      // the system's sound could not be reached
#define DECKIE_CAPTURE_NO_INPUT 2       // no such input, or none at all
#define DECKIE_CAPTURE_NOT_ALLOWED 3    // the system refused (a privacy switch, a permission)
#define DECKIE_CAPTURE_BUSY 4           // another program holds the input for itself
#define DECKIE_CAPTURE_FAILED 5         // anything else

/// Opens one input (`id` from deckie_capture_list, or NULL for the system's default) in shared mode, at the input's
/// own rate and channel count, as 32-bit float, with no voice processing asked for (see deckie_capture.c for what
/// each system allows). `rate` and `channels` receive the format the sound will come in. Returns NULL on failure, with
/// `error` set to a code above and `message` a short reason.
deckie_capture *deckie_capture_open(const unsigned char *id, deckie_capture_sound sound, deckie_capture_event event,
                                    void *user, uint32_t *rate, uint32_t *channels, int *error,
                                    char *message, size_t message_size);
/// The input's name as the system gives it once opened (UTF-8), into `name`.
void deckie_capture_name(deckie_capture *capture, char *name, size_t name_size);
/// Starts the sound coming. Returns a code above.
int deckie_capture_start(deckie_capture *capture);
/// Stops it; no callback runs once this returns. Safe to call twice.
void deckie_capture_stop(deckie_capture *capture);
/// Stops and frees everything. `capture` is gone afterwards.
void deckie_capture_close(deckie_capture *capture);

#ifdef __cplusplus
}
#endif

#endif
