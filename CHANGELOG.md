# Changelog — markdown-server

## v1.7.0 — 2026-11-12 — Any admin password works, and a re-run keeps it

### Fixed
- **An admin password over 72 bytes works, and a refused re-run no longer leaves the site down** (spec 21, M1). Caddy
  hashed the password with bcrypt, which stops at 72 bytes, and by then the running site had been stopped, so it stayed
  down until a re-run with a shorter password. The hash is now argon2id. The installer gives the password to Caddy's
  `hash-password` on stdin instead of `--plaintext`, where `ps` showed it to every local account. Every check on the
  login now comes before anything is stopped, and the running site stays up while the image is built and the password
  hashed.
- **An admin user name the Caddyfile can't carry is refused** (spec 21, M2). It went into the Caddyfile as written:
  a space broke the Caddyfile after the site was stopped, `#admin` made every login fail, `{$HOME}` became a path, and
  `ad:min` could never log in. `MD_ADMIN_USER` is now letters, digits and `. _ @ + -`. Anything else stops the run with
  a message naming `MD_ADMIN_USER`, before anything changes.
- **A re-run without `MD_ADMIN_PASSWORD` keeps the login** (spec 21, M3). Before, the hash was made again on every run
  from `${MD_ADMIN_PASSWORD:-changeme}`, so an upgrade that didn't pass the password set the login back to `changeme`,
  and so did an empty value. Now an unset `MD_ADMIN_PASSWORD` keeps the stored login, and an empty one is refused. A
  first install with no password still gets `changeme`, and the banner says to change it.
- **The install no longer prints the admin password** (spec 21, M4). The closing banner printed it, and
  `md-install.log`, where it was copied, was readable by every local account. The banner now says where the password
  came from (`MD_ADMIN_PASSWORD`, unchanged, or the default `changeme`), and `md-install.log` is 0600, for `install`,
  `save` and `uninstall`, including a log an older run left at 0644.

### Changed
- **A re-run that changes nothing doesn't restart Caddy** (spec 21, Q5). Before, every run stopped the stack first.
  Now a stack that already serves `TCP_PORT` stays up: `docker compose up -d` recreates it only if its image or compose
  file changed, and a changed Caddyfile restarts it once. A stack on another port, or a run with `MD_RESET=true`, is
  stopped as before, but only once the image and the hash are ready. The image is now built without a provenance
  attestation, which carried the build time, so with Docker's containerd image store every rebuild had a new ID and
  compose recreated Caddy on every run.
