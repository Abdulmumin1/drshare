# Agent Handoff Checklist

Use this file before making architecture changes or starting implementation work.

## Mission

- Build a tiny local-first sharing tool between a Mac host and browser-based clients.
- Keep the first implementation useful without a remote server.
- Do not expand the scope into a general sync platform.

## Current Product Decision

- The chosen path is `Mac host app + LAN web UI/API`.
- The Mac app is required.
- Browser support is required.
- Native Android support is optional and comes later.
- Raycast is not the core product path.
- Remote relay is not the default architecture.

## Non-Negotiable Constraints

- no remote backend for `v0`
- no account system
- no hidden clipboard sync promise
- no mandatory Android native app for the first demo
- no peer mesh or multi-host architecture
- no internet-wide access requirements

## Success Definition

An acceptable first demo must let a user:

- run a tiny Mac app
- open a small browser page from another device
- send text to the Mac
- upload a file or image to the Mac
- browse recent drops
- download a file from the browser
- copy text on the Mac

## Scope Guardrails

If you are about to add any of these, stop and justify it:

- WebSocket sync
- background clipboard watcher
- end-to-end encryption system
- login/account tables
- cloud relay mode
- multi-user auth model
- simultaneous host election
- native Android dependency before browser flow works

## Core Architecture Checklist

- Confirm the Mac app is the only host in `v0`.
- Confirm browser clients connect to the Mac host directly.
- Confirm the web app is served by the Mac host itself.
- Confirm transport is local LAN HTTP in `v0`.
- Confirm files are stored locally on the Mac host.
- Confirm metadata is persisted locally.
- Confirm the protocol is simple enough for a later Android native client to reuse unchanged.

## Repo Setup Checklist

- Create `/mac-app`.
- Create `/web-client`.
- Create `/shared`.
- Create `/docs` if missing.
- Add a short top-level README that matches the chosen architecture.
- Avoid leaving stale docs that still describe the relay/Raycast path as the default.

## Mac App Checklist

- Decide whether to use pure SwiftUI app lifecycle.
- Use `MenuBarExtra` as the main entry point.
- Provide a visible host status indicator.
- Provide a start/stop hosting control.
- Provide a way to reveal the local URL.
- Provide a way to reveal the pairing token.
- Provide a QR code for quick onboarding.
- Provide a way to copy the local URL.
- Provide a way to reset the token.
- Provide a recent drops view or popover.
- Provide a copy-latest-text action.
- Provide an open-file action for file drops.
- Persist recent drops across app restarts.
- Fail cleanly if the local server cannot bind its port.

## Mac Networking Checklist

- Pick a local port strategy.
- Decide whether the port is fixed or dynamically selected.
- Expose a `/health` endpoint.
- Expose a session/info endpoint.
- Expose a text submit endpoint.
- Expose a file upload endpoint.
- Expose a recent drops endpoint.
- Expose a download endpoint.
- Require a token for mutating operations.
- Prefer requiring a token for reads too.
- Validate content length.
- Reject oversized uploads.
- Sanitize uploaded filenames.
- Never serve arbitrary file paths from query params.
- Return consistent JSON response shapes.

## Discovery and Pairing Checklist

- Decide whether Bonjour is included in Milestone 0 or later.
- Support manual URL entry even if Bonjour exists.
- Generate a random pairing token.
- Make the token human-resettable.
- Encode URL and token into a QR code.
- Ensure the QR code flow works from Android camera/browser.
- Handle token rotation invalidating old clients.
- Document the trusted-LAN assumption clearly.

## Web Client Checklist

- Ensure the web UI works on mobile widths first.
- Keep the UI single-purpose and minimal.
- Include a text input/send path.
- Include a file picker/upload path.
- Include a recent drops list.
- Include a detail/download view for a selected drop.
- Include clear loading states.
- Include clear upload error states.
- Include token entry or tokenized URL handling.
- Preserve as little client state as possible.
- Avoid assuming clipboard permissions are available.
- Treat clipboard integration as optional enhancement only.

## Browser Compatibility Checklist

- Verify the core flow works without advanced clipboard APIs.
- Verify file upload works in Android Chrome.
- Verify file download works in Android Chrome.
- Verify the UI behaves acceptably in desktop Safari/Chrome.
- Do not block the product on PWA install support.
- Do not rely on Web Share Target for the first usable build.

## Storage Checklist

