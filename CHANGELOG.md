# Changelog — markdown-server

## 1.5.0 — Images & media in markdown (feature/media-embeds)

Display images, video files, audio files, and YouTube links in pages by pointing the
markdown at a local path or a URL — no hand-written HTML required.

### Added
- **Auto-embed** (client-side, scoped to the rendered article): a video/audio file or a
  YouTube link written as plain markdown on **its own line** becomes a real player/embed —
  `![](clip.mp4)` → `<video>`, `![](song.mp3)` → `<audio>`, `[t](https://youtu.be/ID)` →
  a responsive 16:9 YouTube `<iframe>`. YouTube IDs are sanitised and the embed URL rebuilt
  (no injection); players are built via DOM APIs, never `innerHTML` of page content.
- **Responsive media + click-to-enlarge** — images, video, audio, and embeds are constrained
  to the content width; real images get `loading="lazy"` and enlarge in an **in-page lightbox
  modal** on click (click the backdrop or press Esc to close — no new tab).
- **Uploader guidance** — the `/admin` upload input now has an `accept` filter for supported
  types (images / video / audio / `.md`; multi-select already supported), plus a how-it-works
  note in the Upload and edit cards.
- **Discoverable demo** — a text-based `media-sample.svg` and an `images-and-media.md` page in
  the generated demo content; README gains an "Images & media" section.

### Unchanged
- No server change: media files were already served by `file_server`, and goldmark's raw-HTML
  passthrough is untouched, so raw `<video>` / `<iframe>` still work for power users. Images
  via `![](path|url)` already rendered — this adds players/embeds + responsiveness on top.
  `/api/files.json` still indexes `.md` only. No Caddyfile / Dockerfile / compose changes.

## 1.4.2 — Nested-folder depth shading (feature/nest-depth-shading)

Make the folder hierarchy in the sidebar easier to scan, on top of the existing
indent + ▶ arrow.

### Added
- Each nested `.folder-contents` gets a left guide line (`border-left`) and a faint
  translucent tint (`--nest-shade`, `rgba(139,148,158,0.05)`). Because nested levels
  paint over their parent, the tint **compounds with depth** — deeper folders read as
  progressively shaded — with no per-level rules, so it scales to any nesting depth.
- Subtle hover affordance: the guide line brightens when hovering a folder's contents.

### Unchanged
- CSS-only change in `generate_layout()`. Indentation, the expand/collapse arrow, the
  navtree, ordering (`.order`), auth/TLS, the agent API, and the admin UI are all untouched.
  No backend / Caddyfile / Dockerfile / compose changes.

## 1.4.1 — Fix: Organize card listed the folder itself (fix/organize-self-entry)

Bugfix for the v1.4.0 "Organize sidebar order" card. The WebDAV `PROPFIND` hrefs come
back rooted at the WebDAV root **without** the `/dav` route prefix (the route strips it
before `webdav`), so the self-entry filter — which compared against a `/dav/...` path —
never matched. Result: loading a folder wrongly included **the folder itself** as an
entry, making e.g. `elry` look like it contained a child `elry` (and inviting a 404 from
trying to load `elry/elry`).

### Fixed
- Normalise each `PROPFIND` href (strip optional scheme/host and `/dav` prefix, trim
  slashes) to a content-root-relative path, then skip the entry whose path equals the
  requested folder. The folder itself is no longer listed; only real children appear.
- Friendlier message when listing a non-existent folder (`folder not found` on 404).

## 1.4.0 — Custom sidebar order (feature/sidebar-ordering)

Let an editor arrange the left-sidebar navigation per folder instead of being stuck with
strict alphabetical order. Motivated by folders like `home-lab` rendering *hardware, index,
network, proxmox cluster, services* — hard to scan, with `index.md` buried in the middle.

### Added
- **Per-folder `.order` manifest** — a hidden, newline-delimited list of child names that
  fixes the sidebar order for that folder. Read by the `navtree` template at render time
  (guarded so a missing/empty file never breaks the page). Stays out of the sidebar, the
  `/admin` file list, and `/api/files.json` (all already skip dotfiles). No new routes.
- **/admin → "Organize sidebar order" card** — pick a folder, list its pages and subfolders
  (via WebDAV `PROPFIND` Depth 1), reorder with ▲/▼ buttons, and **Save order** (writes
  `.order` through the existing auth-gated `/dav/` handler). Folder labels are HTML-escaped.
- **Combined ordered list** — files and subfolders share one ordered list per directory, so a
  folder can sit between two pages (previously: all files, then all folders).
- **Sensible default** — with no `.order`, `index.md`/`README.md` are pinned to the top, then
  the rest alphabetically. New pages/folders always fall to the bottom until ordered.

### Changed
- `SCRIPT_VERSION` → `1.4.0` (was stale at `1.2.0`; 1.3.0 only bumped docs).
- Demo `index.md` + README document the Organize workflow; the old "files sort alphabetically,
  use number prefixes" guidance is reframed (numeric prefixes still sort, as a fallback).

### Unchanged
- File/folder labels (dashes → spaces, numbers kept — no prefix stripping), depth-limit
  guardrail, collapse/drag-resize, folder expand/collapse, auth/TLS, the agent API
  (`/api/files.json`, `/raw/<path>.md`, `/llms.txt` stay alphabetical), and the WebDAV admin
  UI. No backend, compose, Dockerfile, or Caddyfile changes.

## 1.3.0 — Collapsible sidebar (feature/collapsible-sidebar)

Make the left navigation sidebar collapsible so the markdown view can use the full
viewport width — especially useful on phones and other narrow screens.

