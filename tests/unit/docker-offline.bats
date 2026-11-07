#!/usr/bin/env bats
# Spec 11, U2: the air-gapped install starts Docker, and on Rocky 10's image kernel it says why it can't, and what to do.
load ../helpers
setup() {
  load_script install-md
  setup_stubs
  BASE_DIR=$(mktemp -d)
  MODULES_ROOT=$(mktemp -d)
  mkdir -p "$MODULES_ROOT/6.12.0-211.16.1.el10_2.0.1.x86_64/kernel"
  stub uname 'echo 6.12.0-211.16.1.el10_2.0.1.x86_64'
  stub docker 'exit 0'
  ID=rocky
}
# systemctl that knows docker.service, and says it isn't running
docker_stopped() { stub systemctl 'case "$1" in cat) exit 0 ;; is-active) exit 3 ;; *) exit 0 ;; esac'; }

@test "on Rocky with no xt_addrtype and no other kernel: name the running kernel's package, and stop" {
  docker_stopped
  stub modprobe 'exit 1'
  run ensure_docker_offline
  [ "$status" -eq 1 ]
  [[ "$output" == *"the running kernel (6.12.0-211.16.1.el10_2.0.1.x86_64) doesn't have"* ]]
  [[ "$output" == *"dnf install kernel-modules-extra-6.12.0-211.16.1.el10_2.0.1.x86_64"* ]]
  ! called "systemctl enable"
}
@test "a newer kernel on this host that has the module: say to reboot into it" {
  docker_stopped
  stub modprobe 'exit 1'
  mkdir -p "$MODULES_ROOT/6.12.0-211.74.1.el10_2.x86_64/kernel/net/netfilter"
  touch "$MODULES_ROOT/6.12.0-211.74.1.el10_2.x86_64/kernel/net/netfilter/xt_addrtype.ko.xz"
  run ensure_docker_offline
  [ "$status" -eq 1 ]
  [[ "$output" == *"Kernel 6.12.0-211.74.1.el10_2.x86_64, installed on this host, has it: reboot into it"* ]]
}
@test "with the module, a stopped Docker is started" {
  docker_stopped
  stub modprobe 'exit 0'
  run ensure_docker_offline
  [ "$status" -eq 0 ]
  called "systemctl enable --now docker"
}
@test "a Docker that won't start stops the run, and says where to look" {
  stub systemctl 'case "$1" in cat) exit 0 ;; is-active) exit 3 ;; enable) exit 1 ;; esac'
  stub modprobe 'exit 0'
  run ensure_docker_offline
  [ "$status" -eq 1 ]
  [[ "$output" == *"journalctl -u docker"* ]]
}
@test "a running Docker is left alone" {
  stub systemctl 'case "$1" in cat) exit 0 ;; is-active) exit 0 ;; esac'
  stub modprobe 'exit 1'
  run ensure_docker_offline
  [ "$status" -eq 0 ]
  ! called "systemctl enable"
  ! called "modprobe"
}
@test "Ubuntu is never asked for xt_addrtype" {
  ID=ubuntu
  docker_stopped
  stub modprobe 'exit 1'
  run ensure_docker_offline
  [ "$status" -eq 0 ]
  ! called "modprobe"
  called "systemctl enable --now docker"
}
@test "Docker is installed from the bundle when it's missing" {
  docker_stopped
  stub modprobe 'exit 0'
  stub docker 'exit 0'
  # No docker on PATH until the bundle's install runs
  mv "$STUB_DIR/docker" "$STUB_DIR/docker.later"
  mkdir -p "$BASE_DIR/.offline"; : > "$BASE_DIR/.offline/offline-packages.tar.gz"
  printf '#!/bin/bash\necho "install_packages.sh $*" >> "$STUB_LOG"\nmv "%s/docker.later" "%s/docker"\n' "$STUB_DIR" "$STUB_DIR" > "$BASE_DIR/.offline/install_packages.sh"
  chmod +x "$BASE_DIR/.offline/install_packages.sh"
  run ensure_docker_offline
  [ "$status" -eq 0 ]
  called "install_packages.sh offline docker-ce"
  called "systemctl enable --now docker"
}