- Choose a metadata store.
- Choose a managed files directory.
- Record MIME type, size, filename, and creation time.
- Define a recent-history retention count.
- Define a max storage budget.
- Define pruning behavior.
- Handle missing file blobs gracefully if metadata remains.
- Avoid storing giant file payloads in the metadata store.

## Data Model Checklist

- Define a canonical drop schema.
- Include stable `id`.
- Include `kind`.
- Include `mime`.
- Include `filename` when relevant.
- Include `size`.
- Include `created_at`.
- Include `sender`.
- Include inline text only for text drops.
- Use managed file references for file drops.
- Keep shared schema definitions in `/shared`.

## API Contract Checklist

- Write sample request and response payloads.
- Keep endpoint names stable once the browser client uses them.
- Use explicit status codes.
- Return actionable error messages.
- Distinguish validation errors from server failures.
- Make download responses stream files, not JSON wrappers.
- Keep text submission and file submission separate if that reduces complexity.

## Security Checklist

- Treat `v0` as trusted-LAN only.
- Still require a token.
- Do not expose the host without any write protection.
- Do not allow path traversal in file names.
- Do not trust client MIME types blindly.
- Apply upload size limits.
- Consider basic CSRF implications if the token is query-based.
- Prefer bearer-style token headers once convenient.
- Make token reset easy from the Mac app.
- Do not claim strong security properties that do not exist.

## Clipboard Checklist

- Mac-side copy action is in scope.
- Browser-side clipboard use is optional.
- Do not promise passive clipboard monitoring.
- Do not make browser clipboard permissions a blocker.
- Treat image clipboard sync as out of scope for the first milestone.

## Android Strategy Checklist

- Keep Android optional for `v0`.
- Ensure the browser flow is good enough before building native Android.
- When native Android starts, reuse the same LAN API.
- Add Android share target only after browser send/download works.
- Keep native Android focused on OS integration advantages:
  - share sheet intake
  - file opening/saving
  - smoother recent list

## UX Checklist

- Optimize for one-minute setup.
- Avoid deep settings pages.
- Avoid onboarding copy that explains too much.
- Make the local URL obvious.
- Make QR scan the fastest path.
- Make the difference between `send` and `download` obvious.
- Show recent drops clearly.
- Use plain labels for MIME/file states.
- Keep error messages direct and actionable.

## Performance Checklist

- Keep app startup fast.
- Keep the web UI small.
- Stream file uploads if the chosen stack supports it simply.
- Avoid large in-memory copies for files where possible.
- Avoid polling loops unless necessary.
- Do not overengineer caching in `v0`.

## Testing Checklist

- Test on the same device via localhost/browser.
- Test on another device on the same Wi-Fi network.
- Test text send from Android Chrome to Mac host.
- Test file upload from Android Chrome to Mac host.
- Test file download back to Android Chrome.
- Test app restart and metadata persistence.
- Test invalid token behavior.
- Test oversize upload rejection.
- Test missing file handling.
- Test with Wi-Fi temporarily disabled.
- Test with the host app stopped while the browser page is open.

## Demo Checklist

- Fresh launch shows host status.
- User can start hosting without reading docs first.
- QR code appears.
- Android camera/browser can open the page.
- Text can be sent in under 10 seconds.
- A small image upload works.
- Recent drops appear on both host and web UI.
- Mac can copy latest text.
- Browser can download a previous file.

## Documentation Checklist

- README matches the actual architecture.
- Plan doc reflects current milestone order.
- Any old relay-first docs are removed or clearly marked obsolete.
- Dev setup instructions are present once scaffolding exists.
- API examples exist in `/shared` or `/docs`.
- Known non-goals are written down.
- Known risks are written down.

## Decision Log Checklist

Before closing a milestone, explicitly record:

- what was built
- what was deferred
- what changed in architecture
- what assumptions were made
- what remains risky

## Stop Conditions

Pause and reassess if any of these become necessary:

- the Mac app cannot practically host a reliable LAN server
- browser file upload or download is too unreliable on target Android devices
- local network discovery is consistently blocked by real network conditions
- the product only becomes useful with a remote relay

## Final Sanity Check

Before shipping any implementation slice, ask:

- Is this still tiny?
- Is the Mac app still the only required native app?
- Can a browser client still use the product meaningfully?
- Did we avoid turning `v0` into a sync platform?
- Did we preserve a clean path for an Android native client later?
