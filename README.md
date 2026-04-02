# drshare

Local-first drop sharing between your Mac and nearby devices.

`drshare` runs as a tiny macOS menu bar host, serves a browser client over your LAN, and lets you send text or files without a remote backend.

## What It Is

Current project shape:

- Mac menu bar app is the host
- browser client works immediately on phones, tablets, and other computers on the same network
- no cloud relay
- no account system
- no App Store dependency right now

Current supported actions:

- send text from the Mac app
- send text from the web client
- upload files from the Mac app
- upload files from the web client
- browse recent drops
- download received files
- copy received text

## Current Scope

Implemented now:

- macOS host app
- LAN web UI
- pairing token
- QR pairing
- Bonjour advertisement
- transfer progress for uploads and downloads
- drop expiry with configurable retention

Not shipped yet:

- Android native app
- background clipboard sync
- App Store distribution

## Requirements

- macOS 14 or newer
- Xcode installed
- another device on the same local network if you want to use the browser client remotely

## Quick Start

Clone the repo and run:

```bash
./scripts/run-mac.sh
```

The app will:

- build with the Xcode Swift toolchain
- launch the menu bar host
- print a LAN URL with a pairing token

Example:

```txt
http://192.168.1.15:3847/?token=ABCD-1234-EFGH
```

Open that URL in a browser on another device on the same network.

## Local Storage

By default, app state is stored in:

- `.drshare-state/` when using the wrapper script in this repo

You can override that:

```bash
DRSHARE_STORAGE_ROOT=$PWD/.drshare-state ./scripts/run-mac.sh
```

## Retention

Drops expire after `24h` by default.

The Mac app lets you switch retention to:

- `1h`
- `24h`
- `7d`
- `never`

You can also override retention while testing:

```bash
DRSHARE_RETENTION_HOURS=0.5 ./scripts/run-mac.sh
```

## How To Use It

### On Mac

Use the menu bar app to:

- drag and drop a file
- choose a file from disk
- send a short text note
- copy text from recent drops
- open downloaded files
- show the QR code for pairing

### On Another Device

Open the LAN URL in a browser and:

- enter the pairing token if needed
- send text
- upload a file
- download recent files

## API

Public:

- `GET /`
- `GET /health`

Requires the pairing token via `X-DrShare-Token` or `?token=`:

- `GET /api/session`
- `GET /api/drops`
- `POST /api/drops/text`
- `POST /api/drops/file`
- `GET /api/drops/:id/download`

File upload contract:

- raw request body is the file payload
- send `X-DrShare-Filename`
- send `Content-Type`
- send a positive `Content-Length`

Current file transfer notes:

- uploads stream to disk
- max upload size is `5 GB`
- chunked transfer encoding is not supported yet

## Development

Internal implementation notes now live in:

- [DEVELOPMENT.md](/Users/macbookpro/Documents/projects/drshare/DEVELOPMENT.md)

## Troubleshooting

### Swift Toolchain Errors

Do not use plain `swift run` unless you know your active Swift toolchain matches previous build artifacts.

Use:

```bash
./scripts/run-mac.sh
```

That wrapper avoids mixed-toolchain build issues.

### Can’t Connect From Phone

Check:

- both devices are on the same network
- the Mac app is running
- you are using the LAN URL, not only `127.0.0.1`
- the pairing token matches

## Status

This is a working prototype meant for local use and source installs.
