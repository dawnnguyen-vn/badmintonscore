# Bluetooth-capable Android emulator on Linux

An Android emulator with **real Bluetooth**, talking to physical devices through
the laptop's own adapter. Built to sideload `.rpk` quick apps onto a Xiaomi Smart
Band 10 without an Android phone, but the emulator recipe is general-purpose.

Status: **working.** Verified 2026-08-27 — Bluetooth turns on inside the emulator
with no error and HCI flows over the bridge.

## The chain

    Android app (in the emulator)
      -> Android Bluetooth host stack
      -> netsim / Rootcanal            gRPC on localhost:8554
      -> bumble hci_bridge             Python, needs 2 patches (see below)
      -> Intel BE200  8087:0036        the laptop's real adapter, via libusb
      -> the physical device

## Two non-obvious things that make or break it

**1. Bumble needs patching.** bumble 0.0.233 does not work with emulator 37.x
out of the box. Two independent bugs, the second hidden behind the first:

- _Wire format._ Emulator ~37+ sends raw H4 frames in `PacketRequest.packet`.
  Bumble only accepted the structured `PacketRequest.hci_packet` and answered
  everything with `Unexpected request type`. Both fields already exist in
  bumble's bundled proto; only the handler was stuck on the old one.
- _Sink leasing / crash._ `pump_loop` leases its sink only inside the
  `initial_info` branch. This emulator streams HCI _without_ sending
  `initial_info` first, so execution fell through to the data path with
  `sink=None` and hit `assert self.sink is not None`. That AssertionError
  escapes the gRPC servicer, kills the stream, and **aborts the emulator
  process** (core dump). Fix: lease lazily, and never assert in a servicer.

`patch-netsim.py` applies both. It restores from `android_netsim.py.orig` first,
so it is idempotent. **RE-RUN IT after any `pip install -U bumble`** or the
bridge goes silently dead.

**2. The endpoint must be explicit.** `-packet-streamer-endpoint default` does
not work — the emulator never opens the gRPC connection. Pass `localhost:8554`.
`emu.sh` already does.

## Files

| File              | Purpose                                                              |
| ----------------- | -------------------------------------------------------------------- |
| `setup.sh`        | Provision everything on a fresh machine. Idempotent                  |
| `bt-release.sh`   | Detach the adapter from the kernel `btusb` driver                    |
| `bt-restore.sh`   | Give it back to the kernel                                           |
| `bridge.sh`       | Run the bumble HCI bridge (own terminal, sudo)                       |
| `emu.sh`          | Launch the AVD wired to the bridge                                   |
| `patch-netsim.py` | The two bumble fixes above                                           |
| `push-rpk.sh`     | Copy the newest `.rpk` from `<repo>/dist` into the AVD's `Download/` |
| `get-authkey.sh`  | Pull a Xiaomi auth key out of Mi Fitness logs in the AVD             |
| `common.sh`       | Shared paths and the adapter/AVD detection helpers                   |

Downloads (venv, JDK, APKs) go to `$MIBAND_HOME`, default
`~/.local/share/miband-bridge` — outside the repo, since they are machine state,
not source. The Android SDK goes to `$ANDROID_HOME`, default `~/Android/Sdk`.

## New machine

    tools/miband-bridge/setup.sh

Creates the venv, installs `bumble[android]`, applies both patches, fetches a
private Temurin 21 if the system Java is older than 17, installs the SDK
packages and creates the AVD. `--venv-only` skips the Android side;
`--with-gadgetbridge` also fetches and installs the Gadgetbridge APK.

Overridable, so nothing needs editing per machine:
`MIBAND_HOME`, `ANDROID_HOME`, `AVD`, `PORT`, `API`, `IMAGE`, and `VID`/`PID`
for the Bluetooth adapter (auto-detected otherwise).

AVD `miband_bridge`: API 32, `google_apis_playstore`, x86_64, 4 GB RAM, boots in
~23 s. **API 32 deliberately** — 33/34 are reported flaky for emulator
Bluetooth. Playstore image so the Play Store is available; it cannot be rooted
(`adb root` is refused), which is fine, nothing here needs root.

