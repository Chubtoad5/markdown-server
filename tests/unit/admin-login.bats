#!/usr/bin/env bats
# Spec 21, M1-M4: the admin login. The whole install runs with Docker stubbed: the stub records what reaches Caddy's
# hash-password on stdin, answers with a hash made from it, and keeps track of whether the stack is running.
# Each of spec 21's test passwords goes through every place the password goes (the hash step's stdin, the Caddyfile,
# the fingerprint), and the bytes that arrive are compared.
load ../helpers
load ../vectors
SCRIPT="$BATS_TEST_DIRNAME/../../install-md"

# The docker stub. compose: `port` answers while the stack runs on that port, `up` starts it on $TCP_PORT, `down`
# stops it. run: hash-password reads stdin when it has -i (otherwise it takes its arguments) and prints a hash made from
# that, argon2id when asked for it, else bcrypt. OLD_CADDY=1 plays a Caddy older than 2.11, which has no argon2id, and
# HASH_FAILS=1 one whose hashing fails.
DOCKER_STUB='D=${STUB_LOG%/*}
case "$1" in
  compose)
    shift; [[ "$1" == -f ]] && shift 2
    case "$1" in
      port) [[ -f "$D/running" && "$(cat "$D/running")" == "$3" ]] && echo "0.0.0.0:$3" ;;
      up) echo "$TCP_PORT" > "$D/running" ;;
      down) rm -f "$D/running" ;;
    esac ;;
  run)
    if [[ " $* " == *" --help "* ]]; then
      if [[ -n "$OLD_CADDY" ]]; then echo "currently only supports bcrypt"; else echo "argon2id bcrypt"; fi
      exit 0
    fi
    [[ -z "$HASH_FAILS" ]] || { echo "Error: hashing failed" >&2; exit 1; }
    if [[ " $* " == *" -i "* ]]; then cat > "$D/hash.stdin"; in=$(cat "$D/hash.stdin"); else in="$*"; fi
    if [[ " $* " == *" --algorithm argon2id "* ]]; then
      [[ -z "$OLD_CADDY" ]] || { echo "Error: unrecognized hash algorithm: argon2id" >&2; exit 1; }
      pfx="\$argon2id\$v=19\$m=47104,t=1,p=1\$c2FsdHNhbHRzYWx0\$"
    else
      pfx="\$2a\$14\$"
    fi
    printf "%s%s\n" "$pfx" "$(printf "%s" "$in" | sha256sum | cut -c1-43)" | tee "$D/hash.out" ;;
esac
exit 0'

setup() {
  setup_stubs
  load_vectors
  cd "$BATS_TEST_TMPDIR"
  export MGMT_IP=127.0.0.1 FQDN=md.example.test TCP_PORT=8080
  unset MD_ADMIN_USER MD_ADMIN_PASSWORD AUTH_MODE ENABLE_WEBDAV MD_RESET OLD_CADDY HASH_FAILS
  new_base main
  stub docker "$DOCKER_STUB"
  stub ss 'exit 0'
}
# new_base <name>: a fresh install directory, with the vendored assets in place so nothing is downloaded
new_base() {
  export BASE_DIR="$BATS_TEST_TMPDIR/base-$1"
  mkdir -p "$BASE_DIR/assets"
  : > "$BASE_DIR/assets/github-markdown-dark.min.css"
}
install_md() { : > "$STUB_LOG"; rm -f "$STUB_DIR/hash.stdin" "$STUB_DIR/hash.out"; run "$SCRIPT" install; echo "$output"; }
hashed() { grep -q 'hash-password' "$STUB_LOG"; }
# stopped: the run took the stack down (docker compose -f <file> down)
stopped() { grep -qE '^docker compose .* down$' "$STUB_LOG"; }
# line_of <pattern>: the line of the stub log where it first appears
line_of() { grep -nE -m1 -- "$1" "$STUB_LOG" | cut -d: -f1; }
# fingerprint_of <hash> <password>: the fingerprint .auth-hash should hold, worked out by Python from the bytes
fingerprint_of() {
  printf '%s' "$2" > "$BATS_TEST_TMPDIR/pw"
  python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.argv[1].encode() + b":" + open(sys.argv[2], "rb").read()).hexdigest())' \
    "$1" "$BATS_TEST_TMPDIR/pw"
}
stored() { sed -n "s/^$1=//p" "$BASE_DIR/.auth-hash"; }
# The account line in both auth-gated handles, and nothing else that looks like one
account_lines() { grep -cxF "            $1 $2" "$BASE_DIR/Caddyfile"; }

