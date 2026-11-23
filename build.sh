#!/usr/bin/env bash
# Build, run, or package the RACE CONTROL watch face.
#   ./build.sh            debug .prg for fr57047mm (or DEVICE=fr57042mm)
#   ./build.sh run        build, then load it into the running simulator
#   ./build.sh test       compile unit tests and run them in the simulator
#   ./build.sh release    optimised .prg (what goes on the watch)
#   ./build.sh package    store-ready .iq for every product in manifest.xml
# Needs CIQ_SDK (Connect IQ SDK root) and CIQ_KEY (developer_key.der).
set -euo pipefail
cd "$(dirname "$0")"
SDK="${CIQ_SDK:?set CIQ_SDK to the Connect IQ SDK directory}"
KEY="${CIQ_KEY:?set CIQ_KEY to your developer_key.der}"
DEVICE="${DEVICE:-fr57047mm}"
mkdir -p bin
case "${1:-build}" in
  build)
    "$SDK/bin/monkeyc" -f monkey.jungle -d "$DEVICE" -y "$KEY" -o "bin/RaceControl-$DEVICE.prg" -w -l 3 ;;
  run)
    "$SDK/bin/monkeyc" -f monkey.jungle -d "$DEVICE" -y "$KEY" -o "bin/RaceControl-$DEVICE.prg" -w -l 3
    "$SDK/bin/monkeydo" "bin/RaceControl-$DEVICE.prg" "$DEVICE" ;;
  test)
    "$SDK/bin/monkeyc" -f monkey.jungle -d "$DEVICE" -y "$KEY" -o bin/RaceControl-test.prg --unit-test -w -l 3
    "$SDK/bin/monkeydo" bin/RaceControl-test.prg "$DEVICE" -t ;;
  release)
    "$SDK/bin/monkeyc" -f monkey.jungle -d "$DEVICE" -y "$KEY" -o "bin/RaceControl-$DEVICE-release.prg" -w -l 3 -r -O 3 ;;
  package)
    "$SDK/bin/monkeyc" -f monkey.jungle -e -r -O 3 -y "$KEY" -o bin/RaceControl.iq -w -l 3 ;;
  *) echo "usage: $0 [build|run|test|release|package]" >&2; exit 2 ;;
esac
