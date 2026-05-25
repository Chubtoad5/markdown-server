# Changelog — markdown-server

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