@test "M1: every test password reaches hash-password on stdin, byte for byte, with argon2id and never as an argument" {
  local n i=0 pw
  for n in "${VEC_NAMES[@]}"; do
    echo "vector: $n"
    i=$((i + 1)); new_base "v$i"
    pw=${VEC[$n]}
    export MD_ADMIN_PASSWORD="$pw"
    install_md
    [ "$status" -eq 0 ]
    # <<< or printf '%s\n' adds one newline, which Caddy drops
    cmp <(printf '%s\n' "$pw") "$STUB_DIR/hash.stdin"
    called 'caddy hash-password --algorithm argon2id'
    ! called '--plaintext' || false
    if [ "${#pw}" -ge 8 ]; then ! grep -qF -- "$pw" "$STUB_LOG" || false; fi
  done
}

@test "M1, Q5: for every test password the Caddyfile names argon2id and holds the hash, and .auth-hash ties the hash to the password" {
  local n i=0 pw h
  for n in "${VEC_NAMES[@]}"; do
    echo "vector: $n"
    i=$((i + 1)); new_base "c$i"
    pw=${VEC[$n]}
    export MD_ADMIN_PASSWORD="$pw"
    install_md
    [ "$status" -eq 0 ]
    h=$(cat "$STUB_DIR/hash.out")
    [ "$(grep -cx '        basic_auth argon2id {' "$BASE_DIR/Caddyfile")" -eq 2 ]
    [ "$(account_lines admin "$h")" -eq 2 ]
    [ "$(stored user)" = admin ]
    [ "$(stored hash)" = "$h" ]
    [ "$(stored fingerprint)" = "$(fingerprint_of "$h" "$pw")" ]
    [ "$(stat -c %a "$BASE_DIR/.auth-hash")" = 600 ]
    if [ "${#pw}" -ge 8 ]; then
      ! grep -qF -- "$pw" "$BASE_DIR/Caddyfile" || false
      ! grep -qF -- "$pw" "$BASE_DIR/.auth-hash" || false
    fi
  done
}

@test "Q5: for every test password, a re-run with the same password keeps the hash and doesn't restart Caddy" {
  local n i=0
  for n in "${VEC_NAMES[@]}"; do
    echo "vector: $n"
    i=$((i + 1)); new_base "r$i"
    export MD_ADMIN_PASSWORD="${VEC[$n]}"
    install_md
    [ "$status" -eq 0 ]
    cp "$BASE_DIR/Caddyfile" "$BATS_TEST_TMPDIR/Caddyfile.before"
    install_md
    [ "$status" -eq 0 ]
    ! hashed || false
    cmp "$BATS_TEST_TMPDIR/Caddyfile.before" "$BASE_DIR/Caddyfile"
    ! stopped || false
    ! called '--force-recreate' || false
    called 'compose up -d'
  done
}

@test "Q5: a changed password is hashed again, and only then is Caddy restarted" {
  export MD_ADMIN_PASSWORD='Aa1 first pass'
  install_md
  local h1; h1=$(stored hash)
  export MD_ADMIN_PASSWORD='Aa1 second pass'
  install_md
  [ "$status" -eq 0 ]
  cmp <(printf '%s\n' 'Aa1 second pass') "$STUB_DIR/hash.stdin"
  [ "$(stored hash)" != "$h1" ]
  [ "$(stored fingerprint)" = "$(fingerprint_of "$(stored hash)" 'Aa1 second pass')" ]
  called 'compose up -d --force-recreate'
  ! stopped || false
}

@test "M3: a re-run with MD_ADMIN_PASSWORD unset keeps the stored login, and the banner says so" {
  export MD_ADMIN_PASSWORD='Aa1 kept pass'
  install_md
  cp "$BASE_DIR/Caddyfile" "$BATS_TEST_TMPDIR/Caddyfile.before"
  local h; h=$(stored hash)
  unset MD_ADMIN_PASSWORD
  install_md
  [ "$status" -eq 0 ]
  ! hashed || false
  cmp "$BATS_TEST_TMPDIR/Caddyfile.before" "$BASE_DIR/Caddyfile"
  [ "$(stored hash)" = "$h" ]
  [ "$(stored fingerprint)" = "$(fingerprint_of "$h" 'Aa1 kept pass')" ]
  [[ "$output" == *"password: unchanged"* ]]
  ! called '--force-recreate' || false
}

@test "M3: an empty MD_ADMIN_PASSWORD is refused, before anything is stopped or changed" {
  export MD_ADMIN_PASSWORD='Aa1 kept pass'
  install_md
  cp "$BASE_DIR/Caddyfile" "$BATS_TEST_TMPDIR/Caddyfile.before"
  export MD_ADMIN_PASSWORD=
  install_md
  [ "$status" -eq 1 ]
  [[ "$output" == *"MD_ADMIN_PASSWORD is set but empty"* ]]
  ! called docker || false
  cmp "$BATS_TEST_TMPDIR/Caddyfile.before" "$BASE_DIR/Caddyfile"
  [ "$(stored fingerprint)" = "$(fingerprint_of "$(stored hash)" 'Aa1 kept pass')" ]
}

