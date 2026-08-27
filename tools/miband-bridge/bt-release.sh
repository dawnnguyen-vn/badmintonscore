#!/usr/bin/env bash
# Detach the USB Bluetooth adapter from the kernel btusb driver so bumble can
# claim it through libusb. THE HOST LOSES BLUETOOTH until bt-restore.sh.
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/common.sh"

dev="$(find_bt_usb)" || { echo "No USB Bluetooth adapter found. Set VID/PID to force one." >&2; exit 1; }

# Collect interface names first: btusb claims both interfaces as one device, so
# unbinding :1.0 detaches :1.1 too and the glob stops matching mid-loop.
ifaces=()
for i in /sys/bus/usb/drivers/btusb/"$dev":*; do
  [ -e "$i" ] && ifaces+=("$(basename "$i")")
done
if [ ${#ifaces[@]} -eq 0 ]; then
  echo "usb $dev is already detached from btusb - nothing to do."
  exit 0
fi

echo "Releasing usb $dev from btusb..."
for n in "${ifaces[@]}"; do
  if [ ! -e "/sys/bus/usb/drivers/btusb/$n" ]; then
    echo "  $n already released"; continue
  fi
  if echo -n "$n" | sudo tee /sys/bus/usb/drivers/btusb/unbind >/dev/null 2>&1; then
    echo "  unbound $n"
  else
    echo "  $n already released"
  fi
done
echo "Done. Host Bluetooth is offline; bt-restore.sh gives it back."
