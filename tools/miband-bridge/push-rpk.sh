#!/usr/bin/env bash
# Copy a built .rpk into the emulator's Download folder.
#   ./push-rpk.sh [/path/to/file.rpk]
#
# Default is the newest *release* build. Debug builds are for the emulator only
# - a real band rejects them ("firmware invalid"), so they are never picked
# automatically and are called out loudly if passed explicitly.
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/common.sh"

if [ $# -ge 1 ]; then
  RPK="$1"
else
  RPK="$(ls -t "$REPO/dist/"*release*.rpk 2>/dev/null | head -1)"
  if [ -z "$RPK" ]; then
    echo "No release .rpk in $REPO/dist - run 'npm run release'." >&2
    if ls "$REPO/dist/"*.rpk >/dev/null 2>&1; then
      echo "(There is a debug build there, but a real band will not take it.)" >&2
    fi
    exit 1
  fi
fi
[ -f "$RPK" ] || { echo "Not a file: $RPK" >&2; exit 1; }

case "$(basename "$RPK")" in
  *debug*) echo "WARNING: $(basename "$RPK") is a DEBUG build. Real bands reject" >&2
           echo "         these as invalid; use 'npm run release' instead." >&2 ;;
esac

SER="${SERIAL:-$(find_avd_serial || true)}"
[ -n "$SER" ] || { echo "AVD '$AVD' is not running - start emu.sh." >&2; exit 1; }

if ! avd_storage_ready "$SER"; then
  cat >&2 <<MSG
$SER has no shared storage mounted (/storage/self/primary is missing), so
nothing can be copied into it. This happens when the emulator comes up without
its FUSE volume, typically after a crash.

Fix: close the emulator window and start it again with ./emu.sh, then re-run
this. If it persists, wipe the AVD's data:
    $EMULATOR -avd $AVD -wipe-data
MSG
  exit 1
fi

BASE="$(basename "$RPK")"
STEM="${BASE%.rpk}"

echo "Pushing $BASE to $SER"
# A fresh AVD has no Download dir until something creates it.
"$ADB" -s "$SER" shell mkdir -p /sdcard/Download
# Scoped storage does NOT overwrite: pushing over an existing file lands as
# "name-1.rpk", "name-2.rpk"... and the installer picker then offers several
# builds with no way to tell which is current. Clear this build's old copies
# first - the exact name plus any -N variants of it, nothing else.
"$ADB" -s "$SER" shell "rm -f '/sdcard/Download/$STEM.rpk' /sdcard/Download/'$STEM'-*.rpk" 2>/dev/null || true
"$ADB" -s "$SER" push "$RPK" /sdcard/Download/

# Old pushes linger and the installer picker shows them all, so spell out
# exactly which file to choose.
echo
echo "Install THIS file from the phone's installer app:"
echo "    $(basename "$RPK")"
echo
echo "Everything currently in Download/:"
"$ADB" -s "$SER" shell ls -1 /sdcard/Download/*.rpk 2>/dev/null | sed 's|.*/|    |' || true

# Cheap proof the phone has this exact build and not a leftover.
want="$(md5sum "$RPK" | cut -d" " -f1)"
got="$("$ADB" -s "$SER" shell "md5sum '/sdcard/Download/$BASE'" 2>/dev/null | cut -d" " -f1 | tr -d "\r")"
if [ -n "$got" ] && [ "$want" = "$got" ]; then
  echo
  echo "md5 matches the local build ($want)"
else
  echo
  echo "WARNING: md5 mismatch - phone=[$got] local=[$want]" >&2
fi