### Added
- **Toggle button** (☰ / ‹‹) fixed at the top-left of the page. Click to collapse the
  sidebar to width 0 (desktop) or slide it off-canvas (mobile). Click again to restore.
- **Persistence** — collapsed/expanded state stored in `localStorage.mdSidebarCollapsed`,
  alongside the existing `mdSidebarWidth` drag-resize key.
- **Mobile defaults** — at viewports ≤768 px the sidebar becomes a slide-in drawer with a
  dimmed backdrop, and starts **collapsed by default** on first visit (no localStorage entry).
  Tapping the backdrop closes the drawer.
- ARIA: `aria-label`, `aria-controls`, and `aria-expanded` on the toggle button.

### Unchanged
- The drag-resize handle still works (desktop, expanded only). When collapsed or on
  mobile widths it is hidden so it can't fight the new state.
- Admin button, folder expand/collapse, navtree depth limit, auth/TLS modes, the
  agent API (`/api/files.json`, `/raw/<path>.md`, `/llms.txt`), and the WebDAV admin
  UI are all untouched. No backend, compose, or Caddyfile changes.

## 1.2.0 — Private registry push/pull (feature/registry-push-pull)

Push the custom image to an OCI registry (e.g. Harbor) or pull-and-run it from one,
mirroring the `-registry`/`push` conventions of the sibling Chubtoad5 installers.
Validated end-to-end on lab host 192.168.10.201 against a real Harbor (push, pull-and-run,
`save push`, and an offline-bundle regression check).

### Added
- **`push` command token** — builds the image, then pushes it to the registry. Valid with
  `install` and `save`. Requires `-registry`.
- **`-registry <host:port> <user> <pass>`** — three positional args (matching rke2/seaweedfs),
  or the `REGISTRY_INFO` / `REG_USER` / `REG_PASS` env-vars. Validates scheme/port/FQDN-or-IP/creds.
  - *with `push`* → build (or load from bundle) then push.
  - *without `push`* → **skip the build** and pull-and-run the image from the registry (`install` only).
- **`REGISTRY_NS`** (default `library`) — registry project/namespace; image lands as
  `<host:port>/<REGISTRY_NS>/markdown-caddy:<CADDY_VERSION>`.
- Automatic trust of a self-signed/internal registry CA (via `image_pull_push.sh reg-cert`).

### Changed
- **Assets are now baked into the image** (`COPY assets /assets`) instead of bind-mounted, so a
  registry-pulled (or offline-loaded) image renders fully offline with no CDN and no host volume.
  The `./assets` mount was removed from the compose file; a `.dockerignore` keeps the build context tiny.
- Compose `image:` and `pull_policy:` are now mode-aware: the registry ref with `pull_policy: missing`
  when a registry is in play, else the local build with `pull_policy: never`.
- `save` no longer stages a separate `assets/` dir in the bundle (assets travel inside the image).

## 1.1.1 — Admin button in the sidebar (feature/admin-nav-button)

### Added
- An **"⚙ Admin" button** at the top of the left sidebar, above "Navigation", linking to `/admin`. Shown only when `ENABLE_WEBDAV=true`.

## 1.1.0 — Portability, air-gap, agent API, and upload UI (feature/portability-and-features)

A ground-up hardening and feature pass on `install-md`. Validated end-to-end on lab
hosts 192.168.10.203 and 192.168.10.201 (including a real gateway-blocked air-gap run).

### Added
- **CLI subcommands:** `install` / `save` / `uninstall` / `status` / `version` / `help`
  (previously: bare run to install, `uninstall` only).
- **Runtime env-var overrides** — every setting uses `${VAR:-default}`, so
  `sudo VAR=value ./install-md` works (no more editing the script).
- **Custom Caddy image** built via multi-stage `xcaddy` with the `caddy-webdav` module
  (`CADDY_VERSION` drives base + builder tags).
- **Air-gap (`save` / offline)** — `save` bundles the image, vendored assets, and Docker
  offline packages into `md-save.tar.gz`; install auto-detects the bundle and runs with no
  internet. Front-end CSS/JS are now vendored and served locally (no cdnjs at runtime).
- **Agent API** — `GET /raw/<path>.md` and `?raw=1` (raw `text/markdown`),
  `GET /api/files.json` (live recursive index), `GET /llms.txt`.
- **Upload / manage UI** at `/admin` (upload, create, edit, delete, mkdir) backed by
  **WebDAV** at `/dav/` (PUT/DELETE/MKCOL/MOVE) — usable by AI agents too.
- **Auth** — `AUTH_MODE` = `basic` (default, `admin`/`changeme`), `none`, or `forward`
  (forward_auth to an IdP/Authentik outpost).
- **Recursive folder sidebar** up to `MAX_FOLDER_DEPTH` (default 5) with a guardrail notice;
  the API reports `truncatedDepth`.
- **Distro detection**, port-in-use pre-flight, automatic Docker install (via the Chubtoad5
  `images-pull-push` tool) when absent, and a per-run `md-install.log`.

### Changed
- **IP-only access guaranteed** — `TLS_MODE=none` binds `:PORT` (any host: IP, localhost,
  or FQDN, with no DNS). `internal` binds IP + FQDN; `auto` requires a resolvable FQDN.
- Compose now uses the locally built/loaded image with `pull_policy: never`.

### Fixed
- **Data loss:** install/uninstall no longer silently `rm -rf` the content directory —
  `srv/` is backed up to a timestamped tarball and preserved (only `MD_RESET=true` wipes it).
- The TLS success message referenced an undefined `$TLS_FQDN`.

### Security
- Write endpoints (`/admin`, `/dav`) are authenticated by default. Change `MD_ADMIN_PASSWORD`
  before exposing the server.
