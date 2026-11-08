#!/bin/bash
# What markdown-server is for, on a throwaway host, as root, from the repo root (spec 09's C4, in the chubtoad-automation
# project): upload pages over WebDAV, read one rendered and raw, then set the folder's sidebar order and see it in the
# sidebar. Runs after 10-lifecycle.sh, which leaves the host uninstalled.
set -uo pipefail
REPO=$PWD
fail=0
ok()  { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=1; }
# within <seconds> <command...>: true once the command is, checking every 3 seconds
within() { local t=$1 i; shift; for ((i = 0; i < t; i += 3)); do "$@" && return 0; sleep 3; done; "$@"; }
W=$(mktemp -d -p /var/tmp); cd "$W" || exit 1
cp "$REPO/install-md" .; chmod +x install-md
P=Test-Pass-1 B=http://127.0.0.1:8080 TAG="c4-$$-$(date +%s)"
export TCP_PORT=8080 MD_ADMIN_PASSWORD=$P
./install-md install > "$W/o" 2>&1 && ok "install" || { bad "install"; tail -6 "$W/o" | cut -c1-170; }
up() { [ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' "$B/")" = 200 ]; }
within 60 up && ok "the site answers" || bad "the site doesn't answer"
dav() { curl -s -m 15 -o /dev/null -w '%{http_code}' -u "admin:$P" "$@"; }
c=$(dav -X MKCOL "$B/dav/ci-c4/"); [[ "$c" == 201 || "$c" == 405 ]] && ok "make a folder over WebDAV" || bad "MKCOL got $c"
for p in a b c; do
  printf '# Page %s\n\nThe text of page %s, %s.\n' "${p^^}" "$p" "$TAG" > "$W/$p.md"
  c=$(dav -T "$W/$p.md" "$B/dav/ci-c4/$p-page.md"); [[ "$c" == 201 || "$c" == 204 ]] && ok "upload $p-page.md over WebDAV" || bad "PUT $p-page.md got $c"
done
c=$(curl -s -m 10 -o /dev/null -w '%{http_code}' -T "$W/a.md" "$B/dav/ci-c4/sneaky.md"); [ "$c" = 401 ] && ok "an upload with no login is refused" || bad "an upload with no login got $c"
raw=$(curl -s -m 10 "$B/raw/ci-c4/b-page.md")
[ "$raw" = "$(cat "$W/b.md")" ] && ok "the raw page is the file, byte for byte" || bad "raw: $(head -c 120 <<< "$raw")"
ct=$(curl -s -m 10 -o /dev/null -w '%{content_type}' "$B/raw/ci-c4/b-page.md"); [[ "$ct" == text/markdown* ]] && ok "raw is text/markdown" || bad "raw is $ct"
html=$(curl -s -m 10 "$B/ci-c4/b-page.md")
grep -qiE '<h1[^>]*>[^<]*Page B' <<< "$html" && grep -qF "$TAG" <<< "$html" && ok "the rendered page has its heading and text, in HTML" || bad "the rendered page: $(head -c 160 <<< "$html")"
idx=$(curl -s -m 10 "$B/api/files.json")
for p in a b c; do grep -q "ci-c4/$p-page.md" <<< "$idx" || bad "files.json doesn't list ci-c4/$p-page.md"; done
grep -q "ci-c4/b-page.md" <<< "$idx" && ok "files.json lists the uploads"
# order_in <html>: the ci-c4 pages in the order the sidebar links them
order_in() { grep -oE 'ci-c4/[a-c]-page\.md' <<< "$1" | awk '!seen[$0]++' | sed -E 's#ci-c4/([a-c])-page\.md#\1#' | tr -d '\n'; }
[ "$(order_in "$html")" = abc ] && ok "with no .order, the sidebar lists the folder alphabetically" || bad "the sidebar's order is '$(order_in "$html")'"
printf 'c-page.md\na-page.md\nb-page.md\n' > "$W/order"
c=$(dav -T "$W/order" "$B/dav/ci-c4/.order"); [[ "$c" == 201 || "$c" == 204 ]] && ok "set the folder's order with a .order file" || bad "PUT .order got $c"
reordered() { [ "$(order_in "$(curl -s -m 10 "$B/ci-c4/b-page.md")")" = cab ]; }
within 30 reordered && ok "the sidebar follows the new order" || bad "the sidebar's order is '$(order_in "$(curl -s -m 10 "$B/ci-c4/b-page.md")")', not cab"
grep -q '\.order' <<< "$(curl -s -m 10 "$B/api/files.json")" && bad "files.json lists .order" || ok "files.json doesn't list .order"
c=$(dav -X DELETE "$B/dav/ci-c4/a-page.md"); [[ "$c" == 204 || "$c" == 200 ]] && ok "delete a page over WebDAV" || bad "DELETE got $c"
c=$(curl -s -m 10 -o /dev/null -w '%{http_code}' "$B/raw/ci-c4/a-page.md"); [ "$c" = 404 ] && ok "the deleted page is gone" || bad "the deleted page answered $c"
./install-md uninstall > "$W/o" 2>&1 && ok "uninstall" || { bad "uninstall"; tail -6 "$W/o" | cut -c1-170; }
echo "=== exit $fail"; exit $fail
