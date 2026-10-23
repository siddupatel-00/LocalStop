# LocalStop (Tauri)

A cross-platform tray/menu-bar app for finding and stopping localhost development servers.

## What it does

LocalStop lists every TCP port currently listening on localhost, with its PID and owning process. From the popover you can:

- Filter the list with live search.
- Sort by port, process name, or custom name.
- Rename any listener inline; custom names are persisted across restarts.
- Open a listener in the default browser.
- Stop a listener's process (SIGTERM, then SIGKILL on Unix; `taskkill /T /F` on Windows).

The window is frameless and hidden from the taskbar. Click the tray icon to toggle it, use the tray menu's Show / Hide item, or press Escape to hide it. On macOS it runs as an accessory (no Dock icon) and uses a template tray icon.

## Tech stack

- [Tauri 2](https://v2.tauri.app/) with a Rust backend.
- Vanilla HTML/CSS/JS frontend in `src/`.
- No bundler or frontend framework: `frontendDist` points directly at `../src`, and `withGlobalTauri` exposes the API as `window.__TAURI__`.

## Prerequisites

- Rust stable (`rustup` recommended).
- Node.js 20 or newer.
- Platform dependencies:
  - macOS: Xcode Command Line Tools (`xcode-select --install`).
  - Windows: Microsoft C++ Build Tools and WebView2 (included with current Windows).
  - Linux: `webkit2gtk-4.1`, `libayatana-appindicator3`, `librsvg2`, `libxdo`, and OpenSSL development packages. For example, on Ubuntu:

```bash
sudo apt-get install -y \
  libwebkit2gtk-4.1-dev libayatana-appindicator3-dev librsvg2-dev \
  libxdo-dev libssl-dev build-essential curl wget file patchelf
```

## Develop

```bash
cd tauri
npm install
npm run dev
```

`npm run dev` builds the frontend assets and launches the app.

## Build

```bash
npm run build
```

Bundle output locations:

- macOS: `.app` and `.dmg` under `src-tauri/target/release/bundle/`.
- Windows: `.msi` and `.exe` under `src-tauri\target\release\bundle\`.
- Linux: `.AppImage` and `.deb` under `src-tauri/target/release/bundle/`.

### Universal macOS build

```bash
rustup target add aarch64-apple-darwin x86_64-apple-darwin
npm run tauri build -- --target universal-apple-darwin
```

The universal bundle is written under `src-tauri/target/universal-apple-darwin/release/bundle/`.

## CI and releases

`.github/workflows/release.yml` builds macOS (universal), Ubuntu 24.04, and Windows in a matrix using `tauri-apps/tauri-action`.

- Every push to `main` and every manual dispatch builds all platforms and uploads artifacts (`localstop-<platform>`) without creating a release.
- Pushing a tag matching `v*` additionally creates a draft GitHub release with all bundles attached.

## How scanning works

| OS | Source |
| --- | --- |
| macOS | `/usr/sbin/lsof -nP -a +c 0 -iTCP -sTCP:LISTEN -u <uid> -Fpcn` |
| Linux | `ss -ltnpH`, falling back to `lsof` only if `ss` fails or is missing |
| Windows | PowerShell `Get-NetTCPConnection -State Listen` joined with `Get-Process` |

Wildcard and empty bind addresses (`*`, `0.0.0.0`, `::`, `::1`, `127.0.0.1`) are normalized to `localhost`. System and helper processes (Control Center, `rapportd`, `svchost`, editor helpers, LocalStop itself, and similar) are filtered out, the app's own PID is excluded, and duplicate `(pid, port)` rows are removed. Results are sorted by port, then PID.

Custom names are stored per port in `servers.json` inside the Tauri app config directory (`app_config_dir`); empty names delete the entry. Ports are the key, so a name follows the port rather than the process.

## Security notes

- `open_url` accepts only `http://localhost:<port>` and `http://127.0.0.1:<port>` URLs; anything else is rejected before reaching the OS opener.
- Stopping a process requires a valid PID greater than 1 and rejects the app's own PID.