@test "M3: a first install with no password gets changeme, and the banner says to change it" {
  install_md
  [ "$status" -eq 0 ]
  cmp <(printf '%s\n' changeme) "$STUB_DIR/hash.stdin"
  [[ "$output" == *"password: the default, changeme"*"set MD_ADMIN_PASSWORD to change it"* ]]
  # A re-run that still doesn't set one keeps it, and still says it's the default
  install_md
  [ "$status" -eq 0 ]
  ! hashed || false
  [[ "$output" == *"password: the default, changeme"* ]]
}

@test "rule 7: a control character, or more than 128 characters, is refused before anything is stopped, and never shown" {
  export MD_ADMIN_PASSWORD='Aa1 kept pass'
  install_md
  cp "$BASE_DIR/Caddyfile" "$BATS_TEST_TMPDIR/Caddyfile.before"
  local pw long=${VEC[long]}
  for pw in $'Aa1\tpass' $'Aa1\npass' $'Aa1pass\r' $'Aa1\x7fpass' $'\e[0mAa1pass'; do
    export MD_ADMIN_PASSWORD="$pw"
    install_md
    [ "$status" -eq 1 ]
    [[ "$output" == *"MD_ADMIN_PASSWORD can't contain a control character"* ]]
    [[ "$output" != *"$pw"* ]]
    ! called docker || false
  done
  export MD_ADMIN_PASSWORD="${long}x"
  install_md
  [ "$status" -eq 1 ]
  [[ "$output" == *"MD_ADMIN_PASSWORD can't be longer than 128 characters"* ]]
  [[ "$output" != *"$long"* ]]
  ! called docker || false
  cmp "$BATS_TEST_TMPDIR/Caddyfile.before" "$BASE_DIR/Caddyfile"
}

@test "M2: an admin user name is letters, digits and . _ @ + -, each one a plain Caddyfile token" {
  local u i=0
  export MD_ADMIN_PASSWORD='Aa1 user pass'
  for u in admin a.b_c@d+e-f @admin -admin +x user@example.com Admin2; do
    i=$((i + 1)); new_base "u$i"
    export MD_ADMIN_USER="$u"
    install_md
    [ "$status" -eq 0 ]
    [ "$(account_lines "$u" "$(cat "$STUB_DIR/hash.out")")" -eq 2 ]
  done
}

@test "M2: any other user name is refused, naming MD_ADMIN_USER, before anything is stopped" {
  local u
  export MD_ADMIN_PASSWORD='Aa1 user pass'
  install_md
  cp "$BASE_DIR/Caddyfile" "$BATS_TEST_TMPDIR/Caddyfile.before"
  for u in 'ad min' ' admin' '#admin' '{$HOME}' '{admin}' 'ad:min' 'ad"min' "ad'min" 'ad\min' 'ad/min' 'ad*min' $'ad\tmin' 'adé'; do
    export MD_ADMIN_USER="$u"
    install_md
    [ "$status" -eq 1 ]
    [[ "$output" == *"MD_ADMIN_USER can only have letters, digits and . _ @ + -"* ]]
    ! called docker || false
  done
  cmp "$BATS_TEST_TMPDIR/Caddyfile.before" "$BASE_DIR/Caddyfile"
}

@test "a bad user name and a bad password are both reported, in one run" {
  export MD_ADMIN_USER='ad min' MD_ADMIN_PASSWORD=
  install_md
  [ "$status" -eq 1 ]
  [[ "$output" == *"MD_ADMIN_USER can only have"* ]]
  [[ "$output" == *"MD_ADMIN_PASSWORD is set but empty"* ]]
}

@test "a re-run with no MD_ADMIN_USER keeps the stored user too" {
  export MD_ADMIN_USER=editor MD_ADMIN_PASSWORD='Aa1 user pass'
  install_md
  unset MD_ADMIN_USER MD_ADMIN_PASSWORD
  install_md
  [ "$status" -eq 0 ]
  [ "$(stored user)" = editor ]
  [ "$(account_lines editor "$(stored hash)")" -eq 2 ]
}

