# Implementation Plan

## Objective

Build a very small local-first sharing tool with these properties:

- no remote server
- one Mac host app
- one tiny LAN web UI/API
- Android can participate through the browser first
- native Android support is optional and comes later

The system should make it easy to move small pieces of data between devices:

- text
- images
- files

## Product Principles

- local-first over cloud-first
- explicit send/download over hidden sync
- one-host model over peer mesh
- shipping a usable slice over platform-complete ambition

## Final `v0` Scope

### In Scope

- Mac app runs as the local host
- Mac app exposes a local HTTP API on the LAN
- Mac app exposes a small browser UI
- one pairing model using a short token
- text send and receive
- file upload and download
- image upload and download as files
- latest-drop list or short recent history
- copy text on Mac
- open downloaded files on Mac

### Out of Scope

- remote relay
- internet-wide access
- real-time clipboard mirroring
- multiple simultaneous host Macs
- background web sync
- end-to-end encryption across untrusted infrastructure
- arbitrary peer-to-peer mesh transport
- push notifications
- account system

## Chosen Architecture

## Components

### 1. Mac Host App

Responsibilities:

- starts on demand or at login
- advertises itself on the LAN
- shows host status in menu bar
- exposes HTTP endpoints
- stores local drop metadata and files
- generates pairing QR code and token
- provides basic controls:
  - host on/off
  - copy latest text
  - open downloads folder
  - show local URL

Preferred implementation:

- Swift
- SwiftUI
- `MenuBarExtra`
- lightweight HTTP server
- Bonjour/mDNS service advertisement

### 2. Local Web Client

Responsibilities:

- connect to host by URL plus token
- send text
- upload files
- show recent drops
- download files
- display host connection state

Preferred implementation:

- static web app served by the Mac host
- minimal JavaScript framework or plain TypeScript if simpler

### 3. Local Storage

Responsibilities:

- store recent drop metadata
- persist uploaded files
- cap storage usage

Suggested shape:

- SQLite for metadata
- file system folder for file blobs

### 4. Optional Android App Later

Responsibilities:

- act as Android share target
- send shared content to local Mac host
- show latest received items
- improve file opening and save behavior

Do not block `v0` on this.

## Transport Model

The Mac app is the only host.

Clients connect to the Mac app over the local network using:

- Bonjour for discovery when possible
- QR code containing URL and token for simple onboarding
- manual URL entry fallback

Suggested example:

```txt
http://192.168.1.20:3847/?token=ABCD-1234
```

## API Shape

Keep the API narrow and explicit.

### Endpoints

```txt
GET  /health
GET  /api/session
GET  /api/drops
GET  /api/drops/:id
POST /api/drops/text
POST /api/drops/file
GET  /api/drops/:id/download
POST /api/clipboard/copy/:id
```

### Notes

- `/health` is for diagnostics and onboarding confidence
- `/api/session` returns host info, token validity, limits, and feature flags
- `/api/drops` returns a short recent list
- `/api/drops/text` accepts plain text payloads
- `/api/drops/file` accepts multipart uploads
- `/api/clipboard/copy/:id` is only meaningful on the Mac host side

### Suggested Data Model

```json
{
  "id": "uuid",
  "kind": "text",
  "sender": "web",
  "mime": "text/plain",
  "filename": null,
  "size": 12,
  "text": "hello world",
  "file_path": null,
  "created_at": "2026-04-02T16:00:00Z"
}
```

For file-like drops:

```json
{
  "id": "uuid",
  "kind": "file",
  "sender": "web",
  "mime": "image/png",
  "filename": "photo.png",
  "size": 483920,
  "text": null,
  "file_path": "/local/storage/photo.png",
  "created_at": "2026-04-02T16:00:00Z"
}
```

## Security Model

This is a trusted-LAN prototype, not a zero-trust system.

`v0` security should still have basics:

- random pairing token
- token required for write operations
- token required for reading drop metadata
- reject uploads over size limit
- sanitize filenames
- do not expose arbitrary file system paths
- serve downloads only from managed storage
- allow token reset from Mac app

Nice-to-have later:

- local HTTPS
- one-time pairing links
- signed sessions
- separate read/write tokens

## UX Model

## Primary Flow

