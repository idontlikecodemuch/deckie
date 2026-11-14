// See cdiscdrive.h. One section per system; each compiles only on its own.
#include "cdiscdrive.h"

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#ifndef ENOTSUP
#define ENOTSUP 129
#endif

static int be16(const unsigned char *p) { return (p[0] << 8) | p[1]; }

#if defined(__linux__)
// ---------------------------------------------------------------- Linux: SG_IO on /dev/srN
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <scsi/sg.h>

int cdd_abilities(void) { return 1 | 2 | 4; }

int cdd_open(const char *path, cdd_handle *out) {
  int fd = open(path, O_RDONLY | O_NONBLOCK);
  if (fd < 0) return errno;
  *out = (cdd_handle)fd;
  return 0;
}

void cdd_close(cdd_handle h) { close((int)h); }

// One command to the drive, reading `length` bytes back. `*got` is how many came.
static int command(cdd_handle h, unsigned char *cdb, int cdb_length, unsigned char *buffer, int length, int *got) {
  sg_io_hdr_t io;
  unsigned char sense[32];
  memset(&io, 0, sizeof io);
  memset(sense, 0, sizeof sense);
  io.interface_id = 'S';
  io.dxfer_direction = SG_DXFER_FROM_DEV;
  io.cmd_len = (unsigned char)cdb_length;
  io.cmdp = cdb;
  io.dxferp = buffer;
  io.dxfer_len = (unsigned int)length;
  io.sbp = sense;
  io.mx_sb_len = sizeof sense;
  io.timeout = 30000; // milliseconds: a drive spinning up takes a few seconds
  if (ioctl((int)h, SG_IO, &io) < 0) return errno;
  if ((io.info & SG_INFO_OK_MASK) != SG_INFO_OK) return EIO;
  if (got) *got = length - io.resid;
  return 0;
}

// READ TOC/PMA/ATIP in `format`, addresses as sectors: the header first, to learn the length, then the whole answer.
static int read_toc_format(cdd_handle h, int format, unsigned char *buffer, int capacity, int *length) {
  if (capacity < 4) return EINVAL;
  unsigned char cdb[10] = {0x43, 0x00, (unsigned char)(format & 0x0F), 0, 0, 0, 0, 0, 4, 0};
  if (format == 0) cdb[6] = 1; // from track 1
  int got = 0;
  int r = command(h, cdb, 10, buffer, 4, &got);
  if (r) return r;
  int want = be16(buffer) + 2;
  if (want > capacity) want = capacity;
  if (want < 4) { *length = got; return 0; }
  cdb[7] = (unsigned char)(want >> 8);
  cdb[8] = (unsigned char)(want & 0xFF);
  r = command(h, cdb, 10, buffer, want, &got);
  if (r) return r;
  *length = got;
  return 0;
}

int cdd_read_toc(cdd_handle h, unsigned char *buffer, int capacity, int *length, int *format) {
  *format = 0;
  return read_toc_format(h, 0, buffer, capacity, length);
}

int cdd_read_cdtext(cdd_handle h, unsigned char *buffer, int capacity, int *length) {
  return read_toc_format(h, 5, buffer, capacity, length);
}

int cdd_read_audio(cdd_handle h, int lba, int count, unsigned char *buffer) {
  // READ CD: expected sector type CD-DA (001b in bits 4 to 2 of byte 1), the user data only (byte 9 = 0x10).
  unsigned char cdb[12] = {0xBE, 0x04,
                           (unsigned char)(lba >> 24), (unsigned char)(lba >> 16), (unsigned char)(lba >> 8), (unsigned char)lba,
                           (unsigned char)(count >> 16), (unsigned char)(count >> 8), (unsigned char)count,
                           0x10, 0, 0};
  int got = 0;
  int r = command(h, cdb, 12, buffer, count * 2352, &got);
  if (r) return r;
  return got == count * 2352 ? 0 : EIO;
}

int cdd_music_cd_device(const char *volume, char *device, int capacity) {
  (void)volume; (void)device; (void)capacity;
  return ENOTSUP;
}

#elif defined(_WIN32)
// ---------------------------------------------------------------- Windows: the CD-ROM class driver's requests
#include <windows.h>

