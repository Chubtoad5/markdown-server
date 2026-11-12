#!/bin/bash
# The real installer on a throwaway host, as root, from the repo root: install, the endpoints from the smoke list, the
# admin login with spec 21's long test password, a re-run that keeps it without restarting Caddy, two refused re-runs
# that leave the site as it was, uninstall.
set -uo pipefail
REPO=$PWD
fail=0
ok()  { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=1; }
W=$(mktemp -d); cd "$W" || exit 1
cp "$REPO/install-md" .; chmod +x install-md
# Spec 21's long test password: 128 characters, with the space and every symbol
P=$(sed -n 's/^long\t//p' "$REPO/tests/password-vectors.txt")
[ "${#P}" -eq 128 ] || bad "the long test password is ${#P} characters, not 128"
export TCP_PORT=8080 MD_ADMIN_PASSWORD="$P"
./install-md install >"$W/o" 2>&1 && ok "install" || { bad "install"; tail -6 "$W/o" | cut -c1-170; }
for _ in $(seq 1 30); do [ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/)" = 200 ] && break; sleep 2; done
for path in / /api/files.json /raw/index.md /llms.txt; do
  code=$(curl -s -m 8 -o /dev/null -w '%{http_code}' "http://127.0.0.1:8080$path"); [ "$code" = 200 ] && ok "$path answers" || bad "$path answered $code"
done
code=$(curl -s -m 8 -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/admin); [ "$code" = 401 ] && ok "/admin needs a login" || bad "/admin answered $code"
# login <password>: what /admin answers to admin and that password, sent as a browser sends it
login() { curl -s -m 8 -o /dev/null -w '%{http_code}' -H "Authorization: Basic $(printf '%s' "admin:$1" | base64 -w0)" http://127.0.0.1:8080/admin; }
code=$(login "$P"); [ "$code" = 200 ] && ok "/admin accepts the long test password" || bad "/admin with the long test password answered $code"
code=$(login changeme); [ "$code" = 401 ] && ok "/admin refuses changeme" || bad "/admin with changeme answered $code"
grep -q '^        basic_auth argon2id {$' /opt/caddy-markdown/Caddyfile && ok "the Caddyfile's login is argon2id" || bad "the Caddyfile's login isn't argon2id"
grep -qF -- "$P" "$W/o" && bad "the install printed the admin password" || ok "the install doesn't print the admin password"
mode=$(stat -c %a "$W/md-install.log"); [ "$mode" = 600 ] && ok "md-install.log is 0600" || bad "md-install.log is $mode"
mode=$(stat -c %a /opt/caddy-markdown/.auth-hash 2>/dev/null); [ "$mode" = 600 ] && ok ".auth-hash is 0600" || bad ".auth-hash is '$mode'"

# A re-run without MD_ADMIN_PASSWORD keeps the login, and leaves Caddy running (spec 21, M3 and Q5)
started() { docker inspect -f '{{.State.StartedAt}}' "$(docker compose -f /opt/caddy-markdown/docker-compose.yml ps -q caddy)" 2>/dev/null; }
s1=$(started)
env -u MD_ADMIN_PASSWORD ./install-md install >"$W/o" 2>&1 && ok "re-run without MD_ADMIN_PASSWORD" || { bad "re-run without MD_ADMIN_PASSWORD"; tail -6 "$W/o" | cut -c1-170; }
code=$(login "$P"); [ "$code" = 200 ] && ok "after the re-run, the long test password still logs in" || bad "after the re-run, the long test password got $code"
code=$(login changeme); [ "$code" = 401 ] && ok "after the re-run, changeme still doesn't" || bad "after the re-run, changeme got $code"
s2=$(started); [[ -n "$s1" && "$s1" == "$s2" ]] && ok "the re-run didn't restart Caddy" || bad "the re-run restarted Caddy ('$s1' -> '$s2')"

# Refused re-runs stop nothing and change nothing (M1, M3): an empty password, and one of 129 characters
MD_ADMIN_PASSWORD='' ./install-md install >"$W/o" 2>&1 && bad "an empty MD_ADMIN_PASSWORD was taken" || ok "an empty MD_ADMIN_PASSWORD is refused"
MD_ADMIN_PASSWORD="${P}x" ./install-md install >"$W/o" 2>&1 && bad "a 129-character password was taken" || ok "a 129-character password is refused"
grep -qF -- "$P" "$W/o" && bad "the refusal printed the password" || ok "the refusal doesn't print the password"
code=$(login "$P"); s3=$(started)
[[ "$code" == 200 && "$s3" == "$s1" ]] && ok "after the refusals the site is up, unrestarted, with its password" || bad "after the refusals: login $code, Caddy started '$s3' (was '$s1')"

./install-md uninstall >"$W/o" 2>&1 && ok "uninstall" || { bad "uninstall"; tail -6 "$W/o" | cut -c1-170; }
echo "=== exit $fail"; exit $fail
