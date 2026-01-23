# markdown-server
Simple Markdown server using Caddy

## Features
- Leverages Caddy in a docker container and exposes the specified TCP port on the host
- Supports serving multiple markdown files
- Left navigation bar automatically lists all markdown files found and serves them
- Click on a file name in the navigation bar to see the markdown content
- Adding or editin markdown files does not require server restart, simply refresh the page

## Instructions

### Setup

Prerequisites:
- Tested on Ubuntu Server, but should work on any standard linux distro
- Docker runtime and cli must be installed

1. Download `install-md` or clone this repo
```
git clone https://github.com/Chubtoad5/markdown-server.git
cd markdown-server
chmod +x install-md
```
2. Optionally, update the `USER DEFINED VARIABLES` section of the `install-md` file

|Variable Name|Description|Default Value|
|:------------|:----------|:------------|
|BASE_DIR|Installation and data directory|"/opt/caddy-markdown"|
|SRV_DIR|Directory where .md and .html is stored|"$BASE_DIR/srv"|
|MGMT_IP| Bind IP Address of the host|"$(hostname -I | awk '{print $1}')"|
|TCP_PORT|TCP port for the web server, change to 443 or higher if using TLS|"80"|
|TLS_MODE|TLS mode, valid values are none=disabled, internal=caddy self-signed, auto=letsencrypt|"none"|
|TLS_FQDN|Only used with TLS, an FQDN for the webserver, must be resolvable|"md.$(hostname -f)"|
|BROWSER_TITLE|Adds a title header to your browser tab|"Markdown Server"|

3. Run the `install-md` script **note** may require root depending on install directory permissions

```
sudo ./install-md
```

4. Once installation is complete, navigate to the provided URL