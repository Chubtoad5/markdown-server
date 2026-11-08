#!/usr/bin/env bats
# Spec 14: image_pull_push.sh and install_packages.sh come from releases, not main. A copy is reused only when its .ref
# record matches, an install from the offline bundle never downloads, and one INSTALL_PACKAGES_REF covers both helpers.
load ../helpers

setup() {
  unset IMAGE_PULL_PUSH_REF IMAGE_PULL_PUSH_URL IMAGE_PULL_PUSH_SHA256 IPP_URL INSTALL_PACKAGES_REF INSTALL_PACKAGES_URL INSTALL_PACKAGES_SHA256
  load_script install-md
  setup_stubs
  BASE_DIR=$BATS_TEST_TMPDIR/b
  U=$BASE_DIR/utilities
  MD_OFFLINE=0
  # A curl that writes a small script to its -o path
  stub curl 'out=""; prev=""; for a in "$@"; do [ "$prev" = "-o" ] && out=$a; prev=$a; done
printf "#!/bin/bash\necho helper\n" > "$out"'
}
helper_sha() { printf '#!/bin/bash\necho helper\n' | sha256sum | cut -d' ' -f1; }
ipp() { helper_check image_pull_push.sh "$IMAGE_PULL_PUSH_URL" "$IMAGE_PULL_PUSH_REF" "$IMAGE_PULL_PUSH_SHA256"; }
ip() { helper_check install_packages.sh "$INSTALL_PACKAGES_URL" "$INSTALL_PACKAGES_REF" "$INSTALL_PACKAGES_SHA256"; }

@test "image_pull_push.sh comes from images-pull-push v1.1.1, by tag" {
  run ensure_ipp
  [ "$status" -eq 0 ]
  called "curl -fsSL https://raw.githubusercontent.com/Chubtoad5/images-pull-push/v1.1.1/image_pull_push.sh"
  [ -x "$U/image_pull_push.sh" ]
  [ "$(cat "$U/.image_pull_push.sh.ref")" = v1.1.1 ]
}
@test "install_packages.sh comes from install-packages v1.1.2, by tag" {
  run ip
  [ "$status" -eq 0 ]
  called "curl -fsSL https://raw.githubusercontent.com/Chubtoad5/install-packages/v1.1.2/install_packages.sh"
  [ "$(cat "$U/.install_packages.sh.ref")" = v1.1.2 ]
}
@test "the refs set the URLs" {
  unset IMAGE_PULL_PUSH_URL IPP_URL INSTALL_PACKAGES_URL
  export IMAGE_PULL_PUSH_REF=v9.9.9 INSTALL_PACKAGES_REF=v8.8.8
  load_script install-md
  [ "$IMAGE_PULL_PUSH_URL" = "https://raw.githubusercontent.com/Chubtoad5/images-pull-push/v9.9.9/image_pull_push.sh" ]
  [ "$INSTALL_PACKAGES_URL" = "https://raw.githubusercontent.com/Chubtoad5/install-packages/v8.8.8/install_packages.sh" ]
}
@test "IPP_URL still works, as an alias, and IMAGE_PULL_PUSH_URL wins over it" {
  unset IMAGE_PULL_PUSH_URL
  export IPP_URL=https://mirror.example/old-name.sh
  load_script install-md
  [ "$IMAGE_PULL_PUSH_URL" = https://mirror.example/old-name.sh ]
  export IMAGE_PULL_PUSH_URL=https://mirror.example/new-name.sh
  load_script install-md
  [ "$IMAGE_PULL_PUSH_URL" = https://mirror.example/new-name.sh ]
  [ "$IPP_URL" = https://mirror.example/new-name.sh ]
}
@test "INSTALL_PACKAGES_REF is exported, so image_pull_push.sh fetches the same install_packages.sh" {
  run bash -c 'echo "$INSTALL_PACKAGES_REF"'
  [ "$output" = v1.1.2 ]
}
@test "a copy whose record names the same ref is reused" {
  ipp >/dev/null
  : > "$STUB_LOG"
  run ipp
  [ "$status" -eq 0 ]
  ! called curl || false
}
@test "a copy with no record, as main used to leave, or from another ref, is fetched again" {
  mkdir -p "$U"
  echo old > "$U/image_pull_push.sh"
  echo old > "$U/install_packages.sh"; echo main > "$U/.install_packages.sh.ref"
  ipp >/dev/null
  ip >/dev/null
  grep -q "echo helper" "$U/image_pull_push.sh"
  grep -q "echo helper" "$U/install_packages.sh"
  [ "$(cat "$U/.install_packages.sh.ref")" = v1.1.2 ]
}
@test "a matching checksum passes, and a mismatch stops and leaves no file" {
  INSTALL_PACKAGES_SHA256=$(helper_sha)
  run ip
  [ "$status" -eq 0 ]
  IMAGE_PULL_PUSH_SHA256=$(printf '0%.0s' {1..64})
  run ipp
  [ "$status" -eq 1 ]
  [[ "$output" == *"doesn't match its checksum"* ]]
  [ ! -e "$U/image_pull_push.sh" ]
  [ ! -e "$U/image_pull_push.sh.tmp" ]
}
@test "a failed download stops, and leaves no file behind" {
  stub curl 'exit 22'
  run ip
  [ "$status" -eq 1 ]
  [[ "$output" == *"couldn't fetch install_packages.sh"* ]]
  [ ! -e "$U/install_packages.sh" ]
}
@test "installing from the offline bundle uses the copy there, and never downloads" {
  MD_OFFLINE=1
  mkdir -p "$U"
  echo bundled > "$U/image_pull_push.sh"
  run ipp
  [ "$status" -eq 0 ]
  ! called curl || false
  [ "$(cat "$U/image_pull_push.sh")" = bundled ]
}
@test "installing from the offline bundle with no copy stops, and never downloads" {
  MD_OFFLINE=1
  run ipp
  [ "$status" -eq 1 ]
  [[ "$output" == *"Nothing is downloaded offline"* ]]
  ! called curl || false
}
@test "the offline install sets the flag; save never does" {
  grep -A4 'if is_offline; then' "$BATS_TEST_DIRNAME/../../install-md" | grep -q 'MD_OFFLINE=1'
  ! declare -f do_save | grep -q 'MD_OFFLINE=1' || false
}
@test "nothing fetches a helper from main any more" {
  ! grep -nE '(images-pull-push|install-packages)/raw/refs/heads/main' "$BATS_TEST_DIRNAME/../../install-md" || false
}
