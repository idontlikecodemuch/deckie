// deckie_mf.c: Media Foundation's source reader, asked for float samples and read to the end.
//
// Nothing here is linked against Media Foundation: its three libraries are opened at run time (LoadLibraryW), because
// the Windows "N" editions come without the media features, and a program linked against mfplat.dll would not start
// there at all. With the libraries missing, the function says so and the caller reports the file as unreadable.
// The identifiers Media Foundation's headers declare (GUIDs) are defined here by including initguid.h first, so no
// import library is needed either.

#include "deckie_mf.h"

#if defined(_WIN32)

#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <initguid.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

typedef HRESULT (WINAPI *co_initialize_fn)(LPVOID, DWORD);
typedef HRESULT (WINAPI *mf_startup_fn)(ULONG, DWORD);
typedef HRESULT (WINAPI *mf_create_media_type_fn)(IMFMediaType **);
typedef HRESULT (WINAPI *mf_create_reader_fn)(LPCWSTR, IMFAttributes *, IMFSourceReader **);

static INIT_ONCE once = INIT_ONCE_STATIC_INIT;
static co_initialize_fn co_initialize;
static mf_create_media_type_fn mf_create_media_type;
static mf_create_reader_fn mf_create_reader;
static int available;

static BOOL CALLBACK load(PINIT_ONCE o, PVOID p, PVOID *c) {
    (void)o; (void)p; (void)c;
    HMODULE ole = LoadLibraryW(L"ole32.dll");
    HMODULE plat = LoadLibraryW(L"mfplat.dll");
    HMODULE rw = LoadLibraryW(L"mfreadwrite.dll");
    if (!ole || !plat || !rw) return TRUE;
    co_initialize = (co_initialize_fn)(void *)GetProcAddress(ole, "CoInitializeEx");
    mf_startup_fn startup = (mf_startup_fn)(void *)GetProcAddress(plat, "MFStartup");
    mf_create_media_type = (mf_create_media_type_fn)(void *)GetProcAddress(plat, "MFCreateMediaType");
    mf_create_reader = (mf_create_reader_fn)(void *)GetProcAddress(rw, "MFCreateSourceReaderFromURL");
    if (!co_initialize || !startup || !mf_create_media_type || !mf_create_reader) return TRUE;
    co_initialize(NULL, COINIT_MULTITHREADED);
    if (FAILED(startup(MF_VERSION, MFSTARTUP_LITE))) return TRUE;
    available = 1;
    return TRUE;
}

static int fail(char *message, size_t size, const char *what, HRESULT hr) {
    if (message && size) snprintf(message, size, "%s (Windows error 0x%08lX)", what, (unsigned long)hr);
    return 2;
}

