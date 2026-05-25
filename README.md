# markdown-server

Serve a directory of Markdown files as a browsable website, using Caddy in Docker. Features a folder-hierarchy sidebar, GitHub dark theme, code copy buttons, an upload/manage UI, an agent-readable API, and full air-gap support.

## Features

- **Live rendering** — drop `.md` files into the content directory; refresh, no restart.
- **Folder sidebar** — nested folders (collapsible) up to a configurable depth, with a clear guardrail notice when content is nested deeper.
- **Agent-friendly API** — raw markdown at `/raw/<path>.md` (or `?raw=1`), a live JSON index at `/api/files.json`, and an `/llms.txt` hint.
- **Upload / manage UI** — `/admin`: upload, create, edit, delete, and make folders. Backed by WebDAV (`/dav/`), which AI agents can also use to write files.
- **Auth** — HTTP basic auth by default; or none; or `forward_auth` to an external IdP.
- **TLS** — none (HTTP), Caddy self-signed (`internal`), or Let's Encrypt (`auto`).
- **Air-gap** — `save` builds a self-contained bundle (image + assets + Docker packages); offline install needs no internet (assets are vendored locally, not pulled from a CDN).
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

## Adding content

- **In the browser:** go to `/admin` and upload / create / edit files and folders.
- **Over the network (or from an AI agent):** WebDAV under `/dav/`:
  ```bash
  curl -u admin:changeme -T page.md http://<host>/dav/notes/page.md   # upload
  curl -u admin:changeme -X MKCOL http://<host>/dav/notes/            # mkdir
  curl -u admin:changeme -X DELETE http://<host>/dav/notes/page.md    # delete
  ```
- **On the host:** copy `.md` files into `/opt/caddy-markdown/srv` (and subdirectories), then refresh.

Files sort alphabetically; prefix with numbers (`01-intro.md`) to control order. Dashes in names render as spaces. Folder names should not contain dots.

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
