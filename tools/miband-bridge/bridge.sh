#!/usr/bin/env bash
# bumble HCI bridge: netsim (emulator side) <-> the real USB controller.
# Run bt-release.sh first, and leave this running in its own terminal.
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/common.sh"

[ -x "$VENV/bin/python" ] || { echo "No venv - run setup.sh first." >&2; exit 1; }

if dev="$(find_bt_usb 2>/dev/null)" && [ -e "/sys/bus/usb/drivers/btusb/$dev:1.0" ]; then
  echo "WARNING: usb $dev still looks bound to btusb. Run bt-release.sh first." >&2
fi

# hci_bridge logs every HCI packet at INFO, a firehose of nearby BLE
# advertising. Quiet by default; LOGLEVEL=info gets the full trace back.
LEVEL="${LOGLEVEL:-warning}"
echo "Bridging android-netsim:$PORT  <->  usb:0   (log level: $LEVEL)"
echo "Quiet output is normal and means it is working. Leave this running."
echo "The traceback printed on Ctrl+C is expected, not an error."
# sudo strips the environment, so pass the log level through explicitly.
exec sudo env "BUMBLE_LOGLEVEL=$LEVEL" "$VENV/bin/python" -m bumble.apps.hci_bridge \
  "android-netsim:_:${PORT},mode=controller" "usb:0"