int deckie_mf_decode(const uint16_t *path, deckie_mf_audio *out, char *message, size_t message_size) {
    memset(out, 0, sizeof(*out));
    InitOnceExecuteOnce(&once, load, NULL, NULL);
    if (!available) {
        if (message && message_size) snprintf(message, message_size, "Windows' media features are not on this PC");
        return 1;
    }
    // Each thread that uses Media Foundation joins COM; joining twice is harmless.
    co_initialize(NULL, COINIT_MULTITHREADED);

    IMFSourceReader *reader = NULL;
    IMFMediaType *want = NULL, *got = NULL;
    HRESULT hr = mf_create_reader((LPCWSTR)path, NULL, &reader);
    if (FAILED(hr)) return fail(message, message_size, "Windows could not open the file", hr);
    int result = 0;
    float *samples = NULL;
    size_t count = 0, capacity = 0;

    IMFSourceReader_SetStreamSelection(reader, (DWORD)MF_SOURCE_READER_ALL_STREAMS, FALSE);
    hr = IMFSourceReader_SetStreamSelection(reader, (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, TRUE);
    if (FAILED(hr)) { result = fail(message, message_size, "the file has no audio Windows can read", hr); goto done; }
    hr = mf_create_media_type(&want);
    if (FAILED(hr)) { result = fail(message, message_size, "Windows could not set up the decoder", hr); goto done; }
    IMFMediaType_SetGUID(want, &MF_MT_MAJOR_TYPE, &MFMediaType_Audio);
    IMFMediaType_SetGUID(want, &MF_MT_SUBTYPE, &MFAudioFormat_Float);
    hr = IMFSourceReader_SetCurrentMediaType(reader, (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, NULL, want);
    if (FAILED(hr)) { result = fail(message, message_size, "Windows has no decoder for this file", hr); goto done; }
    hr = IMFSourceReader_GetCurrentMediaType(reader, (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, &got);
    if (FAILED(hr)) { result = fail(message, message_size, "Windows could not say what the decoder gives", hr); goto done; }
    UINT32 rate = 0, channels = 0, bits = 0;
    IMFMediaType_GetUINT32(got, &MF_MT_AUDIO_SAMPLES_PER_SECOND, &rate);
    IMFMediaType_GetUINT32(got, &MF_MT_AUDIO_NUM_CHANNELS, &channels);
    IMFMediaType_GetUINT32(got, &MF_MT_AUDIO_BITS_PER_SAMPLE, &bits);
    if (rate == 0 || channels == 0 || bits != 32) {
        result = fail(message, message_size, "the decoder did not give 32-bit float samples", E_FAIL);
        goto done;
    }

    for (;;) {
        DWORD flags = 0;
        LONGLONG stamp = 0;
        IMFSample *sample = NULL;
        hr = IMFSourceReader_ReadSample(reader, (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, 0, NULL, &flags, &stamp, &sample);
        if (FAILED(hr)) { result = fail(message, message_size, "the file could not be decoded to its end", hr); break; }
        if (flags & MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED) {
            if (sample) IMFSample_Release(sample);
            result = fail(message, message_size, "the file changes its format part way", E_FAIL);
            break;
        }
        if (sample) {
            IMFMediaBuffer *buffer = NULL;
            if (SUCCEEDED(IMFSample_ConvertToContiguousBuffer(sample, &buffer))) {
                BYTE *data = NULL;
                DWORD length = 0;
                if (SUCCEEDED(IMFMediaBuffer_Lock(buffer, &data, NULL, &length))) {
                    size_t n = length / sizeof(float);
                    if (count + n > capacity) {
                        size_t bigger = capacity ? capacity * 2 : (size_t)1 << 20;
                        while (bigger < count + n) bigger *= 2;
                        float *grown = (float *)realloc(samples, bigger * sizeof(float));
                        if (!grown) {
                            IMFMediaBuffer_Unlock(buffer);
                            IMFMediaBuffer_Release(buffer);
                            IMFSample_Release(sample);
                            result = fail(message, message_size, "not enough memory for the decoded audio", E_OUTOFMEMORY);
                            break;
                        }
                        samples = grown;
                        capacity = bigger;
                    }
                    memcpy(samples + count, data, n * sizeof(float));
                    count += n;
                    IMFMediaBuffer_Unlock(buffer);
                }
                IMFMediaBuffer_Release(buffer);
            }
            if (out->blocks == 0) out->first_timestamp = (int64_t)stamp;
            out->blocks += 1;
            IMFSample_Release(sample);
        }
        if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
    }
    if (result == 0) {
        out->samples = samples;
        out->frames = (uint64_t)(count / channels);
        out->sample_rate = rate;
        out->channels = channels;
        samples = NULL;
    }

done:
    free(samples);
    if (got) IMFMediaType_Release(got);
    if (want) IMFMediaType_Release(want);
    if (reader) IMFSourceReader_Release(reader);
    return result;
}

void deckie_mf_free(deckie_mf_audio *audio) {
    free(audio->samples);
    audio->samples = NULL;
    audio->frames = 0;
}

#else

#include <stdio.h>
#include <string.h>

int deckie_mf_decode(const uint16_t *path, deckie_mf_audio *out, char *message, size_t message_size) {
    (void)path;
    memset(out, 0, sizeof(*out));
    if (message && message_size) snprintf(message, message_size, "Media Foundation is part of Windows only");
    return 1;
}

void deckie_mf_free(deckie_mf_audio *audio) { (void)audio; }

#endif
