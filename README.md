# drshare

Tiny cross-device sharing between a Mac and Android, with a local-first architecture.

## Current Direction

The chosen prototype is:

- no remote server
- no Raycast dependency for the core product
- tiny native Mac host app
- LAN web UI for quick send/download on any client
- optional native Android app for OS-level share integration

The Mac app is the host.

It runs locally, serves a small web UI, and exposes a small HTTP API for sending and downloading drops over the LAN.

## Current Status

The first implementation slice is in place.

Implemented now:

- Swift package scaffold at repo root
- native Mac menu bar app at `/mac-app`
- local HTTP server bound by the Mac app
- browser UI served from `/`
- pairing token required for API access
- QR code pairing UI in the Mac app
- Bonjour advertisement over `_drshare._tcp`
- text send flow
- file upload and download flow
- configurable retention in the Mac app: `1h`, `24h`, `7d`, `never`
- automatic expiry of drops and uploaded files after 24 hours by default
- recent mixed drop list
- local JSON persistence for recent drops

Not implemented yet:

- Android native client
- share extension

## Why This Direction

This keeps the prototype small while still useful:

- works without operating a backend
- supports browser-based access immediately
- leaves room for native Android features where the web is weak
- avoids overcommitting to full clipboard sync, background mirroring, or multi-device complexity

## Product Shape

`v0` is an explicit send/download tool, not a silent background sync system.

Core actions:

- send text
- upload a file or image
- view the latest drops
- download a received drop
- copy received text

## Platform Roles

### Mac

The Mac side is a small native app, ideally:

- `MenuBarExtra` for the main UI
- local HTTP server for transport and web UI
- Bonjour/mDNS for discovery
- QR code for pairing/opening the web client

Optional later:

- Share extension
- Control Center action
- clipboard watcher

### Web Client

The web client is a lightweight fallback interface, intended to:

- send text
- upload files/images
- list latest drops
- download files
- copy text manually

The web client is not the place to promise:

- reliable background sync
- passive clipboard mirroring
- robust browser-independent binary clipboard handling

### Android

Android has two possible roles:

- browser client over LAN for immediate use
- small native app later for share sheet integration and better file handling

That means Android does not block `v0`.

## Docs

- [Implementation Plan](/Users/macbookpro/Documents/projects/drshare/docs/IMPLEMENTATION_PLAN.md)
- [Agent Handoff Checklist](/Users/macbookpro/Documents/projects/drshare/docs/AGENT_HANDOFF_CHECKLIST.md)

## Proposed Repo Layout

```txt
/mac-app
/web-client
/shared
/docs
```

Possible later:

```txt
/android-app
```

## Run

Build:

```bash
swift build
```

If your active developer directory points to Command Line Tools instead of full Xcode, use:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
```

This repo should be run with the Xcode toolchain, not the standalone Command Line Tools toolchain. Mixing them can leave incompatible build artifacts behind.

Run the Mac host app:

```bash
./scripts/run-mac.sh
```

The app starts hosting automatically and prints a URL like:

```txt
http://127.0.0.1:3847/?token=ABCD-1234-EFGH
```

Open that URL from another device on the same LAN, or swap `127.0.0.1` for the LAN IP shown by the app/session endpoint.

The wrapper script:

- forces the Xcode Swift toolchain
- uses a toolchain-specific scratch directory under `.build/`
- defaults storage to `.drshare-state/`

If you need a custom storage location:

```bash
DRSHARE_STORAGE_ROOT=$PWD/.drshare-state ./scripts/run-mac.sh
```

For retention testing, you can override the default 24-hour expiry:

```bash
DRSHARE_RETENTION_HOURS=0.5 ./scripts/run-mac.sh
```

## Current API

Public without token:

- `GET /`
- `GET /health`

Requires the pairing token in `X-DrShare-Token` or `?token=`:

- `GET /api/session`
- `GET /api/drops`
- `POST /api/drops/text`
- `POST /api/drops/file`
- `GET /api/drops/:id/download`

`POST /api/drops/file` currently accepts:

- raw request body as the file bytes
- `X-DrShare-Filename` header for the original filename
- `Content-Type` header for the MIME type
- a positive `Content-Length` header

Limits and caveats:

- uploads stream directly to disk instead of being buffered entirely in memory
- max upload size is `5 GB`
- `Transfer-Encoding: chunked` is not supported yet

Behavior:

- drops auto-expire after `24h` by default
- retention can be changed in the Mac app to `1h`, `24h`, `7d`, or `never`
- expired file drops are removed from disk and stop downloading

Example:

```bash
curl http://127.0.0.1:3847/health
curl -H "X-DrShare-Token: ABCD-1234-EFGH" http://127.0.0.1:3847/api/session
curl -X POST \
  -H "X-DrShare-Token: ABCD-1234-EFGH" \
  -H "Content-Type: application/json" \
  -d '{"text":"hello from another device"}' \
  http://127.0.0.1:3847/api/drops/text
curl -X POST \
  -H "X-DrShare-Token: ABCD-1234-EFGH" \
  -H "X-DrShare-Filename: note.txt" \
  -H "Content-Type: text/plain" \
  --data-binary @note.txt \
  http://127.0.0.1:3847/api/drops/file
```

## Next Milestone

Add the next layer on top of the working host, pairing, and file flow:

1. Android-native share target using the existing LAN API
2. better host feedback in the menu bar app
3. optional QR scanning or manual host entry on Android
4. share extension on macOS if Finder/app send-in becomes important