- **The login is stored in `$BASE_DIR/.auth-hash`**, readable by root only: the user, Caddy's hash, and a fingerprint
  of the hash with the password (as SeaweedFS's installer does). A password that matches the fingerprint keeps its
  hash, so the Caddyfile stays the same. `uninstall` removes it with the rest of `$BASE_DIR`.
- **An install by v1.6.1 or earlier keeps its bcrypt hash**, and its Caddyfile unchanged, while `MD_ADMIN_PASSWORD`
  is unset. The first run that sets a password hashes it with argon2id, and Caddy restarts once.
- **An unset `MD_ADMIN_USER` keeps the stored user,** as the password does. Before, it went back to `admin`.
- **A password with a control character, such as a tab or a newline, or over 128 characters, is refused**, with a
  message that names `MD_ADMIN_PASSWORD` and never shows the value. A user name and a password that are both wrong are
  reported in the same run.
- **A Caddy older than 2.11 hashes with bcrypt, as before.** It has no argon2id: an old bundle or registry image, or
  an older `CADDY_VERSION`. A password over 72 bytes is then refused, before the running site is stopped, with a
  message that says to use a newer Caddy.

### Tests
- `tests/password-vectors.txt` and `tests/vectors.bash`: spec 21's test passwords, the same in every changed repo.
- `tests/unit/admin-login.bats`: the whole install with Docker stubbed. Each test password goes through each place the
  password goes, compared byte for byte: what reaches `hash-password` on stdin (never an argument), the Caddyfile
  (argon2id, the hash, never the password) and `.auth-hash` (the fingerprint, worked out again in Python, and mode
  0600). Then a re-run with the same password, which keeps the hash and doesn't restart Caddy; a changed password;
  unset and empty `MD_ADMIN_PASSWORD`; the first install's `changeme`; control characters and 129 characters; the
  user-name rule; the stored user; an install by v1.6.1; an unreadable `.auth-hash`; a failed hash, which leaves the
  site up; the order of the stop for another port and `MD_RESET`; a Caddy older than 2.11; the banner and the log's
  mode.
- `tests/secret-lint.py` and `tests/unit/secret-lint.bats`: spec 21's static check, which fails on an unquoted secret,
  or a secret given to `echo`, `eval`, `sed` or `--set`. It found the banner's `echo` of the password.
- `tests/integration/10-lifecycle.sh` installs with the long test password (128 characters) and logs in with it, then
  re-runs without `MD_ADMIN_PASSWORD`: the password still logs in, `changeme` doesn't, and Caddy's start time is
  unchanged. An empty and a 129-character password are then refused, with the site still up and unrestarted. It also
  checks the banner, the log's mode and `.auth-hash`'s.

## v1.6.1 — 2026-11-09 — Air-gapped Docker on SUSE and on Rocky 10's image kernel

### Fixed
- **A SUSE bundle holds Docker** (spec 15, F2). `save` asked for Docker CE's package names, which SUSE doesn't have, so
  the bundle had no Docker and an air-gapped SUSE install needed Docker there already. `save` and the offline install now
  use SUSE's own `docker` and `docker-compose`, as `images-pull-push` does.
- **An air-gapped install on Rocky, Alma or RHEL 10 no longer stops for `kernel-modules-extra`** (spec 15, F1). `save` on
  an EL host now also bundles `kernel-modules-extra-$(uname -r)` when the build host's repos still have it, and the
  offline install installs it from the bundle when the target runs that same kernel, then starts Docker. On another
  kernel the message names the kernel the bundle was built for, and today's advice follows.

- **A SUSE bundle's Docker installs with SELinux enforcing** (spec 15, F7). `INSTALL_PACKAGES_REF` now defaults to
  `install-packages` v1.1.3, whose SUSE `save` also takes Docker's `container-selinux`.

- **Uploads work on SLES and openSUSE with SELinux enforcing.** SUSE's own `docker` package turns SELinux on in the
  daemon (`"selinux-enabled": true`), so Caddy runs confined and could read `/srv` but not write to it. Every WebDAV
  upload got a 404, which is how the WebDAV handler reports a failed open. The compose file's mounts now carry `:z`, so
  Docker labels them for containers. Docker ignores it where SELinux isn't enabled. Found by F2's A1 on Leap 16: before
  F2, a SUSE air-gapped install never got that far. Online, images-pull-push writes its own `daemon.json` first, so it
  wasn't seen there.

### Added
- **`LICENSES/` in a save bundle** (spec 15, Q9): a manifest of what it redistributes, meaning the server image's parts
  (Caddy, caddy-webdav, goldmark, github-markdown-css, highlight.js, and the official caddy image's Alpine base layer) and
  the OS packages, plus a written offer for the GPL and LGPL ones. `LICENSE_OFFER_CONTACT` sets who the offer names.

### Tests
- `tests/unit/licences.bats`: the manifest, the contact, and that `save` writes it into the bundle.
- `tests/unit/helper-pins.bats` follows the pin to v1.1.3.
- `tests/unit/docker-offline.bats`: both F1 outcomes, what `save` adds, and SUSE's package names in `save` and the offline install.

## v1.6.0 — 2026-11-08 — The helpers come from releases

### Changed
- **`image_pull_push.sh` and `install_packages.sh` are fetched from releases, `images-pull-push` `v1.1.1` and
  `install-packages` `v1.1.2`, instead of `main`** (spec 14, as spec 12 did for rke2 and SeaweedFS). So a merge in
  either no longer reaches this installer until a pin moves.
- **A copy already in `$BASE_DIR/utilities` is reused only if it came from the same ref,** recorded beside it in a `.ref`
  file. Before, any copy was kept for good, so a host never saw a fix. A copy with no record is fetched again once.
- **An install from the offline bundle never downloads a helper.** The bundle now carries both helpers and their `.ref`
  records, so an offline install with a registry uses the bundle's `image_pull_push.sh`. An older bundle with no copy
  stops and says what to do, before anything changes. A `save` always fetches the pinned copies.
- **A registry install gets `image_pull_push.sh` before it stops the running site,** so a failed download leaves the site
  up. A failed download's error names the `_URL` setting to point at a mirror.
- **`INSTALL_PACKAGES_REF` is passed on to `image_pull_push.sh`,** which reads it, so one setting covers both helpers.

### Added
- **`IMAGE_PULL_PUSH_REF`** (default `v1.1.1`) and **`INSTALL_PACKAGES_REF`** (default `v1.1.2`).
- **`IMAGE_PULL_PUSH_URL`** and **`INSTALL_PACKAGES_URL`**, which win over their refs. `IPP_URL`, fixed until now, works
  as an alias for `IMAGE_PULL_PUSH_URL`.
- **`IMAGE_PULL_PUSH_SHA256`** and **`INSTALL_PACKAGES_SHA256`**: optional checksums. A mismatch, or a failed download,
  stops the run and leaves no file.

### Tests
- `tests/unit/helper-pins.bats`: both default tags, the ref and URL settings and the `IPP_URL` alias, the export, reuse
  and refetch, both checksum cases, a failed download, the offline cases (a copy in place, the bundle's copy, an older
  bundle with none), that `save` bundles both helpers and never sets the offline flag, and that a registry install gets
  the helper before it stops the site.

## v1.5.1 — 2026-11-07 — The air-gapped install starts Docker

### Fixed
- **An air-gapped install on Rocky, Alma or RHEL starts Docker.** It installed Docker from the bundle, but only
  Ubuntu's package starts Docker by itself, so the install then failed at its first `docker` command (`failed to
  connect to the docker API`). It now enables and starts Docker whenever it's installed but not running, which also
  covers a re-run after a failed start.
- **On Rocky 10's cloud image, it says what Docker is missing.** That image leaves out `kernel-modules-extra`, which
  holds the module Docker needs for its NAT rules (`xt_addrtype`), so Docker can't start, and the bundle can't carry
  a package for a kernel it doesn't know. The install now stops before starting Docker, and names the package to
  install from local media, `kernel-modules-extra-<running kernel>`, or the kernel on this host to reboot into, when
  one has the module. Online installs were already fine: `images-pull-push` installs the running kernel's package.

### Tests
- `tests/unit/docker-offline.bats`: the missing-module messages, the start, and a Docker that won't start.

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
Validated end-to-end on a lab host against a real Harbor (push, pull-and-run,
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
hosts (including a real gateway-blocked air-gap run).

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
