// The three system calls that read a music CD (research AA, section 2.2), each compiled only on its own system, behind
// one small C interface that Swift calls (DeckieDisc's DriveDevice). Nothing is linked from outside the system.
//
// - Linux: the drive's own commands through the kernel's general pass-through, SG_IO, on /dev/srN opened read-only:
//   READ TOC/PMA/ATIP (0x43) in format 0 (the table of contents) and format 5 (CD-Text), and READ CD (0xBE) for the
//   sound. These are commands the kernel lets a read-only opener send.
// - Windows: the CD-ROM class driver's own requests through DeviceIoControl on \\.\E: opened for reading:
//   IOCTL_CDROM_READ_TOC (the table, returned as minutes, seconds and frames, turned here into the drive's sector
//   form), IOCTL_CDROM_READ_TOC_EX with the CD-Text format, and IOCTL_CDROM_RAW_READ in the CD-DA mode for the sound.
//   The request numbers and structures are written out here from Microsoft's documentation (ntddcdrm.h), so no driver
//   header is needed.
// - macOS: DKIOCCDREADTOC on the disc's raw device (/dev/rdiskN) in format 2 (the full table) and format 5 (CD-Text).
//   The Mac reads the sound itself: a music CD shows as AIFF files, which Desk copies (DeckieDisc's MacVolumeReader),
//   so there is no sound call here. Whether a Mac app may open that raw device without extra permission is not known
//   (letter AA, 2.2); when it may not, the call fails and Desk says it could not ask the drive.
//
// Every function returns 0 on success, or the system's error number (errno, or GetLastError on Windows).
#ifndef CDISCDRIVE_H
#define CDISCDRIVE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef intptr_t cdd_handle;

/// Which calls this system has: bit 0 the table, bit 1 CD-Text, bit 2 the sound read by sector.
int cdd_abilities(void);

/// Opens the drive at `path` (UTF-8: "/dev/sr0", "\\\\.\\E:", "/dev/rdisk4") for reading.
int cdd_open(const char *path, cdd_handle *out);
void cdd_close(cdd_handle h);

/// The table of contents: format 0 with sector addresses on Linux and Windows, format 2 (the full table) on the Mac.
/// Up to `capacity` bytes into `buffer`; `*length` is how many came. `*format` says which format it is (0 or 2).
int cdd_read_toc(cdd_handle h, unsigned char *buffer, int capacity, int *length, int *format);

/// CD-Text: the drive's answer to "read table of contents" in format 5, header and packs, as it gave them.
int cdd_read_cdtext(cdd_handle h, unsigned char *buffer, int capacity, int *length);

/// `count` sectors of CD audio (2352 bytes each, 44.1 kHz, two 16-bit little-endian channels) from sector `lba` into
/// `buffer` (at least count * 2352 bytes). Not on the Mac (ENOTSUP).
int cdd_read_audio(cdd_handle h, int lba, int count, unsigned char *buffer);

/// On the Mac: whether the volume mounted at `volume` is a music CD (the system's cddafs), and if so its raw device
/// ("/dev/rdisk4") into `device`. 0 when it is; elsewhere always ENOTSUP.
int cdd_music_cd_device(const char *volume, char *device, int capacity);

#ifdef __cplusplus
}
#endif

#endif
