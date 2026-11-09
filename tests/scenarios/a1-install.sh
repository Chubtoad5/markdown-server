#!/bin/bash
# A1, on a clean host with no route out: install from the bundle the build role made, beside install-md, as
# its README says, then check the site serves and takes an upload.
set -uo pipefail
REPO=$PWD
fail=0
ok()  { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=1; }
# within <seconds> <command...>: true once the command is, checking every 3 seconds
within() { local t=$1 i; shift; for ((i = 0; i < t; i += 3)); do "$@" && return 0; sleep 3; done; "$@"; }
W=$(mktemp -d -p /var/tmp); cd "$W" || exit 1
cp "$REPO/install-md" .; chmod +x install-md
cp "$CI_HANDOFF/md-save.tar.gz" . && ok "put the bundle beside install-md" || { bad "put the bundle beside install-md"; echo "=== exit 1"; exit 1; }
P=Test-Pass-1 B=http://127.0.0.1:8080
export TCP_PORT=8080 MD_ADMIN_PASSWORD=$P
./install-md install > "$W/o" 2>&1 && ok "install with no route out" || { bad "install with no route out"; tail -8 "$W/o" | cut -c1-170; echo "  (the checks after it would only fail too)"; echo "=== exit 1"; exit 1; }
up() { [ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' "$B/")" = 200 ]; }
within 60 up && ok "the site answers" || bad "the site doesn't answer"
printf '# A1\n\nfrom the bundle\n' > page.md
c=$(curl -s -m 10 -o /dev/null -w '%{http_code}' -u "admin:$P" -T page.md "$B/dav/a1-page.md"); [[ "$c" == 201 || "$c" == 204 ]] && ok "upload a page over WebDAV" || bad "upload got $c"
[ "$(curl -s -m 10 "$B/raw/a1-page.md")" = "$(cat page.md)" ] && ok "read it back raw" || bad "the page didn't read back"
./install-md uninstall > "$W/o" 2>&1 && ok "uninstall" || { bad "uninstall"; tail -6 "$W/o" | cut -c1-170; }
echo "=== exit $fail"; exit $fail
