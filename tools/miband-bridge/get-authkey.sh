#!/usr/bin/env bash
# Pull the Xiaomi auth key out of the Mi Fitness logs inside the AVD.
# Only needed for the Gadgetbridge route. Mi Fitness must have paired the band
# in the AVD first. No root needed - adb shell can read /sdcard/Android/data.
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/common.sh"

SER="${SERIAL:-$(find_avd_serial)}"
[ -n "$SER" ] || { echo "AVD '$AVD' is not running." >&2; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# The log filename moves between Mi Fitness versions (XiaomiFit.device.log ->
# XiaomiFit.main.log -> Transfer.device.log), so pull the whole log dir.
for pkg in com.xiaomi.wearable com.mi.health; do
  "$ADB" -s "$SER" pull "/sdcard/Android/data/$pkg/files/log" "$TMP/$pkg" >/dev/null 2>&1
done

if [ -z "$(find "$TMP" -type f 2>/dev/null)" ]; then
  echo "No Mi Fitness logs in the AVD."
  echo "  Install Mi Fitness, pair the band, let it sync once."
  echo "  Check: $ADB -s $SER shell ls /sdcard/Android/data/com.xiaomi.wearable/files/log/"
  exit 1
fi

# Field name varies too: authKey (old, often null) / token / encryptKey /
# huamiAuthKey, in both key=value and JSON "key":"value" form.
python3 - "$TMP" <<'PY'
import os, re, sys
pat = re.compile(rb'(?:encryptKey|token|authKey|huamiAuthKey)["\'\s:=]+([0-9a-fA-F]{32})')
keys = {}
for root, _, files in os.walk(sys.argv[1]):
    for f in files:
        try: data = open(os.path.join(root, f), 'rb').read()
        except OSError: continue
        for m in pat.finditer(data):
            keys.setdefault(m.group(1).decode().lower(), set()).add(f)
if not keys:
    print("Logs found, but no 32-hex key in them.")
    print("Open Mi Fitness and let the band connect once - the key is written on connect.")
    sys.exit(1)
print(f"Found {len(keys)} key(s). Enter into Gadgetbridge WITH the 0x prefix:\n")
for k, where in keys.items():
    print(f"    0x{k}    (from {', '.join(sorted(where))})")
print("\nIf several appear, match against the band's MAC on the pairing screen.")
PY
