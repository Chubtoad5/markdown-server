#!/bin/bash
# The real installer on a throwaway host, as root, from the repo root: install, the endpoints from the smoke list, uninstall.
set -uo pipefail
REPO=$PWD
fail=0
ok()  { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=1; }
W=$(mktemp -d); cd "$W" || exit 1
cp "$REPO/install-md" .; chmod +x install-md
export TCP_PORT=8080 MD_ADMIN_PASSWORD=Test-Pass-1
./install-md install >"$W/o" 2>&1 && ok "install" || { bad "install"; tail -6 "$W/o" | cut -c1-170; }
for _ in $(seq 1 30); do [ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/)" = 200 ] && break; sleep 2; done
for path in / /api/files.json /raw/index.md /llms.txt; do
  code=$(curl -s -m 8 -o /dev/null -w '%{http_code}' "http://127.0.0.1:8080$path"); [ "$code" = 200 ] && ok "$path answers" || bad "$path answered $code"
done
code=$(curl -s -m 8 -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/admin); [ "$code" = 401 ] && ok "/admin needs a login" || bad "/admin answered $code"
code=$(curl -s -m 8 -o /dev/null -w '%{http_code}' -u "admin:$MD_ADMIN_PASSWORD" http://127.0.0.1:8080/admin); [ "$code" = 200 ] && ok "/admin accepts the login" || bad "/admin with a login answered $code"
./install-md uninstall >"$W/o" 2>&1 && ok "uninstall" || { bad "uninstall"; tail -6 "$W/o" | cut -c1-170; }
echo "=== exit $fail"; exit $fail