Verified on: Arch Linux, kernel 6.12 LTS, Intel BE200 (`8087:0036`), emulator
37.1.11, bumble 0.0.233, Python 3.14.

## Run it

    1.  ./bt-release.sh    # laptop's own Bluetooth goes offline until step 4
    2.  ./bridge.sh        # new terminal, leave running
    3.  ./emu.sh           # new terminal, leave running - this IS the phone
    4.  ./bt-restore.sh    # when finished, after closing 3 and Ctrl+C-ing 2

All paths below are relative to `tools/miband-bridge/`; the scripts resolve the
repo themselves, so they work from any cwd.

In the emulator window: Settings -> Connected devices -> Connection preferences
-> Bluetooth. If it toggles on and stays on, the whole chain is live. If there
is no adapter, or it flips back off, that is the known upstream breakage
(google/bumble#662, issuetracker 260968394) — not a misconfiguration.

Log noise: `bridge.sh` runs at `warning` by default because `hci_bridge` logs
every HCI packet at INFO, which is a firehose of nearby BLE advertising.
`LOGLEVEL=info ./bridge.sh` to watch actual traffic; look for
`Leased sink on first data packet`. The traceback on Ctrl+C is expected.

## Installing the .rpk (what we actually do)

The Notify-for-Xiaomi app, installed in the AVD from the Play Store, handles the
rpk install directly. So in practice: steps 1-3 above, then

    npm run release              # in the repo root
    ./push-rpk.sh                # lands in /sdcard/Download/

and install it from that app.

Gadgetbridge is the fallback path (`setup.sh --with-gadgetbridge`). If you go
that route instead: it needs a Xiaomi auth key (`0x`-prefixed), obtained by
pairing the band in Mi Fitness _inside the AVD_ and then running
`./get-authkey.sh`. Install via Gadgetbridge's App Manager picker, not from a
file manager — `.rpk` is not in its intent filters. See the notes at the bottom.

## Gotchas

- The Vela band emulator (`xiaomi_band_10`) also answers to adb, and its SDK
  ships its own adb at `~/.vela/sdk/tools/adb/linux/adb`. Scripts here target
  the AVD by name; bare `adb` needs `-s`.
- One adapter on this laptop, so the host is deaf while bridging. A second USB
  dongle avoids that: `VID=xxxx PID=xxxx ./bt-release.sh`.
- `bt-release.sh` prints `already released` for the second interface. Normal:
  `btusb` claims both interfaces as one device, so unbinding `:1.0` detaches
  `:1.1` too.
- Keep the real phone's Bluetooth OFF while using the band here — the band holds
  one connection at a time and the phone will keep grabbing it back.
- Do NOT unbind the band from Mi Fitness on the real phone. That invalidates any
  auth key and typically resets the band. It is the one irreversible action in
  this whole procedure, and nothing here requires it.

## Xiaomi auth key notes (Gadgetbridge path only)

`mmk.pw/xiaomikey` does **not** work for this band: it covers Amazfit/Zepp Life
devices and explicitly excludes 70mai-designed bands (8 and newer) and anything
paired via Mi Fitness. The Band 10 is both. An iPhone is no help either — iOS
gives no access to app logs.

The key lives in Mi Fitness's own logs, readable by plain `adb shell` with no
root (verified on API 32):

    /sdcard/Android/data/com.xiaomi.wearable/files/log/*.log

Field name and filename both drift between Mi Fitness versions
(`authKey` -> `token` / `encryptKey` / `huamiAuthKey`;
`XiaomiFit.device.log` -> `XiaomiFit.main.log` -> `Transfer.device.log`), so
`get-authkey.sh` scans every log under `com.xiaomi.wearable` and `com.mi.health`
for any 32-hex value. Live fallback:

    adb logcat --pid=$(adb shell pidof com.xiaomi.wearable) | grep -i encryptKey

## Still unproven

Bluetooth works in the emulator. Not yet confirmed: that the band actually
pairs through this chain, and that its firmware accepts an rpk install at all.
Gadgetbridge's `XiaomiRpkService` (command type 20) was tested upstream on
Band 9, Band 8 Pro and Redmi Watch 4 — the Band 10 inherits app-management
support in `MiBand10Coordinator` rather than opting out, but the firmware side
is untested.
