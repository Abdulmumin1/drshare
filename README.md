# drshare

Tiny local-first sharing between your Mac and nearby devices.

![](https://mac-file.yaqeen.me/E3E325D0-Untitled%20design%20%283%29.png)

`drshare` runs as a macOS menu bar app, serves a browser client on your LAN, and lets you send text or files without a cloud relay.

## Download

Download the latest macOS build from GitHub Releases:

- <https://github.com/Abdulmumin1/drshare/releases>

Current release builds are unsigned, so macOS may warn on first launch.

## What Works

- Mac menu bar host
- browser client for phones, tablets, and other computers on the same network
- text send
- file upload and download
- QR pairing
- transfer progress
- configurable retention

## What Is Not Built Yet

- Android native app
- background clipboard sync
- signed and notarized macOS releases

## Run From Source

Requirements:

- macOS 14 or newer
- Xcode installed

Start the app:

```bash
./scripts/run-mac.sh
```

That prints a LAN URL like:

```txt
http://192.168.1.15:3847/?token=ABCD-1234-EFGH
```

Open that URL on another device on the same network.

## Install Locally

Build and install a real app bundle into `/Applications`:

```bash
./scripts/install-mac-app.sh
```

If you only want the bundle:

```bash
./scripts/build-mac-app.sh
```

The built app is placed at:

- `dist/DrShare.app`

## Use

On Mac:

- drag in a file
- choose a file from disk
- send a short text note
- copy recent text
- open recent files
- show the QR code for pairing

On another device:

- open the LAN URL in a browser
- send text
- upload a file
- download recent files

## Limits

- no remote backend
- local network only
- max upload size is `5 GB`
- file uploads require `Content-Length`
- chunked transfer encoding is not supported yet

## Troubleshooting

If you hit Swift toolchain errors, use:

```bash
./scripts/run-mac.sh
```

That wrapper avoids mixed-toolchain build issues.
