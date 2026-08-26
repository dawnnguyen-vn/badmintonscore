# Badminton Score

A badminton scoreboard for the **Xiaomi Smart Band 10**, built as a Vela QuickApp
(`.rpk`) with the `aiot-toolkit`. The whole app lives in
[`src/pages/index/index.ux`](src/pages/index/index.ux).

## Features

- Two large scores — **B** on top (orange), **A** on bottom (blue).
- A top-down **badminton court** in the middle showing the serve situation:
  - a coloured **dot** marks the **server's** service court,
  - a **ring** marks the **receiver's** service court (diagonally opposite),
  - at **0–0** both possible service courts are dotted, since either side may serve first.
- Serve court follows the rules: the serving side serves from the **right** court on an
  **even** score, **left** on **odd** (same rule for singles and doubles).
- The middle net band shows the current **time**.
- Status line: `● GAME POINT X` at game point, `★ X WINS w-l` when the game ends
  (21 points, win by 2; hard cap at 30).

## Controls

| Gesture | Action |
|---|---|
| Swipe up | B +1 (top player) |
| Swipe down | A +1 (bottom player) |
| Swipe left | Undo last point |
| Long press | Reset to 0–0 |
| Tap a score | Edit that score (`−` / `+` / Done) |

## Develop

```bash
npm install
npm run start   # build + deploy to a running emulator, with hot reload
```

`npm run start` prompts for an AVD and deploys over `adb`, so `adb` must be on your
`PATH` and a Vela emulator (e.g. `xiaomi_band_10`) must be running.

## Build

```bash
npm run build     # signed debug .rpk -> ./dist
npm run release   # production .rpk (requires signing certs in ./sign)
```

The generated `.rpk` can be installed on the emulator or a real device.
