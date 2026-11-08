#!/usr/bin/env bats
# Spec 14, live test 2: this test fails on purpose, so the lab goes red and both ship.sh and the ruleset must stop the
# merge. The next commit on this branch removes this file.
@test "live test 2 (spec 14): fails on purpose, so nothing may merge" {
  false
}