@test "Q5: an install by v1.6.1 keeps its bcrypt hash and its Caddyfile until the password changes" {
  # v1.6.1's Caddyfile: the same text, with 'basic_auth {' and a bcrypt hash, and no .auth-hash
  local old='$2a$14$N6TJhAPreEyINXtAVFarwuE4En3yCmJ0CTsGt1RavZC47kG738u2W'
  cat > "$BATS_TEST_TMPDIR/gen.sh" <<'GEN'
source "$1"
MD_ADMIN_USER=admin ADMIN_HASH=$2
generate_caddyfile > /dev/null
GEN
  bash "$BATS_TEST_TMPDIR/gen.sh" "$SCRIPT" "$old"
  [ "$(grep -cx '        basic_auth {' "$BASE_DIR/Caddyfile")" -eq 2 ]
  [ "$(account_lines admin "$old")" -eq 2 ]
  cp "$BASE_DIR/Caddyfile" "$BATS_TEST_TMPDIR/Caddyfile.before"
  : > "$BASE_DIR/docker-compose.yml"
  echo 8080 > "$STUB_DIR/running"
  install_md
  [ "$status" -eq 0 ]
  ! hashed || false
  cmp "$BATS_TEST_TMPDIR/Caddyfile.before" "$BASE_DIR/Caddyfile"
  ! called '--force-recreate' || false
  [ "$(stored hash)" = "$old" ]
  [ -z "$(stored fingerprint)" ]
  [ "$(stat -c %a "$BASE_DIR/.auth-hash")" = 600 ]
  # A password, even the same one, can't be checked against the old hash, so it's hashed again, with argon2id
  export MD_ADMIN_PASSWORD='Test-Pass-1'
  install_md
  [ "$status" -eq 0 ]
  cmp <(printf '%s\n' 'Test-Pass-1') "$STUB_DIR/hash.stdin"
  [ "$(grep -cx '        basic_auth argon2id {' "$BASE_DIR/Caddyfile")" -eq 2 ]
  called 'compose up -d --force-recreate'
}

@test "a stored login that can't be read is refused when no password is given, and replaced when one is" {
  mkdir -p "$BASE_DIR"
  printf 'user=admin\nhash=not-a-hash\nfingerprint=\n' > "$BASE_DIR/.auth-hash"
  install_md
  [ "$status" -eq 1 ]
  [[ "$output" == *"can't be read. Set MD_ADMIN_PASSWORD"* ]]
  ! called docker || false
  export MD_ADMIN_PASSWORD='Aa1 new pass'
  install_md
  [ "$status" -eq 0 ]
  [[ "$(stored hash)" == '$argon2id$'* ]]
}

@test "M1: the running site stays up while the image is built and the password hashed, so a failed hash leaves it up" {
  export MD_ADMIN_PASSWORD='Aa1 first pass'
  install_md
  export MD_ADMIN_PASSWORD='Aa1 second pass' HASH_FAILS=1
  install_md
  [ "$status" -eq 1 ]
  ! stopped || false
  [ -f "$STUB_DIR/running" ]
  [[ "$output" == *"couldn't hash the admin password"* ]]
}

@test "a stack on another port, or MD_RESET=true, is stopped only once the image and the hash are ready" {
  export MD_ADMIN_PASSWORD='Aa1 first pass'
  install_md
  export TCP_PORT=8081 MD_ADMIN_PASSWORD='Aa1 second pass'
  install_md
  [ "$status" -eq 0 ]
  called 'ss -ltnH'
  stopped
  [ "$(line_of 'hash-password')" -lt "$(line_of ' down$')" ]
  [ "$(line_of '^docker build')" -lt "$(line_of ' down$')" ]
  [ "$(cat "$STUB_DIR/running")" = 8081 ]
  export MD_RESET=true
  install_md
  [ "$status" -eq 0 ]
  stopped
  ! called '--force-recreate' || false
}

@test "a Caddy older than 2.11 hashes with bcrypt, from stdin; a password over 72 bytes is then refused with the site up" {
  export OLD_CADDY=1 MD_ADMIN_PASSWORD='Aa1 old caddy'
  install_md
  [ "$status" -eq 0 ]
  [[ "$output" == *"older than 2.11"* ]]
  cmp <(printf '%s\n' 'Aa1 old caddy') "$STUB_DIR/hash.stdin"
  [ "$(grep -cx '        basic_auth {' "$BASE_DIR/Caddyfile")" -eq 2 ]
  [[ "$(stored hash)" == '$2a$'* ]]
  export MD_ADMIN_PASSWORD="${VEC[long]}"
  install_md
  [ "$status" -eq 1 ]
  [[ "$output" == *"MD_ADMIN_PASSWORD is over 72 bytes"* ]]
  ! stopped || false
  ! called '--force-recreate' || false
}

@test "M4: the banner names MD_ADMIN_PASSWORD, never the password, and md-install.log is 0600, even an older one" {
  ( umask 022; echo old > md-install.log )
  export MD_ADMIN_PASSWORD="${VEC[full]}"
  install_md
  [ "$status" -eq 0 ]
  [[ "$output" == *"password: the one in MD_ADMIN_PASSWORD"* ]]
  [[ "$output" != *"${VEC[full]}"* ]]
  [ "$(stat -c %a md-install.log)" = 600 ]
  ! grep -qF -- "${VEC[full]}" md-install.log || false
  chmod 644 md-install.log
  run "$SCRIPT" uninstall
  [ "$status" -eq 0 ]
  [ "$(stat -c %a md-install.log)" = 600 ]
}
