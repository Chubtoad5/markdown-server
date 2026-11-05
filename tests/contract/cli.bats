#!/usr/bin/env bats
SCRIPT="$BATS_TEST_DIRNAME/../../install-md"
@test "version needs no root" {
  run su -s /bin/bash nobody -c "bash '$SCRIPT' version"
  [ "$status" -eq 0 ]
}
@test "help lists the commands" {
  run "$SCRIPT" help
  [ "$status" -eq 0 ]
  for c in install save uninstall; do [[ "$output" == *"$c"* ]]; done
}
@test "the sentinel's name stays the same" {
  grep -q 'OFFLINE_SENTINEL="md-save.tar.gz"' "$SCRIPT"
}
