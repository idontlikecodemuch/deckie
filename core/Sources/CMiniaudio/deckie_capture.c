// deckie_capture.c: miniaudio compiled in, with only what capture needs, and the small face deckie_capture.h gives
// Swift. miniaudio itself is vendor/miniaudio.h, unmodified (0.11.26; DEPENDENCIES.md section 15).
//
// What is left out: decoding, encoding, the sound generators, miniaudio's engine, node graph and resource manager
// (Deckie decodes with dr_mp3 and dr_flac, and never plays sound here). Only four of the system interfaces are
// compiled: WASAPI (Windows), Core Audio (macOS), PulseAudio and ALSA (Linux; PipeWire answers programs written for
// PulseAudio). PulseAudio and ALSA are opened at run time (dlopen), so nothing extra is needed to build on Linux and a
// computer without one of them simply has the other. On the Mac the frameworks are linked (MA_NO_RUNTIME_LINKING,
// set by Package.swift), which is what Apple's notarisation wants; on Windows miniaudio loads ole32 and avrt itself.
//
// Voice processing, system by system (none of it is asked for here; this is what each system does with that):
// - Mac: miniaudio opens the input through Core Audio's HAL output unit, not the voice-processing unit, so macOS adds
//   no automatic gain, noise suppression or echo cancelling (and the Mic Mode menu does not apply to it). What a
//   built-in microphone's driver does in itself (the MacBook's microphone array is beam-formed) cannot be switched off.
// - Windows: the stream is a shared-mode WASAPI stream of the category "Other", not "Communications", so Windows'
//   communications processing (echo cancelling, the call-time gain) is not applied. miniaudio 0.11.26 cannot ask for
//   the RAW stream option (AUDCLNT_STREAMOPTIONS_RAW), so a driver's own default-mode effects (a maker's "audio
//   enhancements": noise suppression, automatic gain) stay as the person set them in Sound settings.
// - Linux: PulseAudio, PipeWire and ALSA add nothing unless the person loaded an echo-cancelling module as their
//   default input; nothing here can switch that off.
#if defined(__APPLE__) && !defined(MA_NO_RUNTIME_LINKING)
#define MA_NO_RUNTIME_LINKING
#endif
#define MA_ENABLE_ONLY_SPECIFIC_BACKENDS
#define MA_ENABLE_WASAPI
#define MA_ENABLE_COREAUDIO
#define MA_ENABLE_PULSEAUDIO
#define MA_ENABLE_ALSA
#define MA_NO_DECODING
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#define MA_NO_ENGINE
#define MA_NO_NODE_GRAPH
#define MA_NO_RESOURCE_MANAGER
#define MINIAUDIO_IMPLEMENTATION
#include "vendor/miniaudio.h"

#include "deckie_capture.h"
#include <string.h>
#include <stdlib.h>

typedef char deckie_capture_id_fits[(sizeof(ma_device_id) <= DECKIE_CAPTURE_ID_BYTES) ? 1 : -1];

struct deckie_capture {
    ma_context context;
    ma_device device;
    deckie_capture_sound sound;
    deckie_capture_event event;
    void *user;
    volatile int stopping;   // set before a stop we asked for, so its notification is not taken for an unplugged input
    int started;
};

static void copy_text(char *to, size_t size, const char *from) {
    if (to == NULL || size == 0) return;
    if (from == NULL) from = "";
    size_t n = strlen(from);
    if (n >= size) n = size - 1;
    memcpy(to, from, n);
    to[n] = 0;
}

static int code_for(ma_result r) {
    switch (r) {
    case MA_SUCCESS: return DECKIE_CAPTURE_OK;
    case MA_NO_BACKEND: return DECKIE_CAPTURE_NO_SYSTEM;
    case MA_NO_DEVICE: case MA_DOES_NOT_EXIST: case MA_DEVICE_TYPE_NOT_SUPPORTED: return DECKIE_CAPTURE_NO_INPUT;
    case MA_ACCESS_DENIED: return DECKIE_CAPTURE_NOT_ALLOWED;
    case MA_BUSY: return DECKIE_CAPTURE_BUSY;
    default: return DECKIE_CAPTURE_FAILED;
    }
}

static ma_result init_context(ma_context *context) {
    ma_context_config config = ma_context_config_init();
    // No thread priority games, nothing that needs a permission of its own.
    config.threadPriority = ma_thread_priority_default;
    return ma_context_init(NULL, 0, &config, context);
}

int deckie_capture_list(deckie_capture_input *out, int max, char *backend, size_t backend_size, char *message, size_t message_size) {
    ma_context context;
    ma_result r = init_context(&context);
    if (r != MA_SUCCESS) { copy_text(message, message_size, ma_result_description(r)); copy_text(backend, backend_size, ""); return -1; }
    copy_text(backend, backend_size, ma_get_backend_name(context.backend));
    ma_device_info *capture = NULL;
    ma_uint32 count = 0;
    r = ma_context_get_devices(&context, NULL, NULL, &capture, &count);
    if (r != MA_SUCCESS) {
        copy_text(message, message_size, ma_result_description(r));
        ma_context_uninit(&context);
        return -1;
    }
    for (ma_uint32 i = 0; i < count && (int)i < max; i++) {
        memset(&out[i], 0, sizeof(out[i]));
        copy_text(out[i].name, sizeof(out[i].name), capture[i].name);
        out[i].is_default = capture[i].isDefault ? 1 : 0;
        memcpy(out[i].id, &capture[i].id, sizeof(ma_device_id));
    }
    ma_context_uninit(&context);
    return (int)count;
}