1. Open the Mac app.
2. Turn hosting on.
3. See a QR code and local URL.
4. Open the URL from Android or any browser client.
5. Send text or upload a file.
6. See the drop appear on the Mac.
7. Copy or open it.

## Secondary Flow

1. Browser client opens recent drops.
2. User downloads a file or copies text.

## UX Constraints

- no account creation
- no hidden background work promise
- no complicated pairing ceremony
- no modal-heavy desktop UI

## Milestones

## Milestone 0: Skeleton

Goal:

- repo structure exists
- Mac app launches
- local server responds
- web UI is served

Deliverables:

- `/mac-app`
- `/web-client`
- `/shared`
- basic README/dev instructions

Acceptance:

- opening the Mac app shows a menu bar item
- local `GET /health` returns success
- web page loads from the Mac host

## Milestone 1: Text End-to-End

Goal:

- send text from web client to Mac host
- show recent text drops
- copy text on Mac

Deliverables:

- text POST endpoint
- local persistence
- recent list UI
- copy action

Acceptance:

- a browser on Android or another device can submit text
- the Mac app shows the new item without restart
- text can be copied from the Mac app

## Milestone 2: File End-to-End

Goal:

- upload files/images from web client
- list and download them
- open them on Mac

Deliverables:

- multipart upload endpoint
- file storage
- recent file list
- download/open actions

Acceptance:

- upload of a small image works
- upload of a generic file works
- download from browser works
- open on Mac works

## Milestone 3: Pairing and Discovery

Goal:

- remove manual setup friction

Deliverables:

- Bonjour advertisement
- visible local URL
- QR code rendering
- token generation/reset

Acceptance:

- user can connect by scanning QR code
- user can reset token and invalidate old links

## Milestone 4: Polish

Goal:

- make the prototype stable enough to demo

Deliverables:

- storage cap
- error states
- upload progress
- empty states
- copy/open success feedback

Acceptance:

- bad uploads fail cleanly
- stale items do not break the UI
- app survives restart and retains recent items

## Milestone 5: Native Android Follow-Up

Goal:

- improve Android OS integration without changing the protocol

Deliverables:

- share target
- native recent drops UI
- file open/save improvements

Acceptance:

- share text/image/file from Android to Mac host from the Android share sheet

## Suggested Repo Structure

```txt
/mac-app
  /drshare
  /drshareTests
/web-client
/shared
  /api-schema
  /sample-payloads
/docs
```

## Suggested Internal Module Boundaries

### Mac App

- `AppShell`
- `MenuBarUI`
- `HostServer`
- `Discovery`
- `Storage`
- `ClipboardActions`
- `Pairing`

### Web Client

- `session`
- `drops`
- `upload`
- `download`
- `ui`

### Shared

- API types
- validation schemas
- sample payload contracts

## Implementation Order

Build in this order:

1. Mac shell app
2. in-process HTTP server
3. static web page serving
4. text endpoint and persistence
5. text recent list on both sides
6. file endpoint and storage
7. QR code and pairing token
8. Bonjour discovery

This order keeps each step demoable.

## Key Technical Decisions

- The Mac app is the host authority.
- The web UI is served by the host, not separately deployed.
- Files are treated as opaque blobs plus metadata.
- Images are not a distinct transport path in `v0`; they are files with image MIME types.
- Browser clipboard integration is optional sugar, not a core dependency.
- Android-native integration is a follow-up, not a blocker.

## Open Questions

These can be deferred, but the next implementer should resolve them explicitly:

- Which local HTTP server library should the Mac app use?
- Should hosting be manual start only or auto-start on launch?
- What recent history length is appropriate: `1`, `5`, or `20`?
- What file size cap should `v0` enforce?
- Where should files be stored on macOS?
- Should the browser client require the token on every request or retain a session cookie?

## Risks

- local network permissions or firewall prompts may confuse setup
- Bonjour discovery may be less reliable than QR/manual URL in some networks
- browser file handling varies across mobile browsers
- clipboard permissions in browsers are inconsistent
- macOS sandboxing choices may affect local server and file-access behavior if the app is later distributed

## Exit Criteria For `v0`

`v0` is complete when all of these are true:

- the Mac app can host locally
- a browser on Android can connect without custom backend infrastructure
- text transfer works both into the Mac app and back out through the browser UI
- file upload and download work for normal small files
- pairing is simple enough to explain in one sentence
- the demo can be run entirely on a trusted local network
