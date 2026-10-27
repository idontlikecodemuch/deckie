---
name: project-mike-page-hosting
description: "Where Mike's Halloween disc page is hosted, how it got there, and the host's quirks (Bluehost FTPS, Cloudflare blocks curl)"
metadata:
  node_type: memory
  type: project
  originSessionId: 7b79f783-1f73-4ec8-a7b1-409505270949
  modified: 2026-10-21T20:53:58.830Z
---

Mike's phone page for the two Halloween MP3 CDs is live at https://christophershannon.io/mike-halloween/ (uploaded Oct 21, 2026). The site is on Bluehost (box jnw.qqk.mybluehost.me) behind Cloudflare, which answers curl with a "Just a moment" challenge: verify pages in a real browser, never by curl. Uploads go over explicit FTPS with `_pool build/ftp_upload_mike.py` in the playlist folder, run by Chris in his terminal because it prompts for the password; Claude must not type or store FTP passwords. The FTP account Chris made for this had its directory doubled (`/home1/jnwqqkmy/home1/jnwqqkmy/public_html`), so the first upload had to be moved into the real `public_html`; the credential was meant to be rotated afterwards.

**Why:** the first live check failed at every guessed URL and cost a round of debugging; the cause was the FTP account's directory, not the upload.

**How to apply:** for any future upload to christophershannon.io, confirm the FTP account's directory is `public_html` before sending 1.5 GB, verify in the browser pane, and expect MP3 range requests (206) to work through Cloudflare. Related: [[project-two-disc-pool-build]].
