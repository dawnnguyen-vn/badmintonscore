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
- The match survives leaving the app — score and server are saved after every
  change and read back on launch, so a stray swipe out costs nothing.

## Controls

| Gesture                       | Action                                   |
| ----------------------------- | ---------------------------------------- |
| Swipe up                      | B +1 (top player)                        |
| Swipe down                    | A +1 (bottom player)                     |
| Swipe left                    | Undo last point                          |
| Swipe right (back)            | Close the open overlay, or leave the app |
| Double tap a score            | Edit that score (`−` / `+` / Done)       |
| Double tap between the scores | Menu: **Reset game** / **Exit app**      |

Which one you get depends on where you tap: the top or bottom score zone edits
that score, the whole band between them — the court diagram and the space
around it — opens the menu. A _single_ tap does nothing, and neither action
changes the score directly (each opens an overlay you have to confirm), so a
stray touch mid-rally is harmless.

These were a long press until it turned out that nothing in the app may bind
`longpress`: that gesture belongs to the watch, which needs it to bring up the
system panel holding the app's **remove** button, and binding it here swallows
it. `doubleTap()` in the page counts two taps on the same zone inside 350 ms —
the framework has no `doubleclick` event of its own.

### Leaving the app

Swipe right is the system back gesture. It's routed through `handleBack()`,
which dismisses whatever overlay is open and otherwise leaves — no "are you
sure?", because the score is in storage and reopening the app picks the match
up where it was. Quitting calls `app.terminate()` from `@system.app`, with
`router.back()` on the entry page as the fallback. **Exit app** in the menu
does the same thing, which is the way out if the back gesture isn't reaching
the app at all.

`handleBack()` is called from two places, because neither is reliable on its
own: on some builds the page's `swipe` handler consumes the right swipe and
`onBackPress()` never fires, and where `onBackPress()` _does_ fire, one
physical swipe arrives twice, at a delay that varies. So the first
`onBackPress()` sets `_sysBack`, after which right-swipes are ignored here and
left to it, and a 700 ms guard covers the first press, before that is known.
The old quit-confirm overlay is gone: it was the thing the duplicate event
could half-answer, and with the score saved it wasn't buying anything.

### Saved state

The score, its opposite number and who serves are written to `@system.storage`
under one key as a single `"scoreA,scoreB,server"` string, after every change.
It's read back in `onInit()`; a point scored before that read lands wins over
the stored value, and anything that doesn't parse leaves the board at 0–0.
`encode()` / `decode()` are also what the undo stack stores, so it holds one
short string per point rather than an object.

## Memory

Watch apps are held to a low memory ceiling, so the page follows Xiaomi's
[memory checklist](https://iot.mi.com/vela/quickapp/en/guide/best-practice/memory.html):

- Constants (`DIAG`, the timing thresholds, the storage-failure callback) live
  at module scope. Anything on `private` gets a change observer, and anything
  built inside a method is re-allocated on every call — `DIAG` used to be a
  literal inside `courtDots()`, which runs on every score change.
- Non-UI state (`_history`, `_timer`, the back/tap timestamps) is set on `this`
  in `onInit()` rather than declared in `private`, for the same reason.
- The undo stack is capped at `HISTORY_MAX` (40) entries of one string each, so
  a long match can't grow it without limit.
- The clock interval is cleared in `onHide()` and `onDestroy()`.
- Read values are released as soon as they're consumed, and `onDestroy()` calls
  `global.runGC()` once — on the way out only, since a frequent one stutters
  the page.
- No third-party dependencies, one page, and the only asset is the icon.

Nothing on this page is a candidate for the `static` template marker: every
binding here (`courtDots`, the scores, `statusClass`, every overlay's `if`)
genuinely changes at runtime.

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
