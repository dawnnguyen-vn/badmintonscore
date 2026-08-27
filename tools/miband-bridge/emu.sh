#!/usr/bin/env bash
# Launch the AVD wired to the bumble bridge. Start bridge.sh first.
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/common.sh"

[ -x "$EMULATOR" ] || { echo "No emulator at $EMULATOR - run setup.sh first." >&2; exit 1; }
# NOTE: '-packet-streamer-endpoint default' does NOT work; the emulator never
# opens the gRPC connection unless the host:port is explicit.
exec "$EMULATOR" -avd "$AVD" \
  -packet-streamer-endpoint "localhost:${PORT}" \
  -no-snapshot-load "$@"
