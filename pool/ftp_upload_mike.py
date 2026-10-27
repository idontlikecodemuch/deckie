#!/usr/bin/env python3
"""Resume-safe, parallel FTPS uploader for the "Mike page" folder.

Usage (you will be asked for the FTP password at the prompt; it is never stored):

  python3 ftp_upload_mike.py --server ftp.example.com --user someone@example.com \
      --local-dir "/path/to/Mike page" --remote-dir mike-halloween

Behaviour, borrowed from the gagged project's vote-packet uploader and its Bluehost lessons:
* TLS on the control channel (explicit FTPS, port 21) so the login is encrypted; the data channel is
  left plain because Bluehost truncates TLS data connections.
* Resume-safe: a file already present on the server at the same byte size is skipped, except
  index.html, which is always resent so page edits land even when the size does not change.
* Parallel workers with their own connections; on any error a worker reconnects and retries the
  same file with backoff; every upload is verified with SIZE afterwards.
* Prints "ALL DONE" as the last line only when every file is confirmed at full size; otherwise
  "NOT COMPLETE -- rerun to resume". Bluehost may block an IP for a while after a burst (403s):
  wait a few minutes and rerun.
"""
from __future__ import annotations

import argparse
import ftplib
import getpass
import queue
import ssl
import threading
import time
from pathlib import Path

BLOCKSIZE = 1 << 20
_print_lock = threading.Lock()


def log(msg: str) -> None:
    with _print_lock:
        print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def connect(cfg: dict) -> ftplib.FTP:
    ctx = ssl.create_default_context()
    ctx.check_hostname = False          # Bluehost presents a *.bluehost.com certificate
    ctx.verify_mode = ssl.CERT_NONE
    ftp = ftplib.FTP_TLS(cfg["server"], timeout=120, context=ctx)
    ftp.login(cfg["user"], cfg["password"])
    ftp.prot_c()                        # plain data channel (see the module docstring)
    ftp.set_pasv(True)
    ftp.voidcmd("TYPE I")
    return ftp


def connect_retry(cfg: dict, who: str) -> ftplib.FTP:
    delay = 3
    while True:
        try:
            return connect(cfg)
        except ftplib.error_perm as exc:
            if "530" in str(exc):
                raise SystemExit(f"{who}: login refused ({exc}); check the username and password")
            log(f"{who}: connect failed ({exc!r}); retry in {delay}s")
        except Exception as exc:
            log(f"{who}: connect failed ({exc!r}); retry in {delay}s")
        time.sleep(delay)
        delay = min(30, delay * 2)


def ensure_dirs(cfg: dict, dirs: list[str]) -> None:
    ftp = connect(cfg)
    for d in dirs:
        ftp.cwd("/")
        for part in [p for p in d.strip("/").split("/") if p]:
            try:
                ftp.mkd(part)
            except ftplib.error_perm as exc:
                if not str(exc).startswith("550"):
                    raise
            ftp.cwd(part)
    ftp.quit()


def remote_size(ftp: ftplib.FTP, remote_path: str) -> int | None:
    try:
        return ftp.size(remote_path)
    except Exception:
        return None


class Counters:
    def __init__(self, total: int):
        self.total, self.uploaded, self.skipped, self.failed = total, 0, 0, 0
        self.fails: list[str] = []
        self.lock = threading.Lock()

    def done(self) -> int:
        return self.uploaded + self.skipped + self.failed


