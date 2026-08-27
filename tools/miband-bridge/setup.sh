#!/usr/bin/env bash
# Provision everything this rig needs on a fresh machine. Idempotent - re-run
# it any time, including after upgrading bumble (it re-applies the patches).
#
#   ./setup.sh                    venv + bumble + patches + SDK + AVD
#   ./setup.sh --venv-only        just the Python side
#   ./setup.sh --with-gadgetbridge  also fetch + install the Gadgetbridge APK
#
# Nothing here needs root. Downloads land in $MIBAND_HOME and $ANDROID_HOME,
# both outside the repo.
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/common.sh"

VENV_ONLY=0; WITH_GB=0
for a in "$@"; do
  case "$a" in
    --venv-only) VENV_ONLY=1 ;;
    --with-gadgetbridge) WITH_GB=1 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

mkdir -p "$MIBAND_HOME"
echo "==> work dir: $MIBAND_HOME"

# ---------------------------------------------------------------- python side
if [ ! -x "$VENV/bin/python" ]; then
  echo "==> creating venv"
  python3 -m venv "$VENV"
fi
echo "==> installing bumble (the [android] extra is required - it pulls grpcio,"
echo "    without which the android-netsim transport cannot even import)"
"$VENV/bin/pip" -q install --upgrade pip
"$VENV/bin/pip" -q install "bumble[android]"
"$VENV/bin/python" -c "import bumble.transport.android_netsim" \
  || { echo "netsim transport still not importable" >&2; exit 1; }

echo "==> patching bumble for emulator 37.x"
"$VENV/bin/python" "$(dirname "$(readlink -f "$0")")/patch-netsim.py"

[ "$VENV_ONLY" = 1 ] && { echo "Done (venv only)."; exit 0; }

# ------------------------------------------------------------------ java side
# sdkmanager needs JDK 17+. Use the system one if it qualifies, else keep a
# private Temurin in $MIBAND_HOME rather than touching system packages.
need_jdk=1
if command -v java >/dev/null 2>&1; then
  v=$(java -version 2>&1 | head -1 | grep -oE '[0-9]+' | head -1)
  [ "${v:-0}" -ge 17 ] 2>/dev/null && { need_jdk=0; export JAVA_HOME="${JAVA_HOME:-}"; }
fi
if [ "$need_jdk" = 1 ]; then
  if [ ! -x "$MIBAND_HOME/jdk/bin/java" ]; then
    echo "==> system Java is missing or <17; fetching a private Temurin 21"
    mkdir -p "$MIBAND_HOME/jdk"
    curl -fsSL -o "$MIBAND_HOME/jdk.tar.gz" \
      "https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jdk/hotspot/normal/eclipse"
    tar xzf "$MIBAND_HOME/jdk.tar.gz" -C "$MIBAND_HOME/jdk" --strip-components=1
    rm -f "$MIBAND_HOME/jdk.tar.gz"
  fi
  export JAVA_HOME="$MIBAND_HOME/jdk"
fi
echo "==> java: $("${JAVA_HOME:+$JAVA_HOME/bin/}java" -version 2>&1 | head -1)"

# ------------------------------------------------------------------- sdk side
SDKMGR="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$SDKMGR" ]; then
  echo "==> installing Android command-line tools"
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  curl -fsSL -o "$ANDROID_HOME/cmdline-tools/cmdline.zip" \
    "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
  ( cd "$ANDROID_HOME/cmdline-tools" \
    && unzip -q -o cmdline.zip && rm -f cmdline.zip \
    && rm -rf latest && mv cmdline-tools latest )
fi

echo "==> installing SDK packages (this is the slow part, ~1.5 GB)"
yes | "$SDKMGR" --licenses >/dev/null 2>&1 || true
"$SDKMGR" platform-tools emulator "platforms;android-$API" "$IMAGE" 2>&1 \
  | grep -viE '^\[=*|^ *$' | tail -5 || true

# ------------------------------------------------------------------------ avd
if "$EMULATOR" -list-avds 2>/dev/null | grep -qx "$AVD"; then
  echo "==> AVD '$AVD' already exists"
else
  echo "==> creating AVD '$AVD'"
  echo no | "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" \
    create avd -n "$AVD" -k "$IMAGE" -d pixel_5 --force >/dev/null
  CFG="$HOME/.android/avd/$AVD.avd/config.ini"
  { echo "hw.ramSize=4096"
    echo "vm.heapSize=576"
    echo "hw.lcd.density=440"
    echo "disk.dataPartition.size=8G"; } >> "$CFG"
fi

# ------------------------------------------------------------- optional: g.b.
if [ "$WITH_GB" = 1 ]; then
  echo "==> fetching Gadgetbridge from F-Droid"
  code=$(curl -fsSL "https://f-droid.org/api/v1/packages/nodomain.freeyourgadget.gadgetbridge" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["suggestedVersionCode"])')
  apk="$MIBAND_HOME/gadgetbridge_$code.apk"
  [ -f "$apk" ] || curl -fsSL -o "$apk" \
    "https://f-droid.org/repo/nodomain.freeyourgadget.gadgetbridge_$code.apk"
  echo "    $apk"
  ser="$(find_avd_serial || true)"
  if [ -n "$ser" ]; then
    "$ADB" -s "$ser" install -r "$apk" | tail -1
  else
    echo "    AVD not running; install later with:"
    echo "    $ADB -s <serial> install -r $apk"
  fi
fi

cat <<MSG

Done. Next:
  ./bt-release.sh     # host Bluetooth goes offline
  ./bridge.sh         # own terminal, leave running
  ./emu.sh            # own terminal, leave running
  ./push-rpk.sh       # after 'npm run release'
  ./bt-restore.sh     # when finished
MSG
