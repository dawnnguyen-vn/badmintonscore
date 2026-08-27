#!/usr/bin/env bash
# Give the Bluetooth adapter back to the kernel (undoes bt-release.sh).
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/common.sh"

dev="$(find_bt_usb)" || { echo "No USB Bluetooth adapter found." >&2; exit 1; }
echo "Rebinding usb $dev to btusb..."
for i in /sys/bus/usb/devices/"$dev":*; do
  [ -e "$i" ] || continue
  n="$(basename "$i")"
  if [ -e "/sys/bus/usb/drivers/btusb/$n" ]; then echo "  $n already bound"; continue; fi
  echo -n "$n" | sudo tee /sys/bus/usb/drivers/btusb/bind >/dev/null 2>&1 \
    && echo "  bound $n" || echo "  skipped $n"
done
sleep 1
rfkill unblock bluetooth 2>/dev/null || true
echo "Done. Check with: bluetoothctl list"
