#!/usr/bin/env bash
# Build, test and package smokenot.
#
# The link flags are not optional: the interface calls GTK, cairo and glib
# directly, and mojo resolves those symbols at link time. Mojo compiles inside
# core24 for the snap (the host glibc is newer than the snap base), so the
# same flags are repeated in snap/snapcraft.yaml.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOJO="$ROOT/.venv/bin/mojo"
BUILD="${BUILD_DIR:-$ROOT/build}"
GTK_LINKS=(
  -Xlinker=-lgtk-4
  -Xlinker=-lcairo
  -Xlinker=-lgobject-2.0
  -Xlinker=-lgio-2.0
  -Xlinker=-lglib-2.0
)

quiet() { grep -v "Crashpad" || true; }

build_selftest() {
  echo "==> building the logic tests"
  "$MOJO" build "$ROOT/src/selftest.mojo" -o "$BUILD/selftest" 2>&1 | quiet
}

build_app() {
  echo "==> building the app"
  "$MOJO" build "$ROOT/src/main.mojo" -o "$BUILD/smokenot" "${GTK_LINKS[@]}" 2>&1 | quiet
}

build_probe() {
  echo "==> building the ui probe"
  "$MOJO" build -g1 "$ROOT/src/ui_probe.mojo" -o "$BUILD/ui-probe" "${GTK_LINKS[@]}" 2>&1 | quiet
}

pack_snap() {
  # The snap is built inside core24, which needs LXD and a network to fetch the
  # base image, so it is kept out of the default targets.
  echo "==> packing the snap (needs lxd and a network)"
  (cd "$ROOT" && snapcraft pack)
}

run_probe() {
  # The probe keeps its saved profile in a scratch directory so a run never
  # touches the state of the person running it.
  local home="$BUILD/probe-home"
  rm -rf "$home"
  mkdir -p "$home"
  echo "==> running the ui probe"
  XDG_DATA_HOME="$home" "$BUILD/ui-probe"
}

run_selftest() {
  echo "==> running the logic tests"
  "$BUILD/selftest"
}

case "${1:-all}" in
  test)
    build_selftest
    run_selftest
    ;;
  app)
    build_app
    ;;
  probe)
    build_probe
    run_probe
    ;;
  check)
    build_selftest
    run_selftest
    build_probe
    run_probe
    build_app
    ;;
  all)
    build_selftest
    run_selftest
    build_probe
    run_probe
    build_app
    ;;
  snap)
    pack_snap
    ;;
  clean)
    rm -rf "$BUILD"
    ;;
  *)
    echo "usage: $0 [test|probe|app|check|all|snap|clean]" >&2
    exit 2
    ;;
esac