def worker(wid: int, cfg: dict, q: "queue.Queue", c: Counters, args) -> None:
    ftp = connect_retry(cfg, f"w{wid}")
    since_reconnect = 0
    while True:
        try:
            path, remote_path, size = q.get_nowait()
        except queue.Empty:
            break
        attempt = 0
        while True:
            attempt += 1
            try:
                rs = remote_size(ftp, "/" + remote_path)
                if rs == size and path.name != "index.html":
                    with c.lock:
                        c.skipped += 1
                    break
                if args.verify_only:
                    with c.lock:
                        c.failed += 1
                        c.fails.append(f"{remote_path} (remote={rs} local={size})")
                    break
                with path.open("rb") as fh:
                    ftp.storbinary(f"STOR /{remote_path}", fh, blocksize=BLOCKSIZE)
                rs2 = remote_size(ftp, "/" + remote_path)
                if rs2 != size:
                    raise OSError(f"size after upload {rs2} != {size}")
                with c.lock:
                    c.uploaded += 1
                    u = c.uploaded
                log(f"w{wid} up {u} skip={c.skipped} fail={c.failed} done={c.done()}/{c.total} {remote_path}")
                since_reconnect += 1
                break
            except (ftplib.Error, OSError, EOFError) as exc:
                log(f"w{wid} ERR {remote_path} attempt {attempt}/{args.max_attempts}: {exc!r}")
                try:
                    ftp.close()
                except Exception:
                    pass
                time.sleep(min(30, 2 ** attempt))
                ftp = connect_retry(cfg, f"w{wid}")
                since_reconnect = 0
                if attempt >= args.max_attempts:
                    with c.lock:
                        c.failed += 1
                        c.fails.append(f"{remote_path} ({exc!r})")
                    log(f"w{wid} GIVEUP {remote_path}")
                    break
        q.task_done()
        if args.sleep:
            time.sleep(args.sleep)
        if since_reconnect >= args.reconnect_every:
            try:
                ftp.close()
            except Exception:
                pass
            ftp = connect_retry(cfg, f"w{wid}")
            since_reconnect = 0
    try:
        ftp.quit()
    except Exception:
        pass


