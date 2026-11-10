#!/bin/bash
# A5: install the last release (its source archive from GitHub), upload a page and a sidebar order over WebDAV, then
# install the commit under test over it. The content, the order and the admin password survive.
set -uo pipefail
REPO=$PWD
fail=0
ok()  { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=1; }
within() { local t=$1 i; shift; for ((i = 0; i < t; i += 3)); do "$@" && return 0; sleep 3; done; "$@"; }
W=$(mktemp -d -p /var/tmp); cd "$W" || exit 1
R=markdown-server
old=$(curl -sI -m 20 "https://github.com/Chubtoad5/$R/releases/latest" | tr -d '\r' | sed -n 's#^[Ll]ocation: .*/tag/##p')
[[ "$old" =~ ^v[0-9]+(\.[0-9]+)+$ ]] && ok "the last release is $old" || { bad "couldn't find the last release: '$old'"; echo "=== exit 1"; exit 1; }
mkdir old new
curl -sfL -m 180 "https://github.com/Chubtoad5/$R/archive/refs/tags/$old.tar.gz" | tar -xz -C old --strip-components=1 && [ -x old/install-md ] \
  && ok "download $old" || { bad "download $old"; echo "=== exit 1"; exit 1; }
cp "$REPO/install-md" new/; chmod +x new/install-md
P=Test-Pass-1 B=http://127.0.0.1:8080
export TCP_PORT=8080 MD_ADMIN_PASSWORD=$P
up() { [ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' "$B/")" = 200 ]; }
dav() { curl -s -m 10 -o /dev/null -w '%{http_code}' -u "admin:$P" "$@"; }

(cd old && ./install-md install) > o1 2>&1 && ok "install $old" || { bad "install $old"; tail -8 o1 | cut -c1-170; echo "=== exit 1"; exit 1; }
within 60 up && ok "$old's site answers" || bad "$old's site doesn't answer"
printf '# A5\n\nwritten before the upgrade\n' > page.md
printf 'zeta.md\na5-page.md\n' > order
printf '# Zeta\n' > zeta.md
c=$(dav -X MKCOL "$B/dav/a5/"); [[ "$c" =~ ^20 ]] && ok "make a folder" || bad "make a folder: $c"
for f in page.md:a5-page.md zeta.md:zeta.md order:.order; do
  c=$(dav -T "${f%%:*}" "$B/dav/a5/${f#*:}"); [[ "$c" == 201 || "$c" == 204 ]] && ok "upload ${f#*:}" || bad "upload ${f#*:}: $c"
done

(cd new && ./install-md install) > o2 2>&1 && ok "install the commit under test over $old" || { bad "install the commit under test over $old"; tail -10 o2 | cut -c1-170; }
within 60 up && ok "the site answers after the upgrade" || bad "the site doesn't answer after the upgrade"
[ "$(curl -s -m 10 "$B/raw/a5/a5-page.md")" = "$(cat page.md)" ] && ok "the page survived" || bad "the page changed or is gone"
[ "$(curl -s -m 10 -u "admin:$P" "$B/dav/a5/.order")" = "$(cat order)" ] && ok "the sidebar order survived" || bad "the sidebar order changed or is gone"
# The sidebar links the folder's pages in the saved order: zeta first
side() { curl -s -m 10 "$B/a5/a5-page.md" | grep -oE 'a5/(zeta|a5-page)\.md' | awk '!seen[$0]++' | tr '\n' ' '; }
[ "$(side)" = "a5/zeta.md a5/a5-page.md " ] && ok "the sidebar uses the saved order" || bad "the sidebar's order is '$(side)'"
[ "$(dav "$B/admin")" = 200 ] && ok "the admin password still works" || bad "the admin password no longer works"
(cd new && ./install-md uninstall) > o3 2>&1 && ok "uninstall" || { bad "uninstall"; tail -6 o3 | cut -c1-170; }
echo "=== exit $fail"; exit $fail