// CTL_CODE(IOCTL_CDROM_BASE = FILE_DEVICE_CD_ROM = 2, function, method, FILE_READ_ACCESS = 1), from ntddcdrm.h.
#define DECKIE_IOCTL_CDROM_READ_TOC    0x00024000 // function 0x0000, METHOD_BUFFERED
#define DECKIE_IOCTL_CDROM_RAW_READ    0x0002403E // function 0x000F, METHOD_OUT_DIRECT
#define DECKIE_IOCTL_CDROM_READ_TOC_EX 0x00024054 // function 0x0015, METHOD_BUFFERED

int cdd_abilities(void) { return 1 | 2 | 4; }

static int widen(const char *s, wchar_t *out, int capacity) {
  return MultiByteToWideChar(CP_UTF8, 0, s, -1, out, capacity);
}

int cdd_open(const char *path, cdd_handle *out) {
  wchar_t wide[MAX_PATH];
  if (!widen(path, wide, MAX_PATH)) return (int)GetLastError();
  HANDLE h = CreateFileW(wide, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
  if (h == INVALID_HANDLE_VALUE) return (int)GetLastError();
  *out = (cdd_handle)h;
  return 0;
}

void cdd_close(cdd_handle h) { CloseHandle((HANDLE)h); }

// IOCTL_CDROM_READ_TOC returns CDROM_TOC: Length[2], FirstTrack, LastTrack, then TRACK_DATA[100] of eight bytes
// (Reserved; Control in the low four bits and Adr in the high four, the drive's own byte; TrackNumber; Reserved1;
// Address[4] as 0, minutes, seconds, frames). Written back here in the drive's format 0 with sector addresses, so
// Swift reads one format on Linux and Windows.
int cdd_read_toc(cdd_handle h, unsigned char *buffer, int capacity, int *length, int *format) {
  unsigned char toc[4 + 100 * 8];
  DWORD got = 0;
  memset(toc, 0, sizeof toc);
  if (!DeviceIoControl((HANDLE)h, DECKIE_IOCTL_CDROM_READ_TOC, NULL, 0, toc, sizeof toc, &got, NULL)) return (int)GetLastError();
  int declared = be16(toc) + 2;
  if (declared > (int)got) declared = (int)got;
  if (declared > capacity) declared = capacity - (capacity - 4) % 8;
  if (declared < 4) return EIO;
  memcpy(buffer, toc, 4);
  for (int i = 4; i + 8 <= declared; i += 8) {
    const unsigned char *t = toc + i;
    unsigned char *o = buffer + i;
    long lba = ((long)t[5] * 60 + t[6]) * 75 + t[7] - 150;
    o[0] = 0; o[1] = t[1]; o[2] = t[2]; o[3] = 0;
    o[4] = (unsigned char)((unsigned long)lba >> 24); o[5] = (unsigned char)((unsigned long)lba >> 16);
    o[6] = (unsigned char)((unsigned long)lba >> 8); o[7] = (unsigned char)lba;
  }
  *length = declared;
  *format = 0;
  return 0;
}

// CDROM_READ_TOC_EX: one byte of Format (low four bits; CDROM_READ_TOC_EX_FORMAT_CDTEXT is 5), Reserved1 and Msf (bit
// 7), then SessionTrack and two reserved bytes. The answer is CDROM_TOC_CD_TEXT_DATA: the drive's header and packs.
int cdd_read_cdtext(cdd_handle h, unsigned char *buffer, int capacity, int *length) {
  unsigned char request[4] = {0x05, 0, 0, 0};
  DWORD got = 0;
  if (!DeviceIoControl((HANDLE)h, DECKIE_IOCTL_CDROM_READ_TOC_EX, request, sizeof request, buffer, (DWORD)capacity, &got, NULL)) {
    return (int)GetLastError();
  }
  *length = (int)got;
  return 0;
}

// RAW_READ_INFO: DiskOffset (a LARGE_INTEGER, the sector times 2048, as the driver counts), SectorCount (a ULONG) and
// TrackMode (an int; CDDA is 2): sixteen bytes.
int cdd_read_audio(cdd_handle h, int lba, int count, unsigned char *buffer) {
  unsigned char info[16];
  long long offset = (long long)lba * 2048;
  unsigned long sectors = (unsigned long)count;
  int mode = 2;
  memcpy(info, &offset, 8);
  memcpy(info + 8, &sectors, 4);
  memcpy(info + 12, &mode, 4);
  DWORD got = 0;
  if (!DeviceIoControl((HANDLE)h, DECKIE_IOCTL_CDROM_RAW_READ, info, sizeof info, buffer, (DWORD)(count * 2352), &got, NULL)) {
    return (int)GetLastError();
  }
  return got == (DWORD)(count * 2352) ? 0 : EIO;
}

int cdd_music_cd_device(const char *volume, char *device, int capacity) {
  (void)volume; (void)device; (void)capacity;
  return ENOTSUP;
}

#elif defined(__APPLE__)
// ---------------------------------------------------------------- macOS: DKIOCCDREADTOC on the raw device
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/param.h>
#include <sys/mount.h>
#include <IOKit/storage/IOCDMediaBSDClient.h>

int cdd_abilities(void) { return 1 | 2; }

int cdd_open(const char *path, cdd_handle *out) {
  int fd = open(path, O_RDONLY | O_NONBLOCK);
  if (fd < 0) return errno;
  *out = (cdd_handle)fd;
  return 0;
}

void cdd_close(cdd_handle h) { close((int)h); }

static int read_toc_format(cdd_handle h, int format, unsigned char *buffer, int capacity, int *length) {
  dk_cd_read_toc_t r;
  memset(&r, 0, sizeof r);
  memset(buffer, 0, (size_t)capacity);
  r.format = (CDTOCFormat)format;
  r.formatAsTime = format == 2 ? 1 : 0;
  r.address.session = format == 2 ? 1 : 0;
  r.bufferLength = (uint16_t)(capacity > 0xFFFF ? 0xFFFF : capacity);
  r.buffer = buffer;
  if (ioctl((int)h, DKIOCCDREADTOC, &r) < 0) return errno;
  int declared = be16(buffer) + 2;
  *length = declared < r.bufferLength ? declared : r.bufferLength;
  return 0;
}

int cdd_read_toc(cdd_handle h, unsigned char *buffer, int capacity, int *length, int *format) {
  *format = 2;
  return read_toc_format(h, 2, buffer, capacity, length);
}

int cdd_read_cdtext(cdd_handle h, unsigned char *buffer, int capacity, int *length) {
  return read_toc_format(h, 5, buffer, capacity, length);
}

int cdd_read_audio(cdd_handle h, int lba, int count, unsigned char *buffer) {
  (void)h; (void)lba; (void)count; (void)buffer;
  return ENOTSUP;
}

int cdd_music_cd_device(const char *volume, char *device, int capacity) {
  struct statfs s;
  if (statfs(volume, &s) != 0) return errno;
  if (strcmp(s.f_fstypename, "cddafs") != 0) return ENOENT;
  const char *from = s.f_mntfromname; // "/dev/disk4"
  if (strncmp(from, "/dev/", 5) != 0) return ENOENT;
  int n = snprintf(device, (size_t)capacity, "/dev/r%s", from + 5);
  return n > 0 && n < capacity ? 0 : ENAMETOOLONG;
}

#else
int cdd_abilities(void) { return 0; }
int cdd_open(const char *path, cdd_handle *out) { (void)path; (void)out; return ENOTSUP; }
void cdd_close(cdd_handle h) { (void)h; }
int cdd_read_toc(cdd_handle h, unsigned char *b, int c, int *l, int *f) { (void)h; (void)b; (void)c; (void)l; (void)f; return ENOTSUP; }
int cdd_read_cdtext(cdd_handle h, unsigned char *b, int c, int *l) { (void)h; (void)b; (void)c; (void)l; return ENOTSUP; }
int cdd_read_audio(cdd_handle h, int a, int c, unsigned char *b) { (void)h; (void)a; (void)c; (void)b; return ENOTSUP; }
int cdd_music_cd_device(const char *v, char *d, int c) { (void)v; (void)d; (void)c; return ENOTSUP; }
#endif
