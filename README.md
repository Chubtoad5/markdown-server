# markdown-server

Serve a directory of Markdown files as a browsable website, using Caddy in Docker. Features a folder-hierarchy sidebar, GitHub dark theme, code copy buttons, an upload/manage UI, an agent-readable API, and full air-gap support.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Commands](#commands)
- [Private registry (Harbor, etc.)](#private-registry-harbor-etc)
- [Configuration (environment variables)](#configuration-environment-variables)
- [Adding content](#adding-content)
- [Reading content programmatically (AI agents)](#reading-content-programmatically-ai-agents)
- [Air-gapped install](#air-gapped-install)
- [License](#license)

---

## Features

- **Live rendering** — drop `.md` files into the content directory; refresh, no restart.
- **Folder sidebar** — nested folders (collapsible) up to a configurable depth, with a clear guardrail notice when content is nested deeper.
- **Collapsible sidebar** — toggle the left navigation in/out for a full-width reading view; auto-collapsed on phones and slides in as a drawer when needed.
- **Custom sidebar order** — reorder pages and folders per directory from the `/admin` UI (▲/▼ buttons); new content lands at the bottom. Saved as a hidden `.order` file; no manifest means `index.md`/`README.md` first, then alphabetical.
- **Images & media** — embed images (local or URL), video/audio files, and YouTube links by pointing markdown at a path or URL; auto-rendered as responsive players/embeds. Images are click-to-enlarge.
- **Agent-friendly API** — raw markdown at `/raw/<path>.md` (or `?raw=1`), a live JSON index at `/api/files.json`, and an `/llms.txt` hint.
- **Upload / manage UI** — `/admin`: upload, create, edit, delete, make folders, and **organize sidebar order**. Backed by WebDAV (`/dav/`), which AI agents can also use to write files.
- **Auth** — HTTP basic auth by default; or none; or `forward_auth` to an external IdP.
- **TLS** — none (HTTP), Caddy self-signed (`internal`), or Let's Encrypt (`auto`).
- **Air-gap** — `save` builds a self-contained bundle (image + Docker packages); offline install needs no internet. Front-end CSS/JS are vendored and **baked into the image**, so it renders fully offline with no CDN.
- **Private registry** — `push` builds the image and pushes it to an OCI registry (e.g. Harbor); `-registry` alone skips the build and **pulls-and-runs** that image. Because assets are baked in, the pushed image is a complete, portable artifact.
- **Runtime env-var overrides** and a clean CLI — no editing the script.

## Requirements

- A supported Linux distro (Ubuntu/Debian, RHEL family, or SUSE family).
- Root (`sudo`). Docker is installed automatically if absent.

## Quick start

```bash
git clone https://github.com/Chubtoad5/markdown-server.git
cd markdown-server
chmod +x install-md
sudo ./install-md install
```

Then open `http://<host-ip>/` and the upload UI at `http://<host-ip>/admin` (default `admin` / `changeme` — change it!).

Override any setting at runtime, e.g.:

```bash
sudo TCP_PORT=8088 BROWSER_TITLE="My Docs" MD_ADMIN_PASSWORD='s3cret' ./install-md install
```

## Commands

| Command | Description |
|---------|-------------|
| `install` (default) | Install or refresh. Offline install is automatic when `md-save.tar.gz` is present. |
| `save` | Build an air-gap bundle `md-save.tar.gz` (does not deploy). |
| `uninstall` | Stop + remove the stack and image (backs up content first). |
| `status` | Container status + HTTP health probe. |
| `version` / `help` | Info / usage. |
| `push` (option) | With `-registry`: build, then push the image to the registry. Combine with `install` or `save`. |

## Private registry (Harbor, etc.)

Push the custom image to an OCI registry, or pull-and-run it from one — credentials are three positional args after `-registry` (matching the sibling Chubtoad5 installers), or the `REGISTRY_INFO` / `REG_USER` / `REG_PASS` env-vars.

```bash
# Build the image and push it to the registry (then run from the registry ref):
sudo ./install-md install push -registry harbor.example.com:443 admin 's3cret'

# On another host: skip the build, pull-and-run the pushed image:
sudo ./install-md install -registry harbor.example.com:443 admin 's3cret'

# Build an air-gap bundle AND push the image in one go:
sudo ./install-md save push -registry harbor.example.com:443 admin 's3cret'
```

The image is pushed as `<host:port>/<REGISTRY_NS>/markdown-caddy:<CADDY_VERSION>` (`REGISTRY_NS` defaults to `library`, Harbor's default project). A self-signed/internal registry CA is fetched and trusted automatically. `-registry` without `push` (pull-and-run) is valid with `install` only.

## Configuration (environment variables)

| Variable | Default | Description |
|----------|---------|-------------|
| `BASE_DIR` | `/opt/caddy-markdown` | Install + data directory |
| `SRV_DIR` | `$BASE_DIR/srv` | Where `.md` files live |
| `MGMT_IP` | first host IP | Bind/advertise IP |
| `FQDN` (`TLS_FQDN`) | `md.$(hostname -f)` | FQDN for TLS modes (must resolve) |
| `TCP_PORT` | `80` | Listen port |
| `TLS_MODE` | `none` | `none` / `internal` (self-signed) / `auto` (Let's Encrypt) |
| `BROWSER_TITLE` | `Markdown Server` | Browser tab title |
| `CADDY_VERSION` | `latest` | Caddy base image tag |
| `MAX_FOLDER_DEPTH` | `5` | Folder nesting shown in sidebar / allowed in the UI |
| `AUTH_MODE` | `basic` | `basic` / `none` / `forward` (guards `/admin` + `/dav`) |
| `MD_ADMIN_USER` | `admin` | basic-auth user |
| `MD_ADMIN_PASSWORD` | `changeme` | basic-auth password |
| `ENABLE_WEBDAV` | `true` | Enable `/dav` + `/admin` |
| `FORWARD_AUTH_URL` | (empty) | `AUTH_MODE=forward`: IdP outpost URL |
| `MD_RESET` | `false` | Wipe content on install (backup still taken) |
| `MD_PURGE` | `false` | Skip the content backup on uninstall |
| `REGISTRY_NS` | `library` | Registry project/namespace for the pushed image |
| `REGISTRY_INFO` | (empty) | Registry `host:port` (env-var alternative to `-registry`) |
| `REG_USER` / `REG_PASS` | (empty) | Registry credentials (env-var alternative) |

## Adding content

- **In the browser:** go to `/admin` and upload / create / edit files and folders.
- **Over the network (or from an AI agent):** WebDAV under `/dav/`:
  ```bash
  curl -u admin:changeme -T page.md http://<host>/dav/notes/page.md   # upload
  curl -u admin:changeme -X MKCOL http://<host>/dav/notes/            # mkdir
  curl -u admin:changeme -X DELETE http://<host>/dav/notes/page.md    # delete
  ```
- **On the host:** copy `.md` files into `/opt/caddy-markdown/srv` (and subdirectories), then refresh.

### Sidebar order

Each folder lists `index.md`/`README.md` first, then everything else alphabetically. To set a custom order, open `/admin` → **Organize sidebar order**, pick a folder, reorder its pages and subfolders with the ▲/▼ buttons, and **Save order**. Pages and folders share one list, so a folder can sit between two pages. Newly added content always appears at the bottom until you order it.

Order is stored as a hidden per-folder `.order` file (one entry name per line) written via WebDAV — you can also hand-edit it on the host, e.g. `curl -u admin:changeme -T .order http://<host>/dav/notes/.order`. This affects the navigation sidebar only; `/api/files.json` and `/llms.txt` stay alphabetical. A leading number in a file name still sorts naturally if you prefer that. Dashes in names render as spaces; folder names should not contain dots.

### Images & media

Point a page at media by **relative path** (a file you uploaded next to the page) or a full **URL**. Put each reference on **its own line** so it renders as a block:

```markdown
![Diagram](diagram.png)                  # image — local file or URL
![](clip.mp4)                            # video player (mp4, webm, ogv, mov, m4v, mkv)
![](song.mp3)                            # audio player (mp3, wav, m4a, flac, aac, ogg, oga)
[watch](https://youtu.be/VIDEO_ID)        # responsive YouTube embed
```

Upload the `.md` page **and** its media into the same folder from `/admin` (multi-select; the picker is filtered to supported types). Images are responsive and **click-to-enlarge**; inline (mid-sentence) media links stay as links — only references on their own line auto-embed. Power users can still write raw `<video>` / `<iframe>` HTML directly in the markdown. Media is served straight from `/srv`; only `.md` pages are indexed by `/api/files.json`.

## Reading content programmatically (AI agents)

```bash
curl http://<host>/api/files.json        # JSON index of every .md file
curl http://<host>/raw/notes/page.md      # raw markdown (text/markdown)
curl "http://<host>/notes/page.md?raw=1"  # same, via query
```

## Air-gapped install

```bash
# On a connected host (same OS family/version as the target):
sudo ./install-md save                    # produces md-save.tar.gz

# Transfer install-md + md-save.tar.gz to the target, then:
sudo ./install-md install                 # detects the bundle, installs offline
```

## License

See [LICENSE](LICENSE).
