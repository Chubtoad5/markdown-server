#!/usr/bin/env bats
# Spec 15, Q9: the save bundle's LICENSES/ lists what it redistributes and carries a written offer for the GPL and LGPL parts.
load ../helpers
setup() {
  load_script install-md
  D=$(mktemp -d)
  LICENSE_OFFER_CONTACT=me@example.invalid CADDY_VERSION=2.11.3
}
@test "the manifest names the image's parts and the bundle's OS packages, and the offer names the contact" {
  s=$(mktemp -d); mkdir -p "$s/offline-packages"; touch "$s/offline-packages/docker-29.7.2_ce-160000.8.1.x86_64.rpm" "$s/offline-packages/container-selinux-2.239.0-160000.3.1.noarch.rpm"
  tar -czf "$D/offline-packages.tar.gz" -C "$s" offline-packages
  generate_bundle_licenses "$D"
  N="$D/LICENSES/THIRD_PARTY_NOTICES.txt"
  grep -q "^  docker-29.7.2_ce-160000.8.1.x86_64.rpm$" "$N"
  grep -q "^  container-selinux-2.239.0-160000.3.1.noarch.rpm$" "$N"
  grep -q "built from caddy:2.11.3" "$N"
  grep -q "BusyBox (GPL-2.0)" "$N"
  grep -q "highlight.js 11.8.0" "$N"
  grep -q "contact: me@example.invalid" "$D/LICENSES/WRITTEN_OFFER.txt"
}
@test "with no package archive (a failed Docker save), both files are still written" {
  generate_bundle_licenses "$D"
  grep -q "^  (none)$" "$D/LICENSES/THIRD_PARTY_NOTICES.txt"
  [ -s "$D/LICENSES/WRITTEN_OFFER.txt" ]
}
@test "save writes LICENSES into the stage it archives" {
  sed -n '/^do_save() {/,/^}/p' "$BATS_TEST_DIRNAME/../../install-md" | grep -q 'generate_bundle_licenses "$stage"'
}
@test "with CADDY_VERSION=latest, the notice records the image's own version label" {
  CADDY_VERSION=latest
  setup_stubs
  stub docker 'echo 2.11.3'
  generate_bundle_licenses "$D"
  grep -q "built from caddy:latest (Caddy 2.11.3)" "$D/LICENSES/THIRD_PARTY_NOTICES.txt"
  ! grep -q "inside the image\\.$" "$D/LICENSES/THIRD_PARTY_NOTICES.txt"
}
@test "save keeps Docker in the bundle when the kernel package can't be saved" {
  sed -n '/^do_save() {/,/^}/p' "$BATS_TEST_DIRNAME/../../install-md" | grep -q 'elif \[\[ -n "$extra" \]\] && ( cd "$stage" && ./install_packages.sh save "${pkgs\[@\]}" )'
}
