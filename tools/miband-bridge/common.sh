# Shared settings. Sourced by the other scripts; not meant to be run.
#
# Everything machine-specific is an override, so a new machine needs no edits:
#   MIBAND_HOME   where the venv / JDK / SDK downloads live  (default ~/.local/share/miband-bridge)
#   ANDROID_HOME  Android SDK                                (default ~/Android/Sdk)
#   AVD           emulator name                              (default miband_bridge)
#   PORT          netsim gRPC port                           (default 8554)
#   VID / PID     USB Bluetooth adapter                      (default: auto-detect)

MIBAND_HOME="${MIBAND_HOME:-$HOME/.local/share/miband-bridge}"
ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
AVD="${AVD:-miband_bridge}"
PORT="${PORT:-8554}"
API="${API:-32}"                 # 33/34 are reported flaky for emulator Bluetooth
IMAGE="${IMAGE:-system-images;android-$API;google_apis_playstore;x86_64}"

VENV="$MIBAND_HOME/venv"
ADB="$ANDROID_HOME/platform-tools/adb"
EMULATOR="$ANDROID_HOME/emulator/emulator"

# Repo root, so scripts work from any cwd.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Print the usb device id (e.g. "3-10") of the Bluetooth adapter.
# With VID/PID set, match those; otherwise take whatever btusb currently owns,
# falling back to a USB device whose interface class is Bluetooth (e0/01/01).
find_bt_usb() {
  local d v p
  if [ -n "${VID:-}" ] && [ -n "${PID:-}" ]; then
    for d in /sys/bus/usb/devices/*/; do
      [ -f "$d/idVendor" ] || continue
      v=$(cat "$d/idVendor"); p=$(cat "$d/idProduct")
      [ "$v" = "$VID" ] && [ "$p" = "$PID" ] && { basename "$d"; return 0; }
    done
    return 1
  fi
  # Whatever the kernel driver holds right now.
  for d in /sys/bus/usb/drivers/btusb/*:*; do
    [ -e "$d" ] || continue
    basename "$d" | cut -d: -f1
    return 0
  done
  # Already detached: look for the Bluetooth interface class.
  for d in /sys/bus/usb/devices/*:*/; do
    [ -f "$d/bInterfaceClass" ] || continue
    if [ "$(cat "$d/bInterfaceClass")" = "e0" ] \
    && [ "$(cat "$d/bInterfaceSubClass" 2>/dev/null)" = "01" ] \
    && [ "$(cat "$d/bInterfaceProtocol" 2>/dev/null)" = "01" ]; then
      basename "$d" | cut -d: -f1
      return 0
    fi
  done
  return 1
}

# Serial of the running AVD. The Vela band emulator also answers to adb, so
# never just take the first line of `adb devices`. Deliberately not a pipeline:
# `return` from inside `while read` only exits the subshell, which made this
# return every match instead of the first.
find_avd_serial() {
  local s name
  for s in $("$ADB" devices 2>/dev/null | awk '/emulator-/{print $1}'); do
    name="$("$ADB" -s "$s" emu avd name 2>/dev/null | head -1 | tr -d '\r')"
    [ "$name" = "$AVD" ] && { echo "$s"; return 0; }
  done
  return 1
}

# True if the AVD has shared storage mounted. It sometimes comes up without it
# - notably after the emulator has crashed - and then every /sdcard path fails
# with a misleading "No such file or directory".
avd_storage_ready() {
  "$ADB" -s "$1" shell 'ls -d /storage/self/primary' >/dev/null 2>&1
}