static void on_data(ma_device *device, void *output, const void *input, ma_uint32 frames) {
    (void)output;
    deckie_capture *c = (deckie_capture *)device->pUserData;
    if (c == NULL || c->stopping || input == NULL || frames == 0) return;
    c->sound(c->user, (const float *)input, frames, device->capture.channels);
}

static void on_notification(const ma_device_notification *n) {
    deckie_capture *c = (deckie_capture *)n->pDevice->pUserData;
    if (c == NULL || c->event == NULL) return;
    switch (n->type) {
    case ma_device_notification_type_stopped:
        if (!c->stopping && c->started) c->event(c->user, DECKIE_CAPTURE_GONE);
        break;
    case ma_device_notification_type_rerouted:
        c->event(c->user, DECKIE_CAPTURE_REROUTED);
        break;
    default: break;
    }
}

deckie_capture *deckie_capture_open(const unsigned char *id, deckie_capture_sound sound, deckie_capture_event event,
                                    void *user, uint32_t *rate, uint32_t *channels, int *error,
                                    char *message, size_t message_size) {
    if (error) *error = DECKIE_CAPTURE_FAILED;
    deckie_capture *c = (deckie_capture *)calloc(1, sizeof(deckie_capture));
    if (c == NULL) { copy_text(message, message_size, "out of memory"); return NULL; }
    c->sound = sound; c->event = event; c->user = user;
    ma_result r = init_context(&c->context);
    if (r != MA_SUCCESS) {
        if (error) *error = code_for(r) == DECKIE_CAPTURE_FAILED ? DECKIE_CAPTURE_NO_SYSTEM : code_for(r);
        copy_text(message, message_size, ma_result_description(r));
        free(c);
        return NULL;
    }
    ma_device_id chosen;
    ma_device_config config = ma_device_config_init(ma_device_type_capture);
    if (id != NULL) { memcpy(&chosen, id, sizeof(ma_device_id)); config.capture.pDeviceID = &chosen; }
    // The input's own format: 0 asks for the device's native rate and channel count, so nothing is resampled or mixed
    // down here (the listener takes any rate and channel count); only the sample type becomes float.
    config.capture.format = ma_format_f32;
    config.capture.channels = 0;
    config.sampleRate = 0;
    config.capture.shareMode = ma_share_mode_shared;
    // A tenth of a second a callback is plenty: the listener reads once a second from the last eight.
    config.periodSizeInMilliseconds = 50;
    config.noFixedSizedCallback = MA_TRUE;
    config.dataCallback = on_data;
    config.notificationCallback = on_notification;
    config.pUserData = c;
    // Windows: no hardware offload (a capture stream has none to give, and it stays a plain shared stream).
    config.wasapi.noHardwareOffloading = MA_TRUE;
    config.wasapi.noAutoConvertSRC = MA_TRUE;
    // Linux, PulseAudio: the stream's name in the system's sound settings.
    config.pulse.pStreamNameCapture = "Deckie listening";
    // Mac: never change the input's own rate for us.
    config.coreaudio.allowNominalSampleRateChange = MA_FALSE;
    r = ma_device_init(&c->context, &config, &c->device);
    if (r != MA_SUCCESS) {
        if (error) *error = code_for(r);
        copy_text(message, message_size, ma_result_description(r));
        ma_context_uninit(&c->context);
        free(c);
        return NULL;
    }
    if (rate) *rate = c->device.sampleRate;
    if (channels) *channels = c->device.capture.channels;
    if (error) *error = DECKIE_CAPTURE_OK;
    return c;
}

void deckie_capture_name(deckie_capture *c, char *name, size_t name_size) {
    if (c == NULL || name == NULL || name_size == 0) return;
    name[0] = 0;
    ma_device_get_name(&c->device, ma_device_type_capture, name, name_size, NULL);
}

int deckie_capture_start(deckie_capture *c) {
    if (c == NULL) return DECKIE_CAPTURE_FAILED;
    c->stopping = 0;
    c->started = 1;
    ma_result r = ma_device_start(&c->device);
    if (r != MA_SUCCESS) c->started = 0;
    return code_for(r);
}

void deckie_capture_stop(deckie_capture *c) {
    if (c == NULL) return;
    c->stopping = 1;
    if (ma_device_get_state(&c->device) == ma_device_state_started) ma_device_stop(&c->device);
    c->started = 0;
}

void deckie_capture_close(deckie_capture *c) {
    if (c == NULL) return;
    deckie_capture_stop(c);
    ma_device_uninit(&c->device);
    ma_context_uninit(&c->context);
    free(c);
}