def move_remote(cfg: dict, src: str, dst: str) -> int:
    """Server-side move (FTP RNFR/RNTO) of a file or whole folder; paths are relative to the account root."""
    ftp = connect(cfg)
    src = "/" + src.strip("/"); dst = "/" + dst.strip("/")
    root = sorted(ftp.nlst("/"))
    log(f"account root holds: {root[:15]}")
    name = src.rsplit("/", 1)[1]
    def exists(p: str) -> bool:
        try:
            ftp.cwd(p); ftp.cwd("/"); return True
        except ftplib.error_perm:
            return False
    if not exists(src):
        # breadth-first search for a folder with that name, up to 5 levels down, skipping hidden entries
        # and anything that looks like site code (wp-*, cgi-bin) to keep it quick
        found = None; queue_ = ["/"]; seen = 0
        while queue_ and not found and seen < 400:
            d = queue_.pop(0); seen += 1
            try:
                entries = [e.rsplit("/", 1)[-1] for e in ftp.nlst(d)]
            except ftplib.error_perm:
                continue
            for e in entries:
                if e in (".", "..") or e.startswith(".") or e.startswith("wp-") or e == "cgi-bin":
                    continue
                p = (d.rstrip("/") + "/" + e)
                if e == name and exists(p):
                    found = p; break
                if p.count("/") <= 5 and exists(p):
                    queue_.append(p)
        if not found:
            log(f"could not find a folder named {name!r} anywhere within 5 levels of the root ({seen} folders checked)")
            ftp.quit()
            return 1
        log(f"source not at {src}; found it at {found}")
        src = found
    try:
        markers = [e.rsplit("/", 1)[-1] for e in ftp.nlst("/public_html")]
        log("/public_html " + ("looks like the WordPress site root" if any(m in ("wp-config.php", "wp-content") for m in markers) else f"is NOT the WordPress root; it holds {sorted(markers)[:10]}"))
    except ftplib.error_perm:
        log("/public_html is not listable from this account")
    parent = dst.rsplit("/", 1)[0]
    if parent and parent != "/":
        ftp.cwd("/")
        for part in [p for p in parent.strip("/").split("/") if p]:
            try:
                ftp.mkd(part)
            except ftplib.error_perm as exc:
                if not str(exc).startswith("550"):
                    raise
            ftp.cwd(part)
        ftp.cwd("/")
    try:
        ftp.rename(src, dst)
    except ftplib.error_perm as exc:
        log(f"move failed: {exc}")
        ftp.quit()
        return 1
    ftp.cwd(dst)
    names = ftp.nlst()
    log(f"moved {src} -> {dst}; it now holds {len(names)} entries: {sorted(names)[:8]}")
    ftp.quit()
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Upload a folder over explicit FTPS, resume-safe; or move a folder on the server.")
    ap.add_argument("--server", help="FTP host (or in the --env file as server/host)")
    ap.add_argument("--user", help="FTP account (or in the --env file as user)")
    ap.add_argument("--env", help="file with lines like user: ..., pass: ..., server: ... (colon or = separated); the password is read by this script only")
    ap.add_argument("--move", nargs=2, metavar=("SRC", "DST"), help="server-side move of a folder, e.g. home1/jnwqqkmy/public_html/mike-halloween public_html/mike-halloween; nothing is uploaded")
    ap.add_argument("--local-dir", help="folder to upload")
    ap.add_argument("--remote-dir", help="folder under the FTP account's root, e.g. mike-halloween")
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--sleep", type=float, default=0.3, help="pause per file per worker, to stay under Bluehost's burst limit")
    ap.add_argument("--reconnect-every", type=int, default=200)
    ap.add_argument("--max-attempts", type=int, default=6)
    ap.add_argument("--verify-only", action="store_true", help="only report files missing or short on the server")
    args = ap.parse_args()

    env = {}
    if args.env:
        for line in open(args.env, encoding="utf-8"):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            k, _, v = line.partition("=") if "=" in line.split(":")[0] else line.partition(":")
            k, v = k.strip().lower(), v.strip().strip('"').strip("'")
            if k in ("user", "username", "ftp_user"): env["user"] = v
            elif k in ("pass", "password", "ftp_password", "ftp_pass"): env["password"] = v
            elif k in ("server", "host", "ftp_host", "ftp_server"): env["server"] = v
    args.user = args.user or env.get("user")
    args.server = args.server or env.get("server") or "ftp.jnw.qqk.mybluehost.me"
    if not args.user:
        raise SystemExit("no FTP user: pass --user or put user: ... in the --env file")
    def password() -> str:
        return env.get("password") or getpass.getpass("FTP password (not echoed, not stored): ")

    if args.move:
        cfg = {"server": args.server, "user": args.user, "password": password()}
        return move_remote(cfg, args.move[0], args.move[1])
    if not args.local_dir or not args.remote_dir:
        raise SystemExit("--local-dir and --remote-dir are required for an upload (or use --move SRC DST)")

    local_dir = Path(args.local_dir).resolve()
    if not local_dir.is_dir():
        raise SystemExit(f"local dir not found: {local_dir}")
    files = [p for p in sorted(local_dir.rglob("*")) if p.is_file() and p.name != ".DS_Store"]
    total_bytes = sum(p.stat().st_size for p in files)
    cfg = {"server": args.server, "user": args.user, "password": password()}
    remote_base = args.remote_dir.strip("/")
    if remote_base == "auto":
        # decide from what the account's root holds: the page folder itself, or something above it
        ftp = connect(cfg)
        names = {e.rsplit("/", 1)[-1] for e in ftp.nlst()}
        ftp.quit()
        if "index.html" in names and "tracks" in names:
            remote_base = ""
        elif "mike-halloween" in names:
            remote_base = "mike-halloween"
        elif "public_html" in names:
            remote_base = "public_html/mike-halloween"
        else:
            raise SystemExit(f"cannot tell where the page folder is from the root listing: {sorted(names)[:12]}")
        log(f"account root holds {sorted(names)[:8]} -> uploading into /{remote_base or '(root)'}")
    rp = lambda rel: f"{remote_base}/{rel}" if remote_base else rel
    log(f"{len(files)} files, {total_bytes / 1e6:.1f} MB -> /{remote_base} on {args.server} as {args.user}")

    parents = sorted({rp(p.relative_to(local_dir).as_posix()).rsplit("/", 1)[0] for p in files if "/" in rp(p.relative_to(local_dir).as_posix())})
    if not args.verify_only:
        ensure_dirs(cfg, parents)
        log(f"remote folders ready ({len(parents)})")

    q: "queue.Queue" = queue.Queue()
    for p in files:
        q.put((p, rp(p.relative_to(local_dir).as_posix()), p.stat().st_size))
    c = Counters(len(files))
    threads = [threading.Thread(target=worker, args=(i + 1, cfg, q, c, args), daemon=True) for i in range(max(1, args.workers))]
    t0 = time.time()
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    log(f"SUMMARY: uploaded={c.uploaded} skipped={c.skipped} failed={c.failed} of {len(files)} in {time.time() - t0:.0f}s")
    if c.fails:
        log("FAILURES: " + "; ".join(c.fails[:20]))
    if c.failed == 0 and c.uploaded + c.skipped == len(files):
        log(f"ALL DONE: {c.uploaded} uploaded, {c.skipped} skipped, {len(files)} total")
        return 0
    log("NOT COMPLETE -- rerun to resume")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
